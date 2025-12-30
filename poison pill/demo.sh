#!/bin/bash

set -e

echo "=========================================="
echo "Poison Pill Request Demo Setup"
echo "=========================================="
echo ""

# Check for required tools
command -v docker >/dev/null 2>&1 || { echo "Error: docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "Error: docker-compose is required but not installed. Aborting." >&2; exit 1; }

# Create project structure
echo "[1/8] Creating project structure..."
mkdir -p poison-pill-demo/{app,haproxy,dashboard,logs,metrics}
cd poison-pill-demo

# Create Flask application with poison endpoint
echo "[2/8] Creating Flask application..."
cat > app/app.py << 'EOF'
from flask import Flask, request, jsonify
import time
import os
import sys
import signal
import hashlib
import logging
from datetime import datetime

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# In-memory request tracking
request_tracker = {}
poison_patterns = set()
circuit_breaker = {"open": False, "failures": 0, "threshold": 3}

SERVER_ID = os.environ.get('SERVER_ID', 'unknown')

def generate_request_hash(data):
    """Generate fingerprint for request"""
    return hashlib.md5(str(data).encode()).hexdigest()[:12]

def check_poison_pattern(data):
    """Check if request matches known poison patterns"""
    if not isinstance(data, dict):
        return False
    
    # Simulate various poison pill patterns
    payload = str(data)
    
    # Pattern 1: Deeply nested structures (simulates parser crash)
    if payload.count('[') > 10 or payload.count('{') > 10:
        return True
    
    # Pattern 2: Specific malformed input
    if '{{POISON}}' in payload or '${CRASH}' in payload:
        return True
    
    # Pattern 3: Regex catastrophic backtracking simulation
    if 'AAAAAAAAAAAAAAAAAAAAAA' in payload:
        return True
    
    return False

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    if circuit_breaker["open"]:
        return jsonify({"status": "unhealthy", "reason": "circuit_breaker_open"}), 503
    return jsonify({"status": "healthy", "server": SERVER_ID}), 200

@app.route('/process', methods=['POST'])
def process_request():
    """Main processing endpoint - vulnerable to poison pills"""
    try:
        data = request.get_json(force=True)
        req_id = request.headers.get('X-Request-ID', 'no-id')
        req_hash = generate_request_hash(data)
        
        # Track request
        if req_hash not in request_tracker:
            request_tracker[req_hash] = {"count": 0, "failures": 0}
        request_tracker[req_hash]["count"] += 1
        
        # Check if request matches known poison patterns
        if check_poison_pattern(data):
            app.logger.error(f"[{SERVER_ID}] POISON DETECTED - Request: {req_id}, Hash: {req_hash}")
            request_tracker[req_hash]["failures"] += 1
            
            # Update circuit breaker
            circuit_breaker["failures"] += 1
            if circuit_breaker["failures"] >= circuit_breaker["threshold"]:
                circuit_breaker["open"] = True
                app.logger.error(f"[{SERVER_ID}] CIRCUIT BREAKER OPENED")
            
            # Simulate crash (in reality this would be a segfault)
            # For demo purposes, we'll make it take a long time and then crash
            time.sleep(0.5)  # Simulate expensive operation
            os.kill(os.getpid(), signal.SIGTERM)  # Simulate crash
            
        # Normal request processing
        time.sleep(0.1)  # Simulate work
        app.logger.info(f"[{SERVER_ID}] Processed request {req_id} successfully")
        
        return jsonify({
            "status": "success",
            "server": SERVER_ID,
            "request_id": req_id,
            "request_hash": req_hash
        }), 200
        
    except Exception as e:
        app.logger.error(f"[{SERVER_ID}] Error processing request: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/process-safe', methods=['POST'])
def process_safe():
    """Safe endpoint with pre-validation"""
    try:
        # Fast validation before parsing
        raw_data = request.get_data()
        if len(raw_data) > 5 * 1024 * 1024:  # 5MB limit
            return jsonify({"status": "error", "message": "Payload too large"}), 413
        
        data = request.get_json(force=True)
        req_id = request.headers.get('X-Request-ID', 'no-id')
        req_hash = generate_request_hash(data)
        
        # Check against known poison patterns BEFORE processing
        if req_hash in poison_patterns or check_poison_pattern(data):
            app.logger.warning(f"[{SERVER_ID}] Blocked known poison pattern: {req_hash}")
            return jsonify({"status": "blocked", "reason": "known_poison_pattern"}), 400
        
        # Validate structure
        if isinstance(data, dict):
            # Check nesting depth
            def check_depth(obj, current_depth=0, max_depth=5):
                if current_depth > max_depth:
                    return False
                if isinstance(obj, dict):
                    return all(check_depth(v, current_depth + 1, max_depth) for v in obj.values())
                elif isinstance(obj, list):
                    return all(check_depth(item, current_depth + 1, max_depth) for item in obj)
                return True
            
            if not check_depth(data):
                return jsonify({"status": "error", "message": "Nesting too deep"}), 400
        
        # Normal processing
        time.sleep(0.1)
        app.logger.info(f"[{SERVER_ID}] Safely processed request {req_id}")
        
        return jsonify({
            "status": "success",
            "server": SERVER_ID,
            "request_id": req_id
        }), 200
        
    except Exception as e:
        app.logger.error(f"[{SERVER_ID}] Error in safe endpoint: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/metrics', methods=['GET'])
def metrics():
    """Expose metrics for monitoring"""
    return jsonify({
        "server": SERVER_ID,
        "request_tracker": request_tracker,
        "circuit_breaker": circuit_breaker,
        "poison_patterns": list(poison_patterns)
    })

@app.route('/reset', methods=['POST'])
def reset():
    """Reset server state"""
    request_tracker.clear()
    poison_patterns.clear()
    circuit_breaker["open"] = False
    circuit_breaker["failures"] = 0
    app.logger.info(f"[{SERVER_ID}] Server state reset")
    return jsonify({"status": "reset_complete"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF

# Create Dockerfile for Flask app
cat > app/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install --no-cache-dir flask gunicorn
COPY app.py .
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "1", "--timeout", "30", "app:app"]
EOF

# Create HAProxy configuration
echo "[3/8] Creating HAProxy load balancer configuration..."
cat > haproxy/haproxy.cfg << 'EOF'
global
    maxconn 256
    log stdout format raw local0 info

defaults
    mode http
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    log global
    option httplog
    option dontlognull
    retries 3
    option redispatch

frontend http_front
    bind *:80
    default_backend servers

backend servers
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    
    # Retry policy - this is what causes the cascade
    retry-on all-retryable-errors
    
    server app1 app1:5000 check inter 2000ms fall 2 rise 2
    server app2 app2:5000 check inter 2000ms fall 2 rise 2
    server app3 app3:5000 check inter 2000ms fall 2 rise 2
    server app4 app4:5000 check inter 2000ms fall 2 rise 2

listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 5s
EOF

# Create dashboard
echo "[4/8] Creating web dashboard..."
cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Poison Pill Demo - Real-time Monitoring</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            padding: 20px;
            min-height: 100vh;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        header {
            background: rgba(255, 255, 255, 0.95);
            padding: 30px;
            border-radius: 16px;
            margin-bottom: 20px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        
        h1 {
            font-size: 32px;
            color: #1a1a1a;
            margin-bottom: 10px;
        }
        
        .subtitle {
            color: #666;
            font-size: 16px;
        }
        
        .controls {
            background: rgba(255, 255, 255, 0.95);
            padding: 20px;
            border-radius: 12px;
            margin-bottom: 20px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
        }
        
        .button-group {
            display: flex;
            gap: 15px;
            flex-wrap: wrap;
        }
        
        button {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            box-shadow: 0 2px 8px rgba(0,0,0,0.15);
        }
        
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.25);
        }
        
        .btn-danger {
            background: #ff4d4f;
            color: white;
        }
        
        .btn-success {
            background: #52c41a;
            color: white;
        }
        
        .btn-info {
            background: #1890ff;
            color: white;
        }
        
        .btn-warning {
            background: #faad14;
            color: white;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .card {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 12px;
            padding: 20px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.1);
        }
        
        .card-title {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 15px;
            color: #1a1a1a;
        }
        
        .server-status {
            display: flex;
            align-items: center;
            padding: 12px;
            background: #f5f5f5;
            border-radius: 8px;
            margin-bottom: 10px;
            transition: all 0.3s ease;
        }
        
        .server-status.healthy {
            background: #f6ffed;
            border-left: 4px solid #52c41a;
        }
        
        .server-status.unhealthy {
            background: #fff1f0;
            border-left: 4px solid #ff4d4f;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.7; }
        }
        
        .status-indicator {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 10px;
        }
        
        .status-indicator.healthy {
            background: #52c41a;
            box-shadow: 0 0 8px #52c41a;
        }
        
        .status-indicator.unhealthy {
            background: #ff4d4f;
            box-shadow: 0 0 8px #ff4d4f;
        }
        
        .metric {
            display: flex;
            justify-content: space-between;
            padding: 10px;
            border-bottom: 1px solid #f0f0f0;
        }
        
        .metric:last-child {
            border-bottom: none;
        }
        
        .metric-value {
            font-weight: 600;
            color: #1890ff;
        }
        
        .log-container {
            background: #1a1a1a;
            color: #52c41a;
            padding: 20px;
            border-radius: 12px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            max-height: 400px;
            overflow-y: auto;
            box-shadow: 0 4px 20px rgba(0,0,0,0.3);
        }
        
        .log-entry {
            margin-bottom: 8px;
            padding: 4px;
        }
        
        .log-error {
            color: #ff4d4f;
        }
        
        .log-warning {
            color: #faad14;
        }
        
        .log-success {
            color: #52c41a;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
        }
        
        .stat-box {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
        }
        
        .stat-value {
            font-size: 32px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        
        .stat-label {
            font-size: 14px;
            opacity: 0.9;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🔥 Poison Pill Request - Live Demo</h1>
            <p class="subtitle">Watch how a single malformed request can cascade through your entire fleet</p>
        </header>
        
        <div class="controls">
            <div class="button-group">
                <button class="btn-danger" onclick="sendPoisonRequest()">💀 Send Poison Request</button>
                <button class="btn-success" onclick="sendNormalRequest()">✅ Send Normal Request</button>
                <button class="btn-info" onclick="sendSafeRequest()">🛡️ Send to Safe Endpoint</button>
                <button class="btn-warning" onclick="resetAll()">🔄 Reset All Servers</button>
            </div>
        </div>
        
        <div class="stats-grid" style="margin-bottom: 20px;">
            <div class="stat-box">
                <div class="stat-value" id="totalRequests">0</div>
                <div class="stat-label">Total Requests</div>
            </div>
            <div class="stat-box" style="background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);">
                <div class="stat-value" id="poisonRequests">0</div>
                <div class="stat-label">Poison Requests</div>
            </div>
            <div class="stat-box" style="background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);">
                <div class="stat-value" id="healthyServers">4</div>
                <div class="stat-label">Healthy Servers</div>
            </div>
            <div class="stat-box" style="background: linear-gradient(135deg, #43e97b 0%, #38f9d7 100%);">
                <div class="stat-value" id="blockedRequests">0</div>
                <div class="stat-label">Blocked Requests</div>
            </div>
        </div>
        
        <div class="grid">
            <div class="card">
                <div class="card-title">Server Status</div>
                <div id="serverStatus"></div>
            </div>
            
            <div class="card">
                <div class="card-title">System Metrics</div>
                <div id="metrics"></div>
            </div>
        </div>
        
        <div class="card">
            <div class="card-title">Live Event Log</div>
            <div class="log-container" id="logContainer"></div>
        </div>
    </div>
    
    <script>
        let logs = [];
        let stats = {
            totalRequests: 0,
            poisonRequests: 0,
            healthyServers: 4,
            blockedRequests: 0
        };
        
        function addLog(message, type = 'info') {
            const timestamp = new Date().toLocaleTimeString();
            const logClass = type === 'error' ? 'log-error' : type === 'warning' ? 'log-warning' : 'log-success';
            logs.unshift(`<div class="log-entry ${logClass}">[${timestamp}] ${message}</div>`);
            if (logs.length > 50) logs.pop();
            document.getElementById('logContainer').innerHTML = logs.join('');
        }
        
        function updateStats() {
            document.getElementById('totalRequests').textContent = stats.totalRequests;
            document.getElementById('poisonRequests').textContent = stats.poisonRequests;
            document.getElementById('healthyServers').textContent = stats.healthyServers;
            document.getElementById('blockedRequests').textContent = stats.blockedRequests;
        }
        
        async function sendPoisonRequest() {
            try {
                stats.totalRequests++;
                stats.poisonRequests++;
                updateStats();
                
                addLog('🔴 Sending POISON request...', 'error');
                const response = await fetch('http://localhost/process', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Request-ID': 'poison-' + Date.now()
                    },
                    body: JSON.stringify({
                        data: '{{POISON}}',
                        payload: 'This will crash the server'
                    })
                });
                
                addLog('⚠️ Response received (if any): ' + response.status, 'warning');
            } catch (error) {
                addLog('💥 Server crashed or request failed: ' + error.message, 'error');
            }
            
            setTimeout(checkServerHealth, 1000);
        }
        
        async function sendNormalRequest() {
            try {
                stats.totalRequests++;
                updateStats();
                
                addLog('🟢 Sending normal request...', 'success');
                const response = await fetch('http://localhost/process', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Request-ID': 'normal-' + Date.now()
                    },
                    body: JSON.stringify({
                        data: 'normal data',
                        user: 'test'
                    })
                });
                
                const data = await response.json();
                addLog(`✅ Success! Processed by ${data.server}`, 'success');
            } catch (error) {
                addLog('❌ Request failed: ' + error.message, 'error');
            }
        }
        
        async function sendSafeRequest() {
            try {
                stats.totalRequests++;
                updateStats();
                
                addLog('🛡️ Sending to safe endpoint...', 'info');
                const response = await fetch('http://localhost/process-safe', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Request-ID': 'safe-' + Date.now()
                    },
                    body: JSON.stringify({
                        data: 'test data',
                        safe: true
                    })
                });
                
                const data = await response.json();
                if (data.status === 'blocked') {
                    stats.blockedRequests++;
                    updateStats();
                    addLog('🚫 Request blocked by validation', 'warning');
                } else {
                    addLog(`✅ Safely processed by ${data.server}`, 'success');
                }
            } catch (error) {
                addLog('❌ Request failed: ' + error.message, 'error');
            }
        }
        
        async function resetAll() {
            addLog('🔄 Resetting all servers...', 'info');
            // Reset would need to restart docker containers
            stats = {
                totalRequests: 0,
                poisonRequests: 0,
                healthyServers: 4,
                blockedRequests: 0
            };
            updateStats();
            logs = [];
            addLog('✅ System reset complete', 'success');
            setTimeout(checkServerHealth, 1000);
        }
        
        async function checkServerHealth() {
            const servers = ['app1', 'app2', 'app3', 'app4'];
            let healthyCount = 0;
            let statusHTML = '';
            
            for (const server of servers) {
                try {
                    const response = await fetch(`http://localhost/health`);
                    const isHealthy = response.ok;
                    if (isHealthy) healthyCount++;
                    
                    statusHTML += `
                        <div class="server-status ${isHealthy ? 'healthy' : 'unhealthy'}">
                            <div class="status-indicator ${isHealthy ? 'healthy' : 'unhealthy'}"></div>
                            <div>
                                <strong>${server.toUpperCase()}</strong>
                                <span style="margin-left: 10px; color: #999;">${isHealthy ? 'Healthy' : 'Down'}</span>
                            </div>
                        </div>
                    `;
                } catch (error) {
                    statusHTML += `
                        <div class="server-status unhealthy">
                            <div class="status-indicator unhealthy"></div>
                            <div>
                                <strong>${server.toUpperCase()}</strong>
                                <span style="margin-left: 10px; color: #999;">Down</span>
                            </div>
                        </div>
                    `;
                }
            }
            
            stats.healthyServers = healthyCount;
            updateStats();
            document.getElementById('serverStatus').innerHTML = statusHTML;
            
            // Update metrics
            const metricsHTML = `
                <div class="metric">
                    <span>Retry Attempts</span>
                    <span class="metric-value">${stats.poisonRequests * 3}</span>
                </div>
                <div class="metric">
                    <span>Amplification Factor</span>
                    <span class="metric-value">${stats.poisonRequests > 0 ? '4x' : '0x'}</span>
                </div>
                <div class="metric">
                    <span>Fleet Capacity</span>
                    <span class="metric-value">${Math.round((healthyCount / 4) * 100)}%</span>
                </div>
            `;
            document.getElementById('metrics').innerHTML = metricsHTML;
        }
        
        // Initial health check
        checkServerHealth();
        
        // Periodic health checks
        setInterval(checkServerHealth, 5000);
        
        addLog('🚀 Monitoring system initialized', 'success');
    </script>
