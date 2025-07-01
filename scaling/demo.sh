#!/bin/bash

# demo.sh - Scaling to 1M Users Interactive Demo Setup
# This script creates a complete environment to demonstrate scaling patterns

set -e

echo "🚀 Setting up Scaling to 1M Users Demo Environment..."

# Create project structure
echo "📁 Creating project structure..."
mkdir -p scaling-demo/{backend,frontend,docker,tests,docs}
cd scaling-demo

# Create requirements.txt with latest compatible versions
echo "📋 Creating requirements.txt..."
cat > requirements.txt << 'EOF'
flask==3.0.0
flask-cors==4.0.0
flask-socketio==5.3.6
python-socketio==5.9.0
eventlet==0.33.3
requests==2.31.0
pytest==7.4.3
pytest-flask==1.3.0
gunicorn==21.2.0
redis==5.0.1
psutil==5.9.6
numpy==1.24.4
json-logging==1.3.0
prometheus-client==0.19.0
EOF

# Create Flask backend
echo "🐍 Creating Flask backend..."
cat > backend/app.py << 'EOF'
from flask import Flask, render_template, jsonify, request
from flask_cors import CORS
from flask_socketio import SocketIO, emit
import time
import random
import threading
import json
import psutil
import os
from datetime import datetime

app = Flask(__name__, template_folder='../frontend')
app.config['SECRET_KEY'] = 'scaling-demo-secret'
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Global state for demonstration
demo_state = {
    'current_stage': 1,
    'user_count': 1,
    'response_time': 150,
    'throughput': 10,
    'error_rate': 0.1,
    'is_load_testing': False,
    'system_capacity': 1000,
    'start_time': time.time()
}

# Architecture stages configuration
STAGES = {
    1: {
        'name': 'Single Server',
        'capacity': 1000,
        'components': ['Web Server + Database'],
        'description': 'Everything on one machine. Simple and fast to develop.',
        'scaling_trigger': {'users': 800, 'response_time': 500}
    },
    2: {
        'name': 'Separate Database',
        'capacity': 10000,
        'components': ['Web Server', 'Database'],
        'description': 'Separate concerns for better resource utilization.',
        'scaling_trigger': {'users': 8000, 'response_time': 800}
    },
    3: {
        'name': 'Load Balanced',
        'capacity': 100000,
        'components': ['Load Balancer', 'App Server 1', 'App Server 2', 'Database'],
        'description': 'Horizontal scaling with multiple application servers.',
        'scaling_trigger': {'users': 80000, 'response_time': 1200}
    },
    4: {
        'name': 'Caching & CDN',
        'capacity': 500000,
        'components': ['CDN', 'Load Balancer', 'Cache', 'App Servers', 'DB + Replicas'],
        'description': 'Add caching layers and content delivery for performance.',
        'scaling_trigger': {'users': 400000, 'response_time': 2000}
    },
    5: {
        'name': 'Microservices',
        'capacity': 1000000,
        'components': ['API Gateway', 'User Service', 'Order Service', 'Payment Service', 'Message Queue'],
        'description': 'Service decomposition for team autonomy and fault isolation.',
        'scaling_trigger': None
    }
}

def calculate_performance_metrics():
    """Calculate realistic performance metrics based on current load"""
    stage = demo_state['current_stage']
    capacity = STAGES[stage]['capacity']
    load_factor = demo_state['user_count'] / capacity
    
    # Base response time increases with load
    base_response_time = 150 + (load_factor * 500)
    
    # Add random variation
    variation = random.uniform(0.8, 1.2)
    demo_state['response_time'] = int(base_response_time * variation)
    
    # Error rate increases exponentially with overload
    if load_factor > 1.0:
        demo_state['error_rate'] = min(10.0, 0.1 + (load_factor - 1.0) * 5)
    else:
        demo_state['error_rate'] = max(0.1, 0.1 + (load_factor - 0.5) * 0.2)
    
    # Throughput calculation
    demo_state['throughput'] = min(
        demo_state['user_count'] * random.uniform(0.7, 0.9),
        capacity * 0.8  # Maximum sustainable throughput
    )

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/metrics')
def get_metrics():
    """Get current system metrics"""
    calculate_performance_metrics()
    return jsonify({
        'user_count': demo_state['user_count'],
        'response_time': demo_state['response_time'],
        'throughput': int(demo_state['throughput']),
        'error_rate': round(demo_state['error_rate'], 1),
        'current_stage': demo_state['current_stage'],
        'capacity_utilization': min(100, (demo_state['user_count'] / STAGES[demo_state['current_stage']]['capacity']) * 100),
        'uptime': int(time.time() - demo_state['start_time'])
    })

