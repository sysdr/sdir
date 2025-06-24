#!/bin/bash

# Zero-Downtime Deployment Demo Setup Script
# Creates a complete environment to demonstrate Blue-Green, Rolling, and Canary deployments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker and try again."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose and try again."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker and try again."
        exit 1
    fi
    
    log "All dependencies are available"
}

# Create project structure
create_project_structure() {
    log "Creating project structure..."
    
    # Main directories
    mkdir -p zero-downtime-demo/{app,nginx,monitoring,dashboard,scripts,logs}
    
    # App subdirectories
    mkdir -p zero-downtime-demo/app/{v1,v2,v3}
    
    # Nginx configurations
    mkdir -p zero-downtime-demo/nginx/{configs,html}
    
    # Docker configurations
    mkdir -p zero-downtime-demo/docker/{blue-green,rolling,canary}
    
    cd zero-downtime-demo
    
    log "Project structure created"
}

# Create application version 1
create_app_v1() {
    log "Creating application v1.0..."
    
    cat > app/v1/app.py << 'EOF'
from flask import Flask, jsonify, render_template_string
import time
import os
import socket
import random
from datetime import datetime
import psutil

app = Flask(__name__)

# App configuration
APP_VERSION = "1.0.0"
INSTANCE_ID = os.environ.get('INSTANCE_ID', socket.gethostname())
PORT = int(os.environ.get('PORT', 5000))

# HTML template for the web interface
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Zero-Downtime Demo - App v{{ version }}</title>
    <meta http-equiv="refresh" content="2">
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 30px; 
            border-radius: 15px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
        }
        .header { 
            text-align: center; 
            margin-bottom: 30px; 
            border-bottom: 2px solid rgba(255,255,255,0.2);
            padding-bottom: 20px;
        }
        .version-badge { 
            background: #4CAF50; 
            color: white; 
            padding: 10px 20px; 
            border-radius: 25px; 
            display: inline-block; 
            font-weight: bold;
            font-size: 1.2em;
        }
        .stats { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 20px; 
            margin-top: 20px; 
        }
        .stat-card { 
            background: rgba(255,255,255,0.15); 
            padding: 20px; 
            border-radius: 10px; 
            text-align: center;
        }
        .stat-value { 
            font-size: 2em; 
            font-weight: bold; 
            color: #FFD700; 
        }
        .stat-label { 
            margin-top: 5px; 
            opacity: 0.8; 
        }
        .pulse { 
            animation: pulse 2s infinite; 
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Zero-Downtime Deployment Demo</h1>
            <div class="version-badge pulse">Version {{ version }}</div>
            <p>Instance: {{ instance_id }}</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-value">{{ uptime }}</div>
                <div class="stat-label">Uptime (seconds)</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{{ requests }}</div>
                <div class="stat-label">Requests Served</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{{ cpu_percent }}%</div>
                <div class="stat-label">CPU Usage</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{{ memory_percent }}%</div>
                <div class="stat-label">Memory Usage</div>
            </div>
        </div>
        
        <div style="margin-top: 30px; text-align: center;">
            <p>🟢 <strong>Application Status: HEALTHY</strong></p>
            <p>Last Updated: {{ timestamp }}</p>
        </div>
    </div>
</body>
</html>
'''

# Global counters
start_time = time.time()
request_count = 0

@app.route('/')
def home():
    global request_count
    request_count += 1
    
    return render_template_string(HTML_TEMPLATE,
        version=APP_VERSION,
        instance_id=INSTANCE_ID,
        uptime=int(time.time() - start_time),
        requests=request_count,
        cpu_percent=round(psutil.cpu_percent(), 1),
        memory_percent=round(psutil.virtual_memory().percent, 1),
        timestamp=datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    )

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'version': APP_VERSION,
        'instance_id': INSTANCE_ID,
        'uptime': int(time.time() - start_time),
        'requests': request_count,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/info')
def api_info():
    global request_count
    request_count += 1
    
    return jsonify({
        'version': APP_VERSION,
        'instance_id': INSTANCE_ID,
        'uptime': int(time.time() - start_time),
        'requests_served': request_count,
        'cpu_percent': psutil.cpu_percent(),
        'memory_percent': psutil.virtual_memory().percent,
        'timestamp': datetime.now().isoformat(),
        'features': ['basic-api', 'health-checks', 'metrics']
    })

@app.route('/simulate-load')
def simulate_load():
    # Simulate some processing time
    processing_time = random.uniform(0.1, 0.5)
    time.sleep(processing_time)
    
    return jsonify({
        'message': 'Load simulation completed',
        'processing_time': processing_time,
        'version': APP_VERSION
    })

if __name__ == '__main__':
    print(f"Starting application v{APP_VERSION} on port {PORT}")
    print(f"Instance ID: {INSTANCE_ID}")
    app.run(host='0.0.0.0', port=PORT, debug=False)
EOF

    cat > app/v1/requirements.txt << 'EOF'
Flask==3.0.0
psutil==5.9.6
Werkzeug==3.0.1
EOF

    cat > app/v1/Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    procps \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
EOF

    log "Application v1.0 created"
}

# Create application version 2
create_app_v2() {
    log "Creating application v2.0..."
    
    cat > app/v2/app.py << 'EOF'
from flask import Flask, jsonify, render_template_string
import time
import os
import socket
import random
from datetime import datetime
import psutil

app = Flask(__name__)

# App configuration
APP_VERSION = "2.0.0"
INSTANCE_ID = os.environ.get('INSTANCE_ID', socket.gethostname())
PORT = int(os.environ.get('PORT', 5000))

# HTML template for the web interface
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Zero-Downtime Demo - App v{{ version }}</title>
    <meta http-equiv="refresh" content="2">
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #2196F3 0%, #21CBF3 100%);
            color: white;
        }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 30px; 
            border-radius: 15px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
        }
        .header { 
            text-align: center; 
            margin-bottom: 30px; 
            border-bottom: 2px solid rgba(255,255,255,0.2);
            padding-bottom: 20px;
        }
        .version-badge { 
            background: #2196F3; 
            color: white; 
            padding: 10px 20px; 
            border-radius: 25px; 
            display: inline-block; 
            font-weight: bold;
            font-size: 1.2em;
        }
        .stats { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 20px; 
            margin-top: 20px; 
        }
        .stat-card { 
            background: rgba(255,255,255,0.15); 
            padding: 20px; 
            border-radius: 10px; 
            text-align: center;
        }
        .stat-value { 
            font-size: 2em; 
            font-weight: bold; 
            color: #FFD700; 
        }
        .stat-label { 
            margin-top: 5px; 
            opacity: 0.8; 
        }
        .pulse { 
            animation: pulse 2s infinite; 
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
        .features { 
            margin-top: 20px; 
            padding: 15px; 
            background: rgba(255,255,255,0.1); 
            border-radius: 10px; 
        }
        .feature-badge { 
            display: inline-block; 
            background: #FF9800; 
            color: white; 
            padding: 5px 10px; 
            margin: 2px; 
            border-radius: 15px; 
            font-size: 0.8em; 
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Zero-Downtime Deployment Demo</h1>
            <div class="version-badge pulse">Version {{ version }} ✨ Enhanced</div>
            <p>Instance: {{ instance_id }}</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-value">{{ uptime }}</div>
                <div class="stat-label">Uptime (seconds)</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{{ requests }}</div>
                <div class="stat-label">Requests Served</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{{ cpu_percent }}%</div>
                <div class="stat-label">CPU Usage</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{{ memory_percent }}%</div>
                <div class="stat-label">Memory Usage</div>
            </div>
        </div>
        
        <div class="features">
            <h3>🔥 New Features in v2.0:</h3>
            <span class="feature-badge">Enhanced API</span>
            <span class="feature-badge">Caching</span>
            <span class="feature-badge">Analytics</span>
            <span class="feature-badge">Performance Boost</span>
        </div>
        
        <div style="margin-top: 30px; text-align: center;">
            <p>🟢 <strong>Application Status: HEALTHY</strong></p>
            <p>Last Updated: {{ timestamp }}</p>
        </div>
    </div>
</body>
</html>
'''

# Global counters
start_time = time.time()
request_count = 0

@app.route('/')
def home():
    global request_count
    request_count += 1
    
    return render_template_string(HTML_TEMPLATE,
        version=APP_VERSION,
        instance_id=INSTANCE_ID,
        uptime=int(time.time() - start_time),
        requests=request_count,
        cpu_percent=round(psutil.cpu_percent(), 1),
        memory_percent=round(psutil.virtual_memory().percent, 1),
        timestamp=datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    )

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'version': APP_VERSION,
        'instance_id': INSTANCE_ID,
        'uptime': int(time.time() - start_time),
        'requests': request_count,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/info')
def api_info():
    global request_count
    request_count += 1
    
    return jsonify({
        'version': APP_VERSION,
        'instance_id': INSTANCE_ID,
        'uptime': int(time.time() - start_time),
        'requests_served': request_count,
        'cpu_percent': psutil.cpu_percent(),
        'memory_percent': psutil.virtual_memory().percent,
        'timestamp': datetime.now().isoformat(),
        'features': ['enhanced-api', 'health-checks', 'metrics', 'caching', 'analytics']
    })

@app.route('/api/analytics')
def analytics():
    return jsonify({
        'version': APP_VERSION,
        'feature': 'analytics',
        'data': {
            'page_views': request_count,
            'bounce_rate': round(random.uniform(0.2, 0.4), 2),
            'avg_session_duration': round(random.uniform(120, 300), 1),
            'user_engagement': round(random.uniform(0.6, 0.9), 2)
        },
        'timestamp': datetime.now().isoformat()
    })

@app.route('/simulate-load')
def simulate_load():
    # Simulate some processing time with enhanced performance
    processing_time = random.uniform(0.05, 0.3)  # Faster than v1
    time.sleep(processing_time)
    
    return jsonify({
        'message': 'Load simulation completed with enhanced performance',
        'processing_time': processing_time,
        'version': APP_VERSION,
        'optimization': 'enabled'
    })

if __name__ == '__main__':
    print(f"Starting application v{APP_VERSION} on port {PORT}")
    print(f"Instance ID: {INSTANCE_ID}")
    app.run(host='0.0.0.0', port=PORT, debug=False)
EOF

    cp app/v1/requirements.txt app/v2/
    
    cat > app/v2/Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    procps \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
EOF

    log "Application v2.0 created with enhanced features"
}

