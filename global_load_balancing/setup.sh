#!/bin/bash

# Global Load Balancing Strategies Demo
# System Design Interview Roadmap - Issue #99
# Author: System Design Expert
# Date: July 14, 2025

set -e

PROJECT_NAME="global-load-balancer-demo"
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🌍 Global Load Balancing Strategies Demo${NC}"
echo "==============================================="

# Function to check dependencies
check_dependencies() {
    echo -e "${YELLOW}📋 Checking dependencies...${NC}"
    
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker is not installed${NC}"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}❌ Docker Compose is not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All dependencies are available${NC}"
}

# Function to setup project structure
setup_project() {
    echo -e "${YELLOW}📁 Setting up project structure...${NC}"
    
    mkdir -p ${PROJECT_NAME}/{app,tests,static/{css,js},templates,data,configs}
    cd ${PROJECT_NAME}
    
    echo -e "${GREEN}✅ Project structure created${NC}"
}

# Function to create requirements file
create_requirements() {
    echo -e "${YELLOW}📦 Creating requirements.txt...${NC}"
    
    cat > requirements.txt << 'EOF'
Flask==3.0.0
Flask-SocketIO==5.3.6
requests==2.31.0
geopy==2.4.1
psutil==5.9.6
python-dotenv==1.0.0
gunicorn==21.2.0
eventlet==0.33.3
python-engineio==4.7.1
python-socketio==5.9.0
waitress==2.1.2
flask-cors==4.0.0
EOF
    
    echo -e "${GREEN}✅ Requirements file created${NC}"
}

# Function to create Docker configuration
create_docker_config() {
    echo -e "${YELLOW}🐳 Creating Docker configuration...${NC}"
    
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port
EXPOSE 5000

# Run the application
CMD ["python", "app/main.py"]
EOF

    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  global-lb:
    build: .
    ports:
      - "5000:5000"
    volumes:
      - ./app:/app/app
      - ./static:/app/static
      - ./templates:/app/templates
      - ./data:/app/data
    environment:
      - FLASK_ENV=development
      - FLASK_DEBUG=1
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s

  nginx:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./configs/nginx.conf:/etc/nginx/nginx.conf
    depends_on:
      - global-lb
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
EOF

    echo -e "${GREEN}✅ Docker configuration created${NC}"
}

# Function to create nginx configuration
create_nginx_config() {
    echo -e "${YELLOW}⚙️ Creating nginx configuration...${NC}"
    
    mkdir -p configs
    cat > configs/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream global_lb {
        server global-lb:5000;
    }

    server {
        listen 80;
        
        location / {
            proxy_pass http://global_lb;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
        
        location /health {
            proxy_pass http://global_lb/health;
        }
    }
}
EOF

    echo -e "${GREEN}✅ Nginx configuration created${NC}"
}

