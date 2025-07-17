#!/bin/bash

# Predictive Scaling Demo Setup
# System Design Interview Roadmap - Issue #98
# Creates a complete predictive scaling system with web UI

set -e

echo "🚀 Setting up Predictive Scaling Demo..."

# Create project structure
mkdir -p predictive-scaling-demo/{src,static,templates,data,logs}
cd predictive-scaling-demo

# Create requirements.txt
cat > requirements.txt << 'EOF'
flask==3.0.0
pandas==2.1.4
numpy==1.25.2
scikit-learn==1.3.2
plotly==5.18.0
requests==2.31.0
python-dateutil==2.8.2
waitress==3.0.0
statsmodels==0.14.1
gunicorn==21.2.0
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000

CMD ["python", "src/app.py"]
EOF

# Create main application
cat > src/app.py << 'EOF'
import os
import json
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from flask import Flask, render_template, jsonify, request
from sklearn.ensemble import RandomForestRegressor
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error, mean_squared_error
import plotly.graph_objs as go
import plotly.utils
from statsmodels.tsa.arima.model import ARIMA
from statsmodels.tsa.holtwinters import ExponentialSmoothing
import warnings
warnings.filterwarnings('ignore')

app = Flask(__name__)

class PredictiveScalingEngine:
    def __init__(self):
        self.models = {}
        self.historical_data = self.generate_synthetic_data()
        self.predictions = {}
        self.scaling_decisions = []
        
    def generate_synthetic_data(self):
        """Generate realistic traffic patterns"""
        np.random.seed(42)
        dates = pd.date_range(start='2024-01-01', end='2024-07-14', freq='H')
        
        # Base traffic with daily and weekly patterns
        base_traffic = 1000
        daily_pattern = np.sin(np.arange(len(dates)) * 2 * np.pi / 24) * 300
        weekly_pattern = np.sin(np.arange(len(dates)) * 2 * np.pi / (24 * 7)) * 200
        
        # Add noise and random spikes
        noise = np.random.normal(0, 100, len(dates))
        spikes = np.random.exponential(0.01, len(dates)) * 2000
        
        traffic = base_traffic + daily_pattern + weekly_pattern + noise + spikes
        traffic = np.maximum(traffic, 100)  # Minimum traffic
        
        return pd.DataFrame({
            'timestamp': dates,
            'requests_per_second': traffic,
            'cpu_utilization': np.minimum(traffic / 20, 100),
            'memory_usage': np.minimum(traffic / 25 + 30, 90),
            'response_time': np.maximum(50 + traffic / 100, 50)
        })
    
    def train_ensemble_models(self):
        """Train multiple prediction models"""
        # Prepare features
        df = self.historical_data.copy()
        df['hour'] = df['timestamp'].dt.hour
        df['day_of_week'] = df['timestamp'].dt.dayofweek
        df['day_of_month'] = df['timestamp'].dt.day
        
        # Features for ML models
        feature_cols = ['hour', 'day_of_week', 'day_of_month']
        X = df[feature_cols].values
        y = df['requests_per_second'].values
        
        # Train Random Forest
        rf_model = RandomForestRegressor(n_estimators=100, random_state=42)
        rf_model.fit(X, y)
        self.models['random_forest'] = rf_model
        
        # Train Linear Regression
        lr_model = LinearRegression()
        lr_model.fit(X, y)
        self.models['linear_regression'] = lr_model
        
        # Train ARIMA (simplified)
        try:
            arima_model = ARIMA(y[-168:], order=(1, 1, 1))  # Last week
            arima_fit = arima_model.fit()
            self.models['arima'] = arima_fit
        except:
            self.models['arima'] = None
        
        # Train Holt-Winters
        try:
            hw_model = ExponentialSmoothing(y[-168:], seasonal_periods=24, trend='add', seasonal='add')
            hw_fit = hw_model.fit()
            self.models['holt_winters'] = hw_fit
        except:
            self.models['holt_winters'] = None
    
    def predict_future_traffic(self, hours_ahead=24):
        """Generate ensemble predictions"""
        if not self.models:
            self.train_ensemble_models()
        
        predictions = []
        now = datetime.now()
        
        for i in range(hours_ahead):
            future_time = now + timedelta(hours=i)
            
            # Features for ML models
            features = np.array([[
                future_time.hour,
                future_time.weekday(),
                future_time.day
            ]])
            
            # Collect predictions from all models
            model_predictions = []
            
            # Random Forest
            rf_pred = self.models['random_forest'].predict(features)[0]
            model_predictions.append(rf_pred)
            
            # Linear Regression
            lr_pred = self.models['linear_regression'].predict(features)[0]
            model_predictions.append(lr_pred)
            
            # ARIMA
            if self.models['arima']:
                try:
                    arima_pred = self.models['arima'].forecast(steps=1)[0]
                    model_predictions.append(arima_pred)
                except:
                    pass
            
            # Holt-Winters
            if self.models['holt_winters']:
                try:
                    hw_pred = self.models['holt_winters'].forecast(steps=1)[0]
                    model_predictions.append(hw_pred)
                except:
                    pass
            
            # Ensemble prediction (weighted average)
            ensemble_pred = np.mean(model_predictions)
            confidence = 1.0 - (np.std(model_predictions) / np.mean(model_predictions))
            
            predictions.append({
                'timestamp': future_time,
                'predicted_rps': max(ensemble_pred, 100),
                'confidence': max(min(confidence, 1.0), 0.0),
                'individual_predictions': {
                    'random_forest': rf_pred,
                    'linear_regression': lr_pred,
                    'ensemble': ensemble_pred
                }
            })
        
        return predictions
    
    def calculate_scaling_decision(self, predicted_rps, confidence):
        """Calculate scaling decision based on prediction and confidence"""
        current_capacity = 1000  # RPS capacity per instance
        current_instances = 5
        
        # Calculate required instances
        required_instances = int(np.ceil(predicted_rps / current_capacity))
        
        # Apply confidence-based scaling
        if confidence > 0.85:
            # High confidence: scale proactively
            target_instances = int(required_instances * 1.2)
        elif confidence > 0.65:
            # Medium confidence: conservative scaling
            target_instances = int(required_instances * 1.1)
        else:
            # Low confidence: minimal scaling
            target_instances = max(required_instances, current_instances)
        
        # Calculate cost and performance impact
        cost_per_instance_hour = 0.1  # $0.10 per instance per hour
        scaling_decision = {
            'current_instances': current_instances,
            'target_instances': target_instances,
            'scaling_action': 'scale_up' if target_instances > current_instances else 'scale_down' if target_instances < current_instances else 'maintain',
            'cost_impact': (target_instances - current_instances) * cost_per_instance_hour,
            'confidence': confidence,
            'predicted_rps': predicted_rps
        }
        
        return scaling_decision

