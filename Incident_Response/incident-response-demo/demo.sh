#!/bin/bash

set -e

echo "🔧 Building Incident Response Automation Demo..."

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is required but not installed."
    exit 1
fi

# Create main application structure
mkdir -p {src/{monitoring,alerting,automation,dashboard},config,logs,data}

# Create monitoring service
cat > src/monitoring/app.py << 'PYTHON'
from flask import Flask, jsonify
import random
import time
import threading
import json
from datetime import datetime
import redis

app = Flask(__name__)
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

# System metrics simulation
class MetricsCollector:
    def __init__(self):
        self.cpu_usage = 15.0
        self.memory_usage = 40.0
        self.error_rate = 0.1
        self.response_time = 150.0
        self.active_connections = 100
        
    def simulate_incident(self, incident_type):
        """Simulate different types of incidents"""
        if incident_type == "high_cpu":
            self.cpu_usage = random.uniform(85.0, 95.0)
        elif incident_type == "memory_leak":
            self.memory_usage = random.uniform(85.0, 95.0)
        elif incident_type == "high_errors":
            self.error_rate = random.uniform(5.0, 15.0)
        elif incident_type == "slow_response":
            self.response_time = random.uniform(2000.0, 5000.0)
            
    def collect_metrics(self):
        """Continuously collect and publish metrics"""
        while True:
            # Natural variation
            self.cpu_usage += random.uniform(-2, 2)
            self.memory_usage += random.uniform(-1, 1)
            self.error_rate += random.uniform(-0.1, 0.1)
            self.response_time += random.uniform(-20, 20)
            
            # Keep within bounds
            self.cpu_usage = max(5, min(100, self.cpu_usage))
            self.memory_usage = max(20, min(100, self.memory_usage))
            self.error_rate = max(0, min(20, self.error_rate))
            self.response_time = max(50, min(6000, self.response_time))
            
            metrics = {
                'timestamp': datetime.now().isoformat(),
                'cpu_usage': round(self.cpu_usage, 2),
                'memory_usage': round(self.memory_usage, 2),
                'error_rate': round(self.error_rate, 2),
                'response_time': round(self.response_time, 2),
                'active_connections': self.active_connections + random.randint(-10, 10)
            }
            
            # Publish to Redis
            redis_client.lpush('metrics', json.dumps(metrics))
            redis_client.ltrim('metrics', 0, 99)  # Keep last 100 metrics
            
            time.sleep(5)

collector = MetricsCollector()

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

@app.route('/metrics')
def metrics():
    return jsonify({
        'cpu_usage': collector.cpu_usage,
        'memory_usage': collector.memory_usage,
        'error_rate': collector.error_rate,
        'response_time': collector.response_time,
        'active_connections': collector.active_connections
    })

@app.route('/simulate/<incident_type>')
def simulate_incident(incident_type):
    collector.simulate_incident(incident_type)
    return jsonify({"message": f"Simulated {incident_type} incident"})

if __name__ == '__main__':
    # Start metrics collection in background
    threading.Thread(target=collector.collect_metrics, daemon=True).start()
    app.run(host='0.0.0.0', port=5001)
PYTHON

# Create alert manager
cat > src/alerting/app.py << 'PYTHON'
from flask import Flask, jsonify
import redis
import json
import threading
import time
from datetime import datetime

app = Flask(__name__)
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