@app.route('/api/architecture')
def get_architecture():
    """Get current architecture stage information"""
    stage = demo_state['current_stage']
    return jsonify({
        'current_stage': stage,
        'stage_info': STAGES[stage],
        'all_stages': STAGES
    })

@app.route('/api/load-test/start', methods=['POST'])
def start_load_test():
    """Start simulated load testing"""
    if demo_state['is_load_testing']:
        return jsonify({'error': 'Load test already running'}), 400
    
    demo_state['is_load_testing'] = True
    
    def run_load_test():
        """Background thread for load testing simulation"""
        test_duration = 0
        while demo_state['is_load_testing'] and test_duration < 60:  # Max 60 seconds
            # Simulate user growth
            growth_rate = random.randint(50, 200)
            demo_state['user_count'] += growth_rate
            
            # Emit real-time updates
            socketio.emit('metrics_update', {
                'user_count': demo_state['user_count'],
                'response_time': demo_state['response_time'],
                'throughput': int(demo_state['throughput']),
                'error_rate': round(demo_state['error_rate'], 1)
            })
            
            time.sleep(2)
            test_duration += 2
        
        demo_state['is_load_testing'] = False
    
    thread = threading.Thread(target=run_load_test)
    thread.daemon = True
    thread.start()
    
    return jsonify({'status': 'Load test started'})

@app.route('/api/load-test/stop', methods=['POST'])
def stop_load_test():
    """Stop load testing"""
    demo_state['is_load_testing'] = False
    return jsonify({'status': 'Load test stopped'})

@app.route('/api/traffic-spike', methods=['POST'])
def trigger_traffic_spike():
    """Simulate sudden traffic spike"""
    spike_multiplier = random.uniform(2.5, 4.0)
    demo_state['user_count'] = int(demo_state['user_count'] * spike_multiplier)
    
    return jsonify({
        'status': 'Traffic spike triggered',
        'multiplier': round(spike_multiplier, 1),
        'new_user_count': demo_state['user_count']
    })

@app.route('/api/scale-up', methods=['POST'])
def scale_up():
    """Scale up to next architecture stage"""
    if demo_state['current_stage'] >= 5:
        return jsonify({'error': 'Already at maximum scale'}), 400
    
    old_stage = demo_state['current_stage']
    demo_state['current_stage'] += 1
    
    # Improve performance after scaling
    demo_state['response_time'] = max(150, int(demo_state['response_time'] * 0.6))
    demo_state['error_rate'] = max(0.1, demo_state['error_rate'] * 0.4)
    
    return jsonify({
        'status': 'Scaled up successfully',
        'old_stage': old_stage,
        'new_stage': demo_state['current_stage'],
        'stage_info': STAGES[demo_state['current_stage']]
    })

@app.route('/api/reset', methods=['POST'])
def reset_demo():
    """Reset demo to initial state"""
    demo_state.update({
        'current_stage': 1,
        'user_count': 1,
        'response_time': 150,
        'throughput': 10,
        'error_rate': 0.1,
        'is_load_testing': False,
        'start_time': time.time()
    })
    
    return jsonify({'status': 'Demo reset successfully'})

@app.route('/api/health')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'version': '1.0.0'
    })

