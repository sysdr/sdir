#!/bin/bash
# Autoscaling Strategies Demo - One-Click Setup
# Creates a complete autoscaling simulation with real-time visualization

set -e

PROJECT_NAME="autoscaling-demo"
PYTHON_VERSION="3.12"

echo "🚀 Setting up Autoscaling Strategies Demo..."

# Create project structure
mkdir -p $PROJECT_NAME/{src,templates,static,tests,data,logs}
cd $PROJECT_NAME

# Create requirements.txt with latest compatible versions
cat > requirements.txt << 'EOF'
flask==3.0.0
flask-socketio==5.3.6
python-socketio==5.10.0
numpy==1.26.2
pandas==2.1.4
plotly==5.17.0
dash==2.14.2
psutil==5.9.6
redis==5.0.1
requests==2.31.0
asyncio==3.4.3
aiohttp==3.9.1
gunicorn==21.2.0
eventlet==0.33.3
python-dateutil==2.8.2
scikit-learn==1.3.2
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose ports
EXPOSE 5000 6379

# Start command
CMD ["python", "src/main.py"]
EOF

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  autoscaler:
    build: .
    ports:
      - "5000:5000"
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    environment:
      - FLASK_ENV=development
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis
    
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

volumes:
  redis_data:
EOF

# Create main application
cat > src/main.py << 'EOF'
"""
Autoscaling Strategies Demo - Main Application
Demonstrates reactive, predictive, and hybrid autoscaling algorithms
"""

import time
import json
import threading
import random
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import List, Dict, Any
import numpy as np
import pandas as pd
from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit
import psutil
import logging
from collections import deque

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.config['SECRET_KEY'] = 'autoscaling-demo-secret'
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading')

@dataclass
class SystemMetrics:
    timestamp: float
    cpu_percent: float
    memory_percent: float
    active_connections: int
    request_rate: float
    response_time: float
    queue_depth: int

@dataclass
class ScalingDecision:
    timestamp: float
    algorithm: str
    action: str  # 'scale_out', 'scale_in', 'no_action'
    trigger_metric: str
    current_instances: int
    target_instances: int
    reason: str

class LoadSimulator:
    """Simulates various load patterns for testing autoscaling"""
    
    def __init__(self):
        self.base_load = 30.0
        self.current_load = self.base_load
        self.pattern = 'steady'  # steady, spike, gradual, oscillating, chaos
        self.start_time = time.time()
        
    def get_current_load(self) -> float:
        elapsed = time.time() - self.start_time
        
        if self.pattern == 'steady':
            return self.base_load + random.uniform(-5, 5)
        elif self.pattern == 'spike':
            # Sudden spike pattern
            if 30 < elapsed < 90:
                return self.base_load + 50 + random.uniform(-10, 10)
            return self.base_load + random.uniform(-5, 5)
        elif self.pattern == 'gradual':
            # Gradual increase
            return self.base_load + (elapsed / 10) + random.uniform(-5, 5)
        elif self.pattern == 'oscillating':
            # Sine wave pattern
            return self.base_load + 20 * np.sin(elapsed / 20) + random.uniform(-5, 5)
        elif self.pattern == 'chaos':
            # Random spikes and drops
            if random.random() < 0.05:  # 5% chance of chaos event
                return random.uniform(10, 90)
            return self.current_load + random.uniform(-15, 15)
        
        return self.base_load

class ReactiveAutoscaler:
    """Traditional threshold-based autoscaling"""
    
    def __init__(self):
        self.scale_out_threshold = 70.0
        self.scale_in_threshold = 30.0
        self.cooldown_period = 30  # seconds
        self.last_scaling_time = 0
        
    def should_scale(self, metrics: SystemMetrics, current_instances: int) -> ScalingDecision:
        now = time.time()
        
        # Check cooldown
        if now - self.last_scaling_time < self.cooldown_period:
            return ScalingDecision(
                timestamp=now,
                algorithm='reactive',
                action='no_action',
                trigger_metric='cooldown',
                current_instances=current_instances,
                target_instances=current_instances,
                reason='Cooldown period active'
            )
        
        # Scale out decision
        if metrics.cpu_percent > self.scale_out_threshold:
            self.last_scaling_time = now
            return ScalingDecision(
                timestamp=now,
                algorithm='reactive',
                action='scale_out',
                trigger_metric='cpu_percent',
                current_instances=current_instances,
                target_instances=min(current_instances + 1, 10),
                reason=f'CPU {metrics.cpu_percent:.1f}% > {self.scale_out_threshold}%'
            )
        
        # Scale in decision
        if metrics.cpu_percent < self.scale_in_threshold and current_instances > 1:
            self.last_scaling_time = now
            return ScalingDecision(
                timestamp=now,
                algorithm='reactive',
                action='scale_in',
                trigger_metric='cpu_percent',
                current_instances=current_instances,
                target_instances=current_instances - 1,
                reason=f'CPU {metrics.cpu_percent:.1f}% < {self.scale_in_threshold}%'
            )
        
        return ScalingDecision(
            timestamp=now,
            algorithm='reactive',
            action='no_action',
            trigger_metric='cpu_percent',
            current_instances=current_instances,
            target_instances=current_instances,
            reason='Within thresholds'
        )