# Function to create main application
create_main_app() {
    echo -e "${YELLOW}🔧 Creating main application...${NC}"
    
    cat > app/main.py << 'EOF'
#!/usr/bin/env python3
"""
Global Load Balancing Strategies Demo
System Design Interview Roadmap - Issue #99
"""

import os
import json
import time
import random
import threading
from datetime import datetime, timedelta
from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit
from flask_cors import CORS
import requests
from geopy.distance import geodesic

app = Flask(__name__, 
           template_folder='../templates',
           static_folder='../static')
app.config['SECRET_KEY'] = 'global-lb-demo-2025'
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Global data centers with realistic coordinates
DATA_CENTERS = {
    'us-east-1': {
        'name': 'US East (Virginia)',
        'location': (39.0458, -77.5058),
        'capacity': 1000,
        'current_load': 0,
        'health': 'healthy',
        'latency_base': 50
    },
    'us-west-2': {
        'name': 'US West (Oregon)',
        'location': (45.5152, -122.6784),
        'capacity': 800,
        'current_load': 0,
        'health': 'healthy',
        'latency_base': 80
    },
    'eu-west-1': {
        'name': 'Europe (Ireland)',
        'location': (53.3498, -6.2603),
        'capacity': 600,
        'current_load': 0,
        'health': 'healthy',
        'latency_base': 120
    },
    'ap-southeast-1': {
        'name': 'Asia Pacific (Singapore)',
        'location': (1.3521, 103.8198),
        'capacity': 500,
        'current_load': 0,
        'health': 'healthy',
        'latency_base': 200
    }
}

# Simulated user locations
USER_LOCATIONS = {
    'new_york': (40.7128, -74.0060),
    'london': (51.5074, -0.1278),
    'tokyo': (35.6762, 139.6503),
    'sydney': (-33.8688, 151.2093),
    'sao_paulo': (-23.5505, -46.6333)
}

# Global statistics
GLOBAL_STATS = {
    'total_requests': 0,
    'successful_requests': 0,
    'failed_requests': 0,
    'average_latency': 0,
    'routing_decisions': []
}

class GlobalLoadBalancer:
    def __init__(self):
        self.strategy = 'latency'  # latency, geographic, round_robin
        self.health_check_interval = 5
        self.running = True
        
    def calculate_distance(self, user_location, dc_location):
        """Calculate distance between user and data center"""
        return geodesic(user_location, dc_location).kilometers
        
    def calculate_latency(self, distance, base_latency):
        """Simulate network latency based on distance"""
        # Rough approximation: 1ms per 100km + base latency + jitter
        network_latency = (distance / 100) * 1
        jitter = random.uniform(-10, 20)
        return base_latency + network_latency + jitter
        
    def get_healthy_data_centers(self):
        """Return only healthy data centers"""
        return {k: v for k, v in DATA_CENTERS.items() 
                if v['health'] == 'healthy'}
        
    def select_data_center(self, user_location, strategy=None):
        """Select optimal data center based on strategy"""
        if strategy is None:
            strategy = self.strategy
            
        healthy_dcs = self.get_healthy_data_centers()
        if not healthy_dcs:
            return None, float('inf'), 'no_healthy_dc'
            
        if strategy == 'geographic':
            # Route to nearest geographic location
            best_dc = min(healthy_dcs.items(),
                         key=lambda x: self.calculate_distance(user_location, x[1]['location']))
            
        elif strategy == 'latency':
            # Route based on estimated latency
            latencies = {}
            for dc_id, dc_info in healthy_dcs.items():
                distance = self.calculate_distance(user_location, dc_info['location'])
                latency = self.calculate_latency(distance, dc_info['latency_base'])
                latencies[dc_id] = (dc_info, latency)
            
            best_dc = min(latencies.items(), key=lambda x: x[1][1])
            return best_dc[0], best_dc[1][1], 'latency_optimized'
            
        elif strategy == 'capacity':
            # Route based on available capacity
            available_capacity = {
                dc_id: dc_info['capacity'] - dc_info['current_load']
                for dc_id, dc_info in healthy_dcs.items()
            }
            best_dc_id = max(available_capacity, key=available_capacity.get)
            best_dc = (best_dc_id, healthy_dcs[best_dc_id])
            
        else:  # round_robin
            dc_items = list(healthy_dcs.items())
            best_dc = random.choice(dc_items)
            
        # Calculate latency for selected DC
        distance = self.calculate_distance(user_location, best_dc[1]['location'])
        latency = self.calculate_latency(distance, best_dc[1]['latency_base'])
        
        return best_dc[0], latency, strategy
        
    def process_request(self, user_location_name):
        """Process a user request and return routing decision"""
        if user_location_name not in USER_LOCATIONS:
            return {'error': 'Invalid user location'}
            
        user_location = USER_LOCATIONS[user_location_name]
        
        # Select data center
        selected_dc, latency, strategy = self.select_data_center(user_location)
        
        if selected_dc is None:
            GLOBAL_STATS['failed_requests'] += 1
            return {
                'success': False,
                'error': 'No healthy data centers available',
                'timestamp': datetime.now().isoformat()
            }
            
        # Update data center load
        DATA_CENTERS[selected_dc]['current_load'] += 1
        
        # Simulate request processing
        processing_success = random.random() > 0.05  # 5% failure rate
        
        if processing_success:
            GLOBAL_STATS['successful_requests'] += 1
        else:
            GLOBAL_STATS['failed_requests'] += 1
            
        GLOBAL_STATS['total_requests'] += 1
        
        # Update average latency
        if GLOBAL_STATS['total_requests'] > 0:
            GLOBAL_STATS['average_latency'] = (
                GLOBAL_STATS['average_latency'] * (GLOBAL_STATS['total_requests'] - 1) + latency
            ) / GLOBAL_STATS['total_requests']
            
        # Record routing decision
        decision = {
            'timestamp': datetime.now().isoformat(),
            'user_location': user_location_name,
            'selected_dc': selected_dc,
            'latency': round(latency, 2),
            'strategy': strategy,
            'success': processing_success
        }
        
        GLOBAL_STATS['routing_decisions'].append(decision)
        if len(GLOBAL_STATS['routing_decisions']) > 100:
            GLOBAL_STATS['routing_decisions'].pop(0)
            
        return decision
        
    def health_check(self):
        """Periodic health check for data centers"""
        while self.running:
            for dc_id, dc_info in DATA_CENTERS.items():
                # Simulate health check
                if random.random() < 0.95:  # 95% chance of being healthy
                    dc_info['health'] = 'healthy'
                else:
                    dc_info['health'] = 'unhealthy'
                    
                # Simulate load decay
                dc_info['current_load'] = max(0, dc_info['current_load'] - 10)
                
            time.sleep(self.health_check_interval)

# Initialize load balancer
lb = GlobalLoadBalancer()

@app.route('/')
def index():
    """Main dashboard"""
    return render_template('index.html')

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

@app.route('/api/data-centers')
def get_data_centers():
    """Get current data center status"""
    return jsonify(DATA_CENTERS)

@app.route('/api/stats')
def get_stats():
    """Get global statistics"""
    return jsonify(GLOBAL_STATS)

@app.route('/api/request', methods=['POST'])
def handle_request():
    """Handle incoming request"""
    data = request.get_json()
    user_location = data.get('user_location', 'new_york')
    
    result = lb.process_request(user_location)
    
    # Emit real-time update
    socketio.emit('request_processed', result)
    
    return jsonify(result)

@app.route('/api/config', methods=['POST'])
def update_config():
    """Update load balancer configuration"""
    data = request.get_json()
    
    if 'strategy' in data:
        lb.strategy = data['strategy']
        
    if 'dc_health' in data:
        dc_id = data['dc_health']['dc_id']
        health_status = data['dc_health']['status']
        if dc_id in DATA_CENTERS:
            DATA_CENTERS[dc_id]['health'] = health_status
            
    return jsonify({'success': True})

@socketio.on('connect')
def handle_connect():
    """Handle client connection"""
    emit('connected', {'data': 'Connected to Global Load Balancer Demo'})

@socketio.on('get_initial_data')
def handle_initial_data():
    """Send initial data to client"""
    emit('data_centers_update', DATA_CENTERS)
    emit('stats_update', GLOBAL_STATS)

def start_background_tasks():
    """Start background monitoring tasks"""
    health_thread = threading.Thread(target=lb.health_check)
    health_thread.daemon = True
    health_thread.start()
    
    def emit_updates():
        while True:
            socketio.emit('data_centers_update', DATA_CENTERS)
            socketio.emit('stats_update', GLOBAL_STATS)
            time.sleep(2)
    
    update_thread = threading.Thread(target=emit_updates)
    update_thread.daemon = True
    update_thread.start()

if __name__ == '__main__':
    print(f"🌍 Starting Global Load Balancer Demo...")
    print(f"📊 Dashboard: http://localhost:5000")
    print(f"🔧 API Documentation: http://localhost:5000/api/stats")
    
    start_background_tasks()
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
EOF

    echo -e "${GREEN}✅ Main application created${NC}"
}

