import time
import random
import psutil
import gc
from flask import Flask, jsonify, request
import threading
from datetime import datetime
import queue

app = Flask(__name__)

# Simulate zombie server behavior
class ZombieServer:
    def __init__(self):
        self.start_time = datetime.now()
        self.request_count = 0
        self.connection_pool = []  # Exhausted connections
        self.memory_leak = []
        self.hung_threads = []
        self.zombie_mode = "memory_leak"  # memory_leak, thread_exhaustion, db_timeout
        
        # Start zombie behavior
        threading.Thread(target=self._simulate_memory_leak, daemon=True).start()
        threading.Thread(target=self._exhaust_threads, daemon=True).start()
        
    def _simulate_memory_leak(self):
        """Gradually consume memory to simulate memory leaks"""
        while True:
            # Allocate memory continuously
            self.memory_leak.append([0] * 10000)
            time.sleep(1)
            if len(self.memory_leak) > 1000:
                self.memory_leak = self.memory_leak[-500:]  # Partial cleanup
                
    def _exhaust_threads(self):
        """Create hanging threads to simulate thread pool exhaustion"""
        for i in range(100):
            def hanging_operation():
                time.sleep(300)  # Hang for 5 minutes
            thread = threading.Thread(target=hanging_operation, daemon=True)
            thread.start()
            self.hung_threads.append(thread)
            time.sleep(0.1)
    
    def process_request(self):
        self.request_count += 1
        
        # Zombie behavior: appears to work but fails under load
        if random.random() < 0.7:  # 70% failure rate
            time.sleep(random.uniform(5, 10))  # Extremely slow
            raise Exception("Connection timeout")
        
        time.sleep(random.uniform(1, 3))  # Very slow even when working
        return {"status": "success", "processed_by": "zombie_server"}

zombie_server = ZombieServer()

@app.route('/health')
def shallow_health():
    # Zombie servers often pass shallow health checks
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

@app.route('/health/deep')
def deep_health():
    # Deep health check reveals zombie state
    cpu_usage = psutil.cpu_percent(interval=0.1)
    memory_info = psutil.virtual_memory()
    
    health_data = {
        "status": "zombie_detected",
        "cpu_usage": cpu_usage,
        "memory_usage": memory_info.percent,
        "available_connections": len(zombie_server.connection_pool),
        "uptime_seconds": (datetime.now() - zombie_server.start_time).total_seconds(),
        "request_count": zombie_server.request_count,
        "memory_leak_size": len(zombie_server.memory_leak),
        "hung_threads": len(zombie_server.hung_threads),
        "checks": {
            "cpu_ok": cpu_usage < 80,
            "memory_ok": memory_info.percent < 80,
            "connections_ok": len(zombie_server.connection_pool) > 10,
            "threads_ok": len(zombie_server.hung_threads) < 50
        }
    }
    
    # Return 503 if deep check reveals problems
    if memory_info.percent > 70 or len(zombie_server.hung_threads) > 20:
        return jsonify(health_data), 503
    
    return jsonify(health_data)

@app.route('/api/process')
def process_request():
    try:
        return jsonify(zombie_server.process_request())
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/stats')
def get_stats():
    return jsonify({
        "server_type": "zombie",
        "request_count": zombie_server.request_count,
        "uptime": (datetime.now() - zombie_server.start_time).total_seconds(),
        "memory_usage": psutil.virtual_memory().percent,
        "cpu_usage": psutil.cpu_percent(),
        "zombie_indicators": {
            "memory_leak_size": len(zombie_server.memory_leak),
            "hung_threads": len(zombie_server.hung_threads)
        }
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