class AlertManager:
    def __init__(self):
        self.active_alerts = {}
        self.alert_rules = {
            'high_cpu': {'threshold': 80, 'duration': 10},
            'high_memory': {'threshold': 80, 'duration': 15},
            'high_error_rate': {'threshold': 5.0, 'duration': 10},
            'slow_response': {'threshold': 1000, 'duration': 10}
        }
        
    def evaluate_alerts(self):
        """Continuously evaluate alert conditions"""
        while True:
            try:
                # Get latest metrics
                latest_metrics = redis_client.lrange('metrics', 0, 0)
                if not latest_metrics:
                    time.sleep(5)
                    continue
                    
                metrics = json.loads(latest_metrics[0])
                
                # Check CPU alert
                if metrics['cpu_usage'] > self.alert_rules['high_cpu']['threshold']:
                    self.trigger_alert('high_cpu', f"CPU usage at {metrics['cpu_usage']}%", 'critical')
                else:
                    self.resolve_alert('high_cpu')
                    
                # Check memory alert
                if metrics['memory_usage'] > self.alert_rules['high_memory']['threshold']:
                    self.trigger_alert('high_memory', f"Memory usage at {metrics['memory_usage']}%", 'critical')
                else:
                    self.resolve_alert('high_memory')
                    
                # Check error rate
                if metrics['error_rate'] > self.alert_rules['high_error_rate']['threshold']:
                    self.trigger_alert('high_error_rate', f"Error rate at {metrics['error_rate']}%", 'warning')
                else:
                    self.resolve_alert('high_error_rate')
                    
                # Check response time
                if metrics['response_time'] > self.alert_rules['slow_response']['threshold']:
                    self.trigger_alert('slow_response', f"Response time at {metrics['response_time']}ms", 'warning')
                else:
                    self.resolve_alert('slow_response')
                    
            except Exception as e:
                print(f"Error in alert evaluation: {e}")
                
            time.sleep(5)
            
    def trigger_alert(self, alert_id, message, severity):
        if alert_id not in self.active_alerts:
            alert = {
                'id': alert_id,
                'message': message,
                'severity': severity,
                'timestamp': datetime.now().isoformat(),
                'status': 'firing'
            }
            self.active_alerts[alert_id] = alert
            
            # Publish alert
            redis_client.lpush('alerts', json.dumps(alert))
            redis_client.ltrim('alerts', 0, 49)  # Keep last 50 alerts
            
    def resolve_alert(self, alert_id):
        if alert_id in self.active_alerts:
            alert = self.active_alerts[alert_id]
            alert['status'] = 'resolved'
            alert['resolved_at'] = datetime.now().isoformat()
            
            # Publish resolution
            redis_client.lpush('alerts', json.dumps(alert))
            del self.active_alerts[alert_id]

alert_manager = AlertManager()

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

@app.route('/alerts')
def get_alerts():
    return jsonify(list(alert_manager.active_alerts.values()))

if __name__ == '__main__':
    # Start alert evaluation in background
    threading.Thread(target=alert_manager.evaluate_alerts, daemon=True).start()
    app.run(host='0.0.0.0', port=5002)
PYTHON

# Create automation engine
cat > src/automation/app.py << 'PYTHON'
from flask import Flask, jsonify
import redis
import json
import threading
import time
from datetime import datetime
import requests

app = Flask(__name__)
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

class AutomationEngine:
    def __init__(self):
        self.remediation_actions = {
            'high_cpu': self.handle_high_cpu,
            'high_memory': self.handle_high_memory,
            'high_error_rate': self.handle_high_errors,
            'slow_response': self.handle_slow_response
        }
        self.action_history = []
        
    def monitor_alerts(self):
        """Monitor alerts and trigger automated responses"""
        processed_alerts = set()
        
        while True:
            try:
                alerts = redis_client.lrange('alerts', 0, -1)
                for alert_data in alerts:
                    alert = json.loads(alert_data)
                    
                    # Only process firing alerts we haven't seen
                    alert_key = f"{alert['id']}_{alert['timestamp']}"
                    if alert['status'] == 'firing' and alert_key not in processed_alerts:
                        processed_alerts.add(alert_key)
                        self.execute_remediation(alert)
                        
            except Exception as e:
                print(f"Error monitoring alerts: {e}")
                
            time.sleep(3)
            
    def execute_remediation(self, alert):
        """Execute automated remediation based on alert type"""
        alert_id = alert['id']
        
        if alert_id in self.remediation_actions:
            action_result = self.remediation_actions[alert_id](alert)
            
            # Record action
            action_record = {
                'timestamp': datetime.now().isoformat(),
                'alert_id': alert_id,
                'action': action_result['action'],
                'success': action_result['success'],
                'details': action_result['details']
            }
            
            self.action_history.append(action_record)
            redis_client.lpush('automation_actions', json.dumps(action_record))
            redis_client.ltrim('automation_actions', 0, 49)
            
    def handle_high_cpu(self, alert):
        """Automated response to high CPU usage"""
        return {
            'action': 'scale_up_instances',
            'success': True,
            'details': 'Triggered auto-scaling to add 2 additional instances'
        }
        
    def handle_high_memory(self, alert):
        """Automated response to high memory usage"""
        return {
            'action': 'restart_services',
            'success': True,
            'details': 'Initiated rolling restart of application services'
        }
        
    def handle_high_errors(self, alert):
        """Automated response to high error rate"""
        return {
            'action': 'circuit_breaker_activation',
            'success': True,
            'details': 'Activated circuit breaker for downstream services'
        }
        
    def handle_slow_response(self, alert):
        """Automated response to slow response times"""
        return {
            'action': 'cache_warmup',
            'success': True,
            'details': 'Initiated cache warm-up procedure'
        }