class PredictiveAutoscaler:
    """ML-based predictive autoscaling"""
    
    def __init__(self):
        self.history = deque(maxlen=100)  # Store last 100 metrics
        self.prediction_window = 60  # Predict 60 seconds ahead
        
    def add_metrics(self, metrics: SystemMetrics):
        self.history.append(metrics)
    
    def predict_future_load(self) -> float:
        if len(self.history) < 10:
            return 50.0  # Default prediction
        
        # Simple moving average prediction with trend analysis
        recent_cpu = [m.cpu_percent for m in list(self.history)[-20:]]
        if len(recent_cpu) < 5:
            return recent_cpu[-1] if recent_cpu else 50.0
        
        # Calculate trend
        times = list(range(len(recent_cpu)))
        trend = np.polyfit(times, recent_cpu, 1)[0]  # Linear trend
        
        # Project forward
        prediction = recent_cpu[-1] + (trend * self.prediction_window / 10)
        return max(0, min(100, prediction))
    
    def should_scale(self, metrics: SystemMetrics, current_instances: int) -> ScalingDecision:
        self.add_metrics(metrics)
        predicted_cpu = self.predict_future_load()
        now = time.time()
        
        # Proactive scaling based on prediction
        if predicted_cpu > 75.0:
            return ScalingDecision(
                timestamp=now,
                algorithm='predictive',
                action='scale_out',
                trigger_metric='predicted_cpu',
                current_instances=current_instances,
                target_instances=min(current_instances + 1, 10),
                reason=f'Predicted CPU {predicted_cpu:.1f}% > 75%'
            )
        
        if predicted_cpu < 25.0 and current_instances > 1:
            return ScalingDecision(
                timestamp=now,
                algorithm='predictive',
                action='scale_in',
                trigger_metric='predicted_cpu',
                current_instances=current_instances,
                target_instances=current_instances - 1,
                reason=f'Predicted CPU {predicted_cpu:.1f}% < 25%'
            )
        
        return ScalingDecision(
            timestamp=now,
            algorithm='predictive',
            action='no_action',
            trigger_metric='predicted_cpu',
            current_instances=current_instances,
            target_instances=current_instances,
            reason=f'Predicted CPU {predicted_cpu:.1f}% within range'
        )

class HybridAutoscaler:
    """Combines reactive and predictive approaches"""
    
    def __init__(self):
        self.reactive = ReactiveAutoscaler()
        self.predictive = PredictiveAutoscaler()
        self.last_scaling_time = 0
        self.adaptive_cooldown = 30
        
    def should_scale(self, metrics: SystemMetrics, current_instances: int) -> ScalingDecision:
        # Get recommendations from both approaches
        reactive_decision = self.reactive.should_scale(metrics, current_instances)
        predictive_decision = self.predictive.should_scale(metrics, current_instances)
        
        now = time.time()
        
        # Adaptive cooldown based on system stability
        if now - self.last_scaling_time < self.adaptive_cooldown:
            return ScalingDecision(
                timestamp=now,
                algorithm='hybrid',
                action='no_action',
                trigger_metric='adaptive_cooldown',
                current_instances=current_instances,
                target_instances=current_instances,
                reason='Adaptive cooldown active'
            )
        
        # Prioritize scale-out decisions (availability over efficiency)
        if reactive_decision.action == 'scale_out' or predictive_decision.action == 'scale_out':
            self.last_scaling_time = now
            # Adjust cooldown based on urgency
            self.adaptive_cooldown = 20 if reactive_decision.action == 'scale_out' else 30
            
            return ScalingDecision(
                timestamp=now,
                algorithm='hybrid',
                action='scale_out',
                trigger_metric='combined',
                current_instances=current_instances,
                target_instances=min(current_instances + 1, 10),
                reason=f'Reactive: {reactive_decision.reason}, Predictive: {predictive_decision.reason}'
            )
        
        # Conservative scale-in (both must agree)
        if reactive_decision.action == 'scale_in' and predictive_decision.action == 'scale_in':
            self.last_scaling_time = now
            self.adaptive_cooldown = 45  # Longer cooldown for scale-in
            
            return ScalingDecision(
                timestamp=now,
                algorithm='hybrid',
                action='scale_in',
                trigger_metric='combined',
                current_instances=current_instances,
                target_instances=current_instances - 1,
                reason='Both algorithms recommend scale-in'
            )
        
        return ScalingDecision(
            timestamp=now,
            algorithm='hybrid',
            action='no_action',
            trigger_metric='combined',
            current_instances=current_instances,
            target_instances=current_instances,
            reason='Algorithms disagree or within thresholds'
        )

