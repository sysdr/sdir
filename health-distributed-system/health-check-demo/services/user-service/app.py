from flask import Flask, jsonify, request
from flask_cors import CORS
import time
import random
import threading
import psutil
import sqlite3
import os

app = Flask(__name__)
CORS(app)

# Service state
service_state = {
    'healthy': True,
    'database_connected': True,
    'cache_connected': True,
    'high_latency': False,
    'high_memory': False,
    'start_time': time.time()
}

def get_system_metrics():
    return {
        'cpu_usage': round(psutil.cpu_percent(interval=0.1), 1),
        'memory_usage': round(psutil.virtual_memory().percent, 1),
        'response_time': random.randint(50, 200) if not service_state['high_latency'] else random.randint(800, 2000)
    }

@app.route('/health/shallow')
def shallow_health():
    """Fast health check - only checks if service is running"""
    return jsonify({
        'status': 'healthy',
        'service': 'user-service',
        'timestamp': time.time(),
        'uptime': time.time() - service_state['start_time']
    }), 200

@app.route('/health/deep')  
def deep_health():
    """Comprehensive health check - validates all dependencies"""
    checks = {
        'service_healthy': service_state['healthy'],
        'database_connected': service_state['database_connected'],
        'cache_connected': service_state['cache_connected'],
        'memory_ok': not service_state['high_memory']
    }
    
    metrics = get_system_metrics()
    overall_healthy = all(checks.values())
    
    if service_state['high_latency']:
        time.sleep(random.uniform(0.5, 1.5))  # Simulate slow dependency
    
    status = 'healthy' if overall_healthy else ('degraded' if checks['service_healthy'] else 'unhealthy')
    
    return jsonify({
        'status': status,
        'service': 'user-service',
        'checks': checks,
        'metrics': metrics,
        'timestamp': time.time()
    }), 200 if overall_healthy else 503

@app.route('/users/<user_id>')
def get_user(user_id):
    if not service_state['database_connected']:
        return jsonify({'error': 'Database unavailable'}), 503
        
    if service_state['high_latency']:
        time.sleep(random.uniform(0.3, 0.8))
    
    return jsonify({
        'user_id': user_id,
        'name': f'User {user_id}',
        'email': f'user{user_id}@example.com',
        'service': 'user-service'
    })

@app.route('/inject-failure', methods=['POST'])
def inject_failure():
    data = request.json
    failure_type = data.get('type')
    
    if failure_type == 'database':
        service_state['database_connected'] = False
        threading.Timer(30.0, lambda: service_state.update({'database_connected': True})).start()
    elif failure_type == 'latency':
        service_state['high_latency'] = True
        threading.Timer(20.0, lambda: service_state.update({'high_latency': False})).start()
    elif failure_type == 'memory':
        service_state['high_memory'] = True
        threading.Timer(25.0, lambda: service_state.update({'high_memory': False})).start()
    
    return jsonify({'status': 'failure injected', 'type': failure_type})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)