automation_engine = AutomationEngine()

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

@app.route('/actions')
def get_actions():
    return jsonify(automation_engine.action_history[-10:])  # Last 10 actions

if __name__ == '__main__':
    # Start alert monitoring in background
    threading.Thread(target=automation_engine.monitor_alerts, daemon=True).start()
    app.run(host='0.0.0.0', port=5003)
PYTHON

# Create dashboard
cat > src/dashboard/app.py << 'PYTHON'
from flask import Flask, render_template, jsonify
import redis
import json
from datetime import datetime

app = Flask(__name__)
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

@app.route('/')
def dashboard():
    return render_template('dashboard.html')

@app.route('/api/metrics')
def api_metrics():
    try:
        latest_metrics = redis_client.lrange('metrics', 0, 9)  # Last 10 metrics
        metrics = [json.loads(m) for m in latest_metrics]
        return jsonify(metrics)
    except:
        return jsonify([])

@app.route('/api/alerts')
def api_alerts():
    try:
        alerts = redis_client.lrange('alerts', 0, 9)  # Last 10 alerts
        alert_list = [json.loads(a) for a in alerts]
        return jsonify(alert_list)
    except:
        return jsonify([])

@app.route('/api/actions')
def api_actions():
    try:
        actions = redis_client.lrange('automation_actions', 0, 9)  # Last 10 actions
        action_list = [json.loads(a) for a in actions]
        return jsonify(action_list)
    except:
        return jsonify([])

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYTHON

# Create dashboard template
mkdir -p src/dashboard/templates
cat > src/dashboard/templates/dashboard.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Incident Response Automation Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        .header h1 { font-size: 2.5rem; margin-bottom: 10px; }
        .header p { opacity: 0.9; font-size: 1.1rem; }
        .dashboard-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 30px;
            padding: 30px;
        }
        .metrics-panel, .alerts-panel, .actions-panel, .controls-panel {
            background: #f8f9fa;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.08);
        }
        .panel-title {
            font-size: 1.3rem;
            font-weight: 600;
            margin-bottom: 20px;
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        .metric-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 0;
            border-bottom: 1px solid #ecf0f1;
        }
        .metric-label { font-weight: 500; color: #34495e; }
        .metric-value {
            font-weight: 700;
            font-size: 1.1rem;
        }
        .metric-normal { color: #27ae60; }
        .metric-warning { color: #f39c12; }
        .metric-critical { color: #e74c3c; }
        .alert-item {
            padding: 15px;
            margin: 10px 0;
            border-radius: 8px;
            border-left: 4px solid #3498db;
        }
        .alert-critical {
            background: #fee;
            border-left-color: #e74c3c;
        }
        .alert-warning {
            background: #ffc;
            border-left-color: #f39c12;
        }
        .action-item {
            padding: 12px;
            margin: 8px 0;
            background: #e8f5e8;
            border-radius: 8px;
            border-left: 4px solid #27ae60;
        }
        .simulate-btn {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px 20px;
            border-radius: 8px;
            cursor: pointer;
            margin: 5px;
            font-weight: 600;
            transition: transform 0.2s;
        }
        .simulate-btn:hover { transform: translateY(-2px); }
        .chart-container {
            grid-column: span 2;
            background: #f8f9fa;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.08);
        }
        canvas { max-height: 300px; }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-healthy { background: #27ae60; }
        .status-warning { background: #f39c12; }
        .status-critical { background: #e74c3c; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚨 Incident Response Automation</h1>
            <p>Real-time monitoring with automated remediation</p>
        </div>
        
        <div class="dashboard-grid">
            <div class="metrics-panel">
                <h2 class="panel-title">📊 System Metrics</h2>
                <div id="metrics-content">
                    <div class="metric-item">
                        <span class="metric-label">CPU Usage</span>
                        <span class="metric-value metric-normal" id="cpu-value">--</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Memory Usage</span>
                        <span class="metric-value metric-normal" id="memory-value">--</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Error Rate</span>
                        <span class="metric-value metric-normal" id="error-value">--</span>
                    </div>
                    <div class="metric-item">
                        <span class="metric-label">Response Time</span>
                        <span class="metric-value metric-normal" id="response-value">--</span>
                    </div>
                </div>
            </div>
            
            <div class="controls-panel">
                <h2 class="panel-title">🎛️ Incident Simulation</h2>
                <p style="margin-bottom: 15px; color: #7f8c8d;">Trigger incidents to see automation in action:</p>
                <button class="simulate-btn" onclick="simulateIncident('high_cpu')">🔥 High CPU</button>
                <button class="simulate-btn" onclick="simulateIncident('memory_leak')">💾 Memory Leak</button>
                <button class="simulate-btn" onclick="simulateIncident('high_errors')">⚠️ High Errors</button>
                <button class="simulate-btn" onclick="simulateIncident('slow_response')">🐌 Slow Response</button>
            </div>
            
            <div class="alerts-panel">
                <h2 class="panel-title">🚨 Active Alerts</h2>
                <div id="alerts-content">
                    <p style="color: #95a5a6;">No active alerts</p>
                </div>
            </div>
            
            <div class="actions-panel">
                <h2 class="panel-title">🤖 Automated Actions</h2>
                <div id="actions-content">
                    <p style="color: #95a5a6;">No automated actions yet</p>
                </div>
            </div>
            
            <div class="chart-container">
                <h2 class="panel-title">📈 Metrics Timeline</h2>
                <canvas id="metricsChart"></canvas>
            </div>
        </div>
    </div>

    <script>
        // Chart.js setup
        const ctx = document.getElementById('metricsChart').getContext('2d');
        const chart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'CPU Usage (%)',
                        data: [],
                        borderColor: '#3498db',
                        backgroundColor: 'rgba(52, 152, 219, 0.1)',
                        tension: 0.4
                    },
                    {
                        label: 'Memory Usage (%)',
                        data: [],
                        borderColor: '#e74c3c',
                        backgroundColor: 'rgba(231, 76, 60, 0.1)',
                        tension: 0.4
                    },
                    {
                        label: 'Error Rate (%)',
                        data: [],
                        borderColor: '#f39c12',
                        backgroundColor: 'rgba(243, 156, 18, 0.1)',
                        tension: 0.4
                    }
                ]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 100
                    }
                }
            }
        });

        // Update functions
        function updateMetrics() {
            fetch('/api/metrics')
                .then(response => response.json())
                .then(data => {
                    if (data.length > 0) {
                        const latest = data[0];
                        updateMetricValue('cpu-value', latest.cpu_usage, '%');
                        updateMetricValue('memory-value', latest.memory_usage, '%');
                        updateMetricValue('error-value', latest.error_rate, '%');
                        updateMetricValue('response-value', latest.response_time, 'ms');
                        
                        // Update chart
                        const labels = data.map(m => new Date(m.timestamp).toLocaleTimeString());
                        chart.data.labels = labels.reverse();
                        chart.data.datasets[0].data = data.map(m => m.cpu_usage).reverse();
                        chart.data.datasets[1].data = data.map(m => m.memory_usage).reverse();
                        chart.data.datasets[2].data = data.map(m => m.error_rate).reverse();
                        chart.update('none');
                    }
                });
        }

        function updateMetricValue(elementId, value, unit) {
            const element = document.getElementById(elementId);
            element.textContent = value + unit;
            
            // Update color based on thresholds
            element.className = 'metric-value ';
            if (elementId === 'cpu-value' || elementId === 'memory-value') {
                if (value > 80) element.className += 'metric-critical';
                else if (value > 60) element.className += 'metric-warning';
                else element.className += 'metric-normal';
            } else if (elementId === 'error-value') {
                if (value > 5) element.className += 'metric-critical';
                else if (value > 2) element.className += 'metric-warning';
                else element.className += 'metric-normal';
            } else if (elementId === 'response-value') {
                if (value > 1000) element.className += 'metric-critical';
                else if (value > 500) element.className += 'metric-warning';
                else element.className += 'metric-normal';
            }
        }

        function updateAlerts() {
            fetch('/api/alerts')
                .then(response => response.json())
                .then(data => {
                    const alertsContainer = document.getElementById('alerts-content');
                    if (data.length === 0) {
                        alertsContainer.innerHTML = '<p style="color: #95a5a6;">No active alerts</p>';
                    } else {
                        alertsContainer.innerHTML = data
                            .filter(alert => alert.status === 'firing')
                            .map(alert => `
                                <div class="alert-item alert-${alert.severity}">
                                    <div style="font-weight: 600;">
                                        <span class="status-indicator status-${alert.severity}"></span>
                                        ${alert.id.replace(/_/g, ' ').toUpperCase()}
                                    </div>
                                    <div style="font-size: 0.9rem; margin-top: 5px; color: #7f8c8d;">
                                        ${alert.message}
                                    </div>
                                    <div style="font-size: 0.8rem; margin-top: 5px; color: #95a5a6;">
                                        ${new Date(alert.timestamp).toLocaleString()}
                                    </div>
                                </div>
                            `).join('');
                    }
                });
        }

        function updateActions() {
            fetch('/api/actions')
                .then(response => response.json())
                .then(data => {
                    const actionsContainer = document.getElementById('actions-content');
                    if (data.length === 0) {
                        actionsContainer.innerHTML = '<p style="color: #95a5a6;">No automated actions yet</p>';
                    } else {
                        actionsContainer.innerHTML = data.map(action => `
                            <div class="action-item">
                                <div style="font-weight: 600;">
                                    🤖 ${action.action.replace(/_/g, ' ').toUpperCase()}
                                </div>
                                <div style="font-size: 0.9rem; margin-top: 5px; color: #27ae60;">
                                    ${action.details}
                                </div>
                                <div style="font-size: 0.8rem; margin-top: 5px; color: #95a5a6;">
                                    ${new Date(action.timestamp).toLocaleString()}
                                </div>
                            </div>
                        `).join('');
                    }
                });
        }

        function simulateIncident(type) {
            fetch(`http://localhost:5001/simulate/${type}`)
                .then(response => response.json())
                .then(data => {
                    console.log('Incident simulated:', data);
                });
        }

        // Auto-refresh
        setInterval(updateMetrics, 2000);
        setInterval(updateAlerts, 3000);
        setInterval(updateActions, 3000);
        
        // Initial load
        updateMetrics();
        updateAlerts();
        updateActions();
    </script>