@socketio.on('connect')
def handle_connect():
    """Handle client connection"""
    print(f'Client connected: {request.sid}')
    emit('connected', {'status': 'Connected to scaling demo'})

@socketio.on('disconnect')
def handle_disconnect():
    """Handle client disconnection"""
    print(f'Client disconnected: {request.sid}')

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    print(f"🚀 Starting Scaling Demo on port {port}")
    socketio.run(app, host='0.0.0.0', port=port, debug=True)
EOF

# Create the HTML frontend (copy from the artifact)
echo "🌐 Creating frontend..."
cat > frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Scaling to 1M Users - Interactive Demo</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Google Sans', Arial, sans-serif;
            background: linear-gradient(135deg, #f8f9fa 0%, #e3f2fd 100%);
            min-height: 100vh;
            color: #333;
        }

        .header {
            background: #1976d2;
            color: white;
            padding: 1rem 2rem;
            box-shadow: 0 2px 8px rgba(0,0,0,0.1);
        }

        .header h1 {
            font-size: 1.8rem;
            font-weight: 500;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 2rem;
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 2rem;
        }

        .metrics-panel, .architecture-panel {
            background: white;
            border-radius: 12px;
            padding: 2rem;
            box-shadow: 0 4px 16px rgba(0,0,0,0.08);
            border: 1px solid #e0e0e0;
        }

        .panel-title {
            font-size: 1.3rem;
            color: #1976d2;
            margin-bottom: 1.5rem;
            font-weight: 500;
        }

        .metric-card {
            background: #f5f5f5;
            border-radius: 8px;
            padding: 1rem;
            margin-bottom: 1rem;
            border-left: 4px solid #1976d2;
        }

        .metric-value {
            font-size: 2rem;
            font-weight: 600;
            color: #1976d2;
        }

        .metric-label {
            font-size: 0.9rem;
            color: #666;
            margin-top: 0.25rem;
        }

        .architecture-stage {
            background: #f8f9fa;
            border-radius: 8px;
            padding: 1.5rem;
            margin-bottom: 1rem;
            border: 2px solid #e0e0e0;
            transition: all 0.3s ease;
        }

        .architecture-stage.active {
            border-color: #1976d2;
            background: #e3f2fd;
            transform: scale(1.02);
            box-shadow: 0 4px 12px rgba(25, 118, 210, 0.2);
        }

        .stage-title {
            font-weight: 600;
            color: #1976d2;
            margin-bottom: 0.5rem;
        }

        .stage-description {
            font-size: 0.9rem;
            color: #666;
            line-height: 1.4;
        }

        .controls {
            grid-column: 1 / -1;
            background: white;
            border-radius: 12px;
            padding: 2rem;
            box-shadow: 0 4px 16px rgba(0,0,0,0.08);
            text-align: center;
        }

        .btn {
            background: #1976d2;
            color: white;
            border: none;
            border-radius: 6px;
            padding: 0.75rem 1.5rem;
            font-size: 1rem;
            cursor: pointer;
            margin: 0 0.5rem;
            transition: all 0.3s ease;
        }

        .btn:hover {
            background: #1565c0;
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }

        .btn:disabled {
            background: #ccc;
            cursor: not-allowed;
            transform: none;
            box-shadow: none;
        }

        .progress-bar {
            width: 100%;
            height: 8px;
            background: #e0e0e0;
            border-radius: 4px;
            margin: 1rem 0;
            overflow: hidden;
        }

        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #1976d2, #42a5f5);
            transition: width 0.3s ease;
            border-radius: 4px;
        }

        .alert {
            background: #fff3cd;
            border: 1px solid #ffeaa7;
            color: #856404;
            padding: 1rem;
            border-radius: 6px;
            margin: 1rem 0;
            display: none;
        }

        .alert.show {
            display: block;
        }

        .architecture-visual {
            margin-top: 1rem;
            min-height: 100px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: #f8f9fa;
            border-radius: 8px;
            border: 2px dashed #ddd;
            flex-wrap: wrap;
        }

        .component {
            background: #1976d2;
            color: white;
            border-radius: 6px;
            padding: 0.5rem 1rem;
            margin: 0.25rem;
            font-size: 0.8rem;
            display: inline-block;
        }

        @media (max-width: 768px) {
            .container {
                grid-template-columns: 1fr;
                padding: 1rem;
            }
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 Scaling to Your First Million Users - Interactive Demo</h1>
    </div>

    <div class="container">
        <div class="metrics-panel">
            <h2 class="panel-title">📊 System Metrics</h2>
            
            <div class="metric-card">
                <div class="metric-value" id="userCount">1</div>
                <div class="metric-label">Active Users</div>
            </div>

            <div class="metric-card">
                <div class="metric-value" id="responseTime">150ms</div>
                <div class="metric-label">Response Time (P95)</div>
            </div>

            <div class="metric-card">
                <div class="metric-value" id="throughput">10</div>
                <div class="metric-label">Requests/Second</div>
            </div>

            <div class="metric-card">
                <div class="metric-value" id="errorRate">0.1%</div>
                <div class="metric-label">Error Rate</div>
            </div>

            <div class="progress-bar">
                <div class="progress-fill" id="capacityProgress" style="width: 5%"></div>
            </div>
            <div style="text-align: center; font-size: 0.9rem; color: #666;">System Capacity Utilization</div>
        </div>

        <div class="architecture-panel">
            <h2 class="panel-title">🏗️ Architecture Evolution</h2>
            
            <div class="architecture-stage active" data-stage="1">
                <div class="stage-title">Stage 1: Single Server (1-1K users)</div>
                <div class="stage-description">Everything on one machine. Simple, fast to develop, perfect for getting started.</div>
                <div class="architecture-visual">
                    <span class="component">Web Server + Database</span>
                </div>
            </div>

            <div class="architecture-stage" data-stage="2">
                <div class="stage-title">Stage 2: Separate Database (1K-10K users)</div>
                <div class="stage-description">Separate concerns for better resource utilization and failure isolation.</div>
                <div class="architecture-visual">
                    <span class="component">Web Server</span>
                    <span class="component">Database</span>
                </div>
            </div>

            <div class="architecture-stage" data-stage="3">
                <div class="stage-title">Stage 3: Load Balancer (10K-100K users)</div>
                <div class="stage-description">Horizontal scaling with multiple application servers.</div>
                <div class="architecture-visual">
                    <span class="component">Load Balancer</span>
                    <span class="component">App Server 1</span>
                    <span class="component">App Server 2</span>
                    <span class="component">Database</span>
                </div>
            </div>

            <div class="architecture-stage" data-stage="4">
                <div class="stage-title">Stage 4: Caching & CDN (100K-500K users)</div>
                <div class="stage-description">Add caching layers and content delivery for performance.</div>
                <div class="architecture-visual">
                    <span class="component">CDN</span>
                    <span class="component">Load Balancer</span>
                    <span class="component">Cache</span>
                    <span class="component">App Servers</span>
                    <span class="component">DB + Replicas</span>
                </div>
            </div>

            <div class="architecture-stage" data-stage="5">
                <div class="stage-title">Stage 5: Microservices (500K+ users)</div>
                <div class="stage-description">Service decomposition for team autonomy and fault isolation.</div>
                <div class="architecture-visual">
                    <span class="component">API Gateway</span>
                    <span class="component">User Service</span>
                    <span class="component">Order Service</span>
                    <span class="component">Payment Service</span>
                    <span class="component">Message Queue</span>
                </div>
            </div>
        </div>

        <div class="controls">
            <h2 class="panel-title">🎮 Load Testing Controls</h2>
            
            <div class="alert" id="scalingAlert">
                <strong>Scaling Decision Required!</strong> <span id="alertMessage"></span>
            </div>

            <div>
                <button class="btn" onclick="startLoadTest()">🚀 Start Load Test</button>
                <button class="btn" onclick="triggerTrafficSpike()">⚡ Traffic Spike</button>
                <button class="btn" onclick="scaleUp()">📈 Scale Up</button>
                <button class="btn" onclick="resetDemo()">🔄 Reset Demo</button>
            </div>

            <div style="margin-top: 2rem; padding: 1.5rem; background: #f8f9fa; border-radius: 8px;">
                <h3 style="color: #1976d2; margin-bottom: 1rem;">💡 Current Insight</h3>
                <p id="currentInsight">Start with a simple architecture. Premature optimization is the root of all evil in startups.</p>
            </div>
        </div>
    </div>

    <script>
        // API base URL
        const API_BASE = '';
        
        // Load metrics on page load and periodically
        function loadMetrics() {
            fetch('/api/metrics')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('userCount').textContent = data.user_count.toLocaleString();
                    document.getElementById('responseTime').textContent = data.response_time + 'ms';
                    document.getElementById('throughput').textContent = data.throughput.toLocaleString();
                    document.getElementById('errorRate').textContent = data.error_rate + '%';
                    document.getElementById('capacityProgress').style.width = data.capacity_utilization + '%';
                    
                    updateArchitectureStage(data.current_stage);
                })
                .catch(error => console.error('Error loading metrics:', error));
        }

        function updateArchitectureStage(stage) {
            document.querySelectorAll('.architecture-stage').forEach(el => {
                el.classList.remove('active');
            });
            
            const activeStage = document.querySelector(`[data-stage="${stage}"]`);
            if (activeStage) {
                activeStage.classList.add('active');
            }
        }

        function startLoadTest() {
            fetch('/api/load-test/start', { method: 'POST' })
                .then(response => response.json())
                .then(data => {
                    console.log('Load test started:', data);
                })
                .catch(error => console.error('Error starting load test:', error));
        }

        function triggerTrafficSpike() {
            fetch('/api/traffic-spike', { method: 'POST' })
                .then(response => response.json())
                .then(data => {
                    console.log('Traffic spike triggered:', data);
                    loadMetrics();
                })
                .catch(error => console.error('Error triggering traffic spike:', error));
        }

        function scaleUp() {
            fetch('/api/scale-up', { method: 'POST' })
                .then(response => response.json())
                .then(data => {
                    console.log('Scaled up:', data);
                    loadMetrics();
                    updateInsight(data.new_stage);
                })
                .catch(error => console.error('Error scaling up:', error));
        }

        function resetDemo() {
            fetch('/api/reset', { method: 'POST' })
                .then(response => response.json())
                .then(data => {
                    console.log('Demo reset:', data);
                    loadMetrics();
                    document.getElementById('currentInsight').textContent = 
                        'Start with a simple architecture. Premature optimization is the root of all evil in startups.';
                })
                .catch(error => console.error('Error resetting demo:', error));
        }

        function updateInsight(stage) {
            const insights = {
                1: "Start with a simple architecture. Premature optimization is the root of all evil in startups.",
                2: "Separate your database when resource contention becomes an issue. This provides failure isolation.",
                3: "Horizontal scaling requires stateless applications. Session management becomes crucial here.",
                4: "Caching solves read-heavy workloads. But cache invalidation is one of the hardest problems in CS.",
                5: "Microservices solve organizational problems as much as technical ones. Conway's Law applies."
            };
            
            document.getElementById('currentInsight').textContent = insights[stage] || insights[1];
        }

        // Load metrics every 2 seconds
        setInterval(loadMetrics, 2000);
        
        // Initial load
        loadMetrics();
    </script>
