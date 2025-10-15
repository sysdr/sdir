from flask import Flask, jsonify, request
from flask_cors import CORS
import time
import random
import threading
import psutil
import requests

app = Flask(__name__)
CORS(app)

service_state = {
    'healthy': True,
    'database_connected': True,
    'inventory_service_connected': True,
    'high_latency': False,
    'high_memory': False,
    'start_time': time.time()
}

def get_system_metrics():
    return {
        'cpu_usage': round(psutil.cpu_percent(interval=0.1), 1),
        'memory_usage': round(psutil.virtual_memory().percent, 1),
        'response_time': random.randint(80, 250) if not service_state['high_latency'] else random.randint(900, 2500)
    }

@app.route('/health/shallow')
def shallow_health():
    return jsonify({
        'status': 'healthy',
        'service': 'order-service',
        'timestamp': time.time(),
        'uptime': time.time() - service_state['start_time']
    }), 200

@app.route('/health/deep')
def deep_health():
    checks = {
        'service_healthy': service_state['healthy'],
        'database_connected': service_state['database_connected'],
        'inventory_service': service_state['inventory_service_connected'],
        'memory_ok': not service_state['high_memory']
    }
    
    metrics = get_system_metrics()
    overall_healthy = all(checks.values())
    
    if service_state['high_latency']:
        time.sleep(random.uniform(0.6, 1.8))
    
    status = 'healthy' if overall_healthy else ('degraded' if checks['service_healthy'] else 'unhealthy')
    
    return jsonify({
        'status': status,
        'service': 'order-service',
        'checks': checks,
        'metrics': metrics,
        'timestamp': time.time()
    }), 200 if overall_healthy else 503

@app.route('/orders', methods=['POST'])
def create_order():
    if not service_state['database_connected']:
        return jsonify({'error': 'Database unavailable'}), 503
        
    if service_state['high_latency']:
        time.sleep(random.uniform(0.4, 1.0))
    
    data = request.json
    return jsonify({
        'order_id': f'ord_{random.randint(1000, 9999)}',
        'user_id': data.get('user_id'),
        'total': data.get('total'),
        'status': 'created',
        'service': 'order-service'
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
    app.run(host='0.0.0.0', port=5003, debug=True)
