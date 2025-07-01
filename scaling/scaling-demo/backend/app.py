from flask import Flask, render_template, jsonify, request
from flask_cors import CORS
from flask_socketio import SocketIO, emit
import time
import random
import threading
import json
import psutil
import os
from datetime import datetime

app = Flask(__name__, template_folder='../frontend')
app.config['SECRET_KEY'] = 'scaling-demo-secret'
CORS(app)
socketio = SocketIO(app, cors_allowed_origins="*")

# Global state for demonstration
demo_state = {
    'current_stage': 1,
    'user_count': 1,
    'response_time': 150,
    'throughput': 10,
    'error_rate': 0.1,
    'is_load_testing': False,
    'system_capacity': 1000,
    'start_time': time.time()
}

# Architecture stages configuration
STAGES = {
    1: {
        'name': 'Single Server',
        'capacity': 1000,
        'components': ['Web Server + Database'],
        'description': 'Everything on one machine. Simple and fast to develop.',
        'scaling_trigger': {'users': 800, 'response_time': 500}
    },
    2: {
        'name': 'Separate Database',
        'capacity': 10000,
        'components': ['Web Server', 'Database'],
        'description': 'Separate concerns for better resource utilization.',
        'scaling_trigger': {'users': 8000, 'response_time': 800}
    },
    3: {
        'name': 'Load Balanced',
        'capacity': 100000,
        'components': ['Load Balancer', 'App Server 1', 'App Server 2', 'Database'],
        'description': 'Horizontal scaling with multiple application servers.',
        'scaling_trigger': {'users': 80000, 'response_time': 1200}
    },
    4: {
        'name': 'Caching & CDN',
        'capacity': 500000,
        'components': ['CDN', 'Load Balancer', 'Cache', 'App Servers', 'DB + Replicas'],
        'description': 'Add caching layers and content delivery for performance.',
        'scaling_trigger': {'users': 400000, 'response_time': 2000}
    },
    5: {
        'name': 'Microservices',
        'capacity': 1000000,
        'components': ['API Gateway', 'User Service', 'Order Service', 'Payment Service', 'Message Queue'],
        'description': 'Service decomposition for team autonomy and fault isolation.',
        'scaling_trigger': None
    }
}

def calculate_performance_metrics():
    """Calculate realistic performance metrics based on current load"""
    stage = demo_state['current_stage']
    capacity = STAGES[stage]['capacity']
    load_factor = demo_state['user_count'] / capacity
    
    # Base response time increases with load
    base_response_time = 150 + (load_factor * 500)
    
    # Add random variation
    variation = random.uniform(0.8, 1.2)
    demo_state['response_time'] = int(base_response_time * variation)
    
    # Error rate increases exponentially with overload
    if load_factor > 1.0:
        demo_state['error_rate'] = min(10.0, 0.1 + (load_factor - 1.0) * 5)
    else:
        demo_state['error_rate'] = max(0.1, 0.1 + (load_factor - 0.5) * 0.2)
    
    # Throughput calculation
    demo_state['throughput'] = min(
        demo_state['user_count'] * random.uniform(0.7, 0.9),
        capacity * 0.8  # Maximum sustainable throughput
    )

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/metrics')
def get_metrics():
    """Get current system metrics"""
    calculate_performance_metrics()
    return jsonify({
        'user_count': demo_state['user_count'],
        'response_time': demo_state['response_time'],
        'throughput': int(demo_state['throughput']),
        'error_rate': round(demo_state['error_rate'], 1),
        'current_stage': demo_state['current_stage'],
        'capacity_utilization': min(100, (demo_state['user_count'] / STAGES[demo_state['current_stage']]['capacity']) * 100),
        'uptime': int(time.time() - demo_state['start_time'])
    })

@app.route('/api/architecture')
def get_architecture():
    """Get current architecture stage information"""
    stage = demo_state['current_stage']
    return jsonify({
        'current_stage': stage,
        'stage_info': STAGES[stage],
        'all_stages': STAGES
    })

@app.route('/api/load-test/start', methods=['POST'])
def start_load_test():
    """Start simulated load testing"""
    if demo_state['is_load_testing']:
        return jsonify({'error': 'Load test already running'}), 400
    
    demo_state['is_load_testing'] = True
    
    def run_load_test():
        """Background thread for load testing simulation"""
        test_duration = 0
        while demo_state['is_load_testing'] and test_duration < 60:  # Max 60 seconds
            # Simulate user growth
            growth_rate = random.randint(50, 200)
            demo_state['user_count'] += growth_rate
            
            # Emit real-time updates
            socketio.emit('metrics_update', {
                'user_count': demo_state['user_count'],
                'response_time': demo_state['response_time'],
                'throughput': int(demo_state['throughput']),
                'error_rate': round(demo_state['error_rate'], 1)
            })
            
            time.sleep(2)
            test_duration += 2
        
        demo_state['is_load_testing'] = False
    
    thread = threading.Thread(target=run_load_test)
    thread.daemon = True
    thread.start()
    
    return jsonify({'status': 'Load test started'})

@app.route('/api/load-test/stop', methods=['POST'])
def stop_load_test():
    """Stop load testing"""
    demo_state['is_load_testing'] = False
    return jsonify({'status': 'Load test stopped'})

@app.route('/api/traffic-spike', methods=['POST'])
def trigger_traffic_spike():
    """Simulate sudden traffic spike"""
    spike_multiplier = random.uniform(2.5, 4.0)
    demo_state['user_count'] = int(demo_state['user_count'] * spike_multiplier)
    
    return jsonify({
        'status': 'Traffic spike triggered',
        'multiplier': round(spike_multiplier, 1),
        'new_user_count': demo_state['user_count']
    })

@app.route('/api/scale-up', methods=['POST'])
def scale_up():
    """Scale up to next architecture stage"""
    if demo_state['current_stage'] >= 5:
        return jsonify({'error': 'Already at maximum scale'}), 400
    
    old_stage = demo_state['current_stage']
    demo_state['current_stage'] += 1
    
    # Improve performance after scaling
    demo_state['response_time'] = max(150, int(demo_state['response_time'] * 0.6))
    demo_state['error_rate'] = max(0.1, demo_state['error_rate'] * 0.4)
    
    return jsonify({
        'status': 'Scaled up successfully',
        'old_stage': old_stage,
        'new_stage': demo_state['current_stage'],
        'stage_info': STAGES[demo_state['current_stage']]
    })

@app.route('/api/reset', methods=['POST'])
def reset_demo():
    """Reset demo to initial state"""
    demo_state.update({
        'current_stage': 1,
        'user_count': 1,
        'response_time': 150,
        'throughput': 10,
        'error_rate': 0.1,
        'is_load_testing': False,
        'start_time': time.time()
    })
    
    return jsonify({'status': 'Demo reset successfully'})

@app.route('/api/health')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'version': '1.0.0'
    })

@socketio.on('connect')
def handle_connect():
    """Handle client connection"""
    print(f'Client connected: {request.sid}')
    emit('connected', {'status': 'Connected to scaling demo'})

@socketio.on('disconnect')
def handle_disconnect():
    """Handle client disconnection"""
    print(f'Client disconnected: {request.sid}')

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    print(f"🚀 Starting Scaling Demo on port {port}")
    socketio.run(app, host='0.0.0.0', port=port, debug=True)