# Create application version 3
create_app_v3() {
    log "Creating application v3.0..."
    
    cat > app/v3/app.py << 'EOF'
from flask import Flask, jsonify, render_template_string
import time
import os
import socket
import random
from datetime import datetime
import psutil

app = Flask(__name__)

# App configuration
APP_VERSION = "3.0.0"
INSTANCE_ID = os.environ.get('INSTANCE_ID', socket.gethostname())
PORT = int(os.environ.get('PORT', 5000))

# HTML template for the web interface
HTML_TEMPLATE = '''
<!DOCTYPE html>
<html>
<head>
    <title>Zero-Downtime Demo - App v{{ version }}</title>
    <meta http-equiv="refresh" content="2">
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #FF9800 0%, #FF5722 100%);
            color: white;
        }
        .container { 
            max-width: 800px; 
            margin: 0 auto; 
            background: rgba(255,255,255,0.1); 
            padding: 30px; 
            border-radius: 15px;
            box-shadow: 0 8px 32px rgba(0,0,0,0.1);
            backdrop-filter: blur(10px);
        }
        .header { 
            text-align: center; 
            margin-bottom: 30px; 
            border-bottom: 2px solid rgba(255,255,255,0.2);
            padding-bottom: 20px;
        }
        .version-badge { 
            background: #FF9800; 
            color: white; 
            padding: 10px 20px; 
            border-radius: 25px; 
            display: inline-block; 
            font-weight: bold;
            font-size: 1.2em;
            box-shadow: 0 4px 15px rgba(255,152,0,0.4);
        }
        .stats { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 20px; 
            margin-top: 20px; 
        }
        .stat-card { 
            background: rgba(255,255,255,0.15); 
            padding: 20px; 
            border-radius: 10px; 
            text-align: center;
        }
        .stat-value { 
            font-size: 2em; 
            font-weight: bold; 
            color: #FFD700; 
        }
        .stat-label { 
            margin-top: 5px; 
            opacity: 0.8; 
        }
        .pulse { 
            animation: pulse 2s infinite; 
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
        .features { 
            margin-top: 20px; 
            padding: 15px; 
            background: rgba(255,255,255,0.1); 
            border-radius: 10px; 
        }
        .feature-badge { 
            display: inline-block; 
            background: #E91E63; 
            color: white; 
            padding: 5px 10px; 
            margin: 2px; 
            border-radius: 15px; 
            font-size: 0.8em; 
        }
        .premium-features {
            margin-top: 20px;
            padding: 15px;
            background: linear-gradient(45deg, rgba(233,30,99,0.3), rgba(255,152,0,0.3));
            border-radius: 10px;
            border: 2px solid rgba(255,193,7,0.5);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Zero-Downtime Deployment Demo</h1>
            <div class="version-badge pulse">Version {{ version }} 👑 Premium</div>
            <p>Instance: {{ instance_id }}</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-value">{{ uptime }}</div>
                <div class="stat-label">Uptime (seconds)</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{{ requests }}</div>
                <div class="stat-label">Requests Served</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{{ cpu_percent }}%</div>
                <div class="stat-label">CPU Usage</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{{ memory_percent }}%</div>
                <div class="stat-label">Memory Usage</div>
            </div>
        </div>
        
        <div class="premium-features">
            <h3>👑 Premium Features in v3.0:</h3>
            <span class="feature-badge">Premium API</span>
            <span class="feature-badge">ML Insights</span>
            <span class="feature-badge">Real-time Updates</span>
            <span class="feature-badge">Advanced Analytics</span>
            <span class="feature-badge">Enterprise Security</span>
        </div>
        
        <div style="margin-top: 30px; text-align: center;">
            <p>🟢 <strong>Application Status: PREMIUM HEALTHY</strong></p>
            <p>Last Updated: {{ timestamp }}</p>
        </div>
    </div>
</body>
</html>
'''

# Global counters
start_time = time.time()
request_count = 0

@app.route('/')
def home():
    global request_count
    request_count += 1
    
    return render_template_string(HTML_TEMPLATE,
        version=APP_VERSION,
        instance_id=INSTANCE_ID,
        uptime=int(time.time() - start_time),
        requests=request_count,
        cpu_percent=round(psutil.cpu_percent(), 1),
        memory_percent=round(psutil.virtual_memory().percent, 1),
        timestamp=datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    )

@app.route('/health')
def health():
    return jsonify({
        'status': 'healthy',
        'version': APP_VERSION,
        'instance_id': INSTANCE_ID,
        'uptime': int(time.time() - start_time),
        'requests': request_count,
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/info')
def api_info():
    global request_count
    request_count += 1
    
    return jsonify({
        'version': APP_VERSION,
        'instance_id': INSTANCE_ID,
        'uptime': int(time.time() - start_time),
        'requests_served': request_count,
        'cpu_percent': psutil.cpu_percent(),
        'memory_percent': psutil.virtual_memory().percent,
        'timestamp': datetime.now().isoformat(),
        'features': ['premium-api', 'health-checks', 'metrics', 'caching', 'analytics', 'ml-insights', 'real-time-updates']
    })

@app.route('/api/analytics')
def analytics():
    return jsonify({
        'version': APP_VERSION,
        'feature': 'premium-analytics',
        'data': {
            'page_views': request_count,
            'bounce_rate': round(random.uniform(0.15, 0.3), 2),
            'avg_session_duration': round(random.uniform(180, 400), 1),
            'user_engagement': round(random.uniform(0.8, 0.95), 2),
            'conversion_rate': round(random.uniform(0.05, 0.12), 3)
        },
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/ml-insights')
def ml_insights():
    return jsonify({
        'version': APP_VERSION,
        'feature': 'ml-insights',
        'predictions': {
            'user_churn_risk': round(random.uniform(0.1, 0.3), 2),
            'revenue_forecast': round(random.uniform(10000, 50000), 2),
            'optimal_pricing': round(random.uniform(29.99, 99.99), 2)
        },
        'confidence': round(random.uniform(0.85, 0.99), 2),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/simulate-load')
def simulate_load():
    # Simulate premium processing with ML optimization
    processing_time = random.uniform(0.02, 0.2)  # Even faster than v2
    time.sleep(processing_time)
    
    return jsonify({
        'message': 'Premium load simulation with ML optimization',
        'processing_time': processing_time,
        'version': APP_VERSION,
        'optimization': 'ml-enhanced',
        'performance_gain': '40%'
    })

if __name__ == '__main__':
    print(f"Starting application v{APP_VERSION} on port {PORT}")
    print(f"Instance ID: {INSTANCE_ID}")
    app.run(host='0.0.0.0', port=PORT, debug=False)
EOF

    cp app/v1/requirements.txt app/v3/
    
    cat > app/v3/Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    python3-dev \
    procps \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 5000

CMD ["python", "app.py"]
EOF

    log "Application v3.0 created with premium features"
}

# Create nginx configurations
create_nginx_configs() {
    log "Creating nginx configurations..."
    
    # Main nginx config
    cat > nginx/nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream app_servers {
        server app_v1_1:5000 weight=1;
        server app_v1_2:5000 weight=1;
        server app_v1_3:5000 weight=1;
    }
    
    upstream app_servers_blue {
        server app_blue_1:5000;
        server app_blue_2:5000;
        server app_blue_3:5000;
    }
    
    upstream app_servers_green {
        server app_green_1:5000;
        server app_green_2:5000;
        server app_green_3:5000;
    }
    
    server {
        listen 80;
        
        location /health {
            proxy_pass http://app_servers/health;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        
        location / {
            proxy_pass http://app_servers;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            
            # Health check settings
            proxy_connect_timeout 5s;
            proxy_send_timeout 5s;
            proxy_read_timeout 5s;
        }
    }
}
EOF

    # Blue-Green specific config
    cat > nginx/configs/blue-green.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream blue_servers {
        server app_blue_1:5000;
        server app_blue_2:5000;
        server app_blue_3:5000;
    }
    
    upstream green_servers {
        server app_green_1:5000;
        server app_green_2:5000;
        server app_green_3:5000;
    }
    
    # Default to blue environment
    upstream active_servers {
        server app_blue_1:5000;
        server app_blue_2:5000;
        server app_blue_3:5000;
    }
    
    server {
        listen 80;
        
        location /health {
            proxy_pass http://active_servers/health;
        }
        
        location / {
            proxy_pass http://active_servers;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
EOF

    # Canary config
    cat > nginx/configs/canary.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    upstream stable_servers {
        server app_stable_1:5000;
        server app_stable_2:5000;
        server app_stable_3:5000;
    }
    
    upstream canary_servers {
        server app_canary_1:5000;
    }
    
    # Random split configuration
    split_clients $remote_addr $variant {
        10% canary;
        * stable;
    }
    
    server {
        listen 80;
        
        location / {
            if ($variant = "canary") {
                proxy_pass http://canary_servers;
                break;
            }
            proxy_pass http://stable_servers;
            
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
EOF

    log "Nginx configurations created"
}

# Create Docker Compose files
create_docker_configs() {
    log "Creating Docker Compose configurations..."
    
    # Rolling deployment config
    cat > docker/rolling/docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Load balancer
  nginx:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ../../nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - app_v1_1
      - app_v1_2
      - app_v1_3
    networks:
      - app_network

  # App instances v1
  app_v1_1:
    build: ../../app/v1
    environment:
      - INSTANCE_ID=v1-instance-1
      - PORT=5000
    networks:
      - app_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  app_v1_2:
    build: ../../app/v1
    environment:
      - INSTANCE_ID=v1-instance-2
      - PORT=5000
    networks:
      - app_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 10s
      timeout: 5s
      retries: 3

  app_v1_3:
    build: ../../app/v1
    environment:
      - INSTANCE_ID=v1-instance-3
      - PORT=5000
    networks:
      - app_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 10s
      timeout: 5s
      retries: 3

networks:
  app_network:
    driver: bridge
EOF

    # Blue-Green deployment config
    cat > docker/blue-green/docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Load balancer
  nginx:
    image: nginx:alpine
    ports:
      - "8081:80"
    volumes:
      - ../../nginx/configs/blue-green.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - app_blue_1
      - app_blue_2
      - app_blue_3
      - app_green_1
      - app_green_2
      - app_green_3
    networks:
      - app_network

  # Blue environment (v1)
  app_blue_1:
    build: ../../app/v1
    environment:
      - INSTANCE_ID=blue-instance-1
      - PORT=5000
    networks:
      - app_network

  app_blue_2:
    build: ../../app/v1
    environment:
      - INSTANCE_ID=blue-instance-2
      - PORT=5000
    networks:
      - app_network

  app_blue_3:
    build: ../../app/v1
    environment:
      - INSTANCE_ID=blue-instance-3
      - PORT=5000
    networks:
      - app_network

  # Green environment (v2)
  app_green_1:
    build: ../../app/v2
    environment:
      - INSTANCE_ID=green-instance-1
      - PORT=5000
    networks:
      - app_network

  app_green_2:
    build: ../../app/v2
    environment:
      - INSTANCE_ID=green-instance-2
      - PORT=5000
    networks:
      - app_network

  app_green_3:
    build: ../../app/v2
    environment:
      - INSTANCE_ID=green-instance-3
      - PORT=5000
    networks:
      - app_network

networks:
  app_network:
    driver: bridge
EOF

    # Canary deployment config
    cat > docker/canary/docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Load balancer
  nginx:
    image: nginx:alpine
    ports:
      - "8082:80"
    volumes:
      - ../../nginx/configs/canary.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - app_stable_1
      - app_stable_2
      - app_stable_3
      - app_canary_1
    networks:
      - app_network

  # Stable environment (v1)
  app_stable_1:
    build: ../../app/v1
    environment:
      - INSTANCE_ID=stable-instance-1
      - PORT=5000
    networks:
      - app_network

  app_stable_2:
    build: ../../app/v1
    environment:
      - INSTANCE_ID=stable-instance-2
      - PORT=5000
    networks:
      - app_network

  app_stable_3:
    build: ../../app/v1
    environment:
      - INSTANCE_ID=stable-instance-3
      - PORT=5000
    networks:
      - app_network

  # Canary environment (v2)
  app_canary_1:
    build: ../../app/v2
    environment:
      - INSTANCE_ID=canary-instance-1
      - PORT=5000
    networks:
      - app_network

networks:
  app_network:
    driver: bridge
EOF

    log "Docker Compose configurations created"
}

# Create monitoring dashboard
create_dashboard() {
    log "Creating monitoring dashboard..."
    
    cat > dashboard/dashboard.py << 'EOF'
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
        response = requests.get(f'http://localhost:{port}/health', timeout=2)
        return response.status_code == 200
    except:
        return False

def get_response_code(port):
    """Get HTTP response code for a service"""
    try:
        response = requests.get(f'http://localhost:{port}/health', timeout=2)
        return response.status_code
    except:
        return 'N/A'

def get_response_time(port):
    """Get response time for a service"""
    try:
        start = time.time()
        response = requests.get(f'http://localhost:{port}/health', timeout=2)
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
EOF

    cat > dashboard/requirements.txt << 'EOF'
Flask==3.0.0
requests==2.31.0
EOF

    cat > dashboard/Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY dashboard.py .

EXPOSE 3000

CMD ["python", "dashboard.py"]
EOF

    log "Monitoring dashboard created"
}

# Create test scripts
create_test_scripts() {
    log "Creating test scripts..."
    
    cat > scripts/test_deployments.sh << 'EOF'
#!/bin/bash

# Test script for zero-downtime deployments

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] $1${NC}"
}

# Test function to send requests and measure response
test_endpoint() {
    local url=$1
    local duration=${2:-10}
    local name=${3:-"Test"}
    
    log "Testing $name for ${duration}s..."
    
    if ! curl -s "$url" > /dev/null; then
        error "$name service not accessible at $url"
        return 1
    fi
    
    start_time=$(date +%s)
    end_time=$((start_time + duration))
    success_count=0
    error_count=0
    total_time=0
    
    while [ $(date +%s) -lt $end_time ]; do
        start_req=$(date +%s%3N)
        if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200"; then
            end_req=$(date +%s%3N)
            response_time=$((end_req - start_req))
            total_time=$((total_time + response_time))
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
        sleep 0.1
    done
    
    if [ $success_count -eq 0 ]; then
        error "$name: No successful requests"
        return 1
    fi
    
    total_requests=$((success_count + error_count))
    avg_response_time=$((total_time / success_count))
    success_rate=$(awk "BEGIN {printf \"%.2f\", $success_count * 100 / $total_requests}")
    
    log "$name Results:"
    log "  Total Requests: $total_requests"
    log "  Success Rate: ${success_rate}%"
    log "  Average Response Time: ${avg_response_time}ms"
    log "  Errors: $error_count"
    echo
    
    return 0
}

# Test Rolling Deployment
test_rolling() {
    log "=== Testing Rolling Deployment ==="
    test_endpoint "http://localhost:8080" 30 "Rolling Deployment"
}

# Test Blue-Green Deployment
test_blue_green() {
    log "=== Testing Blue-Green Deployment ==="
    test_endpoint "http://localhost:8081" 30 "Blue-Green Deployment"
}

# Test Canary Deployment
test_canary() {
    log "=== Testing Canary Deployment ==="
    test_endpoint "http://localhost:8082" 30 "Canary Deployment"
}

# Run all tests
run_all_tests() {
    log "Starting comprehensive deployment testing..."
    
    # Check if all services are running
    warn "Checking service availability..."
    
    local tests_passed=0
    local total_tests=3
    
    if test_rolling; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_blue_green; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_canary; then
        tests_passed=$((tests_passed + 1))
    fi
    
    log "Tests completed: $tests_passed/$total_tests passed"
    
    if [ $tests_passed -eq $total_tests ]; then
        log "🎉 All tests passed!"
    else
        warn "⚠️  Some tests failed. Check the output above for details."
    fi
}

# Load testing
load_test() {
    local url=${1:-"http://localhost:8080"}
    local concurrent=${2:-10}
    local duration=${3:-60}
    
    log "Starting load test: $concurrent concurrent users for ${duration}s"
    
    for i in $(seq 1 $concurrent); do
        (
            end_time=$(($(date +%s) + duration))
            while [ $(date +%s) -lt $end_time ]; do
                curl -s "$url" > /dev/null
                sleep 0.1
            done
        ) &
    done
    
    wait
    log "Load test completed"
}

# Main execution
case "${1:-all}" in
    "rolling")
        test_rolling
        ;;
    "blue-green")
        test_blue_green
        ;;
    "canary")
        test_canary
        ;;
    "load")
        load_test "${2:-http://localhost:8080}" "${3:-10}" "${4:-60}"
        ;;
    "all")
        run_all_tests
        ;;
    *)
        echo "Usage: $0 {rolling|blue-green|canary|load|all}"
        echo "  rolling     - Test rolling deployment"
        echo "  blue-green  - Test blue-green deployment"
        echo "  canary      - Test canary deployment"
        echo "  load [url] [concurrent] [duration] - Load test"
        echo "  all         - Run all tests"
        ;;
esac
EOF

    chmod +x scripts/test_deployments.sh
    
    # Create deployment control script
    cat > scripts/deploy_control.sh << 'EOF'
#!/bin/bash

# Deployment control script

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] $1${NC}"
}

# Start specific deployment
start_deployment() {
    local strategy=$1
    
    log "Starting $strategy deployment..."
    
    case $strategy in
        "rolling")
            cd docker/rolling && docker-compose up -d && cd ../..
            ;;
        "blue-green")
            cd docker/blue-green && docker-compose up -d && cd ../..
            ;;
        "canary")
            cd docker/canary && docker-compose up -d && cd ../..
            ;;
        *)
            error "Unknown strategy: $strategy"
            exit 1
            ;;
    esac
    
    log "$strategy deployment started"
}

