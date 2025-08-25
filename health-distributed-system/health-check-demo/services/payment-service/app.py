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
    'payment_gateway_connected': True,
    'fraud_check_enabled': True,
    'high_latency': False,
    'high_memory': False,
    'start_time': time.time()
}

def get_system_metrics():
    return {
        'cpu_usage': round(psutil.cpu_percent(interval=0.1), 1),
        'memory_usage': round(psutil.virtual_memory().percent, 1),
        'response_time': random.randint(100, 300) if not service_state['high_latency'] else random.randint(1000, 3000)
    }

@app.route('/health/shallow')
def shallow_health():
    return jsonify({
        'status': 'healthy',
        'service': 'payment-service',
        'timestamp': time.time(),
        'uptime': time.time() - service_state['start_time']
    }), 200

@app.route('/health/deep')
def deep_health():
    checks = {
        'service_healthy': service_state['healthy'],
        'payment_gateway': service_state['payment_gateway_connected'],
        'fraud_detection': service_state['fraud_check_enabled'],
        'memory_ok': not service_state['high_memory']
    }
    
    metrics = get_system_metrics()
    overall_healthy = all(checks.values())
    
    # Simulate external dependency check latency
    if service_state['high_latency']:
        time.sleep(random.uniform(0.8, 2.0))
    
    status = 'healthy' if overall_healthy else ('degraded' if checks['service_healthy'] else 'unhealthy')
    
    return jsonify({
        'status': status,
        'service': 'payment-service', 
        'checks': checks,
        'metrics': metrics,
        'timestamp': time.time()
    }), 200 if overall_healthy else 503

@app.route('/process-payment', methods=['POST'])
def process_payment():
    if not service_state['payment_gateway_connected']:
        return jsonify({'error': 'Payment gateway unavailable'}), 503
        
    if service_state['high_latency']:
        time.sleep(random.uniform(0.5, 1.2))
    
    data = request.json
    return jsonify({
        'payment_id': f'pay_{random.randint(1000, 9999)}',
        'amount': data.get('amount'),
        'status': 'processed',
        'service': 'payment-service'
    })

@app.route('/inject-failure', methods=['POST'])
def inject_failure():
    data = request.json
    failure_type = data.get('type')
    
    if failure_type == 'database':
        service_state['payment_gateway_connected'] = False
        threading.Timer(30.0, lambda: service_state.update({'payment_gateway_connected': True})).start()
    elif failure_type == 'latency':
        service_state['high_latency'] = True
        threading.Timer(20.0, lambda: service_state.update({'high_latency': False})).start()
    elif failure_type == 'memory':
        service_state['high_memory'] = True
        threading.Timer(25.0, lambda: service_state.update({'high_memory': False})).start()
    
    return jsonify({'status': 'failure injected', 'type': failure_type})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5002, debug=True)