</body>
</html>
EOF

# Create Dockerfile
echo "🐳 Creating Dockerfile..."
cat > docker/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY backend/ ./backend/
COPY frontend/ ./frontend/

# Expose port
EXPOSE 5000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:5000/api/health || exit 1

# Run the application
CMD ["python", "backend/app.py"]
EOF

# Create docker-compose.yml
echo "🐳 Creating docker-compose.yml..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  scaling-demo:
    build:
      context: .
      dockerfile: docker/Dockerfile
    ports:
      - "5000:5000"
    environment:
      - FLASK_ENV=production
      - PORT=5000
    volumes:
      - ./backend:/app/backend
      - ./frontend:/app/frontend
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

# Create test file
echo "🧪 Creating tests..."
cat > tests/test_app.py << 'EOF'
import pytest
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'backend'))

from app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_health_check(client):
    """Test health check endpoint"""
    response = client.get('/api/health')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'healthy'

def test_metrics_endpoint(client):
    """Test metrics endpoint"""
    response = client.get('/api/metrics')
    assert response.status_code == 200
    data = response.get_json()
    assert 'user_count' in data
    assert 'response_time' in data
    assert 'throughput' in data
    assert 'error_rate' in data

def test_architecture_endpoint(client):
    """Test architecture endpoint"""
    response = client.get('/api/architecture')
    assert response.status_code == 200
    data = response.get_json()
    assert 'current_stage' in data
    assert 'stage_info' in data