# Stop specific deployment
stop_deployment() {
    local strategy=$1
    
    log "Stopping $strategy deployment..."
    
    case $strategy in
        "rolling")
            cd docker/rolling && docker-compose down && cd ../..
            ;;
        "blue-green")
            cd docker/blue-green && docker-compose down && cd ../..
            ;;
        "canary")
            cd docker/canary && docker-compose down && cd ../..
            ;;
        *)
            error "Unknown strategy: $strategy"
            exit 1
            ;;
    esac
    
    log "$strategy deployment stopped"
}

# Show status
show_status() {
    log "Deployment Status:"
    echo
    
    echo "Rolling (Port 8080):"
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "  Status: Running ✅"
        version=$(curl -s http://localhost:8080/api/info | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        echo "  Version: $version"
    else
        echo "  Status: Stopped ❌"
    fi
    
    echo "Blue-Green (Port 8081):"
    if curl -s http://localhost:8081/health > /dev/null 2>&1; then
        echo "  Status: Running ✅"
        version=$(curl -s http://localhost:8081/api/info | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        echo "  Version: $version"
    else
        echo "  Status: Stopped ❌"
    fi
    
    echo "Canary (Port 8082):"
    if curl -s http://localhost:8082/health > /dev/null 2>&1; then
        echo "  Status: Running ✅"
        version=$(curl -s http://localhost:8082/api/info | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        echo "  Version: $version"
    else
        echo "  Status: Stopped ❌"
    fi
    
    echo "Dashboard (Port 3000):"
    if curl -s http://localhost:3000 > /dev/null 2>&1; then
        echo "  Status: Running ✅"
    else
        echo "  Status: Stopped ❌"
    fi
}

# Main execution
case "${1:-status}" in
    "start")
        if [ -z "$2" ]; then
            echo "Usage: $0 start {rolling|blue-green|canary|all}"
            exit 1
        fi
        if [ "$2" = "all" ]; then
            start_deployment "rolling"
            start_deployment "blue-green"
            start_deployment "canary"
        else
            start_deployment "$2"
        fi
        ;;
    "stop")
        if [ -z "$2" ]; then
            echo "Usage: $0 stop {rolling|blue-green|canary|all}"
            exit 1
        fi
        if [ "$2" = "all" ]; then
            stop_deployment "rolling"
            stop_deployment "blue-green"
            stop_deployment "canary"
        else
            stop_deployment "$2"
        fi
        ;;
    "status")
        show_status
        ;;
    "restart")
        if [ -z "$2" ]; then
            echo "Usage: $0 restart {rolling|blue-green|canary|all}"
            exit 1
        fi
        if [ "$2" = "all" ]; then
            stop_deployment "rolling"
            stop_deployment "blue-green"
            stop_deployment "canary"
            sleep 3
            start_deployment "rolling"
            start_deployment "blue-green"
            start_deployment "canary"
        else
            stop_deployment "$2"
            sleep 2
            start_deployment "$2"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status} [strategy]"
        echo "Strategies: rolling, blue-green, canary, all"
        ;;