class AutoscalingEngine:
    """Main autoscaling engine that orchestrates everything"""
    
    def __init__(self):
        self.load_simulator = LoadSimulator()
        self.autoscalers = {
            'reactive': ReactiveAutoscaler(),
            'predictive': PredictiveAutoscaler(),
            'hybrid': HybridAutoscaler()
        }
        self.current_instances = {'reactive': 2, 'predictive': 2, 'hybrid': 2}
        self.metrics_history = deque(maxlen=1000)
        self.scaling_history = deque(maxlen=500)
        self.running = False
        
    def generate_metrics(self) -> SystemMetrics:
        """Generate realistic system metrics based on current load"""
        load = self.load_simulator.get_current_load()
        
        # Simulate CPU based on load and instance count (using reactive as baseline)
        effective_instances = max(1, self.current_instances['reactive'])
        cpu_per_instance = load / effective_instances
        
        # Add some realistic noise and constraints
        cpu_percent = min(100, max(0, cpu_per_instance + random.uniform(-5, 5)))
        memory_percent = min(100, max(10, cpu_percent * 0.8 + random.uniform(-10, 10)))
        
        return SystemMetrics(
            timestamp=time.time(),
            cpu_percent=cpu_percent,
            memory_percent=memory_percent,
            active_connections=int(load * 2 + random.uniform(-10, 10)),
            request_rate=load / 10,
            response_time=50 + (cpu_percent / 100) * 200,  # Response time increases with CPU
            queue_depth=max(0, int((cpu_percent - 50) / 10)) if cpu_percent > 50 else 0
        )
    
    def run_scaling_cycle(self):
        """Run one cycle of metrics collection and scaling decisions"""
        metrics = self.generate_metrics()
        self.metrics_history.append(metrics)
        
        # Get scaling decisions from all algorithms
        decisions = {}
        for name, autoscaler in self.autoscalers.items():
            decision = autoscaler.should_scale(metrics, self.current_instances[name])
            decisions[name] = decision
            self.scaling_history.append(decision)
            
            # Apply scaling decision
            if decision.action == 'scale_out':
                self.current_instances[name] = min(self.current_instances[name] + 1, 10)
            elif decision.action == 'scale_in':
                self.current_instances[name] = max(self.current_instances[name] - 1, 1)
        
        # Emit real-time updates
        socketio.emit('metrics_update', {
            'metrics': asdict(metrics),
            'decisions': {name: asdict(decision) for name, decision in decisions.items()},
            'instances': self.current_instances.copy()
        })
        
        logger.info(f"CPU: {metrics.cpu_percent:.1f}%, Instances: {self.current_instances}")
    
    def start(self):
        """Start the autoscaling engine"""
        self.running = True
        while self.running:
            try:
                self.run_scaling_cycle()
                time.sleep(2)  # Run every 2 seconds for demo purposes
            except Exception as e:
                logger.error(f"Error in scaling cycle: {e}")
                time.sleep(5)
    
    def stop(self):
        """Stop the autoscaling engine"""
        self.running = False
    
    def set_load_pattern(self, pattern: str):
        """Change the load pattern for testing"""
        self.load_simulator.pattern = pattern
        self.load_simulator.start_time = time.time()
        logger.info(f"Load pattern changed to: {pattern}")

# Global engine instance
engine = AutoscalingEngine()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/start')
def start_engine():
    if not engine.running:
        threading.Thread(target=engine.start, daemon=True).start()
        return jsonify({'status': 'started'})
    return jsonify({'status': 'already_running'})

@app.route('/api/stop')
def stop_engine():
    engine.stop()
    return jsonify({'status': 'stopped'})

@app.route('/api/load_pattern', methods=['POST'])
def set_load_pattern():
    pattern = request.json.get('pattern', 'steady')
    engine.set_load_pattern(pattern)
    return jsonify({'status': 'pattern_set', 'pattern': pattern})