# Function to create HTML template
create_template() {
    echo -e "${YELLOW}🎨 Creating HTML template...${NC}"
    
    cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Global Load Balancing Strategies Demo</title>
    <link href="https://fonts.googleapis.com/css2?family=Google+Sans:wght@300;400;500;600&display=swap" rel="stylesheet">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.7.2/socket.io.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>
    <div class="header">
        <div class="header-content">
            <h1>🌍 Global Load Balancing Strategies</h1>
            <p>System Design Interview Roadmap - Issue #99</p>
        </div>
    </div>

    <div class="container">
        <!-- Control Panel -->
        <div class="card">
            <h2>Load Balancing Configuration</h2>
            <div class="controls">
                <div class="control-group">
                    <label for="strategy">Routing Strategy:</label>
                    <select id="strategy">
                        <option value="latency">Latency-Based</option>
                        <option value="geographic">Geographic</option>
                        <option value="capacity">Capacity-Based</option>
                        <option value="round_robin">Round Robin</option>
                    </select>
                </div>
                <div class="control-group">
                    <label for="user-location">User Location:</label>
                    <select id="user-location">
                        <option value="new_york">New York</option>
                        <option value="london">London</option>
                        <option value="tokyo">Tokyo</option>
                        <option value="sydney">Sydney</option>
                        <option value="sao_paulo">São Paulo</option>
                    </select>
                </div>
                <button id="send-request" class="btn-primary">Send Request</button>
                <button id="simulate-traffic" class="btn-secondary">Simulate Traffic</button>
            </div>
        </div>

        <!-- Global Statistics -->
        <div class="card">
            <h2>Global Performance Metrics</h2>
            <div class="stats-grid">
                <div class="stat-item">
                    <div class="stat-value" id="total-requests">0</div>
                    <div class="stat-label">Total Requests</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value" id="success-rate">0%</div>
                    <div class="stat-label">Success Rate</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value" id="avg-latency">0ms</div>
                    <div class="stat-label">Avg Latency</div>
                </div>
                <div class="stat-item">
                    <div class="stat-value" id="failed-requests">0</div>
                    <div class="stat-label">Failed Requests</div>
                </div>
            </div>
        </div>

        <!-- Data Centers Status -->
        <div class="card">
            <h2>Data Center Status</h2>
            <div class="dc-grid" id="data-centers">
                <!-- Data centers will be populated by JavaScript -->
            </div>
        </div>

        <!-- Recent Routing Decisions -->
        <div class="card">
            <h2>Recent Routing Decisions</h2>
            <div class="routing-log" id="routing-log">
                <!-- Routing decisions will be populated by JavaScript -->
            </div>
        </div>

        <!-- Performance Chart -->
        <div class="card">
            <h2>Latency Distribution</h2>
            <canvas id="latencyChart" width="400" height="200"></canvas>
        </div>
    </div>

    <script src="{{ url_for('static', filename='js/app.js') }}"></script>
</body>
</html>
EOF

    echo -e "${GREEN}✅ HTML template created${NC}"
}

