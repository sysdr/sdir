from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit
import threading
import time
import random
import json
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import List, Dict, Any
import os
from pool_manager import ConnectionPoolManager, PoolMetrics
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__, template_folder='../templates', static_folder='../static')
app.config['SECRET_KEY'] = 'connection-pool-demo-secret'
socketio = SocketIO(app, cors_allowed_origins="*")

# Global pool manager
pool_manager = None
metrics_thread = None
stop_metrics = False

@dataclass
class DemoConfig:
    max_pool_size: int = 10
    min_pool_size: int = 2
    pool_timeout: int = 30
    query_timeout: int = 10
    enable_monitoring: bool = True

demo_config = DemoConfig()

def initialize_pool():
    """Initialize the connection pool with demo configuration"""
    global pool_manager
    
    try:
        # Database URL for PostgreSQL
        db_url = os.getenv('DATABASE_URL', 'postgresql://demo:demo123@localhost:5432/connection_demo')
        
        pool_manager = ConnectionPoolManager(
            database_url=db_url,
            max_pool_size=demo_config.max_pool_size,
            min_pool_size=demo_config.min_pool_size,
            pool_timeout=demo_config.pool_timeout
        )
        
        logger.info(f"Connection pool initialized with max_size={demo_config.max_pool_size}")
        return True
        
    except Exception as e:
        logger.error(f"Failed to initialize pool: {e}")
        return False

def metrics_collector():
    """Background thread to collect and broadcast metrics"""
    global stop_metrics
    
    while not stop_metrics:
        try:
            if pool_manager:
                metrics = pool_manager.get_metrics()
                socketio.emit('metrics_update', asdict(metrics))
            time.sleep(1)  # Update every second
        except Exception as e:
            logger.error(f"Error collecting metrics: {e}")
            time.sleep(5)

@app.route('/')
def index():
    """Main dashboard page"""
    return render_template('index.html')

@app.route('/api/config', methods=['GET', 'POST'])
def config_api():
    """Get or update pool configuration"""
    global demo_config, pool_manager
    
    if request.method == 'POST':
        data = request.json
        demo_config.max_pool_size = data.get('max_pool_size', demo_config.max_pool_size)
        demo_config.min_pool_size = data.get('min_pool_size', demo_config.min_pool_size)
        demo_config.pool_timeout = data.get('pool_timeout', demo_config.pool_timeout)
        
        # Reinitialize pool with new config
        if pool_manager:
            pool_manager.close()
        initialize_pool()
        
        return jsonify({'status': 'updated', 'config': asdict(demo_config)})
    
    return jsonify(asdict(demo_config))

@app.route('/api/scenarios/<scenario_name>', methods=['POST'])
def run_scenario(scenario_name):
    """Execute different test scenarios"""
    if not pool_manager:
        return jsonify({'error': 'Pool not initialized'}), 500
    
    try:
        if scenario_name == 'normal_load':
            result = pool_manager.simulate_normal_load()
        elif scenario_name == 'high_load':
            result = pool_manager.simulate_high_load()
        elif scenario_name == 'pool_exhaustion':
            result = pool_manager.simulate_pool_exhaustion()
        elif scenario_name == 'connection_leaks':
            result = pool_manager.simulate_connection_leaks()
        elif scenario_name == 'database_slowness':
            result = pool_manager.simulate_database_slowness()
        else:
            return jsonify({'error': 'Unknown scenario'}), 400
        
        return jsonify({'status': 'running', 'scenario': scenario_name, 'details': result})
        
    except Exception as e:
        logger.error(f"Error running scenario {scenario_name}: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/metrics')
def get_metrics():
    """Get current pool metrics"""
    if not pool_manager:
        return jsonify({'error': 'Pool not initialized'}), 500
    
    metrics = pool_manager.get_metrics()
    return jsonify(asdict(metrics))

@app.route('/api/health')
def health_check():
    """Health check endpoint"""
    status = {
        'app': 'healthy',
        'pool_initialized': pool_manager is not None,
        'timestamp': datetime.now().isoformat()
    }
    
    if pool_manager:
        try:
            status['database'] = 'connected' if pool_manager.test_connection() else 'disconnected'
        except:
            status['database'] = 'error'
    
    return jsonify(status)

@socketio.on('connect')
def handle_connect():
    """Handle WebSocket connections"""
    logger.info('Client connected')
    emit('connected', {'status': 'Connected to Connection Pool Demo'})

@socketio.on('disconnect')
def handle_disconnect():
    """Handle WebSocket disconnections"""
    logger.info('Client disconnected')

if __name__ == '__main__':
    # Initialize pool
    if initialize_pool():
        # Start metrics collection thread
        metrics_thread = threading.Thread(target=metrics_collector, daemon=True)
        metrics_thread.start()
        
        logger.info("Starting Connection Pool Demo on http://localhost:5000")
        socketio.run(app, host='0.0.0.0', port=5000, debug=False, allow_unsafe_werkzeug=True)
    else:
        logger.error("Failed to start application - pool initialization failed")