</body>
</html>
HTML

# Create requirements files
cat > src/monitoring/requirements.txt << 'REQS'
Flask==3.0.0
redis==5.0.1
REQS

cat > src/alerting/requirements.txt << 'REQS'
Flask==3.0.0
redis==5.0.1
requests==2.31.0
REQS

cat > src/automation/requirements.txt << 'REQS'
Flask==3.0.0
redis==5.0.1
requests==2.31.0
REQS

cat > src/dashboard/requirements.txt << 'REQS'
Flask==3.0.0
redis==5.0.1
REQS

# Create Dockerfiles
cat > src/monitoring/Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5001
CMD ["python", "app.py"]
DOCKERFILE

cat > src/alerting/Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5002
CMD ["python", "app.py"]
DOCKERFILE

cat > src/automation/Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5003
CMD ["python", "app.py"]
DOCKERFILE

cat > src/dashboard/Dockerfile << 'DOCKERFILE'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 5000
CMD ["python", "app.py"]
DOCKERFILE

# Create docker-compose.yml
cat > docker-compose.yml << 'COMPOSE'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    container_name: incident-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  monitoring:
    build: ./src/monitoring
    container_name: incident-monitoring
    ports:
      - "5001:5001"
    depends_on:
      redis:
        condition: service_healthy
    environment:
      - FLASK_ENV=production
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5001/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  alerting:
    build: ./src/alerting
    container_name: incident-alerting
    ports:
      - "5002:5002"
    depends_on:
      redis:
        condition: service_healthy
    environment:
      - FLASK_ENV=production
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5002/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  automation:
    build: ./src/automation
    container_name: incident-automation
    ports:
      - "5003:5003"
    depends_on:
      redis:
        condition: service_healthy
      monitoring:
        condition: service_healthy
    environment:
      - FLASK_ENV=production
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5003/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  dashboard:
    build: ./src/dashboard
    container_name: incident-dashboard
    ports:
      - "5000:5000"
    depends_on:
      redis:
        condition: service_healthy
    environment:
      - FLASK_ENV=production
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000"]
      interval: 30s
      timeout: 10s
      retries: 3