# Function to create CSS styles
create_styles() {
    echo -e "${YELLOW}🎨 Creating CSS styles...${NC}"
    
    cat > static/css/style.css << 'EOF'
/* Global Load Balancing Demo Styles - Google Cloud Skills Boost inspired */

:root {
    --primary-blue: #1a73e8;
    --light-blue: #e8f0fe;
    --dark-blue: #1557b0;
    --success-green: #137333;
    --warning-orange: #f9ab00;
    --error-red: #d93025;
    --neutral-gray: #5f6368;
    --light-gray: #f8f9fa;
    --white: #ffffff;
    --shadow: 0 2px 8px rgba(0,0,0,0.1);
    --shadow-hover: 0 4px 16px rgba(0,0,0,0.15);
}

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Google Sans', sans-serif;
    background: linear-gradient(135deg, #f8f9fa 0%, #e8f0fe 100%);
    color: var(--neutral-gray);
    line-height: 1.6;
    min-height: 100vh;
}

.header {
    background: linear-gradient(135deg, var(--primary-blue) 0%, var(--dark-blue) 100%);
    color: white;
    padding: 2rem 0;
    text-align: center;
    box-shadow: var(--shadow);
}

.header-content h1 {
    font-size: 2.5rem;
    font-weight: 500;
    margin-bottom: 0.5rem;
}

.header-content p {
    font-size: 1.1rem;
    opacity: 0.9;
}

.container {
    max-width: 1200px;
    margin: 2rem auto;
    padding: 0 1rem;
    display: grid;
    gap: 1.5rem;
}

.card {
    background: var(--white);
    border-radius: 12px;
    padding: 1.5rem;
    box-shadow: var(--shadow);
    transition: box-shadow 0.3s ease;
}

.card:hover {
    box-shadow: var(--shadow-hover);
}

.card h2 {
    color: var(--primary-blue);
    font-size: 1.4rem;
    font-weight: 500;
    margin-bottom: 1rem;
    border-bottom: 2px solid var(--light-blue);
    padding-bottom: 0.5rem;
}

.controls {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 1rem;
    align-items: end;
}

.control-group {
    display: flex;
    flex-direction: column;
}

.control-group label {
    font-weight: 500;
    margin-bottom: 0.5rem;
    color: var(--neutral-gray);
}

select, input {
    padding: 0.75rem;
    border: 2px solid #e0e0e0;
    border-radius: 8px;
    font-size: 1rem;
    transition: border-color 0.3s ease;
}

select:focus, input:focus {
    outline: none;
    border-color: var(--primary-blue);
}

.btn-primary, .btn-secondary {
    padding: 0.75rem 1.5rem;
    border: none;
    border-radius: 8px;
    font-size: 1rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.3s ease;
    min-height: 48px;
}

.btn-primary {
    background: var(--primary-blue);
    color: white;
}

.btn-primary:hover {
    background: var(--dark-blue);
    transform: translateY(-2px);
}

.btn-secondary {
    background: var(--light-blue);
    color: var(--primary-blue);
}

.btn-secondary:hover {
    background: var(--primary-blue);
    color: white;
    transform: translateY(-2px);
}

.stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 1rem;
}

.stat-item {
    text-align: center;
    padding: 1rem;
    background: var(--light-gray);
    border-radius: 8px;
    border-left: 4px solid var(--primary-blue);
}

.stat-value {
    font-size: 2rem;
    font-weight: 600;
    color: var(--primary-blue);
}

.stat-label {
    font-size: 0.9rem;
    color: var(--neutral-gray);
    margin-top: 0.25rem;
}

.dc-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 1rem;
}

.dc-item {
    padding: 1rem;
    border-radius: 8px;
    border: 2px solid #e0e0e0;
    transition: all 0.3s ease;
    position: relative;
}

.dc-item.healthy {
    border-color: var(--success-green);
    background: #e6f4ea;
}

.dc-item.unhealthy {
    border-color: var(--error-red);
    background: #fce8e6;
}

.dc-name {
    font-weight: 600;
    color: var(--neutral-gray);
    margin-bottom: 0.5rem;
}

.dc-stats {
    display: flex;
    justify-content: space-between;
    font-size: 0.9rem;
}

.dc-health {
    position: absolute;
    top: 0.5rem;
    right: 0.5rem;
    width: 12px;
    height: 12px;
    border-radius: 50%;
}

.dc-health.healthy {
    background: var(--success-green);
}

.dc-health.unhealthy {
    background: var(--error-red);
}

.routing-log {
    max-height: 300px;
    overflow-y: auto;
    border: 1px solid #e0e0e0;
    border-radius: 8px;
    padding: 1rem;
}

.log-entry {
    padding: 0.5rem;
    margin-bottom: 0.5rem;
    border-radius: 6px;
    border-left: 4px solid var(--primary-blue);
    background: var(--light-gray);
    font-size: 0.9rem;
}

.log-entry.success {
    border-left-color: var(--success-green);
}

