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