volumes:
  redis_data:

networks:
  default:
    name: incident-response-network
COMPOSE

# Create test script
cat > tests/test_automation.py << 'PYTHON'
import requests
import time
import json

def test_system_integration():
    """Test the complete incident response automation flow"""
    
    print("🧪 Testing Incident Response Automation System...")
    
    # Test 1: Check all services are healthy
    services = {
        'monitoring': 'http://localhost:5001/health',
        'alerting': 'http://localhost:5002/health',
        'automation': 'http://localhost:5003/health',
        'dashboard': 'http://localhost:5000'
    }
    
    print("\n1. Checking service health...")
    for service, url in services.items():
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                print(f"   ✅ {service.capitalize()} service: OK")
            else:
                print(f"   ❌ {service.capitalize()} service: ERROR")
        except Exception as e:
            print(f"   ❌ {service.capitalize()} service: {e}")
    
    # Test 2: Trigger incident and verify automation
    print("\n2. Testing incident simulation...")
    incidents = ['high_cpu', 'memory_leak', 'high_errors', 'slow_response']
    
    for incident in incidents:
        try:
            response = requests.get(f'http://localhost:5001/simulate/{incident}')
            if response.status_code == 200:
                print(f"   ✅ {incident} incident: Triggered")
            time.sleep(2)
        except Exception as e:
            print(f"   ❌ {incident} incident: {e}")
    
    # Test 3: Verify alerts are generated
    print("\n3. Checking alert generation...")
    time.sleep(10)  # Wait for alerts to be processed
    try:
        response = requests.get('http://localhost:5002/alerts')
        if response.status_code == 200:
            alerts = response.json()
            print(f"   ✅ Generated {len(alerts)} alerts")
        else:
            print("   ❌ Failed to fetch alerts")
    except Exception as e:
        print(f"   ❌ Alert check failed: {e}")
    
    # Test 4: Verify automated actions
    print("\n4. Checking automated actions...")
    try:
        response = requests.get('http://localhost:5003/actions')
        if response.status_code == 200:
            actions = response.json()
            print(f"   ✅ Executed {len(actions)} automated actions")
            for action in actions[-3:]:  # Show last 3 actions
                print(f"      - {action['action']}: {action['details']}")
        else:
            print("   ❌ Failed to fetch actions")
    except Exception as e:
        print(f"   ❌ Action check failed: {e}")
    
    print("\n🎉 Incident Response Automation Test Complete!")
    print("\n📊 Access the dashboard at: http://localhost:5000")
    print("🎛️ Try the incident simulation buttons to see automation in action!")

if __name__ == '__main__':
    test_system_integration()
PYTHON

echo "🏗️ Building Docker images..."
docker-compose build --parallel

echo "🚀 Starting incident response automation system..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 30

echo "🧪 Running integration tests..."
cd tests && python test_automation.py

echo ""
echo "✅ Incident Response Automation Demo Ready!"
echo ""
echo "🌐 Access Points:"
echo "   📊 Dashboard: http://localhost:5000"
echo "   📈 Monitoring API: http://localhost:5001"
echo "   🚨 Alerting API: http://localhost:5002"
echo "   🤖 Automation API: http://localhost:5003"
echo ""
echo "🎯 Demo Steps:"
echo "   1. Open http://localhost:5000 in your browser"
echo "   2. Watch real-time metrics in the dashboard"
echo "   3. Click incident simulation buttons (High CPU, Memory Leak, etc.)"
echo "   4. Observe automated alerts and remediation actions"
echo "   5. Check the metrics timeline to see incident patterns"
echo ""
echo "🔍 Logs: docker-compose logs -f [service-name]"
echo "🛑 Stop: ./cleanup.sh"