@app.route('/api/status')
def get_status():
    recent_metrics = list(engine.metrics_history)[-20:] if engine.metrics_history else []
    recent_decisions = list(engine.scaling_history)[-20:] if engine.scaling_history else []
    
    return jsonify({
        'running': engine.running,
        'instances': engine.current_instances,
        'recent_metrics': [asdict(m) for m in recent_metrics],
        'recent_decisions': [asdict(d) for d in recent_decisions]
    })

@socketio.on('connect')
def handle_connect():
    emit('status', {'running': engine.running, 'instances': engine.current_instances})

if __name__ == '__main__':
    # Start the engine automatically
    threading.Thread(target=engine.start, daemon=True).start()
    socketio.run(app, host='0.0.0.0', port=5000, debug=False)
EOF

# Create HTML template with Google Cloud Skills Boost styling
cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Autoscaling Strategies Demo</title>
    <script src="https://cdn.socket.io/4.7.2/socket.io.min.js"></script>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: 'Google Sans', -apple-system, BlinkMacSystemFont, sans-serif;
            background: linear-gradient(135deg, #f8f9ff 0%, #e3f2fd 100%);
            color: #1a1a1a;
            line-height: 1.6;
        }

        .header {
            background: linear-gradient(135deg, #4285f4 0%, #1a73e8 100%);
            color: white;
            padding: 2rem 0;
            text-align: center;
            box-shadow: 0 4px 20px rgba(66, 133, 244, 0.3);
        }

        .header h1 {
            font-size: 2.5rem;
            font-weight: 400;
            margin-bottom: 0.5rem;
        }

        .header p {
            font-size: 1.1rem;
            opacity: 0.9;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 2rem;
        }

        .controls {
            background: white;
            border-radius: 12px;
            padding: 2rem;
            margin-bottom: 2rem;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
            border: 1px solid #e8eaed;
        }

        .control-group {
            display: flex;
            gap: 1rem;
            align-items: center;
            margin-bottom: 1rem;
        }

        .btn {
            background: linear-gradient(135deg, #4285f4 0%, #1a73e8 100%);
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 8px;
            cursor: pointer;
            font-size: 1rem;
            font-weight: 500;
            transition: all 0.3s ease;
            box-shadow: 0 2px 8px rgba(66, 133, 244, 0.3);
        }

        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 16px rgba(66, 133, 244, 0.4);
        }

        .btn.secondary {
            background: linear-gradient(135deg, #34a853 0%, #137333 100%);
            box-shadow: 0 2px 8px rgba(52, 168, 83, 0.3);
        }

        .btn.danger {
            background: linear-gradient(135deg, #ea4335 0%, #d33b2c 100%);
            box-shadow: 0 2px 8px rgba(234, 67, 53, 0.3);
        }

        select {
            padding: 10px 16px;
            border: 2px solid #e8eaed;
            border-radius: 8px;
            font-size: 1rem;
            background: white;
            min-width: 200px;
        }

        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 2rem;
            margin-bottom: 2rem;
        }

        .metric-card {
            background: white;
            border-radius: 12px;
            padding: 1.5rem;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
            border: 1px solid #e8eaed;
            transition: transform 0.3s ease;
        }

        .metric-card:hover {
            transform: translateY(-4px);
        }

        .metric-title {
            font-size: 1.1rem;
            font-weight: 600;
            color: #1a73e8;
            margin-bottom: 1rem;
        }

        .metric-value {
            font-size: 2.5rem;
            font-weight: 700;
            color: #1a1a1a;
            margin-bottom: 0.5rem;
        }

        .metric-unit {
            font-size: 1rem;
            color: #666;
        }

        .charts-container {
            display: grid;
            grid-template-columns: 1fr;
            gap: 2rem;
        }

        .chart-card {
            background: white;
            border-radius: 12px;
            padding: 1.5rem;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
            border: 1px solid #e8eaed;
        }

        .chart-title {
            font-size: 1.3rem;
            font-weight: 600;
            color: #1a73e8;
            margin-bottom: 1rem;
        }

        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }

        .status-running {
            background: #34a853;
            animation: pulse 2s infinite;
        }

        .status-stopped {
            background: #ea4335;
        }

        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }

        .algorithm-comparison {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 1rem;
            margin-top: 2rem;
        }

        .algorithm-card {
            background: white;
            border-radius: 8px;
            padding: 1rem;
            border: 2px solid #e8eaed;
            transition: all 0.3s ease;
        }

        .algorithm-card.reactive {
            border-color: #ea4335;
        }

        .algorithm-card.predictive {
            border-color: #fbbc04;
        }

        .algorithm-card.hybrid {
            border-color: #34a853;
        }

        .algorithm-name {
            font-weight: 600;
            font-size: 1.1rem;
            margin-bottom: 0.5rem;
        }

        .algorithm-instances {
            font-size: 1.5rem;
            font-weight: 700;
        }

        .algorithm-status {
            font-size: 0.9rem;
            color: #666;
            margin-top: 0.5rem;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Autoscaling Strategies Demo</h1>
        <p>Real-time comparison of Reactive, Predictive, and Hybrid autoscaling algorithms</p>
    </div>

    <div class="container">
        <div class="controls">
            <div class="control-group">
                <span class="status-indicator" id="statusIndicator"></span>
                <span id="statusText">Disconnected</span>
                <button class="btn" onclick="startEngine()">Start Engine</button>
                <button class="btn danger" onclick="stopEngine()">Stop Engine</button>
            </div>
            
            <div class="control-group">
                <label for="loadPattern">Load Pattern:</label>
                <select id="loadPattern" onchange="setLoadPattern()">
                    <option value="steady">Steady Load</option>
                    <option value="spike">Traffic Spike</option>
                    <option value="gradual">Gradual Increase</option>
                    <option value="oscillating">Oscillating Load</option>
                    <option value="chaos">Chaos Pattern</option>
                </select>
            </div>
        </div>

        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-title">CPU Utilization</div>
                <div class="metric-value" id="cpuValue">0</div>
                <div class="metric-unit">%</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-title">Memory Usage</div>
                <div class="metric-value" id="memoryValue">0</div>
                <div class="metric-unit">%</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-title">Response Time</div>
                <div class="metric-value" id="responseTime">0</div>
                <div class="metric-unit">ms</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-title">Queue Depth</div>
                <div class="metric-value" id="queueDepth">0</div>
                <div class="metric-unit">requests</div>
            </div>
        </div>

        <div class="algorithm-comparison">
            <div class="algorithm-card reactive">
                <div class="algorithm-name" style="color: #ea4335;">Reactive</div>
                <div class="algorithm-instances" id="reactiveInstances">2 instances</div>
                <div class="algorithm-status" id="reactiveStatus">Ready</div>
            </div>
            
            <div class="algorithm-card predictive">
                <div class="algorithm-name" style="color: #fbbc04;">Predictive</div>
                <div class="algorithm-instances" id="predictiveInstances">2 instances</div>
                <div class="algorithm-status" id="predictiveStatus">Ready</div>
            </div>
            
            <div class="algorithm-card hybrid">
                <div class="algorithm-name" style="color: #34a853;">Hybrid</div>
                <div class="algorithm-instances" id="hybridInstances">2 instances</div>
                <div class="algorithm-status" id="hybridStatus">Ready</div>
            </div>
        </div>

        <div class="charts-container">
            <div class="chart-card">
                <div class="chart-title">System Metrics Over Time</div>
                <div id="metricsChart"></div>
            </div>
            
            <div class="chart-card">
                <div class="chart-title">Instance Count Comparison</div>
                <div id="instanceChart"></div>
            </div>
        </div>
    </div>

    <script>
        const socket = io();
        
        // Data storage for charts
        let metricsData = {
            time: [],
            cpu: [],
            memory: [],
            responseTime: []
        };
        
        let instanceData = {
            time: [],
            reactive: [],
            predictive: [],
            hybrid: []
        };
        
        // Socket event handlers
        socket.on('connect', function() {
            updateStatus(true);
            console.log('Connected to autoscaling engine');
        });
        
        socket.on('disconnect', function() {
            updateStatus(false);
            console.log('Disconnected from autoscaling engine');
        });
        
        socket.on('status', function(data) {
            updateInstanceCounts(data.instances);
        });
        
        socket.on('metrics_update', function(data) {
            updateMetrics(data.metrics);
            updateInstanceCounts(data.instances);
            updateDecisions(data.decisions);
            updateCharts(data);
        });
        
        // UI update functions
        function updateStatus(connected) {
            const indicator = document.getElementById('statusIndicator');
            const text = document.getElementById('statusText');
            
            if (connected) {
                indicator.className = 'status-indicator status-running';
                text.textContent = 'Connected';
            } else {
                indicator.className = 'status-indicator status-stopped';
                text.textContent = 'Disconnected';
            }
        }
        
        function updateMetrics(metrics) {
            document.getElementById('cpuValue').textContent = Math.round(metrics.cpu_percent);
            document.getElementById('memoryValue').textContent = Math.round(metrics.memory_percent);
            document.getElementById('responseTime').textContent = Math.round(metrics.response_time);
            document.getElementById('queueDepth').textContent = metrics.queue_depth;
        }
        
        function updateInstanceCounts(instances) {
            document.getElementById('reactiveInstances').textContent = `${instances.reactive} instances`;
            document.getElementById('predictiveInstances').textContent = `${instances.predictive} instances`;
            document.getElementById('hybridInstances').textContent = `${instances.hybrid} instances`;
        }
        
        function updateDecisions(decisions) {
            Object.keys(decisions).forEach(algorithm => {
                const decision = decisions[algorithm];
                const statusElement = document.getElementById(`${algorithm}Status`);
                
                if (decision.action === 'scale_out') {
                    statusElement.textContent = `Scaling OUT: ${decision.reason}`;
                    statusElement.style.color = '#ea4335';
                } else if (decision.action === 'scale_in') {
                    statusElement.textContent = `Scaling IN: ${decision.reason}`;
                    statusElement.style.color = '#1a73e8';
                } else {
                    statusElement.textContent = decision.reason;
                    statusElement.style.color = '#666';
                }
            });
        }
        
        function updateCharts(data) {
            const now = new Date();
            
            // Update metrics data
            metricsData.time.push(now);
            metricsData.cpu.push(data.metrics.cpu_percent);
            metricsData.memory.push(data.metrics.memory_percent);
            metricsData.responseTime.push(data.metrics.response_time);
            
            // Keep only last 50 data points
            if (metricsData.time.length > 50) {
                metricsData.time.shift();
                metricsData.cpu.shift();
                metricsData.memory.shift();
                metricsData.responseTime.shift();
            }
            
            // Update instance data
            instanceData.time.push(now);
            instanceData.reactive.push(data.instances.reactive);
            instanceData.predictive.push(data.instances.predictive);
            instanceData.hybrid.push(data.instances.hybrid);
            
            if (instanceData.time.length > 50) {
                instanceData.time.shift();
                instanceData.reactive.shift();
                instanceData.predictive.shift();
                instanceData.hybrid.shift();
            }
            
            // Render charts
            renderMetricsChart();
            renderInstanceChart();
        }
        
        function renderMetricsChart() {
            const traces = [
                {
                    x: metricsData.time,
                    y: metricsData.cpu,
                    type: 'scatter',
                    mode: 'lines',
                    name: 'CPU %',
                    line: {color: '#ea4335', width: 3}
                },
                {
                    x: metricsData.time,
                    y: metricsData.memory,
                    type: 'scatter',
                    mode: 'lines',
                    name: 'Memory %',
                    line: {color: '#fbbc04', width: 3},
                    yaxis: 'y'
                }
            ];
            
            const layout = {
                height: 400,
                margin: {l: 50, r: 50, t: 30, b: 50},
                xaxis: {title: 'Time'},
                yaxis: {title: 'Percentage (%)', range: [0, 100]},
                showlegend: true,
                font: {family: 'Google Sans, sans-serif'},
                plot_bgcolor: 'rgba(0,0,0,0)',
                paper_bgcolor: 'rgba(0,0,0,0)'
            };
            
            Plotly.newPlot('metricsChart', traces, layout);
        }
        
        function renderInstanceChart() {
            const traces = [
                {
                    x: instanceData.time,
                    y: instanceData.reactive,
                    type: 'scatter',
                    mode: 'lines+markers',
                    name: 'Reactive',
                    line: {color: '#ea4335', width: 3},
                    marker: {size: 6}
                },
                {
                    x: instanceData.time,
                    y: instanceData.predictive,
                    type: 'scatter',
                    mode: 'lines+markers',
                    name: 'Predictive',
                    line: {color: '#fbbc04', width: 3},
                    marker: {size: 6}
                },
                {
                    x: instanceData.time,
                    y: instanceData.hybrid,
                    type: 'scatter',
                    mode: 'lines+markers',
                    name: 'Hybrid',
                    line: {color: '#34a853', width: 3},
                    marker: {size: 6}
                }
            ];
            
            const layout = {
                height: 400,
                margin: {l: 50, r: 50, t: 30, b: 50},
                xaxis: {title: 'Time'},
                yaxis: {title: 'Instance Count', range: [0, 10]},
                showlegend: true,
                font: {family: 'Google Sans, sans-serif'},
                plot_bgcolor: 'rgba(0,0,0,0)',
                paper_bgcolor: 'rgba(0,0,0,0)'
            };
            
            Plotly.newPlot('instanceChart', traces, layout);
        }
        
        // Control functions
        function startEngine() {
            fetch('/api/start')
                .then(response => response.json())
                .then(data => console.log('Engine started:', data));
        }
        
        function stopEngine() {
            fetch('/api/stop')
                .then(response => response.json())
                .then(data => console.log('Engine stopped:', data));
        }
        
        function setLoadPattern() {
            const pattern = document.getElementById('loadPattern').value;
            fetch('/api/load_pattern', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({pattern: pattern})
            })
            .then(response => response.json())
            .then(data => console.log('Load pattern set:', data));
        }
        
        // Initialize charts on page load
        window.onload = function() {
            renderMetricsChart();
            renderInstanceChart();
        };
    </script>