def test_scale_up(client):
    """Test scale up functionality"""
    response = client.post('/api/scale-up')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'Scaled up successfully'

def test_reset_demo(client):
    """Test demo reset"""
    response = client.post('/api/reset')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'Demo reset successfully'

def test_traffic_spike(client):
    """Test traffic spike simulation"""
    response = client.post('/api/traffic-spike')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'Traffic spike triggered'
EOF

# Create run script
echo "🏃 Creating run script..."
cat > run.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting Scaling Demo..."

# Check if running in Docker
if [ -f /.dockerenv ]; then
    echo "Running in Docker container"
    python backend/app.py
else
    echo "Running locally"
    # Install dependencies if needed
    if [ ! -d "venv" ]; then
        echo "Creating virtual environment..."
        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt
    else
        source venv/bin/activate
    fi
    
    # Run the application
    python backend/app.py
fi
EOF

chmod +x run.sh

# Create documentation
echo "📚 Creating documentation..."
cat > docs/README.md << 'EOF'
# Scaling to 1M Users - Interactive Demo

This demo simulates the journey of scaling a web application from 1 user to 1 million users, showing the architectural decisions and trade-offs at each stage.

## Architecture Stages

1. **Single Server (1-1K users)**: Everything on one machine
2. **Separate Database (1K-10K users)**: Database isolation
3. **Load Balanced (10K-100K users)**: Horizontal scaling
4. **Caching & CDN (100K-500K users)**: Performance optimization
5. **Microservices (500K+ users)**: Service decomposition