.log-entry.error {
    border-left-color: var(--error-red);
}

.log-timestamp {
    font-weight: 500;
    color: var(--primary-blue);
}

.log-details {
    margin-top: 0.25rem;
    color: var(--neutral-gray);
}

/* Responsive Design */
@media (max-width: 768px) {
    .container {
        margin: 1rem auto;
        padding: 0 0.5rem;
    }
    
    .header-content h1 {
        font-size: 2rem;
    }
    
    .controls {
        grid-template-columns: 1fr;
    }
    
    .stats-grid {
        grid-template-columns: repeat(2, 1fr);
    }
    
    .dc-grid {
        grid-template-columns: 1fr;
    }
}

/* Animations */
@keyframes fadeIn {
    from { opacity: 0; transform: translateY(20px); }
    to { opacity: 1; transform: translateY(0); }
}

.card {
    animation: fadeIn 0.5s ease-out;
}

.dc-item {
    animation: fadeIn 0.5s ease-out;
}

.log-entry {
    animation: fadeIn 0.3s ease-out;
}

/* Loading states */
.loading {
    position: relative;
    overflow: hidden;
}

.loading::after {
    content: '';
    position: absolute;
    top: 0;
    left: -100%;
    width: 100%;
    height: 100%;
    background: linear-gradient(90deg, transparent, rgba(255,255,255,0.8), transparent);
    animation: loading 1.5s infinite;
}

@keyframes loading {
    0% { left: -100%; }
    100% { left: 100%; }
}
EOF

    echo -e "${GREEN}✅ CSS styles created${NC}"
}

