from flask import Flask, jsonify, request
import random
import time
import threading
import json
from datetime import datetime
import redis

app = Flask(__name__)
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

# Add CORS headers manually
@app.after_request
def after_request(response):
    response.headers.add('Access-Control-Allow-Origin', 'http://localhost:5000')
    response.headers.add('Access-Control-Allow-Headers', 'Content-Type,Authorization')
    response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE,OPTIONS')
    return response

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