## Features

- Real-time metrics simulation
- Interactive load testing
- Architecture visualization
- Performance impact demonstration
- Scaling decision triggers

## API Endpoints

- `GET /api/metrics` - Current system metrics
- `GET /api/architecture` - Architecture information
- `POST /api/load-test/start` - Start load test
- `POST /api/traffic-spike` - Trigger traffic spike
- `POST /api/scale-up` - Scale to next stage
- `POST /api/reset` - Reset demo

## Learning Objectives

- Understand scaling triggers and decisions
- Experience performance degradation patterns
- Learn about capacity planning
- See the evolution of system architecture
- Understand trade-offs at each stage
EOF

echo "✅ Demo setup complete!"
echo ""
echo "📁 Project structure created in ./scaling-demo/"
echo "🚀 To start the demo:"
echo "   cd scaling-demo"
echo "   ./run.sh"
echo ""
echo "🐳 Or with Docker:"
echo "   cd scaling-demo"
echo "   docker-compose up --build"
echo ""
echo "🌐 Access the demo at: http://localhost:5000"
echo "🧪 Run tests with: cd scaling-demo && python -m pytest tests/"
echo ""
echo "🎯 Try these scenarios:"
echo "   1. Start a load test and watch metrics change"
echo "   2. Trigger traffic spikes to see performance impact"
echo "   3. Scale up when the system struggles"
echo "   4. Reset and try different scaling strategies"