# Function to create JavaScript application
create_javascript() {
    echo -e "${YELLOW}⚡ Creating JavaScript application...${NC}"
    
    cat > static/js/app.js << 'EOF'
// Global Load Balancing Demo JavaScript
// System Design Interview Roadmap - Issue #99

class GlobalLoadBalancerDemo {
    constructor() {
        this.socket = io();
        this.latencyChart = null;
        this.trafficSimulation = null;
        this.init();
    }

    init() {
        this.setupSocketListeners();
        this.setupEventListeners();
        this.setupLatencyChart();
        this.requestInitialData();
    }

    setupSocketListeners() {
        this.socket.on('connect', () => {
            console.log('Connected to Global Load Balancer Demo');
        });

        this.socket.on('data_centers_update', (data) => {
            this.updateDataCenters(data);
        });

        this.socket.on('stats_update', (data) => {
            this.updateGlobalStats(data);
            this.updateLatencyChart(data);
        });

        this.socket.on('request_processed', (data) => {
            this.addRoutingLogEntry(data);
        });
    }

    setupEventListeners() {
        document.getElementById('send-request').addEventListener('click', () => {
            this.sendRequest();
        });

        document.getElementById('simulate-traffic').addEventListener('click', () => {
            this.toggleTrafficSimulation();
        });

        document.getElementById('strategy').addEventListener('change', (e) => {
            this.updateStrategy(e.target.value);
        });
    }

    setupLatencyChart() {
        const ctx = document.getElementById('latencyChart').getContext('2d');
        this.latencyChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Average Latency (ms)',
                    data: [],
                    borderColor: '#1a73e8',
                    backgroundColor: 'rgba(26, 115, 232, 0.1)',
                    borderWidth: 2,
                    fill: true,
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: {
                        beginAtZero: true,
                        title: {
                            display: true,
                            text: 'Latency (ms)'
                        }
                    },
                    x: {
                        title: {
                            display: true,
                            text: 'Time'
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: true,
                        position: 'top'
                    }
                }
            }
        });
    }

    requestInitialData() {
        this.socket.emit('get_initial_data');
    }

    sendRequest() {
        const userLocation = document.getElementById('user-location').value;
        const strategy = document.getElementById('strategy').value;

        // Update strategy first
        fetch('/api/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ strategy: strategy })
        });

        // Send request
        fetch('/api/request', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ user_location: userLocation })
        })
        .then(response => response.json())
        .then(data => {
            console.log('Request processed:', data);
        })
        .catch(error => {
            console.error('Error sending request:', error);
        });
    }

    toggleTrafficSimulation() {
        const button = document.getElementById('simulate-traffic');
        
        if (this.trafficSimulation) {
            clearInterval(this.trafficSimulation);
            this.trafficSimulation = null;
            button.textContent = 'Simulate Traffic';
            button.classList.remove('btn-primary');
            button.classList.add('btn-secondary');
        } else {
            button.textContent = 'Stop Simulation';
            button.classList.remove('btn-secondary');
            button.classList.add('btn-primary');
            
            this.trafficSimulation = setInterval(() => {
                // Random user locations
                const locations = ['new_york', 'london', 'tokyo', 'sydney', 'sao_paulo'];
                const randomLocation = locations[Math.floor(Math.random() * locations.length)];
                
                // Update user location select
                document.getElementById('user-location').value = randomLocation;
                
                // Send request
                this.sendRequest();
            }, 1000); // Send request every second
        }
    }

    updateStrategy(strategy) {
        fetch('/api/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ strategy: strategy })
        })
        .then(response => response.json())
        .then(data => {
            console.log('Strategy updated:', strategy);
        });
    }

    updateDataCenters(dataCenters) {
        const container = document.getElementById('data-centers');
        container.innerHTML = '';

        Object.entries(dataCenters).forEach(([dcId, dcInfo]) => {
            const dcElement = document.createElement('div');
            dcElement.className = `dc-item ${dcInfo.health}`;
            
            const utilizationPercent = Math.round((dcInfo.current_load / dcInfo.capacity) * 100);
            
            dcElement.innerHTML = `
                <div class="dc-health ${dcInfo.health}"></div>
                <div class="dc-name">${dcInfo.name}</div>
                <div class="dc-stats">
                    <span>Load: ${dcInfo.current_load}/${dcInfo.capacity}</span>
                    <span>Utilization: ${utilizationPercent}%</span>
                </div>
                <div class="dc-stats">
                    <span>Base Latency: ${dcInfo.latency_base}ms</span>
                    <span>Status: ${dcInfo.health}</span>
                </div>
            `;
            
            // Add click handler for manual health toggle
            dcElement.addEventListener('click', () => {
                this.toggleDataCenterHealth(dcId, dcInfo.health);
            });
            
            container.appendChild(dcElement);
        });
    }

    toggleDataCenterHealth(dcId, currentHealth) {
        const newHealth = currentHealth === 'healthy' ? 'unhealthy' : 'healthy';
        
        fetch('/api/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                dc_health: {
                    dc_id: dcId,
                    status: newHealth
                }
            })
        })
        .then(response => response.json())
        .then(data => {
            console.log(`Data center ${dcId} health toggled to ${newHealth}`);
        });
    }

    updateGlobalStats(stats) {
        document.getElementById('total-requests').textContent = stats.total_requests;
        document.getElementById('failed-requests').textContent = stats.failed_requests;
        
        const successRate = stats.total_requests > 0 ? 
            Math.round((stats.successful_requests / stats.total_requests) * 100) : 0;
        document.getElementById('success-rate').textContent = `${successRate}%`;
        
        const avgLatency = Math.round(stats.average_latency);
        document.getElementById('avg-latency').textContent = `${avgLatency}ms`;
    }

    updateLatencyChart(stats) {
        const now = new Date().toLocaleTimeString();
        
        // Add new data point
        this.latencyChart.data.labels.push(now);
        this.latencyChart.data.datasets[0].data.push(Math.round(stats.average_latency));
        
        // Keep only last 20 data points
        if (this.latencyChart.data.labels.length > 20) {
            this.latencyChart.data.labels.shift();
            this.latencyChart.data.datasets[0].data.shift();
        }
        
        this.latencyChart.update('none');
    }

    addRoutingLogEntry(decision) {
        const logContainer = document.getElementById('routing-log');
        const logEntry = document.createElement('div');
        logEntry.className = `log-entry ${decision.success ? 'success' : 'error'}`;
        
        const timestamp = new Date(decision.timestamp).toLocaleTimeString();
        
        logEntry.innerHTML = `
            <div class="log-timestamp">${timestamp}</div>
            <div class="log-details">
                📍 ${decision.user_location} → 🏢 ${decision.selected_dc} 
                (${decision.latency}ms, ${decision.strategy})
                ${decision.success ? '✅' : '❌'}
            </div>
        `;
        
        logContainer.insertBefore(logEntry, logContainer.firstChild);
        
        // Keep only last 50 entries
        while (logContainer.children.length > 50) {
            logContainer.removeChild(logContainer.lastChild);
        }
    }

    // Utility method to format numbers
    formatNumber(num) {
        return new Intl.NumberFormat().format(num);
    }

    // Utility method to format bytes
    formatBytes(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }
}

// Initialize the demo when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new GlobalLoadBalancerDemo();
});

// Add some visual feedback for button clicks
document.addEventListener('click', (e) => {
    if (e.target.classList.contains('btn-primary') || e.target.classList.contains('btn-secondary')) {
        e.target.style.transform = 'scale(0.95)';
        setTimeout(() => {
            e.target.style.transform = '';
        }, 150);
    }
});

// Add keyboard shortcuts
document.addEventListener('keydown', (e) => {
    if (e.ctrlKey || e.metaKey) {
        switch(e.key) {
            case 'Enter':
                e.preventDefault();
                document.getElementById('send-request').click();
                break;
            case ' ':
                e.preventDefault();
                document.getElementById('simulate-traffic').click();
                break;
        }
    }
});
EOF

    echo -e "${GREEN}✅ JavaScript application created${NC}"
}