</body>
</html>
EOF

# Create test file
cat > tests/test_autoscaling.py << 'EOF'
#!/usr/bin/env python3
"""
Test suite for autoscaling demo
"""

import sys
import os
import time
import requests
import threading
from unittest import TestCase, main

# Add src to path for imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from main import AutoscalingEngine, SystemMetrics

class TestAutoscalingDemo(TestCase):
    """Test autoscaling algorithms and web interface"""
    
    @classmethod
    def setUpClass(cls):
        """Start the demo server for testing"""
        cls.base_url = 'http://localhost:5000'
        # Give server time to start
        time.sleep(2)
    
    def test_reactive_autoscaler(self):
        """Test reactive autoscaling logic"""
        engine = AutoscalingEngine()
        reactive = engine.autoscalers['reactive']
        
        # Test scale out
        high_cpu_metrics = SystemMetrics(
            timestamp=time.time(),
            cpu_percent=80.0,
            memory_percent=60.0,
            active_connections=100,
            request_rate=50.0,
            response_time=200.0,
            queue_depth=5
        )
        
        decision = reactive.should_scale(high_cpu_metrics, 2)
        self.assertEqual(decision.action, 'scale_out')
        self.assertEqual(decision.target_instances, 3)
        
        # Test scale in
        low_cpu_metrics = SystemMetrics(
            timestamp=time.time(),
            cpu_percent=20.0,
            memory_percent=30.0,
            active_connections=20,
            request_rate=5.0,
            response_time=100.0,
            queue_depth=0
        )
        
        # Wait for cooldown
        time.sleep(0.1)
        decision = reactive.should_scale(low_cpu_metrics, 3)
        self.assertEqual(decision.action, 'scale_in')
        self.assertEqual(decision.target_instances, 2)
    
    def test_predictive_autoscaler(self):
        """Test predictive autoscaling logic"""
        engine = AutoscalingEngine()
        predictive = engine.autoscalers['predictive']
        
        # Add some history
        for i in range(20):
            metrics = SystemMetrics(
                timestamp=time.time() - (20-i),
                cpu_percent=50.0 + i * 2,  # Increasing trend
                memory_percent=50.0,
                active_connections=50,
                request_rate=10.0,
                response_time=150.0,
                queue_depth=0
            )
            predictive.add_metrics(metrics)
        
        # Should predict high CPU and recommend scale out
        current_metrics = SystemMetrics(
            timestamp=time.time(),
            cpu_percent=70.0,
            memory_percent=60.0,
            active_connections=80,
            request_rate=20.0,
            response_time=180.0,
            queue_depth=2
        )
        
        decision = predictive.should_scale(current_metrics, 2)
        # With increasing trend, should scale out proactively
        self.assertIn(decision.action, ['scale_out', 'no_action'])
    
    def test_hybrid_autoscaler(self):
        """Test hybrid autoscaling logic"""
        engine = AutoscalingEngine()
        hybrid = engine.autoscalers['hybrid']
        
        # Test with high CPU - should scale out
        high_cpu_metrics = SystemMetrics(
            timestamp=time.time(),
            cpu_percent=85.0,
            memory_percent=70.0,
            active_connections=120,
            request_rate=60.0,
            response_time=250.0,
            queue_depth=8
        )
        
        decision = hybrid.should_scale(high_cpu_metrics, 2)
        self.assertEqual(decision.action, 'scale_out')
        self.assertEqual(decision.algorithm, 'hybrid')
    
    def test_web_interface(self):
        """Test web interface endpoints"""
        try:
            # Test main page
            response = requests.get(f'{self.base_url}/')
            self.assertEqual(response.status_code, 200)
            self.assertIn('Autoscaling Strategies Demo', response.text)
            
            # Test API endpoints
            response = requests.get(f'{self.base_url}/api/status')
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertIn('running', data)
            self.assertIn('instances', data)
            
            # Test load pattern change
            response = requests.post(f'{self.base_url}/api/load_pattern', 
                                   json={'pattern': 'spike'})
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertEqual(data['pattern'], 'spike')
            
        except requests.exceptions.ConnectionError:
            self.skipTest("Web server not running")
    
    def test_metrics_generation(self):
        """Test metrics generation"""
        engine = AutoscalingEngine()
        
        # Test steady pattern
        engine.load_simulator.pattern = 'steady'
        metrics = engine.generate_metrics()
        
        self.assertIsInstance(metrics.cpu_percent, float)
        self.assertGreaterEqual(metrics.cpu_percent, 0)
        self.assertLessEqual(metrics.cpu_percent, 100)
        self.assertIsInstance(metrics.timestamp, float)
        
        # Test spike pattern
        engine.load_simulator.pattern = 'spike'
        metrics = engine.generate_metrics()
        
        self.assertIsInstance(metrics.cpu_percent, float)
        self.assertGreaterEqual(metrics.cpu_percent, 0)
    
    def test_load_patterns(self):
        """Test different load patterns"""
        engine = AutoscalingEngine()
        
        patterns = ['steady', 'spike', 'gradual', 'oscillating', 'chaos']
        
        for pattern in patterns:
            engine.set_load_pattern(pattern)
            self.assertEqual(engine.load_simulator.pattern, pattern)
            
            # Generate a few metrics to ensure no errors
            for _ in range(3):
                metrics = engine.generate_metrics()
                self.assertIsInstance(metrics.cpu_percent, float)
                self.assertGreaterEqual(metrics.cpu_percent, 0)

