from flask import Flask, jsonify, request
from flask_cors import CORS
from flask_socketio import SocketIO, emit
import requests
import time
import threading
import json

app = Flask(__name__)
app.config['SECRET_KEY'] = 'health-monitor-secret'
CORS(app, resources={r"/*": {"origins": "*"}})
socketio = SocketIO(app, cors_allowed_origins="*")

SERVICES = {
    'user-service': 'http://user-service:5001',
    'payment-service': 'http://payment-service:5002', 
    'order-service': 'http://order-service:5003'
}

health_data = {}

def check_service_health(service_name, base_url):
    """Check both shallow and deep health for a service"""
    try:
        # Shallow health check
        shallow_response = requests.get(f'{base_url}/health/shallow', timeout=2)
        shallow_check = shallow_response.status_code == 200
        
        # Deep health check
        deep_response = requests.get(f'{base_url}/health/deep', timeout=5)
        deep_check = deep_response.status_code == 200
        deep_data = deep_response.json() if deep_check else {}
        
        # Determine overall status
        if shallow_check and deep_check:
            status = 'healthy'
        elif shallow_check:
            status = 'degraded'
        else:
            status = 'unhealthy'
            
        health_info = {
            'service': service_name,
            'status': status,
            'shallow_check': shallow_check,
            'deep_check': deep_check,
            'response_time': deep_data.get('metrics', {}).get('response_time', 0),
            'cpu_usage': deep_data.get('metrics', {}).get('cpu_usage', 0),
            'memory_usage': deep_data.get('metrics', {}).get('memory_usage', 0),
            'timestamp': time.time(),
            'checks': deep_data.get('checks', {})
        }
        
        health_data[service_name] = health_info
        
        # Emit real-time update
        socketio.emit('health-update', health_info)
        
        # Log health status change
        log_message = f"Health check: {service_name} is {status}"
        log_data = {
            'timestamp': time.strftime('%H:%M:%S'),
            'message': log_message,
            'type': 'info' if status == 'healthy' else 'warning',
            'id': int(time.time() * 1000)
        }
        socketio.emit('log-update', log_data)
        
    except requests.exceptions.RequestException as e:
        health_info = {
            'service': service_name,
            'status': 'unhealthy',
            'shallow_check': False,
            'deep_check': False,
            'response_time': 0,
            'cpu_usage': 0,
            'memory_usage': 0,
            'timestamp': time.time(),
            'error': str(e)
        }
        health_data[service_name] = health_info
        socketio.emit('health-update', health_info)

def health_monitor_loop():
    """Continuous health monitoring loop"""
    while True:
        for service_name, base_url in SERVICES.items():
            check_service_health(service_name, base_url)
        time.sleep(5)

@app.route('/health/all')
def get_all_health():
    return jsonify(health_data)

@app.route('/inject-failure', methods=['POST'])
def inject_failure():
    data = request.json
    service = data.get('service')
    failure_type = data.get('type')
    
    if service in SERVICES:
        try:
            response = requests.post(
                f'{SERVICES[service]}/inject-failure',
                json={'type': failure_type},
                timeout=5
            )
            return jsonify({'status': 'success', 'message': f'Injected {failure_type} failure in {service}'})
        except requests.exceptions.RequestException as e:
            return jsonify({'status': 'error', 'message': str(e)}), 500
    
    return jsonify({'status': 'error', 'message': 'Service not found'}), 404

@socketio.on('connect')
def handle_connect():
    print('Client connected')
    # Send current health data to newly connected client
    for service_data in health_data.values():
        emit('health-update', service_data)

@socketio.on('disconnect')
def handle_disconnect():
    print('Client disconnected')

if __name__ == '__main__':
    # Start health monitoring in background thread
    monitor_thread = threading.Thread(target=health_monitor_loop, daemon=True)
    monitor_thread.start()
    
    socketio.run(app, host='0.0.0.0', port=4000, debug=False, allow_unsafe_werkzeug=True)