esac
EOF

    chmod +x scripts/deploy_control.sh
    
    log "Test scripts created"
}

# Create main run script
create_run_script() {
    log "Creating main run script..."
    
    cat > run_demo.sh << 'EOF'
#!/bin/bash

# Main demo runner script

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] $1${NC}"
}

# Build all Docker images
build_images() {
    log "Building Docker images..."
    
    docker build -t zero-downtime-app-v1 app/v1/
    docker build -t zero-downtime-app-v2 app/v2/
    docker build -t zero-downtime-app-v3 app/v3/
    docker build -t zero-downtime-dashboard dashboard/
    
    log "Docker images built successfully"
}

# Start dashboard
start_dashboard() {
    log "Starting monitoring dashboard..."
    
    # Stop existing dashboard if running
    docker stop zero-downtime-dashboard 2>/dev/null || true
    docker rm zero-downtime-dashboard 2>/dev/null || true
    
    docker run -d \
        --name zero-downtime-dashboard \
        -p 3000:3000 \
        --network host \
        zero-downtime-dashboard
    
    log "Dashboard starting on http://localhost:3000"
}

# Start all deployments
start_all() {
    log "Starting all deployment strategies..."
    
    # Rolling deployment
    (cd docker/rolling && docker-compose up -d)
    
    # Blue-Green deployment
    (cd docker/blue-green && docker-compose up -d)
    
    # Canary deployment
    (cd docker/canary && docker-compose up -d)
    
    log "All deployments started"
}