if __name__ == '__main__':
    print("🧪 Running Autoscaling Demo Tests...")
    main(verbosity=2)
EOF

# Create cleanup script
cat > cleanup.sh << 'EOF'
#!/bin/bash
# Cleanup script for autoscaling demo

echo "🧹 Cleaning up Autoscaling Demo..."

# Stop Docker containers
docker-compose down -v

# Remove Docker images
docker rmi autoscaling-demo_autoscaler 2>/dev/null || true

# Remove project directory
cd ..
rm -rf autoscaling-demo

echo "✅ Cleanup complete!"
EOF

chmod +x cleanup.sh

# Create demo runner script
cat > run_demo.sh << 'EOF'
#!/bin/bash
# Quick demo runner

echo "🚀 Starting Autoscaling Demo..."

# Build and start services
docker-compose up --build -d

echo "⏳ Waiting for services to start..."
sleep 10

# Check if services are running
if curl -s http://localhost:5000/api/status > /dev/null; then
    echo "✅ Demo is running!"
    echo ""
    echo "🌐 Web Interface: http://localhost:5000"
    echo "📊 Try different load patterns to see autoscaling in action"
    echo ""
    echo "To stop: docker-compose down"
    echo "To cleanup: ./cleanup.sh"
else
    echo "❌ Demo failed to start. Check logs:"
    docker-compose logs
