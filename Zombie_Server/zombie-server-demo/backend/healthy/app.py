import time
import random
import psutil
import gc
from flask import Flask, jsonify, request
import threading
from datetime import datetime

app = Flask(__name__)

# Simulate healthy server behavior
class HealthyServer:
    def __init__(self):
        self.start_time = datetime.now()
        self.request_count = 0
        self.connection_pool = list(range(50))  # Healthy connection pool
        
    def process_request(self):
        self.request_count += 1
        # Simulate normal processing
        time.sleep(random.uniform(0.01, 0.05))
        return {"status": "success", "processed_by": "healthy_server"}

healthy_server = HealthyServer()

@app.route('/health')
def shallow_health():
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

@app.route('/health/deep')
def deep_health():
    # Comprehensive health check
    cpu_usage = psutil.cpu_percent(interval=0.1)
    memory_info = psutil.virtual_memory()
    
    health_data = {
        "status": "healthy",
        "cpu_usage": cpu_usage,
        "memory_usage": memory_info.percent,
        "available_connections": len(healthy_server.connection_pool),
        "uptime_seconds": (datetime.now() - healthy_server.start_time).total_seconds(),
        "request_count": healthy_server.request_count,
        "checks": {
            "cpu_ok": cpu_usage < 80,
            "memory_ok": memory_info.percent < 80,
            "connections_ok": len(healthy_server.connection_pool) > 10
        }
    }
    
    if not all(health_data["checks"].values()):
        return jsonify(health_data), 503
    
    return jsonify(health_data)

@app.route('/api/process')
def process_request():
    return jsonify(healthy_server.process_request())

@app.route('/api/stats')
def get_stats():
    return jsonify({
        "server_type": "healthy",
        "request_count": healthy_server.request_count,
        "uptime": (datetime.now() - healthy_server.start_time).total_seconds(),
        "memory_usage": psutil.virtual_memory().percent,
        "cpu_usage": psutil.cpu_percent()
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
