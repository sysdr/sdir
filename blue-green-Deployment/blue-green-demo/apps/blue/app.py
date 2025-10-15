from flask import Flask, jsonify, render_template_string
import time
import os
import psutil
import threading
from datetime import datetime

app = Flask(__name__)

# App metadata
APP_VERSION = "1.0.0"
APP_COLOR = "blue"
START_TIME = time.time()

# Health metrics
health_status = {"status": "healthy", "checks": 0, "errors": 0}

def background_health_check():
    """Simulate background health monitoring"""
    while True:
        time.sleep(5)
        health_status["checks"] += 1
        # Simulate occasional health issue
        if health_status["checks"] % 20 == 0:
            health_status["errors"] += 1

threading.Thread(target=background_health_check, daemon=True).start()

@app.route('/')
def home():
    return render_template_string('''
    <!DOCTYPE html>
    <html>
    <head>
        <title>{{color|title}} Environment</title>
        <style>
            body { 
                font-family: Arial, sans-serif; 
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white; text-align: center; padding: 50px;
                margin: 0; min-height: 100vh;
                display: flex; flex-direction: column; justify-content: center;
            }
            .container { 
                background: rgba(255,255,255,0.1); 
                padding: 40px; border-radius: 15px;
                backdrop-filter: blur(10px); box-shadow: 0 8px 32px rgba(0,0,0,0.1);
                max-width: 600px; margin: 0 auto;
            }
            .version { 
                font-size: 2.5em; margin-bottom: 20px; 
                text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
            }
            .status { 
                background: rgba(255,255,255,0.2); 
                padding: 20px; border-radius: 10px; margin: 20px 0;
            }
            .metric { 
                display: inline-block; margin: 10px 20px; 
                background: rgba(255,255,255,0.1); padding: 10px 15px;
                border-radius: 8px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="version">{{color|title}} Environment v{{version}}</div>
            <div class="status">
                <h3>Service Status: {{health.status|title}}</h3>
                <div class="metric">Uptime: {{uptime}}s</div>
                <div class="metric">Health Checks: {{health.checks}}</div>
                <div class="metric">CPU: {{cpu}}%</div>
                <div class="metric">Memory: {{memory}}%</div>
            </div>
            <p>Current Time: {{current_time}}</p>
            <p>Environment: {{color|upper}}</p>
        </div>
    </body>
    </html>
    ''', 
    color=APP_COLOR, 
    version=APP_VERSION,
    uptime=int(time.time() - START_TIME),
    health=health_status,
    cpu=round(psutil.cpu_percent(), 1),
    memory=round(psutil.virtual_memory().percent, 1),
    current_time=datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    )

@app.route('/health')
def health():
    """Comprehensive health check endpoint"""
    cpu_usage = psutil.cpu_percent()
    memory_usage = psutil.virtual_memory().percent
    
    # Determine health based on system metrics
    is_healthy = (cpu_usage < 80 and 
                 memory_usage < 85 and 
                 health_status["errors"] < 5)
    
    status_code = 200 if is_healthy else 503
    
    return jsonify({
        "status": "healthy" if is_healthy else "unhealthy",
        "version": APP_VERSION,
        "environment": APP_COLOR,
        "uptime": int(time.time() - START_TIME),
        "metrics": {
            "cpu_usage": cpu_usage,
            "memory_usage": memory_usage,
            "health_checks": health_status["checks"],
            "error_count": health_status["errors"]
        },
        "timestamp": datetime.now().isoformat()
    }), status_code

@app.route('/api/info')
def info():
    """Service information endpoint"""
    return jsonify({
        "service": "demo-app",
        "version": APP_VERSION,
        "environment": APP_COLOR,
        "features": ["health-monitoring", "metrics", "blue-green-ready"]
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