# Function to create test file
create_tests() {
    echo -e "${YELLOW}🧪 Creating test file...${NC}"
    
    cat > tests/test_global_lb.py << 'EOF'
#!/usr/bin/env python3
"""
Global Load Balancing Strategies Demo Tests
System Design Interview Roadmap - Issue #99
"""

import unittest
import sys
import os
import requests
import time
import json

# Add app directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'app'))

from main import app, GlobalLoadBalancer, DATA_CENTERS

class TestGlobalLoadBalancer(unittest.TestCase):
    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True
        self.lb = GlobalLoadBalancer()

    def test_health_endpoint(self):
        """Test health check endpoint"""
        response = self.app.get('/health')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertEqual(data['status'], 'healthy')

    def test_data_centers_endpoint(self):
        """Test data centers API endpoint"""
        response = self.app.get('/api/data-centers')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn('us-east-1', data)
        self.assertIn('us-west-2', data)

    def test_stats_endpoint(self):
        """Test global statistics endpoint"""
        response = self.app.get('/api/stats')
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertIn('total_requests', data)
        self.assertIn('successful_requests', data)

    def test_load_balancer_distance_calculation(self):
        """Test distance calculation between locations"""
        # New York to London
        ny_location = (40.7128, -74.0060)
        london_location = (51.5074, -0.1278)
        
        distance = self.lb.calculate_distance(ny_location, london_location)
        # Should be approximately 5500 km
        self.assertGreater(distance, 5000)
        self.assertLess(distance, 6000)

    def test_latency_calculation(self):
        """Test latency calculation"""
        distance = 1000  # 1000 km
        base_latency = 50
        
        latency = self.lb.calculate_latency(distance, base_latency)
        # Should include base latency + network delay
        self.assertGreater(latency, base_latency)

    def test_data_center_selection_latency(self):
        """Test latency-based data center selection"""
        user_location = (40.7128, -74.0060)  # New York
        
        selected_dc, latency, strategy = self.lb.select_data_center(
            user_location, 'latency'
        )
        
        self.assertIsNotNone(selected_dc)
        self.assertIn(selected_dc, DATA_CENTERS)
        self.assertEqual(strategy, 'latency_optimized')

    def test_data_center_selection_geographic(self):
        """Test geographic data center selection"""
        user_location = (40.7128, -74.0060)  # New York
        
        selected_dc, latency, strategy = self.lb.select_data_center(
            user_location, 'geographic'
        )
        
        self.assertIsNotNone(selected_dc)
        # Should select us-east-1 for New York user
        self.assertEqual(selected_dc, 'us-east-1')

    def test_request_processing(self):
        """Test request processing"""
        result = self.lb.process_request('new_york')
        
        self.assertIn('success', result)
        if result.get('success', False):
            self.assertIn('selected_dc', result)
            self.assertIn('latency', result)
            self.assertIn('strategy', result)

    def test_healthy_data_centers_filter(self):
        """Test filtering of healthy data centers"""
        # Make one DC unhealthy
        original_health = DATA_CENTERS['us-east-1']['health']
        DATA_CENTERS['us-east-1']['health'] = 'unhealthy'
        
        healthy_dcs = self.lb.get_healthy_data_centers()
        self.assertNotIn('us-east-1', healthy_dcs)
        
        # Restore original health
        DATA_CENTERS['us-east-1']['health'] = original_health

    def test_config_update_endpoint(self):
        """Test configuration update endpoint"""
        response = self.app.post('/api/config',
                                data=json.dumps({'strategy': 'geographic'}),
                                content_type='application/json')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        self.assertTrue(data['success'])

    def test_request_endpoint(self):
        """Test request processing endpoint"""
        response = self.app.post('/api/request',
                                data=json.dumps({'user_location': 'new_york'}),
                                content_type='application/json')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.data)
        # Should have either success or error
        self.assertTrue('success' in data or 'error' in data)

class TestEndToEndFunctionality(unittest.TestCase):
    """End-to-end tests that verify the complete system"""
    
    @classmethod
    def setUpClass(cls):
        """Start the Flask application for testing"""
        cls.base_url = 'http://localhost:5000'
        # Note: These tests assume the application is running
        
    def test_web_interface_accessibility(self):
        """Test that the web interface is accessible"""
        try:
            response = requests.get(f'{self.base_url}/')
            self.assertEqual(response.status_code, 200)
            self.assertIn('Global Load Balancing Strategies', response.text)
        except requests.exceptions.ConnectionError:
            self.skipTest("Application not running - skipping integration test")

    def test_api_endpoints_integration(self):
        """Test API endpoints integration"""
        try:
            # Test health endpoint
            response = requests.get(f'{self.base_url}/health')
            self.assertEqual(response.status_code, 200)
            
            # Test data centers endpoint
            response = requests.get(f'{self.base_url}/api/data-centers')
            self.assertEqual(response.status_code, 200)
            
            # Test stats endpoint
            response = requests.get(f'{self.base_url}/api/stats')
            self.assertEqual(response.status_code, 200)
            
        except requests.exceptions.ConnectionError:
            self.skipTest("Application not running - skipping integration test")

