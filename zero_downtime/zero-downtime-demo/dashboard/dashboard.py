from flask import Flask, render_template_string, jsonify
import requests
import time
import threading
import json
from datetime import datetime
import subprocess
import os

app = Flask(__name__)

# Global metrics storage
metrics_data = {
    'rolling': {'status': 'stopped', 'requests': 0, 'errors': 0, 'avg_response_time': 0},
    'blue_green': {'status': 'stopped', 'requests': 0, 'errors': 0, 'avg_response_time': 0},
    'canary': {'status': 'stopped', 'requests': 0, 'errors': 0, 'avg_response_time': 0}
}

DASHBOARD_HTML = '''
<!DOCTYPE html>
<html>
<head>
    <title>Zero-Downtime Deployment Dashboard</title>
    <meta http-equiv="refresh" content="5">
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: #f5f5f5;
        }
        .header { 
            text-align: center; 
            background: #2c3e50; 
            color: white; 
            padding: 20px; 
            margin: -20px -20px 30px -20px;
        }
        .deployment-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        .deployment-card {
            background: white;
            border-radius: 10px;
            padding: 20px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .strategy-title {
            font-size: 1.5em;
            font-weight: bold;
            margin-bottom: 15px;
            padding-bottom: 10px;
            border-bottom: 2px solid #eee;
        }
        .rolling { border-left: 5px solid #3498db; }
        .blue-green { border-left: 5px solid #2ecc71; }
        .canary { border-left: 5px solid #f39c12; }
        
        .status {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            color: white;
            font-weight: bold;
            margin: 10px 0;
        }
        .status.running { background: #2ecc71; }
        .status.stopped { background: #95a5a6; }
        .status.error { background: #e74c3c; }
        
        .metrics {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 10px;
            margin-top: 15px;
        }
        .metric {
            text-align: center;
            padding: 10px;
            background: #ecf0f1;
            border-radius: 5px;
        }
        .metric-value {
            font-size: 1.5em;
            font-weight: bold;
            color: #2c3e50;
        }
        .metric-label {
            font-size: 0.8em;
            color: #7f8c8d;
        }
        
        .controls {
            margin-top: 20px;
            text-align: center;
        }
        .btn {
            background: #3498db;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            margin: 0 5px;
            text-decoration: none;
            display: inline-block;
        }
        .btn:hover { background: #2980b9; }
        .btn.danger { background: #e74c3c; }
        .btn.danger:hover { background: #c0392b; }
        
        .logs {
            background: #2c3e50;
            color: #ecf0f1;
            padding: 15px;
            border-radius: 5px;
            font-family: monospace;
            height: 200px;
            overflow-y: auto;
            margin-top: 20px;
        }
        
        .quick-actions {
            background: white;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        
        .action-btn {
            background: #9b59b6;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 5px;
            cursor: pointer;
            margin: 5px;
            font-weight: bold;
        }
        .action-btn:hover { background: #8e44ad; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🚀 Zero-Downtime Deployment Dashboard</h1>
        <p>Monitor and control different deployment strategies</p>
        <p>Last Updated: {{ timestamp }}</p>
    </div>
    
    <div class="quick-actions">
        <h3>🎯 Quick Actions</h3>
        <button class="action-btn" onclick="startAll()">Start All Deployments</button>
        <button class="action-btn" onclick="stopAll()">Stop All Deployments</button>
        <button class="action-btn" onclick="runTests()">Run Test Suite</button>
        <button class="action-btn" onclick="showStatus()">Check Status</button>
    </div>
    
    <div class="deployment-grid">
        <!-- Rolling Deployment -->
        <div class="deployment-card rolling">
            <div class="strategy-title">🔄 Rolling Deployment</div>
            <div class="status {{ 'running' if check_service(8080) else 'stopped' }}">
                {{ 'RUNNING' if check_service(8080) else 'STOPPED' }}
            </div>
            <p><strong>Strategy:</strong> Gradually replaces instances one by one</p>
            <p><strong>Resource Usage:</strong> Minimal (105% of normal)</p>
            <p><strong>Risk Level:</strong> Medium</p>
            <p><strong>Best For:</strong> Regular updates with backward compatibility</p>
            
            <div class="metrics">
                <div class="metric">
                    <div class="metric-value">{{ get_response_code(8080) }}</div>
                    <div class="metric-label">HTTP Status</div>
                </div>
                <div class="metric">
                    <div class="metric-value">{{ get_response_time(8080) }}ms</div>
                    <div class="metric-label">Response Time</div>
                </div>
                <div class="metric">
                    <div class="metric-value">3</div>
                    <div class="metric-label">Instances</div>
                </div>
            </div>
            
            <div class="controls">
                <a href="http://localhost:8080" target="_blank" class="btn">View App</a>
                <button class="btn" onclick="startService('rolling')">Start</button>
                <button class="btn danger" onclick="stopService('rolling')">Stop</button>
            </div>
        </div>
        
        <!-- Blue-Green Deployment -->
        <div class="deployment-card blue-green">
            <div class="strategy-title">🔀 Blue-Green Deployment</div>
            <div class="status {{ 'running' if check_service(8081) else 'stopped' }}">
                {{ 'RUNNING' if check_service(8081) else 'STOPPED' }}
            </div>
            <p><strong>Strategy:</strong> Instant switch between two identical environments</p>
            <p><strong>Resource Usage:</strong> High (200% during deployment)</p>
            <p><strong>Risk Level:</strong> Low</p>
            <p><strong>Best For:</strong> Major updates requiring instant switching</p>
            
            <div class="metrics">
                <div class="metric">
                    <div class="metric-value">{{ get_response_code(8081) }}</div>
                    <div class="metric-label">HTTP Status</div>
                </div>
                <div class="metric">
                    <div class="metric-value">{{ get_response_time(8081) }}ms</div>
                    <div class="metric-label">Response Time</div>
                </div>
                <div class="metric">
                    <div class="metric-value">6</div>
                    <div class="metric-label">Instances</div>
                </div>
            </div>
            
            <div class="controls">
                <a href="http://localhost:8081" target="_blank" class="btn">View App</a>
                <button class="btn" onclick="startService('blue-green')">Start</button>
                <button class="btn danger" onclick="stopService('blue-green')">Stop</button>
            </div>
        </div>
        
        <!-- Canary Deployment -->
        <div class="deployment-card canary">
            <div class="strategy-title">🐦 Canary Deployment</div>
            <div class="status {{ 'running' if check_service(8082) else 'stopped' }}">
                {{ 'RUNNING' if check_service(8082) else 'STOPPED' }}
            </div>
            <p><strong>Strategy:</strong> Routes 10% of traffic to new version</p>
            <p><strong>Resource Usage:</strong> Low (110% of normal)</p>
            <p><strong>Risk Level:</strong> Very Low</p>
            <p><strong>Best For:</strong> Risk-averse testing of new features</p>
            
            <div class="metrics">
                <div class="metric">
                    <div class="metric-value">{{ get_response_code(8082) }}</div>
                    <div class="metric-label">HTTP Status</div>
                </div>
                <div class="metric">
                    <div class="metric-value">{{ get_response_time(8082) }}ms</div>
                    <div class="metric-label">Response Time</div>
                </div>
                <div class="metric">
                    <div class="metric-value">4</div>
                    <div class="metric-label">Instances</div>
                </div>
            </div>
            
            <div class="controls">
                <a href="http://localhost:8082" target="_blank" class="btn">View App</a>
                <button class="btn" onclick="startService('canary')">Start</button>
                <button class="btn danger" onclick="stopService('canary')">Stop</button>
            </div>
        </div>
    </div>
    
    <div class="logs" id="logs">
        <div>📊 Dashboard initialized at {{ timestamp }}</div>
        <div>💡 Use the controls above to start different deployment strategies</div>
        <div>🔍 Monitor metrics and application behavior in real-time</div>
        <div>📝 Check application logs: docker-compose logs -f</div>
        <div>🧪 Run tests: ./scripts/test_deployments.sh all</div>
    </div>
    
    <script>
        function startService(strategy) {
            alert('Starting ' + strategy + ' deployment...');
            // In a real implementation, this would make API calls
        }
        
        function stopService(strategy) {
            alert('Stopping ' + strategy + ' deployment...');
            // In a real implementation, this would make API calls
        }
        
        function startAll() {
            alert('Starting all deployments... Check terminal for progress.');
        }
        
        function stopAll() {
            alert('Stopping all deployments... Check terminal for progress.');
        }
        
        function runTests() {
            alert('Running test suite... Check terminal for results.');
        }
        
        function showStatus() {
            alert('Checking status... See current status above.');
        }
    </script>
</body>
</html>
'''