# Initialize the engine
engine = PredictiveScalingEngine()

@app.route('/')
def dashboard():
    return render_template('dashboard.html')

@app.route('/api/historical-data')
def get_historical_data():
    # Get last 7 days of data
    recent_data = engine.historical_data.tail(168)  # 7 days * 24 hours
    
    return jsonify({
        'timestamps': recent_data['timestamp'].dt.strftime('%Y-%m-%d %H:%M:%S').tolist(),
        'requests_per_second': recent_data['requests_per_second'].tolist(),
        'cpu_utilization': recent_data['cpu_utilization'].tolist(),
        'memory_usage': recent_data['memory_usage'].tolist(),
        'response_time': recent_data['response_time'].tolist()
    })

@app.route('/api/predictions')
def get_predictions():
    predictions = engine.predict_future_traffic(hours_ahead=24)
    
    result = {
        'timestamps': [p['timestamp'].strftime('%Y-%m-%d %H:%M:%S') for p in predictions],
        'predicted_rps': [p['predicted_rps'] for p in predictions],
        'confidence': [p['confidence'] for p in predictions],
        'individual_predictions': [p['individual_predictions'] for p in predictions]
    }
    
    return jsonify(result)

@app.route('/api/scaling-decisions')
def get_scaling_decisions():
    predictions = engine.predict_future_traffic(hours_ahead=24)
    decisions = []
    
    for pred in predictions:
        decision = engine.calculate_scaling_decision(pred['predicted_rps'], pred['confidence'])
        decision['timestamp'] = pred['timestamp'].strftime('%Y-%m-%d %H:%M:%S')
        decisions.append(decision)
    
    return jsonify(decisions)