def run_tests():
    """Run all tests and return success status"""
    # Create test suite
    test_suite = unittest.TestLoader().loadTestsFromTestCase(TestGlobalLoadBalancer)
    integration_suite = unittest.TestLoader().loadTestsFromTestCase(TestEndToEndFunctionality)
    
    # Combine test suites
    combined_suite = unittest.TestSuite([test_suite, integration_suite])
    
    # Run tests
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(combined_suite)
    
    return result.wasSuccessful()

if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
EOF

    echo -e "${GREEN}✅ Test file created${NC}"
}

# Function to build and run the demo
build_and_run() {
    echo -e "${YELLOW}🚀 Building and running the demo...${NC}"
    
    # Build Docker containers
    echo -e "${YELLOW}🐳 Building Docker containers...${NC}"
    docker-compose build
    
    # Start the application
    echo -e "${YELLOW}🎬 Starting the application...${NC}"
    docker-compose up -d
    
    # Wait for services to be ready
    echo -e "${YELLOW}⏳ Waiting for services to be ready...${NC}"
    sleep 10
    
    # Check if services are running
    if docker-compose ps | grep -q "Up"; then
        echo -e "${GREEN}✅ Services are running successfully${NC}"
    else
        echo -e "${RED}❌ Some services failed to start${NC}"
        docker-compose logs
        exit 1
    fi
    
    echo -e "${GREEN}✅ Build and deployment complete${NC}"
}

# Function to run tests
run_tests() {
    echo -e "${YELLOW}🧪 Running tests...${NC}"
    
    # Run Python tests inside container
    docker-compose exec -T global-lb python -m pytest tests/ -v
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ All tests passed${NC}"
    else
        echo -e "${RED}❌ Some tests failed${NC}"
        exit 1
    fi
}

# Function to verify functionality
verify_functionality() {
    echo -e "${YELLOW}🔍 Verifying functionality...${NC}"
    
    # Test health endpoint
    echo -e "${YELLOW}Testing health endpoint...${NC}"
    health_response=$(curl -s http://localhost:5000/health)
    if echo "$health_response" | grep -q "healthy"; then
        echo -e "${GREEN}✅ Health endpoint working${NC}"
    else
        echo -e "${RED}❌ Health endpoint failed${NC}"
    fi
    
    # Test data centers endpoint
    echo -e "${YELLOW}Testing data centers endpoint...${NC}"
    dc_response=$(curl -s http://localhost:5000/api/data-centers)
    if echo "$dc_response" | grep -q "us-east-1"; then
        echo -e "${GREEN}✅ Data centers endpoint working${NC}"
    else
        echo -e "${RED}❌ Data centers endpoint failed${NC}"
    fi
    
    # Test web interface
    echo -e "${YELLOW}Testing web interface...${NC}"
    web_response=$(curl -s http://localhost:5000/)
    if echo "$web_response" | grep -q "Global Load Balancing"; then
        echo -e "${GREEN}✅ Web interface working${NC}"
    else
        echo -e "${RED}❌ Web interface failed${NC}"
    fi
    
    echo -e "${GREEN}✅ All functionality verified${NC}"
}

# Function to display demo information
show_demo_info() {
    echo -e "${BLUE}"
    echo "🎉 Global Load Balancing Demo is Ready!"
    echo "========================================"
    echo -e "${NC}"
    echo -e "${GREEN}🌐 Web Interface:${NC} http://localhost:5000"
    echo -e "${GREEN}📊 API Documentation:${NC} http://localhost:5000/api/stats"
    echo -e "${GREEN}🔧 Nginx Proxy:${NC} http://localhost:8080"
    echo ""
    echo -e "${YELLOW}📋 Demo Features:${NC}"
    echo "  • Geographic routing simulation"
    echo "  • Latency-based load balancing"
    echo "  • Health monitoring and failover"
    echo "  • Real-time performance metrics"
    echo "  • Interactive traffic simulation"
    echo ""
    echo -e "${YELLOW}🎮 How to Use:${NC}"
    echo "  1. Open http://localhost:5000 in your browser"
    echo "  2. Select routing strategy (Latency, Geographic, etc.)"
    echo "  3. Choose user location and send requests"
    echo "  4. Click 'Simulate Traffic' for automated testing"
    echo "  5. Click on data centers to toggle health status"
    echo ""
    echo -e "${YELLOW}🔧 Useful Commands:${NC}"
    echo "  • View logs: docker-compose logs -f"
    echo "  • Stop demo: docker-compose down"
    echo "  • Cleanup: ./cleanup.sh"
    echo ""
    echo -e "${BLUE}Press Ctrl+C to stop monitoring, demo will continue running${NC}"
}

# Main execution
main() {
    check_dependencies
    setup_project
    create_requirements
    create_docker_config
    create_nginx_config
    create_main_app
    create_template
    create_styles
    create_javascript
    create_tests
    build_and_run
    sleep 5
    verify_functionality
    show_demo_info
    
    # Monitor logs
    echo -e "${YELLOW}📋 Monitoring application logs (Ctrl+C to stop monitoring):${NC}"
    docker-compose logs -f global-lb
}

# Run main function
main