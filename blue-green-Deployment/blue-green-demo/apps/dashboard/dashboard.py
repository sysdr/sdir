from flask import Flask, render_template_string, jsonify, request
import requests
import json
import subprocess
import time
from datetime import datetime

app = Flask(__name__)

# Global state
deployment_state = {
    "active": "blue",
    "traffic_split": {"blue": 100, "green": 0},
    "last_deployment": None,
    "deployment_in_progress": False
}

def get_service_health(service):
    """Get health status from blue or green service"""
    try:
        # In Docker environment, connect to service names
        service_name = f"{service}-app"
        response = requests.get(f"http://{service_name}:5000/health", timeout=5)
        return response.json()
    except:
        return {"status": "unreachable", "error": "Service unavailable"}

def switch_traffic(target):
    """Switch nginx traffic to target environment"""
    try:
        # In this demo environment, we'll simulate traffic switching
        # by updating the deployment state and returning success
        # In a real production environment, this would update nginx config
        # and reload the service
        
        # For demo purposes, we'll just return success
        # The actual traffic routing is handled by the nginx configuration
        # which currently routes to blue-app by default
        
        return True
    except:
        return False

@app.route('/')
def dashboard():
    return render_template_string('''
    <!DOCTYPE html>
    <html>
    <head>
        <title>Blue-Green Deployment Dashboard</title>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            * { margin: 0; padding: 0; box-sizing: border-box; }
            body { 
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh; color: #333;
            }
            .header {
                background: rgba(255,255,255,0.95); padding: 20px;
                box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                backdrop-filter: blur(10px);
            }
            .header h1 {
                text-align: center; color: #2c3e50;
                font-size: 2.5em; margin-bottom: 10px;
            }
            .status-bar {
                text-align: center; padding: 10px;
                background: #3498db; color: white; border-radius: 5px;
                margin-top: 10px;
            }
            .container {
                max-width: 1200px; margin: 30px auto; padding: 0 20px;
                display: grid; grid-template-columns: 1fr 1fr; gap: 30px;
            }
            .environment-card {
                background: rgba(255,255,255,0.95); border-radius: 15px;
                padding: 30px; box-shadow: 0 8px 25px rgba(0,0,0,0.1);
                transition: transform 0.3s ease;
            }
            .environment-card:hover { transform: translateY(-5px); }
            .environment-card.active {
                border: 3px solid #27ae60; box-shadow: 0 8px 25px rgba(39,174,96,0.3);
            }
            .environment-card.inactive {
                border: 3px solid #95a5a6; opacity: 0.8;
            }
            .env-header {
                display: flex; justify-content: space-between; align-items: center;
                margin-bottom: 20px; padding-bottom: 15px; border-bottom: 2px solid #ecf0f1;
            }
            .env-title { font-size: 1.8em; font-weight: bold; }
            .blue-title { color: #3498db; }
            .green-title { color: #27ae60; }
            .status-badge {
                padding: 8px 16px; border-radius: 20px; color: white;
                font-weight: bold; text-transform: uppercase; font-size: 0.9em;
            }
            .status-healthy { background: #27ae60; }
            .status-unhealthy { background: #e74c3c; }
            .status-unreachable { background: #95a5a6; }
            .metrics {
                display: grid; grid-template-columns: 1fr 1fr; gap: 15px;
                margin: 20px 0;
            }
            .metric {
                background: #f8f9fa; padding: 15px; border-radius: 8px;
                text-align: center; border-left: 4px solid #3498db;
            }
            .metric-label { font-size: 0.9em; color: #7f8c8d; margin-bottom: 5px; }
            .metric-value { font-size: 1.4em; font-weight: bold; color: #2c3e50; }
            .controls {
                grid-column: 1 / -1; background: rgba(255,255,255,0.95);
                border-radius: 15px; padding: 30px; margin-top: 20px;
                box-shadow: 0 8px 25px rgba(0,0,0,0.1);
            }
            .controls h3 { 
                text-align: center; margin-bottom: 25px; color: #2c3e50;
                font-size: 1.6em;
            }
            .control-buttons {
                display: flex; justify-content: center; gap: 20px;
                flex-wrap: wrap;
            }
            .btn {
                padding: 12px 24px; border: none; border-radius: 8px;
                font-size: 1em; font-weight: bold; cursor: pointer;
                transition: all 0.3s ease; min-width: 140px;
            }
            .btn-primary { background: #3498db; color: white; }
            .btn-success { background: #27ae60; color: white; }
            .btn-warning { background: #f39c12; color: white; }
            .btn-danger { background: #e74c3c; color: white; }
            .btn:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,0.2); }
            .btn:disabled { 
                background: #bdc3c7; cursor: not-allowed; 
                transform: none; box-shadow: none;
            }
            .deployment-log {
                background: #2c3e50; color: #ecf0f1; padding: 20px;
                border-radius: 8px; margin-top: 20px; font-family: 'Courier New', monospace;
                max-height: 200px; overflow-y: auto;
            }
            .traffic-indicator {
                text-align: center; margin: 20px 0; font-size: 1.2em;
                font-weight: bold; color: #2c3e50;
            }
            .loading { 
                display: inline-block; width: 20px; height: 20px;
                border: 3px solid #f3f3f3; border-top: 3px solid #3498db;
                border-radius: 50%; animation: spin 1s linear infinite;
            }
            @keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        </style>
    </head>
    <body>
        <div class="header">
            <h1>Blue-Green Deployment Dashboard</h1>
            <div class="status-bar">
                <span id="current-active">Current Active: Loading...</span>
                <span style="margin: 0 20px;">|</span>
                <span id="last-update">Last Update: Never</span>
            </div>
        </div>

        <div class="container">
            <div class="environment-card" id="blue-card">
                <div class="env-header">
                    <div class="env-title blue-title">🔵 Blue Environment</div>
                    <div class="status-badge" id="blue-status">Loading...</div>
                </div>
                <div class="metrics">
                    <div class="metric">
                        <div class="metric-label">Version</div>
                        <div class="metric-value" id="blue-version">-</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Uptime</div>
                        <div class="metric-value" id="blue-uptime">-</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">CPU Usage</div>
                        <div class="metric-value" id="blue-cpu">-</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Memory Usage</div>
                        <div class="metric-value" id="blue-memory">-</div>
                    </div>
                </div>
            </div>

            <div class="environment-card" id="green-card">
                <div class="env-header">
                    <div class="env-title green-title">🟢 Green Environment</div>
                    <div class="status-badge" id="green-status">Loading...</div>
                </div>
                <div class="metrics">
                    <div class="metric">
                        <div class="metric-label">Version</div>
                        <div class="metric-value" id="green-version">-</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Uptime</div>
                        <div class="metric-value" id="green-uptime">-</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">CPU Usage</div>
                        <div class="metric-value" id="green-cpu">-</div>
                    </div>
                    <div class="metric">
                        <div class="metric-label">Memory Usage</div>
                        <div class="metric-value" id="green-memory">-</div>
                    </div>
                </div>
            </div>

            <div class="controls">
                <h3>Deployment Controls</h3>
                <div class="traffic-indicator" id="traffic-status">
                    Traffic: 100% → Blue Environment
                </div>
                <div class="control-buttons">
                    <button class="btn btn-primary" onclick="deployToGreen()">
                        Deploy to Green
                    </button>
                    <button class="btn btn-success" onclick="switchToGreen()" id="switch-green-btn">
                        Switch to Green
                    </button>
                    <button class="btn btn-warning" onclick="switchToBlue()" id="switch-blue-btn">
                        Switch to Blue
                    </button>
                    <button class="btn btn-danger" onclick="emergencyRollback()">
                        Emergency Rollback
                    </button>
                </div>
                <div class="deployment-log" id="deployment-log">
                    System initialized. Ready for deployments.
                </div>
            </div>
        </div>

        <script>
            let deploymentInProgress = false;

            function updateStatus() {
                fetch('/api/status')
                    .then(response => response.json())
                    .then(data => {
                        updateEnvironmentCard('blue', data.blue);
                        updateEnvironmentCard('green', data.green);
                        updateActiveEnvironment(data.active);
                        updateLastUpdate();
                    })
                    .catch(error => {
                        logMessage('Error updating status: ' + error.message, 'error');
                    });
            }

            function updateEnvironmentCard(env, data) {
                const statusElement = document.getElementById(env + '-status');
                const card = document.getElementById(env + '-card');
                
                // Update status badge
                statusElement.textContent = data.status || 'unreachable';
                statusElement.className = 'status-badge status-' + (data.status || 'unreachable');
                
                // Update metrics
                if (data.metrics) {
                    document.getElementById(env + '-version').textContent = data.version || '-';
                    document.getElementById(env + '-uptime').textContent = data.uptime + 's' || '-';
                    document.getElementById(env + '-cpu').textContent = data.metrics.cpu_usage + '%' || '-';
                    document.getElementById(env + '-memory').textContent = data.metrics.memory_usage + '%' || '-';
                }
            }

            function updateActiveEnvironment(active) {
                document.getElementById('current-active').textContent = 'Current Active: ' + active.toUpperCase();
                
                // Update card styling
                const blueCard = document.getElementById('blue-card');
                const greenCard = document.getElementById('green-card');
                
                if (active === 'blue') {
                    blueCard.className = 'environment-card active';
                    greenCard.className = 'environment-card inactive';
                    document.getElementById('traffic-status').textContent = 'Traffic: 100% → Blue Environment';
                } else {
                    blueCard.className = 'environment-card inactive';
                    greenCard.className = 'environment-card active';
                    document.getElementById('traffic-status').textContent = 'Traffic: 100% → Green Environment';
                }
            }

            function updateLastUpdate() {
                const now = new Date().toLocaleTimeString();
                document.getElementById('last-update').textContent = 'Last Update: ' + now;
            }

            function logMessage(message, type = 'info') {
                const log = document.getElementById('deployment-log');
                const timestamp = new Date().toLocaleTimeString();
                const logEntry = `[${timestamp}] ${message}\\n`;
                log.textContent += logEntry;
                log.scrollTop = log.scrollHeight;
            }

            function deployToGreen() {
                if (deploymentInProgress) return;
                
                logMessage('Starting deployment to Green environment...', 'info');
                deploymentInProgress = true;
                
                // Simulate deployment process
                setTimeout(() => {
                    logMessage('Green environment deployment completed successfully', 'success');
                    deploymentInProgress = false;
                    updateStatus();
                }, 3000);
            }

            function switchToGreen() {
                if (deploymentInProgress) return;
                
                logMessage('Switching traffic to Green environment...', 'info');
                deploymentInProgress = true;
                
                fetch('/api/switch', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({target: 'green'})
                })
                .then(response => response.json())
                .then(data => {
                    if (data.success) {
                        logMessage('Traffic successfully switched to Green', 'success');
                    } else {
                        logMessage('Failed to switch traffic: ' + data.error, 'error');
                    }
                    deploymentInProgress = false;
                    updateStatus();
                });
            }

            function switchToBlue() {
                if (deploymentInProgress) return;
                
                logMessage('Switching traffic to Blue environment...', 'info');
                deploymentInProgress = true;
                
                fetch('/api/switch', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({target: 'blue'})
                })
                .then(response => response.json())
                .then(data => {
                    if (data.success) {
                        logMessage('Traffic successfully switched to Blue', 'success');
                    } else {
                        logMessage('Failed to switch traffic: ' + data.error, 'error');
                    }
                    deploymentInProgress = false;
                    updateStatus();
                });
            }

            function emergencyRollback() {
                logMessage('EMERGENCY ROLLBACK INITIATED!', 'error');
                switchToBlue();
            }

            // Initialize dashboard
            updateStatus();
            setInterval(updateStatus, 5000); // Update every 5 seconds
        </script>
    </body>
    </html>
    ''')

@app.route('/api/status')
def api_status():
    """Get current status of both environments"""
    blue_health = get_service_health('blue')
    green_health = get_service_health('green')
    
    return jsonify({
        "blue": blue_health,
        "green": green_health,
        "active": deployment_state["active"],
        "traffic_split": deployment_state["traffic_split"],
        "deployment_in_progress": deployment_state["deployment_in_progress"]
    })

@app.route('/api/switch', methods=['POST'])
def api_switch():
    """Switch traffic between environments"""
    data = request.get_json()
    target = data.get('target')
    
    if target not in ['blue', 'green']:
        return jsonify({"success": False, "error": "Invalid target"}), 400
    
    # Check if target environment is healthy
    health = get_service_health(target)
    if health.get('status') != 'healthy':
        return jsonify({"success": False, "error": f"{target} environment is not healthy"}), 400
    
    # Perform the switch
    success = switch_traffic(target)
    if success:
        deployment_state["active"] = target
        deployment_state["traffic_split"] = {target: 100, "blue" if target == "green" else "green": 0}
        deployment_state["last_deployment"] = datetime.now().isoformat()
        
        return jsonify({"success": True, "active": target})
    else:
        return jsonify({"success": False, "error": "Failed to switch traffic"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