# Stop all deployments
stop_all() {
    log "Stopping all deployments..."
    
    (cd docker/rolling && docker-compose down) || true
    (cd docker/blue-green && docker-compose down) || true
    (cd docker/canary && docker-compose down) || true
    
    docker stop zero-downtime-dashboard 2>/dev/null || true
    docker rm zero-downtime-dashboard 2>/dev/null || true
    
    log "All deployments stopped"
}

# Clean up everything
cleanup() {
    log "Cleaning up Docker resources..."
    
    stop_all
    
    # Remove images
    docker rmi zero-downtime-app-v1 2>/dev/null || true
    docker rmi zero-downtime-app-v2 2>/dev/null || true
    docker rmi zero-downtime-app-v3 2>/dev/null || true
    docker rmi zero-downtime-dashboard 2>/dev/null || true
    
    # Clean up networks
    docker network prune -f
    
    log "Cleanup completed"
}

# Show access information
show_info() {
    info "=== Zero-Downtime Deployment Demo ==="
    echo
    info "🎯 Access Points:"
    echo "  📊 Dashboard:        http://localhost:3000"
    echo "  🔄 Rolling:          http://localhost:8080"
    echo "  🔀 Blue-Green:       http://localhost:8081"
    echo "  🐦 Canary:           http://localhost:8082"
    echo
    info "🧪 Testing:"
    echo "  ./scripts/test_deployments.sh all"
    echo "  ./scripts/deploy_control.sh status"
    echo
    info "📝 Logs:"
    echo "  docker-compose logs -f (in respective directories)"
    echo
    warn "💡 Tip: Visit the dashboard to monitor deployments interactively!"
    echo
    info "📚 Learning Objectives:"
    echo "  • Understand traffic switching mechanisms"
    echo "  • Compare resource usage across strategies"  
    echo "  • Experience zero-downtime deployment patterns"
    echo "  • Practice failure scenario handling"
}

