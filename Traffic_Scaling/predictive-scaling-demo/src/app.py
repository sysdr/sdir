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

app = Flask(__name__, template_folder='../templates')

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
    # Add a simulated traffic spike to historical data
    current_time = datetime.now()
    
    # Create spike data point
    spike_timestamp = current_time
    spike_rps = 5000
    spike_cpu = min(spike_rps / 20, 100)
    spike_memory = min(spike_rps / 25 + 30, 90)
    spike_response_time = max(50 + spike_rps / 100, 50)
    
    # Add spike to historical data
    spike_row = pd.DataFrame({
        'timestamp': [spike_timestamp],
        'requests_per_second': [spike_rps],
        'cpu_utilization': [spike_cpu],
        'memory_usage': [spike_memory],
        'response_time': [spike_response_time]
    })
    
    # Append spike to historical data
    engine.historical_data = pd.concat([engine.historical_data, spike_row], ignore_index=True)
    
    # Retrain models with new data
    engine.models = {}  # Clear existing models
    engine.train_ensemble_models()
    
    spike_data = {
        'timestamp': current_time.strftime('%Y-%m-%d %H:%M:%S'),
        'requests_per_second': spike_rps,
        'message': 'Simulated traffic spike detected and added to historical data'
    }
    
    # Get updated predictions and scaling decisions
    predictions = engine.predict_future_traffic(hours_ahead=6)
    scaling_decisions = []
    
    for pred in predictions:
        decision = engine.calculate_scaling_decision(pred['predicted_rps'], pred['confidence'])
        decision['timestamp'] = pred['timestamp'].strftime('%Y-%m-%d %H:%M:%S')
        scaling_decisions.append(decision)
    
    return jsonify({
        'spike_data': spike_data,
        'scaling_decisions': scaling_decisions,
        'message': 'Traffic spike injected and models retrained'
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