@app.route('/api/simulate-traffic-spike')
def simulate_traffic_spike():
    # Add a simulated traffic spike
    current_time = datetime.now()
    spike_data = {
        'timestamp': current_time.strftime('%Y-%m-%d %H:%M:%S'),
        'requests_per_second': 5000,
        'message': 'Simulated traffic spike detected'
    }
    
    # Trigger predictive scaling
    predictions = engine.predict_future_traffic(hours_ahead=6)
    scaling_decisions = []
    
    for pred in predictions:
        decision = engine.calculate_scaling_decision(pred['predicted_rps'], pred['confidence'])
        scaling_decisions.append(decision)
    
    return jsonify({
        'spike_data': spike_data,
        'scaling_decisions': scaling_decisions
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

# Create HTML template
mkdir -p templates
cat > templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Predictive Scaling Dashboard</title>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Google Sans', Arial, sans-serif;
            background-color: #f8f9fa;
            color: #202124;
        }
        
        .header {
            background: linear-gradient(135deg, #1a73e8 0%, #4285f4 100%);
            color: white;
            padding: 20px 0;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        
        .header-content {
            max-width: 1200px;
            margin: 0 auto;
            padding: 0 20px;
        }
        
        .header h1 {
            font-size: 28px;
            font-weight: 400;
            margin-bottom: 8px;
        }
        
        .header p {
            font-size: 16px;
            opacity: 0.9;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            border-left: 4px solid #1a73e8;
        }
        
        .stat-card h3 {
            font-size: 14px;
            color: #5f6368;
            margin-bottom: 8px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .stat-value {
            font-size: 32px;
            font-weight: 300;
            color: #1a73e8;
        }
        
        .chart-container {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        
        .chart-title {
            font-size: 20px;
            font-weight: 500;
            margin-bottom: 20px;
            color: #202124;
        }
        
        .button {
            background: #1a73e8;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 6px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.3s ease;
            box-shadow: 0 2px 6px rgba(26, 115, 232, 0.3);
        }
        
        .button:hover {
            background: #1557b0;
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(26, 115, 232, 0.4);
        }
        
        .controls {
            display: flex;
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .alert {
            padding: 12px 16px;
            border-radius: 6px;
            margin-bottom: 20px;
            border-left: 4px solid #34a853;
            background: #e8f5e8;
            color: #137333;
        }
        
        .loading {
            text-align: center;
            padding: 40px;
            color: #5f6368;
        }
        
        .grid-2 {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
        }
        
        @media (max-width: 768px) {
            .grid-2 {
                grid-template-columns: 1fr;
            }
            
            .stats-grid {
                grid-template-columns: 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="header-content">
            <h1>Predictive Scaling Dashboard</h1>
            <p>Real-time traffic prediction and automated scaling decisions</p>
        </div>
    </div>
    
    <div class="container">
        <div class="stats-grid">
            <div class="stat-card">
                <h3>Current RPS</h3>
                <div class="stat-value" id="current-rps">-</div>
            </div>
            <div class="stat-card">
                <h3>Active Instances</h3>
                <div class="stat-value" id="active-instances">5</div>
            </div>
            <div class="stat-card">
                <h3>Prediction Confidence</h3>
                <div class="stat-value" id="prediction-confidence">-</div>
            </div>
            <div class="stat-card">
                <h3>Next Hour Prediction</h3>
                <div class="stat-value" id="next-hour-prediction">-</div>
            </div>
        </div>
        
        <div class="controls">
            <button class="button" onclick="loadData()">Refresh Data</button>
            <button class="button" onclick="simulateSpike()">Simulate Traffic Spike</button>
        </div>
        
        <div id="alert-container"></div>
        
        <div class="grid-2">
            <div class="chart-container">
                <div class="chart-title">Historical Traffic Patterns</div>
                <div id="historical-chart"></div>
            </div>
            
            <div class="chart-container">
                <div class="chart-title">Traffic Predictions (Next 24 Hours)</div>
                <div id="predictions-chart"></div>
            </div>
        </div>
        
        <div class="chart-container">
            <div class="chart-title">Scaling Decisions Timeline</div>
            <div id="scaling-chart"></div>
        </div>
    </div>
    
    <script>
        let currentData = null;
        let predictions = null;
        let scalingDecisions = null;
        
        async function loadData() {
            try {
                showAlert('Loading data...', 'info');
                
                const [historicalResponse, predictionsResponse, scalingResponse] = await Promise.all([
                    fetch('/api/historical-data'),
                    fetch('/api/predictions'),
                    fetch('/api/scaling-decisions')
                ]);
                
                currentData = await historicalResponse.json();
                predictions = await predictionsResponse.json();
                scalingDecisions = await scalingResponse.json();
                
                updateStats();
                updateCharts();
                
                showAlert('Data loaded successfully!', 'success');
            } catch (error) {
                showAlert('Error loading data: ' + error.message, 'error');
            }
        }
        
        function updateStats() {
            if (!currentData || !predictions) return;
            
            const currentRPS = currentData.requests_per_second[currentData.requests_per_second.length - 1];
            const nextHourPrediction = predictions.predicted_rps[0];
            const confidence = predictions.confidence[0];
            
            document.getElementById('current-rps').textContent = Math.round(currentRPS);
            document.getElementById('next-hour-prediction').textContent = Math.round(nextHourPrediction);
            document.getElementById('prediction-confidence').textContent = Math.round(confidence * 100) + '%';
        }
        
        function updateCharts() {
            if (!currentData || !predictions) return;
            
            // Historical chart
            const historicalTrace = {
                x: currentData.timestamps,
                y: currentData.requests_per_second,
                type: 'scatter',
                mode: 'lines',
                name: 'Historical RPS',
                line: { color: '#1a73e8', width: 2 }
            };
            
            Plotly.newPlot('historical-chart', [historicalTrace], {
                margin: { t: 0, r: 0, b: 40, l: 60 },
                paper_bgcolor: 'white',
                plot_bgcolor: 'white',
                xaxis: { title: 'Time' },
                yaxis: { title: 'Requests per Second' }
            });
            
            // Predictions chart
            const predictionsTrace = {
                x: predictions.timestamps,
                y: predictions.predicted_rps,
                type: 'scatter',
                mode: 'lines+markers',
                name: 'Predicted RPS',
                line: { color: '#34a853', width: 2 },
                marker: { size: 6 }
            };
            
            const confidenceTrace = {
                x: predictions.timestamps,
                y: predictions.confidence.map(c => c * 100),
                type: 'scatter',
                mode: 'lines',
                name: 'Confidence %',
                yaxis: 'y2',
                line: { color: '#ea4335', width: 2, dash: 'dash' }
            };
            
            Plotly.newPlot('predictions-chart', [predictionsTrace, confidenceTrace], {
                margin: { t: 0, r: 60, b: 40, l: 60 },
                paper_bgcolor: 'white',
                plot_bgcolor: 'white',
                xaxis: { title: 'Time' },
                yaxis: { title: 'Predicted RPS' },
                yaxis2: {
                    title: 'Confidence %',
                    overlaying: 'y',
                    side: 'right'
                }
            });
            
            // Scaling decisions chart
            const scalingTrace = {
                x: scalingDecisions.map(d => d.timestamp),
                y: scalingDecisions.map(d => d.target_instances),
                type: 'scatter',
                mode: 'lines+markers',
                name: 'Target Instances',
                line: { color: '#ff9800', width: 3 },
                marker: { size: 8 }
            };
            
            const currentInstancesTrace = {
                x: scalingDecisions.map(d => d.timestamp),
                y: scalingDecisions.map(d => d.current_instances),
                type: 'scatter',
                mode: 'lines',
                name: 'Current Instances',
                line: { color: '#9e9e9e', width: 2, dash: 'dash' }
            };
            
            Plotly.newPlot('scaling-chart', [scalingTrace, currentInstancesTrace], {
                margin: { t: 0, r: 0, b: 40, l: 60 },
                paper_bgcolor: 'white',
                plot_bgcolor: 'white',
                xaxis: { title: 'Time' },
                yaxis: { title: 'Instance Count' }
            });
        }
        
        async function simulateSpike() {
            try {
                showAlert('Simulating traffic spike...', 'info');
                
                const response = await fetch('/api/simulate-traffic-spike');
                const data = await response.json();
                
                showAlert(`Traffic spike simulated! Peak: ${Math.round(data.spike_data.requests_per_second)} RPS`, 'warning');
                
                // Reload data to show new predictions
                setTimeout(() => loadData(), 1000);
            } catch (error) {
                showAlert('Error simulating spike: ' + error.message, 'error');
            }
        }
        
        function showAlert(message, type) {
            const alertContainer = document.getElementById('alert-container');
            const alertClass = type === 'error' ? 'alert-error' : type === 'warning' ? 'alert-warning' : 'alert-success';
            
            alertContainer.innerHTML = `
                <div class="alert ${alertClass}">
                    ${message}
                </div>
            `;
            
            setTimeout(() => {
                alertContainer.innerHTML = '';
            }, 5000);
        }
        
        // Load data on page load
        document.addEventListener('DOMContentLoaded', loadData);
        
        // Auto-refresh every 30 seconds
        setInterval(loadData, 30000);
    </script>
</body>
</html>
EOF

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  predictive-scaling:
    build: .
    ports:
      - "5000:5000"
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    environment:
      - FLASK_ENV=production
      - PYTHONUNBUFFERED=1
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# Create demo script
cat > demo.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting Predictive Scaling Demo..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build and start the application
echo "📦 Building Docker image..."
docker-compose build

echo "🏃 Starting services..."
docker-compose up -d

# Wait for service to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Health check
echo "🔍 Checking service health..."
for i in {1..30}; do
    if curl -f http://localhost:5000/ > /dev/null 2>&1; then
        echo "✅ Service is healthy!"
        break
    fi
    echo "⏳ Waiting for service... ($i/30)"
    sleep 2
done

echo ""
echo "🎉 Predictive Scaling Demo is ready!"
echo ""
echo "📊 Dashboard: http://localhost:5000"
echo ""
echo "🧪 Demo Steps:"
echo "1. Open http://localhost:5000 in your browser"
echo "2. Click 'Refresh Data' to load historical patterns"
echo "3. Click 'Simulate Traffic Spike' to test predictive scaling"
echo "4. Click 'Refresh Data' again to see the spike impact on predictions"
echo "5. Observe how the system predicts and scales proactively"
echo ""
echo "📈 Key Features:"
echo "- Real-time traffic prediction using ensemble models"
echo "- Confidence-based scaling decisions"
echo "- Cost optimization calculations"
echo "- Interactive visualization dashboard"
echo "- Live traffic spike simulation with model retraining"
echo ""
echo "🔧 To stop the demo, run: ./cleanup.sh"
EOF

# Create cleanup script
cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Predictive Scaling Demo..."

# Stop and remove containers
docker-compose down

# Remove Docker images
docker rmi predictive-scaling-demo_predictive-scaling 2>/dev/null || true

# Clean up logs
rm -rf logs/*

echo "✅ Cleanup complete!"
EOF

# Create test script
cat > test.sh << 'EOF'
#!/bin/bash

echo "🧪 Running Predictive Scaling Tests..."

# Test API endpoints
echo "Testing API endpoints..."

# Test historical data endpoint
echo "1. Testing historical data endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/historical-data)
if [ "$response" = "200" ]; then
    echo "✅ Historical data endpoint working"
else
    echo "❌ Historical data endpoint failed (HTTP $response)"
fi

# Test predictions endpoint
echo "2. Testing predictions endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/predictions)
if [ "$response" = "200" ]; then
    echo "✅ Predictions endpoint working"
else
    echo "❌ Predictions endpoint failed (HTTP $response)"
fi

# Test scaling decisions endpoint
echo "3. Testing scaling decisions endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/scaling-decisions)
if [ "$response" = "200" ]; then
    echo "✅ Scaling decisions endpoint working"
else
    echo "❌ Scaling decisions endpoint failed (HTTP $response)"
fi

# Test traffic spike simulation
echo "4. Testing traffic spike simulation..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/simulate-traffic-spike)
if [ "$response" = "200" ]; then
    echo "✅ Traffic spike simulation working"
else
    echo "❌ Traffic spike simulation failed (HTTP $response)"
fi

echo ""
echo "🎯 All tests completed!"
EOF

# Make scripts executable
chmod +x demo.sh cleanup.sh test.sh

echo "✅ Predictive Scaling Demo setup complete!"
echo ""
echo "🚀 To start the demo:"
echo "   ./demo.sh"
echo ""
echo "🧪 To run tests:"
echo "   ./test.sh"
echo ""
echo "🧹 To cleanup:"
echo "   ./cleanup.sh"