#!/bin/bash

# Distributed Cache Topology Demonstrator
# One-click setup for understanding cache patterns and failure modes
# Compatible with latest Python 3.12 and modern Docker

set -e

PROJECT_NAME="cache-topology-demo"
PROJECT_DIR=$(pwd)/$PROJECT_NAME

echo "🚀 Setting up Distributed Cache Topology Demonstrator..."

# Create project structure
create_project_structure() {
    echo "📁 Creating project structure..."
    
    rm -rf $PROJECT_DIR
    mkdir -p $PROJECT_DIR/{app,templates,static/{css,js},config,tests,logs}
    cd $PROJECT_DIR
    
    echo "✅ Project structure created"
}

# Create Python requirements
create_requirements() {
    echo "📦 Creating requirements.txt..."
    
    cat > requirements.txt << 'EOF'
flask==3.0.0
redis==5.0.1
flask-socketio==5.3.6
eventlet==0.33.3
requests==2.31.0
numpy==1.26.2
psutil==5.9.6
python-dotenv==1.0.0
gunicorn==21.2.0
prometheus-client==0.19.0
flask-cors==4.0.0
jinja2==3.1.2
markupsafe==2.1.3
EOF
    
    echo "✅ Requirements file created"
}

# Create main Flask application
create_main_app() {
    echo "🐍 Creating main application..."
    
    cat > app/main.py << 'EOF'
import os
import time
import json
import random
import threading
from datetime import datetime, timedelta
from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit
from flask_cors import CORS
import redis
import logging

app = Flask(__name__, template_folder='../templates', static_folder='../static')
app.config['SECRET_KEY'] = 'cache_demo_secret_key'
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Redis connections for different cache topologies
cache_configs = {
    'cache_aside': {'host': 'redis-primary', 'port': 6379, 'db': 0},
    'write_through': {'host': 'redis-primary', 'port': 6379, 'db': 1},
    'write_behind': {'host': 'redis-primary', 'port': 6379, 'db': 2},
    'read_through': {'host': 'redis-primary', 'port': 6379, 'db': 3}
}

redis_clients = {}
metrics = {
    'cache_hits': 0,
    'cache_misses': 0,
    'database_queries': 0,
    'write_operations': 0,
    'consistency_violations': 0
}

# Simulated database
database = {}
write_behind_queue = []

class CacheTopologyDemo:
    def __init__(self):
        self.connect_redis()
        self.start_background_tasks()
    
    def connect_redis(self):
        """Initialize Redis connections for different cache patterns"""
        for pattern, config in cache_configs.items():
            try:
                client = redis.Redis(
                    host=config['host'], 
                    port=config['port'], 
                    db=config['db'],
                    decode_responses=True,
                    socket_connect_timeout=5,
                    socket_timeout=5,
                    retry_on_timeout=True
                )
                client.ping()
                redis_clients[pattern] = client
                logger.info(f"Connected to Redis for {pattern}")
            except Exception as e:
                logger.error(f"Failed to connect to Redis for {pattern}: {e}")
                # Create mock client for demo
                redis_clients[pattern] = MockRedisClient()
    
    def start_background_tasks(self):
        """Start background tasks for write-behind and monitoring"""
        threading.Thread(target=self.write_behind_worker, daemon=True).start()
        threading.Thread(target=self.metrics_broadcaster, daemon=True).start()
    
    def write_behind_worker(self):
        """Process write-behind queue"""
        while True:
            try:
                if write_behind_queue:
                    item = write_behind_queue.pop(0)
                    # Simulate database write delay
                    time.sleep(0.1)
                    database[item['key']] = item['value']
                    logger.info(f"Write-behind: Persisted {item['key']} to database")
                time.sleep(0.5)
            except Exception as e:
                logger.error(f"Write-behind worker error: {e}")
    
    def metrics_broadcaster(self):
        """Broadcast metrics to connected clients"""
        while True:
            try:
                socketio.emit('metrics_update', metrics)
                time.sleep(1)
            except Exception as e:
                logger.error(f"Metrics broadcaster error: {e}")
    
    # Cache Pattern Implementations
    
    def cache_aside_get(self, key):
        """Cache-aside pattern with TTL jitter"""
        try:
            # Check cache first
            value = redis_clients['cache_aside'].get(key)
            if value:
                metrics['cache_hits'] += 1
                logger.info(f"Cache-aside HIT: {key}")
                return json.loads(value)
            
            # Cache miss - query database
            metrics['cache_misses'] += 1
            metrics['database_queries'] += 1
            
            # Simulate database query
            time.sleep(0.05)  # 50ms database latency
            
            if key in database:
                db_value = database[key]
            else:
                db_value = f"data_for_{key}_{int(time.time())}"
                database[key] = db_value
            
            # Store in cache with jitter (TTL between 30-36 seconds)
            ttl = 30 + random.randint(0, 6)
            redis_clients['cache_aside'].setex(key, ttl, json.dumps(db_value))
            
            logger.info(f"Cache-aside MISS: {key}, stored with TTL {ttl}s")
            return db_value
            
        except Exception as e:
            logger.error(f"Cache-aside error: {e}")
            return f"error_{key}"
    
    def write_through_set(self, key, value):
        """Write-through pattern - synchronous database update"""
        try:
            # Write to database first (synchronous)
            time.sleep(0.1)  # 100ms database write latency
            database[key] = value
            metrics['database_queries'] += 1
            
            # Then update cache
            redis_clients['write_through'].setex(key, 60, json.dumps(value))
            metrics['write_operations'] += 1
            
            logger.info(f"Write-through: {key} -> {value}")
            return True
            
        except Exception as e:
            logger.error(f"Write-through error: {e}")
            return False
    
    def write_behind_set(self, key, value):
        """Write-behind pattern - asynchronous database update"""
        try:
            # Update cache immediately
            redis_clients['write_behind'].setex(key, 60, json.dumps(value))
            metrics['write_operations'] += 1
            
            # Queue for background database write
            write_behind_queue.append({'key': key, 'value': value, 'timestamp': time.time()})
            
            logger.info(f"Write-behind: {key} cached, queued for DB write")
            return True
            
        except Exception as e:
            logger.error(f"Write-behind error: {e}")
            return False
    
    def simulate_cache_stampede(self, key, num_requests=10):
        """Simulate cache stampede scenario"""
        def stampede_request():
            self.cache_aside_get(f"popular_{key}")
        
        # Clear cache to force miss
        try:
            redis_clients['cache_aside'].delete(f"popular_{key}")
        except:
            pass
        
        # Launch concurrent requests
        threads = []
        for i in range(num_requests):
            thread = threading.Thread(target=stampede_request)
            threads.append(thread)
            thread.start()
        
        for thread in threads:
            thread.join()
        
        logger.info(f"Cache stampede simulation completed: {num_requests} concurrent requests")
    
    def inject_network_partition(self, duration=10):
        """Simulate network partition by disconnecting Redis"""
        logger.info(f"Injecting network partition for {duration} seconds")
        
        # Store original clients
        original_clients = redis_clients.copy()
        
        # Replace with mock clients (simulate network failure)
        for pattern in redis_clients:
            redis_clients[pattern] = MockRedisClient()
        
        def restore_connection():
            time.sleep(duration)
            redis_clients.update(original_clients)
            logger.info("Network partition resolved - connections restored")
        
        threading.Thread(target=restore_connection, daemon=True).start()

class MockRedisClient:
    """Mock Redis client for simulating network failures"""
    def __init__(self):
        self.data = {}
    
    def get(self, key):
        return None  # Simulate cache miss during partition
    
    def setex(self, key, ttl, value):
        pass  # Simulate failed write during partition
    
    def delete(self, key):
        pass

# Initialize demo
demo = CacheTopologyDemo()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/cache-aside/<key>')
def cache_aside_api(key):
    start_time = time.time()
    value = demo.cache_aside_get(key)
    latency = (time.time() - start_time) * 1000
    
    return jsonify({
        'pattern': 'cache-aside',
        'key': key,
        'value': value,
        'latency_ms': round(latency, 2),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/write-through', methods=['POST'])
def write_through_api():
    data = request.get_json()
    key = data.get('key')
    value = data.get('value')
    
    start_time = time.time()
    success = demo.write_through_set(key, value)
    latency = (time.time() - start_time) * 1000
    
    return jsonify({
        'pattern': 'write-through',
        'success': success,
        'latency_ms': round(latency, 2),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/write-behind', methods=['POST'])
def write_behind_api():
    data = request.get_json()
    key = data.get('key')
    value = data.get('value')
    
    start_time = time.time()
    success = demo.write_behind_set(key, value)
    latency = (time.time() - start_time) * 1000
    
    return jsonify({
        'pattern': 'write-behind',
        'success': success,
        'latency_ms': round(latency, 2),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/stampede/<key>')
def simulate_stampede(key):
    threading.Thread(target=demo.simulate_cache_stampede, args=(key, 20), daemon=True).start()
    return jsonify({'message': f'Cache stampede simulation started for key: {key}'})

@app.route('/api/partition/<int:duration>')
def simulate_partition(duration):
    threading.Thread(target=demo.inject_network_partition, args=(duration,), daemon=True).start()
    return jsonify({'message': f'Network partition injected for {duration} seconds'})

@app.route('/api/metrics')
def get_metrics():
    return jsonify(metrics)

@app.route('/api/health')
def health_check():
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
EOF
    
    echo "✅ Main application created"
}

# Create HTML template
create_template() {
    echo "🎨 Creating web interface template..."
    
    cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Distributed Cache Topology Demonstrator</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <script src="https://cdn.socket.io/4.7.2/socket.io.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        .topology-card { transition: all 0.3s ease; border-left: 4px solid #007bff; }
        .topology-card:hover { transform: translateY(-2px); box-shadow: 0 4px 8px rgba(0,0,0,0.1); }
        .metrics-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
        .status-indicator { width: 12px; height: 12px; border-radius: 50%; margin-right: 8px; }
        .status-healthy { background-color: #28a745; }
        .status-degraded { background-color: #ffc107; }
        .status-failed { background-color: #dc3545; }
        .log-container { background: #1e1e1e; color: #00ff00; font-family: 'Courier New', monospace; border-radius: 8px; }
    </style>
</head>
<body class="bg-light">
    <nav class="navbar navbar-dark bg-primary">
        <div class="container">
            <span class="navbar-brand mb-0 h1">
                <i class="fas fa-database"></i> Distributed Cache Topology Demonstrator
            </span>
            <div class="d-flex align-items-center">
                <span class="status-indicator" id="connection-status"></span>
                <span id="connection-text">Connecting...</span>
            </div>
        </div>
    </nav>

    <div class="container mt-4">
        <!-- Metrics Dashboard -->
        <div class="row mb-4">
            <div class="col-md-12">
                <div class="card metrics-card">
                    <div class="card-body">
                        <h5 class="card-title"><i class="fas fa-chart-line"></i> Real-time Metrics</h5>
                        <div class="row text-center">
                            <div class="col-md-2">
                                <h3 id="cache-hits">0</h3>
                                <small>Cache Hits</small>
                            </div>
                            <div class="col-md-2">
                                <h3 id="cache-misses">0</h3>
                                <small>Cache Misses</small>
                            </div>
                            <div class="col-md-2">
                                <h3 id="db-queries">0</h3>
                                <small>DB Queries</small>
                            </div>
                            <div class="col-md-2">
                                <h3 id="write-ops">0</h3>
                                <small>Write Ops</small>
                            </div>
                            <div class="col-md-2">
                                <h3 id="hit-ratio">0%</h3>
                                <small>Hit Ratio</small>
                            </div>
                            <div class="col-md-2">
                                <h3 id="violations">0</h3>
                                <small>Violations</small>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Cache Topology Patterns -->
        <div class="row">
            <div class="col-md-6 mb-4">
                <div class="card topology-card">
                    <div class="card-header bg-primary text-white">
                        <h5><i class="fas fa-layer-group"></i> Cache-Aside Pattern</h5>
                    </div>
                    <div class="card-body">
                        <p>Application manages cache population. Lazy loading with TTL jitter.</p>
                        <div class="input-group mb-3">
                            <input type="text" class="form-control" id="cache-aside-key" placeholder="Enter key">
                            <button class="btn btn-primary" onclick="testCacheAside()">
                                <i class="fas fa-search"></i> Get Value
                            </button>
                        </div>
                        <div id="cache-aside-result" class="mt-2"></div>
                    </div>
                </div>
            </div>

            <div class="col-md-6 mb-4">
                <div class="card topology-card">
                    <div class="card-header bg-success text-white">
                        <h5><i class="fas fa-arrow-right"></i> Write-Through Pattern</h5>
                    </div>
                    <div class="card-body">
                        <p>Synchronous writes to both cache and database. Strong consistency.</p>
                        <div class="input-group mb-2">
                            <input type="text" class="form-control" id="write-through-key" placeholder="Key">
                        </div>
                        <div class="input-group mb-3">
                            <input type="text" class="form-control" id="write-through-value" placeholder="Value">
                            <button class="btn btn-success" onclick="testWriteThrough()">
                                <i class="fas fa-save"></i> Write
                            </button>
                        </div>
                        <div id="write-through-result" class="mt-2"></div>
                    </div>
                </div>
            </div>

            <div class="col-md-6 mb-4">
                <div class="card topology-card">
                    <div class="card-header bg-warning text-white">
                        <h5><i class="fas fa-clock"></i> Write-Behind Pattern</h5>
                    </div>
                    <div class="card-body">
                        <p>Asynchronous database writes. Better performance, eventual consistency.</p>
                        <div class="input-group mb-2">
                            <input type="text" class="form-control" id="write-behind-key" placeholder="Key">
                        </div>
                        <div class="input-group mb-3">
                            <input type="text" class="form-control" id="write-behind-value" placeholder="Value">
                            <button class="btn btn-warning" onclick="testWriteBehind()">
                                <i class="fas fa-fast-forward"></i> Write Async
                            </button>
                        </div>
                        <div id="write-behind-result" class="mt-2"></div>
                    </div>
                </div>
            </div>

            <div class="col-md-6 mb-4">
                <div class="card topology-card">
                    <div class="card-header bg-danger text-white">
                        <h5><i class="fas fa-exclamation-triangle"></i> Failure Simulation</h5>
                    </div>
                    <div class="card-body">
                        <p>Test cache behavior under failure conditions.</p>
                        <div class="d-grid gap-2">
                            <button class="btn btn-outline-danger" onclick="simulateStampede()">
                                <i class="fas fa-bolt"></i> Cache Stampede
                            </button>
                            <button class="btn btn-outline-warning" onclick="simulatePartition()">
                                <i class="fas fa-network-wired"></i> Network Partition
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Live Logs -->
        <div class="row">
            <div class="col-md-12">
                <div class="card">
                    <div class="card-header bg-dark text-white">
                        <h5><i class="fas fa-terminal"></i> Live System Logs</h5>
                    </div>
                    <div class="card-body log-container" id="logs" style="height: 300px; overflow-y: auto;">
                        <div>System starting up...</div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        const socket = io();
        let logCount = 0;

        // Socket.IO event handlers
        socket.on('connect', function() {
            document.getElementById('connection-status').className = 'status-indicator status-healthy';
            document.getElementById('connection-text').textContent = 'Connected';
            addLog('Connected to server');
        });

        socket.on('disconnect', function() {
            document.getElementById('connection-status').className = 'status-indicator status-failed';
            document.getElementById('connection-text').textContent = 'Disconnected';
            addLog('Disconnected from server');
        });

        socket.on('metrics_update', function(metrics) {
            updateMetrics(metrics);
        });

        function updateMetrics(metrics) {
            document.getElementById('cache-hits').textContent = metrics.cache_hits || 0;
            document.getElementById('cache-misses').textContent = metrics.cache_misses || 0;
            document.getElementById('db-queries').textContent = metrics.database_queries || 0;
            document.getElementById('write-ops').textContent = metrics.write_operations || 0;
            document.getElementById('violations').textContent = metrics.consistency_violations || 0;
            
            const totalRequests = (metrics.cache_hits || 0) + (metrics.cache_misses || 0);
            const hitRatio = totalRequests > 0 ? ((metrics.cache_hits || 0) / totalRequests * 100).toFixed(1) : 0;
            document.getElementById('hit-ratio').textContent = hitRatio + '%';
        }

        function addLog(message) {
            const logs = document.getElementById('logs');
            const timestamp = new Date().toLocaleTimeString();
            const logEntry = document.createElement('div');
            logEntry.innerHTML = `[${timestamp}] ${message}`;
            logs.appendChild(logEntry);
            logs.scrollTop = logs.scrollHeight;
            
            // Keep only last 100 log entries
            if (logs.children.length > 100) {
                logs.removeChild(logs.firstChild);
            }
        }

        async function testCacheAside() {
            const key = document.getElementById('cache-aside-key').value;
            if (!key) return;

            addLog(`Testing cache-aside pattern for key: ${key}`);
            
            try {
                const response = await fetch(`/api/cache-aside/${key}`);
                const result = await response.json();
                
                const resultDiv = document.getElementById('cache-aside-result');
                resultDiv.innerHTML = `
                    <div class="alert alert-info">
                        <strong>Result:</strong> ${result.value}<br>
                        <strong>Latency:</strong> ${result.latency_ms}ms<br>
                        <strong>Pattern:</strong> ${result.pattern}
                    </div>
                `;
                
                addLog(`Cache-aside result: ${result.value} (${result.latency_ms}ms)`);
            } catch (error) {
                addLog(`Error: ${error.message}`);
            }
        }

        async function testWriteThrough() {
            const key = document.getElementById('write-through-key').value;
            const value = document.getElementById('write-through-value').value;
            if (!key || !value) return;

            addLog(`Testing write-through pattern: ${key} = ${value}`);
            
            try {
                const response = await fetch('/api/write-through', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({key, value})
                });
                const result = await response.json();
                
                const resultDiv = document.getElementById('write-through-result');
                resultDiv.innerHTML = `
                    <div class="alert ${result.success ? 'alert-success' : 'alert-danger'}">
                        <strong>Status:</strong> ${result.success ? 'Success' : 'Failed'}<br>
                        <strong>Latency:</strong> ${result.latency_ms}ms<br>
                        <strong>Pattern:</strong> ${result.pattern}
                    </div>
                `;
                
                addLog(`Write-through result: ${result.success ? 'Success' : 'Failed'} (${result.latency_ms}ms)`);
            } catch (error) {
                addLog(`Error: ${error.message}`);
            }
        }

        async function testWriteBehind() {
            const key = document.getElementById('write-behind-key').value;
            const value = document.getElementById('write-behind-value').value;
            if (!key || !value) return;

            addLog(`Testing write-behind pattern: ${key} = ${value}`);
            
            try {
                const response = await fetch('/api/write-behind', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({key, value})
                });
                const result = await response.json();
                
                const resultDiv = document.getElementById('write-behind-result');
                resultDiv.innerHTML = `
                    <div class="alert ${result.success ? 'alert-success' : 'alert-danger'}">
                        <strong>Status:</strong> ${result.success ? 'Success' : 'Failed'}<br>
                        <strong>Latency:</strong> ${result.latency_ms}ms<br>
                        <strong>Pattern:</strong> ${result.pattern}
                    </div>
                `;
                
                addLog(`Write-behind result: ${result.success ? 'Success' : 'Failed'} (${result.latency_ms}ms)`);
            } catch (error) {
                addLog(`Error: ${error.message}`);
            }
        }

        async function simulateStampede() {
            addLog('Initiating cache stampede simulation...');
            
            try {
                const response = await fetch('/api/stampede/popular_item');
                const result = await response.json();
                addLog(result.message);
            } catch (error) {
                addLog(`Error: ${error.message}`);
            }
        }

        async function simulatePartition() {
            addLog('Initiating network partition simulation...');
            
            try {
                const response = await fetch('/api/partition/10');
                const result = await response.json();
                addLog(result.message);
            } catch (error) {
                addLog(`Error: ${error.message}`);
            }
        }

        // Auto-refresh metrics
        setInterval(async () => {
            try {
                const response = await fetch('/api/metrics');
                const metrics = await response.json();
                updateMetrics(metrics);
            } catch (error) {
                // Ignore errors for auto-refresh
            }
        }, 2000);
    </script>
</body>
</html>
EOF
    
    echo "✅ Web interface template created"
}

# Create Docker configuration
create_docker_config() {
    echo "🐳 Creating Docker configuration..."
    
    cat > Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 5000

# Run application
CMD ["python", "app/main.py"]
EOF

    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis-primary:
    image: redis:7.2-alpine
    container_name: cache-demo-redis
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  cache-demo:
    build: .
    container_name: cache-demo-app
    ports:
      - "5000:5000"
    depends_on:
      redis-primary:
        condition: service_healthy
    environment:
      - FLASK_ENV=development
      - REDIS_HOST=redis-primary
    volumes:
      - ./logs:/app/logs

volumes:
  redis_data:
EOF
    
    echo "✅ Docker configuration created"
}

# Create test suite
create_tests() {
    echo "🧪 Creating test suite..."
    
    cat > tests/test_cache_patterns.py << 'EOF'
import unittest
import requests
import time
import json
from concurrent.futures import ThreadPoolExecutor
import threading

class TestCachePatterns(unittest.TestCase):
    BASE_URL = "http://localhost:5000"
    
    def setUp(self):
        """Setup test environment"""
        # Wait for application to be ready
        max_retries = 30
        for i in range(max_retries):
            try:
                response = requests.get(f"{self.BASE_URL}/api/health", timeout=5)
                if response.status_code == 200:
                    break
            except requests.exceptions.RequestException:
                if i == max_retries - 1:
                    self.fail("Application not ready after 30 seconds")
                time.sleep(1)
    
    def test_cache_aside_pattern(self):
        """Test cache-aside pattern functionality"""
        print("\n🧪 Testing Cache-Aside Pattern...")
        
        # Test cache miss (first request)
        response = requests.get(f"{self.BASE_URL}/api/cache-aside/test_key_1")
        self.assertEqual(response.status_code, 200)
        
        result = response.json()
        self.assertEqual(result['pattern'], 'cache-aside')
        self.assertIn('value', result)
        self.assertIn('latency_ms', result)
        
        print(f"✅ Cache miss latency: {result['latency_ms']}ms")
        
        # Test cache hit (second request for same key)
        response = requests.get(f"{self.BASE_URL}/api/cache-aside/test_key_1")
        self.assertEqual(response.status_code, 200)
        
        result2 = response.json()
        self.assertEqual(result2['pattern'], 'cache-aside')
        
        # Cache hit should be faster than cache miss
        print(f"✅ Cache hit latency: {result2['latency_ms']}ms")
        
    def test_write_through_pattern(self):
        """Test write-through pattern functionality"""
        print("\n🧪 Testing Write-Through Pattern...")
        
        test_data = {
            "key": "write_through_test",
            "value": "test_value_123"
        }
        
        response = requests.post(
            f"{self.BASE_URL}/api/write-through",
            json=test_data,
            headers={'Content-Type': 'application/json'}
        )
        
        self.assertEqual(response.status_code, 200)
        result = response.json()
        
        self.assertEqual(result['pattern'], 'write-through')
        self.assertTrue(result['success'])
        self.assertIn('latency_ms', result)
        
        print(f"✅ Write-through latency: {result['latency_ms']}ms")
        
    def test_write_behind_pattern(self):
        """Test write-behind pattern functionality"""
        print("\n🧪 Testing Write-Behind Pattern...")
        
        test_data = {
            "key": "write_behind_test",
            "value": "async_test_value"
        }
        
        response = requests.post(
            f"{self.BASE_URL}/api/write-behind",
            json=test_data,
            headers={'Content-Type': 'application/json'}
        )
        
        self.assertEqual(response.status_code, 200)
        result = response.json()
        
        self.assertEqual(result['pattern'], 'write-behind')
        self.assertTrue(result['success'])
        self.assertIn('latency_ms', result)
        
        # Write-behind should be faster than write-through
        print(f"✅ Write-behind latency: {result['latency_ms']}ms")
        
    def test_cache_stampede_simulation(self):
        """Test cache stampede simulation"""
        print("\n🧪 Testing Cache Stampede Simulation...")
        
        response = requests.get(f"{self.BASE_URL}/api/stampede/stampede_test")
        self.assertEqual(response.status_code, 200)
        
        result = response.json()
        self.assertIn('message', result)
        
        print("✅ Cache stampede simulation started successfully")
        
    def test_network_partition_simulation(self):
        """Test network partition simulation"""
        print("\n🧪 Testing Network Partition Simulation...")
        
        response = requests.get(f"{self.BASE_URL}/api/partition/5")
        self.assertEqual(response.status_code, 200)
        
        result = response.json()
        self.assertIn('message', result)
        
        print("✅ Network partition simulation started successfully")
        
    def test_concurrent_access(self):
        """Test concurrent access patterns"""
        print("\n🧪 Testing Concurrent Access...")
        
        def make_request(i):
            response = requests.get(f"{self.BASE_URL}/api/cache-aside/concurrent_test_{i}")
            return response.status_code == 200
        
        # Test 10 concurrent requests
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(make_request, i) for i in range(10)]
            results = [future.result() for future in futures]
        
        # All requests should succeed
        self.assertTrue(all(results))
        print("✅ All concurrent requests completed successfully")
        
    def test_metrics_endpoint(self):
        """Test metrics collection"""
        print("\n🧪 Testing Metrics Collection...")
        
        response = requests.get(f"{self.BASE_URL}/api/metrics")
        self.assertEqual(response.status_code, 200)
        
        metrics = response.json()
        required_metrics = ['cache_hits', 'cache_misses', 'database_queries', 'write_operations']
        
        for metric in required_metrics:
            self.assertIn(metric, metrics)
            self.assertIsInstance(metrics[metric], (int, float))
        
        print("✅ All required metrics are present and valid")

if __name__ == '__main__':
    print("🚀 Starting Cache Topology Tests...")
    unittest.main(verbosity=2)
EOF
    
    echo "✅ Test suite created"
}

# Create startup script
create_startup_script() {
    echo "🚀 Creating startup script..."
    
    cat > start_demo.sh << 'EOF'
#!/bin/bash

echo "🚀 Starting Distributed Cache Topology Demonstrator..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Build and start services
echo "🔨 Building Docker images..."
docker-compose build

echo "🏃 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check if services are healthy
if docker-compose ps | grep -q "unhealthy\|Exit"; then
    echo "❌ Some services failed to start properly"
    docker-compose logs
    exit 1
fi

echo "✅ All services are running!"
echo ""
echo "🌐 Access points:"
echo "   Web Interface: http://localhost:5000"
echo "   Redis: localhost:6379"
echo ""
echo "🧪 Run tests:"
echo "   python tests/test_cache_patterns.py"
echo ""
echo "📊 To view logs:"
echo "   docker-compose logs -f cache-demo"
echo ""
echo "🛑 To stop:"
echo "   docker-compose down"
EOF

    chmod +x start_demo.sh
    
    echo "✅ Startup script created"
}

# Create README with instructions
create_readme() {
    echo "📖 Creating README..."
    
    cat > README.md << 'EOF'
# Distributed Cache Topology Demonstrator

A comprehensive demonstration of distributed caching patterns and failure modes.

## Quick Start

```bash
# Start the demonstration
./start_demo.sh

# Access web interface
open http://localhost:5000
```

## Features

### Cache Patterns Demonstrated
- **Cache-Aside**: Lazy loading with TTL jitter to prevent stampedes
- **Write-Through**: Synchronous cache and database updates
- **Write-Behind**: Asynchronous database writes for better performance

### Failure Simulations
- **Cache Stampede**: Multiple concurrent requests for expired data
- **Network Partition**: Redis connectivity failures
- **Performance Analysis**: Real-time metrics and latency tracking

### Testing Scenarios

1. **Basic Functionality**
   ```bash
   python tests/test_cache_patterns.py
   ```

2. **Cache-Aside Pattern**
   - Enter key "user_123" in Cache-Aside section
   - Click "Get Value" - observe cache MISS latency
   - Click again - observe cache HIT latency (faster)

3. **Write Patterns Comparison**
   - Test Write-Through: Enter key/value, observe synchronous latency
   - Test Write-Behind: Enter key/value, observe async latency (faster)

4. **Failure Scenarios**
   - Click "Cache Stampede" - watch logs for concurrent requests
   - Click "Network Partition" - observe degraded performance

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Flask App     │    │  Redis Cluster  │    │   Database      │
│  (Cache Logic)  │◄──►│   (4 DBs for    │◄──►│  (Simulated)    │
│                 │    │   different     │    │                 │
│                 │    │   patterns)     │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲
         │ WebSocket
         ▼
┌─────────────────┐
│   Web UI        │
│ (Real-time      │
│  Monitoring)    │
└─────────────────┘
```

## Key Insights Demonstrated

### Performance Characteristics
- Cache-aside miss: ~55ms (includes DB query)
- Cache-aside hit: ~5ms (cache only)
- Write-through: ~105ms (synchronous DB write)
- Write-behind: ~5ms (async DB write)

### Consistency Models
- **Strong Consistency**: Write-through pattern
- **Eventual Consistency**: Write-behind pattern
- **Best Effort**: Cache-aside with TTL

### Failure Patterns
- **Stampede Prevention**: TTL jitter (30-36 seconds)
- **Graceful Degradation**: Mock clients during partitions
- **Observability**: Real-time metrics and logging

## Troubleshooting

### Port Conflicts
```bash
# If port 5000 is busy
docker-compose down
# Edit docker-compose.yml to change port mapping
# Then restart
docker-compose up -d
```

### Redis Connection Issues
```bash
# Check Redis health
docker-compose exec redis-primary redis-cli ping

# View Redis logs
docker-compose logs redis-primary
```

### Application Errors
```bash
# View application logs
docker-compose logs cache-demo

# Check container status
docker-compose ps
```

## Cleanup

```bash
# Stop all services
docker-compose down

# Remove volumes (clears Redis data)
docker-compose down -v

# Remove built images
docker-compose down --rmi all
```

## Educational Value

This demonstration provides hands-on experience with:

1. **Cache Pattern Selection**: Understanding when to use each pattern
2. **Performance Trade-offs**: Measuring latency vs consistency trade-offs
3. **Failure Handling**: Observing system behavior during outages
4. **Scalability Patterns**: TTL jitter and stampede prevention
5. **Production Readiness**: Monitoring, logging, and health checks

Perfect for system design interviews, production architecture decisions, and team education on distributed caching concepts.
EOF
    
    echo "✅ README created"
}

# Main execution
main() {
    echo "🎯 Distributed Cache Topology Demonstrator Setup"
    echo "================================================="
    
    create_project_structure
    create_requirements
    create_main_app
    create_template
    create_docker_config
    create_tests
    create_startup_script
    create_readme
    
    echo ""
    echo "✅ Setup completed successfully!"
    echo ""
    echo "🚀 Next steps:"
    echo "   cd $PROJECT_NAME"
    echo "   ./start_demo.sh"
    echo ""
    echo "🌐 Then open: http://localhost:5000"
    echo ""
    echo "🧪 Run tests with: python tests/test_cache_patterns.py"
    echo ""
    echo "📚 Read README.md for detailed instructions"
}

# Run main function
main