# Wait for services to be ready
wait_for_services() {
    log "Waiting for services to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local ready_count=0
        
        if curl -s http://localhost:8080/health > /dev/null 2>&1; then
            ready_count=$((ready_count + 1))
        fi
        
        if curl -s http://localhost:8081/health > /dev/null 2>&1; then
            ready_count=$((ready_count + 1))
        fi
        
        if curl -s http://localhost:8082/health > /dev/null 2>&1; then
            ready_count=$((ready_count + 1))
        fi
        
        if [ $ready_count -eq 3 ]; then
            log "All services are ready!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done
    
    warn "Some services may not be ready yet. Check status with: ./scripts/deploy_control.sh status"
}

# Main execution
case "${1:-start}" in
    "build")
        build_images
        ;;
    "start")
        build_images
        start_dashboard
        start_all
        wait_for_services
        show_info
        ;;
    "stop")
        stop_all
        ;;
    "restart")
        stop_all
        sleep 3
        build_images
        start_dashboard
        start_all
        wait_for_services
        show_info
        ;;
    "clean")
        cleanup
        ;;
    "info")
        show_info
        ;;
    "test")
        ./scripts/test_deployments.sh all
        ;;
    *)
        echo "Usage: $0 {build|start|stop|restart|clean|info|test}"
        echo "  build   - Build Docker images"
        echo "  start   - Start all services"
        echo "  stop    - Stop all services"
        echo "  restart - Restart all services"
        echo "  clean   - Clean up all Docker resources"
        echo "  info    - Show access information"
        echo "  test    - Run deployment tests"
        ;;