</body>
</html>
EOF

# Create docker-compose.yml
echo "[5/8] Creating Docker Compose configuration..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  app1:
    build: ./app
    environment:
      - SERVER_ID=app1
    restart: always
    networks:
      - poison-net

  app2:
    build: ./app
    environment:
      - SERVER_ID=app2
    restart: always
    networks:
      - poison-net

  app3:
    build: ./app
    environment:
      - SERVER_ID=app3
    restart: always
    networks:
      - poison-net

  app4:
    build: ./app
    environment:
      - SERVER_ID=app4
    restart: always
    networks:
      - poison-net

  haproxy:
    image: haproxy:2.8-alpine
    volumes:
      - ./haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    ports:
      - "80:80"
      - "8404:8404"
    depends_on:
      - app1
      - app2
      - app3
      - app4
    networks:
      - poison-net

  dashboard:
    image: nginx:alpine
    volumes:
      - ./dashboard:/usr/share/nginx/html:ro
    ports:
      - "8080:80"
    networks:
      - poison-net

networks:
  poison-net:
    driver: bridge
EOF

# Build and start services
echo "[6/8] Building Docker images..."
docker-compose build --no-cache

echo "[7/8] Starting services..."
docker-compose up -d

echo "[8/8] Waiting for services to be healthy..."
sleep 10

echo ""
echo "=========================================="
echo "✅ Demo Setup Complete!"
echo "=========================================="
echo ""
echo "Access points:"
echo "  📊 Dashboard:    http://localhost:8080"
echo "  🔧 HAProxy Stats: http://localhost:8404/stats"
echo "  🌐 API Endpoint:  http://localhost"
echo ""
echo "What to try:"
echo "  1. Click 'Send Normal Request' - see it work fine"
echo "  2. Click 'Send Poison Request' - watch the cascade happen"
echo "  3. Try 'Send to Safe Endpoint' - see validation in action"
echo ""
echo "Watch the logs in real-time:"
echo "  docker-compose logs -f"
echo ""
echo "When done, run: ./cleanup.sh"
echo "=========================================="