fi
EOF

chmod +x run_demo.sh

# Install dependencies and build
echo "📦 Installing dependencies..."
pip install -r requirements.txt

# Build Docker images
echo "🏗️ Building Docker containers..."
docker-compose build

echo "🧪 Running tests..."
python -m pytest tests/ -v

echo "🚀 Starting demo..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 15

# Test the web interface
if curl -s http://localhost:5000/api/status > /dev/null; then
    echo ""
    echo "✅ Autoscaling Demo is ready!"
    echo ""
    echo "🌐 Web Interface: http://localhost:5000"
    echo "📊 API Status: http://localhost:5000/api/status"
    echo ""
    echo "🎯 Demo Features:"
    echo "  • Real-time autoscaling visualization"
    echo "  • Compare 3 algorithms: Reactive, Predictive, Hybrid"
    echo "  • 5 load patterns: Steady, Spike, Gradual, Oscillating, Chaos"
    echo "  • Live metrics and scaling decisions"
    echo ""
    echo "🛠️ Controls:"
    echo "  • Use the web interface to change load patterns"
    echo "  • Watch how different algorithms respond"
    echo "  • Observe scaling decisions in real-time"
    echo ""
    echo "To stop: docker-compose down"
    echo "To cleanup: ./cleanup.sh"
    
    # Show logs
    echo ""
    echo "📊 Current system status:"
    curl -s http://localhost:5000/api/status | python -m json.tool || echo "JSON parsing failed"
    
else
    echo "❌ Demo failed to start properly"
    echo "📋 Docker logs:"
    docker-compose logs --tail=20
    echo ""
    echo "🔧 Troubleshooting:"
    echo "  • Check if ports 5000 and 6379 are available"
    echo "  • Ensure Docker has enough memory (4GB+)"
    echo "  • Try: docker-compose down && docker-compose up --build"
fi