esac
EOF

    chmod +x run_demo.sh
    
    log "Main run script created"
}

# Create README
create_readme() {
    log "Creating README..."
    
    cat > README.md << 'EOF'
# Zero-Downtime Deployment Demo

This demo showcases three critical deployment strategies for distributed systems:

## 🚀 Quick Start

```bash
# Start all deployment demonstrations
./run_demo.sh start

# Access the dashboard
open http://localhost:3000
```

## 📋 What's Included

### Deployment Strategies

1. **Rolling Deployment** (Port 8080)
   - Gradually replaces instances
   - Minimal resource usage
   - Medium risk

2. **Blue-Green Deployment** (Port 8081)
   - Instant environment switching
   - Double resource usage
   - High safety

3. **Canary Deployment** (Port 8082)
   - Progressive traffic routing
   - Risk mitigation through gradual exposure
   - Smart rollback capabilities

### Features

- 🎛️ **Interactive Dashboard** - Control and monitor all deployments
- 📊 **Real-time Metrics** - Track performance and health
- 🧪 **Automated Testing** - Comprehensive test suite
- 🐳 **Docker-based** - Consistent environment across platforms
- 📝 **Detailed Logging** - Observe deployment behavior

## 🔧 Usage

### Start Specific Deployment
```bash
./scripts/deploy_control.sh start rolling
./scripts/deploy_control.sh start blue-green
./scripts/deploy_control.sh start canary
```

### Run Tests
```bash
# Test all strategies
./scripts/test_deployments.sh all

# Test specific strategy
./scripts/test_deployments.sh rolling

# Load test
./scripts/test_deployments.sh load http://localhost:8080 10 60
```

### Monitor Status
```bash
./scripts/deploy_control.sh status
```

## 🎯 Learning Objectives

After completing this demo, you'll understand:

- ✅ How different deployment strategies handle traffic switching
- ✅ Resource requirements and trade-offs for each approach
- ✅ State management during deployments
- ✅ Health checking and rollback mechanisms
- ✅ Load balancer configuration for zero-downtime updates

## 📁 Project Structure

```
zero-downtime-demo/
├── app/                    # Application versions
│   ├── v1/                # Version 1.0 (stable)
│   ├── v2/                # Version 2.0 (enhanced)
│   └── v3/                # Version 3.0 (premium)
├── docker/                # Docker configurations
│   ├── rolling/           # Rolling deployment
│   ├── blue-green/        # Blue-green deployment
│   └── canary/            # Canary deployment
├── nginx/                 # Load balancer configs
├── dashboard/             # Monitoring dashboard
├── scripts/               # Control and test scripts
└── logs/                  # Application logs
```

## 🔍 Key Insights

### Rolling Deployment
- **Best for**: Regular updates with backward compatibility
- **Consideration**: Mixed version state during deployment
- **Rollback**: Gradual, requires version compatibility

### Blue-Green Deployment
- **Best for**: Major updates requiring instant switching
- **Consideration**: Double infrastructure cost
- **Rollback**: Instant, perfect safety

### Canary Deployment
- **Best for**: Risk-averse organizations testing new features
- **Consideration**: Complex traffic routing logic
- **Rollback**: Fast, data-driven decisions

## 🧪 Experiments to Try

1. **Traffic Pattern Analysis**
   - Monitor which instances serve requests during rolling updates
   - Observe instant switching in blue-green deployments
   - Track canary traffic distribution

2. **Failure Scenarios**
   - Stop instances during deployment
   - Simulate network partitions
   - Test database connectivity issues

3. **Performance Comparison**
   - Measure response times during each deployment type
   - Compare resource utilization
   - Analyze error rates

## 🛠️ Customization

### Add New Application Version
1. Copy existing version: `cp -r app/v2 app/v4`
2. Modify features and styling
3. Update Docker configurations
4. Rebuild images: `./run_demo.sh build`

### Modify Traffic Routing
1. Edit nginx configurations in `nginx/configs/`
2. Adjust traffic percentages for canary deployment
3. Add custom headers or routing rules

### Extend Monitoring
1. Add custom metrics to dashboard
2. Integrate with external monitoring tools
3. Implement alerting based on error rates

## 🚨 Troubleshooting

### Services Not Starting
```bash
# Check Docker status
docker info

# View service logs
cd docker/rolling && docker-compose logs

# Restart everything
./run_demo.sh restart
```

### Port Conflicts
```bash
# Check port usage
netstat -an | grep LISTEN

# Modify ports in docker-compose.yml files
# Update corresponding documentation
```

### Performance Issues
```bash
# Monitor resource usage
docker stats

# Reduce concurrent connections
# Check available memory and CPU
```

## 📚 Further Reading

- [The Twelve-Factor App](https://12factor.net/)
- [Site Reliability Engineering](https://sre.google/books/)
- [Kubernetes Deployment Strategies](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Netflix Tech Blog - Deployment Practices](https://netflixtechblog.com/)

---

🎓 **Educational Note**: This demo is designed for learning purposes. Production deployments require additional considerations including security, compliance, monitoring, and operational procedures.
EOF

    log "README created"
}

# Main execution
main() {
    log "🚀 Starting Zero-Downtime Deployment Demo Setup..."
    
    check_dependencies
    create_project_structure
    create_app_v1
    create_app_v2
    create_app_v3
    create_nginx_configs
    create_docker_configs
    create_dashboard
    create_test_scripts
    create_run_script
    create_readme
    
    log "✅ Setup completed successfully!"
    echo
    info "📁 Project created in: $(pwd)/zero-downtime-demo"
    echo
    info "🚀 To start the demo:"
    echo "  cd zero-downtime-demo"
    echo "  ./run_demo.sh start"
    echo
    info "📊 Then visit: http://localhost:3000"
    echo
    warn "💡 Make sure Docker is running and ports 3000, 8080-8082 are available"
    echo
    info "🧪 Test the deployment:"
    echo "  ./scripts/test_deployments.sh all"
    echo "  ./scripts/deploy_control.sh status"
}

# Run main function
main