def check_service(port):
    """Check if a service is responding on the given port"""
    try:
        # Map ports to container names
        container_map = {
            8080: 'rolling-nginx-1',
            8081: 'blue-green-nginx-1', 
            8082: 'canary-nginx-1'
        }
        container_name = container_map.get(port, f'localhost:{port}')
        response = requests.get(f'http://{container_name}/health', timeout=2)
        return response.status_code == 200
    except:
        return False

def get_response_code(port):
    """Get HTTP response code for a service"""
    try:
        # Map ports to container names
        container_map = {
            8080: 'rolling-nginx-1',
            8081: 'blue-green-nginx-1',
            8082: 'canary-nginx-1'
        }
        container_name = container_map.get(port, f'localhost:{port}')
        response = requests.get(f'http://{container_name}/health', timeout=2)
        return response.status_code
    except:
        return 'N/A'

def get_response_time(port):
    """Get response time for a service"""
    try:
        # Map ports to container names
        container_map = {
            8080: 'rolling-nginx-1',
            8081: 'blue-green-nginx-1',
            8082: 'canary-nginx-1'
        }
        container_name = container_map.get(port, f'localhost:{port}')
        start = time.time()
        response = requests.get(f'http://{container_name}/health', timeout=2)
        end = time.time()
        return round((end - start) * 1000, 1)
    except:
        return 'N/A'

@app.route('/')
def dashboard():
    return render_template_string(DASHBOARD_HTML, 
                                timestamp=datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
                                check_service=check_service,
                                get_response_code=get_response_code,
                                get_response_time=get_response_time)

@app.route('/api/status')
def api_status():
    return jsonify({
        'rolling': {
            'running': check_service(8080),
            'response_code': get_response_code(8080),
            'response_time': get_response_time(8080)
        },
        'blue_green': {
            'running': check_service(8081),
            'response_code': get_response_code(8081),
            'response_time': get_response_time(8081)
        },
        'canary': {
            'running': check_service(8082),
            'response_code': get_response_code(8082),
            'response_time': get_response_time(8082)
        }
    })

if __name__ == '__main__':
    print("Starting Zero-Downtime Deployment Dashboard on http://localhost:3000")
    print("Dashboard provides real-time monitoring and control interface")
    app.run(host='0.0.0.0', port=3000, debug=False)
