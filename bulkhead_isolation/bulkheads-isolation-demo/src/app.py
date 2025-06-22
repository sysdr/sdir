import os
import sys
import threading
import time
import random
import sqlite3
import json
import logging
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
from collections import defaultdict, deque
import signal

from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit
import psutil

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('logs/system.log'),
        logging.StreamHandler(sys.stdout)
    ]
)

app = Flask(__name__, template_folder='../templates', static_folder='../static')
app.config['SECRET_KEY'] = 'bulkhead-demo-secret-key'
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')

class ResourceMonitor:
    """Monitor resource usage for bulkhead effectiveness"""
    
    def __init__(self, service_name, max_threads=10, max_connections=5):
        self.service_name = service_name
        self.max_threads = max_threads
        self.max_connections = max_connections
        self.active_threads = 0
        self.active_connections = 0
        self.total_requests = 0
        self.failed_requests = 0
        self.response_times = deque(maxlen=100)
        self.lock = threading.Lock()
        
    def acquire_thread(self):
        with self.lock:
            if self.active_threads >= self.max_threads:
                return False
            self.active_threads += 1
            return True
    
    def release_thread(self):
        with self.lock:
            self.active_threads = max(0, self.active_threads - 1)
    
    def acquire_connection(self):
        with self.lock:
            if self.active_connections >= self.max_connections:
                return False
            self.active_connections += 1
            return True
    
    def release_connection(self):
        with self.lock:
            self.active_connections = max(0, self.active_connections - 1)
    
    def record_request(self, success=True, response_time=0):
        with self.lock:
            self.total_requests += 1
            if not success:
                self.failed_requests += 1
            self.response_times.append(response_time)
    
    def get_stats(self):
        with self.lock:
            avg_response_time = sum(self.response_times) / len(self.response_times) if self.response_times else 0
            success_rate = ((self.total_requests - self.failed_requests) / self.total_requests * 100) if self.total_requests > 0 else 100
            
            return {
                'service_name': self.service_name,
                'active_threads': self.active_threads,
                'max_threads': self.max_threads,
                'active_connections': self.active_connections,
                'max_connections': self.max_connections,
                'total_requests': self.total_requests,
                'failed_requests': self.failed_requests,
                'success_rate': round(success_rate, 2),
                'avg_response_time': round(avg_response_time, 3),
                'thread_utilization': round((self.active_threads / self.max_threads) * 100, 2),
                'connection_utilization': round((self.active_connections / self.max_connections) * 100, 2)
            }

class BulkheadService:
    """Individual service with isolated resources"""
    
    def __init__(self, name, thread_pool_size=5, connection_pool_size=3, failure_rate=0.0):
        self.name = name
        self.failure_rate = failure_rate
        self.monitor = ResourceMonitor(name, thread_pool_size, connection_pool_size)
        self.thread_pool = ThreadPoolExecutor(max_workers=thread_pool_size, thread_name_prefix=f"{name}-pool")
        self.is_healthy = True
        self.logger = logging.getLogger(f"service.{name}")
        
    def simulate_work(self, work_type="normal", duration=None):
        """Simulate service work with configurable patterns"""
        if not self.monitor.acquire_thread():
            raise Exception(f"Thread pool exhausted for {self.name}")
        
        if not self.monitor.acquire_connection():
            self.monitor.release_thread()
            raise Exception(f"Connection pool exhausted for {self.name}")
        
        try:
            start_time = time.time()
            
            # Simulate different work patterns
            if work_type == "heavy":
                work_duration = random.uniform(2.0, 5.0)
            elif work_type == "light":
                work_duration = random.uniform(0.1, 0.5)
            elif work_type == "spike":
                work_duration = random.uniform(0.5, 8.0)
            else:
                work_duration = random.uniform(0.2, 1.0)
            
            if duration:
                work_duration = duration
            
            # Simulate failure
            if random.random() < self.failure_rate:
                time.sleep(work_duration * 0.3)  # Partial work before failure
                raise Exception(f"Simulated failure in {self.name}")
            
            # Simulate actual work
            time.sleep(work_duration)
            
            end_time = time.time()
            response_time = end_time - start_time
            
            self.monitor.record_request(success=True, response_time=response_time)
            self.logger.info(f"Completed {work_type} work in {response_time:.3f}s")
            
            return {
                'success': True,
                'service': self.name,
                'work_type': work_type,
                'duration': response_time,
                'timestamp': datetime.now().isoformat()
            }
            
        except Exception as e:
            end_time = time.time()
            response_time = end_time - start_time
            self.monitor.record_request(success=False, response_time=response_time)
            self.logger.error(f"Failed {work_type} work: {str(e)}")
            
            return {
                'success': False,
                'service': self.name,
                'work_type': work_type,
                'error': str(e),
                'duration': response_time,
                'timestamp': datetime.now().isoformat()
            }
            
        finally:
            self.monitor.release_connection()
            self.monitor.release_thread()
    
    def process_request_async(self, work_type="normal", duration=None):
        """Process request asynchronously"""
        future = self.thread_pool.submit(self.simulate_work, work_type, duration)
        return future
    
    def set_failure_rate(self, rate):
        """Dynamically adjust failure rate"""
        self.failure_rate = max(0.0, min(1.0, rate))
        self.logger.info(f"Failure rate set to {self.failure_rate * 100}%")
    
    def get_health_status(self):
        """Get current health status"""
        stats = self.monitor.get_stats()
        return {
            **stats,
            'is_healthy': self.is_healthy,
            'failure_rate': self.failure_rate * 100
        }

# Global service registry
services = {
    'payment': BulkheadService('payment', thread_pool_size=8, connection_pool_size=5, failure_rate=0.0),
    'analytics': BulkheadService('analytics', thread_pool_size=4, connection_pool_size=3, failure_rate=0.0),
    'user_mgmt': BulkheadService('user_mgmt', thread_pool_size=6, connection_pool_size=4, failure_rate=0.0),
    'notification': BulkheadService('notification', thread_pool_size=3, connection_pool_size=2, failure_rate=0.0)
}

# System metrics
system_stats = {
    'total_requests': 0,
    'total_failures': 0,
    'start_time': datetime.now()
}

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/services/status')
def get_services_status():
    """Get status of all services"""
    status = {}
    for name, service in services.items():
        status[name] = service.get_health_status()
    
    # Add system-wide metrics
    process = psutil.Process()
    status['system'] = {
        'cpu_percent': psutil.cpu_percent(),
        'memory_percent': psutil.virtual_memory().percent,
        'process_memory_mb': process.memory_info().rss / 1024 / 1024,
        'thread_count': threading.active_count(),
        'uptime_seconds': (datetime.now() - system_stats['start_time']).total_seconds()
    }
    
    return jsonify(status)

@app.route('/api/services/<service_name>/request', methods=['POST'])
def submit_service_request(service_name):
    """Submit a request to a specific service"""
    if service_name not in services:
        return jsonify({'error': 'Service not found'}), 404
    
    data = request.get_json() or {}
    work_type = data.get('work_type', 'normal')
    duration = data.get('duration')
    
    try:
        service = services[service_name]
        future = service.process_request_async(work_type, duration)
        
        # Start a background task to handle completion
        def handle_completion():
            try:
                result = future.result(timeout=30)
                socketio.emit('request_completed', result)
                system_stats['total_requests'] += 1
                if not result['success']:
                    system_stats['total_failures'] += 1
            except Exception as e:
                error_result = {
                    'success': False,
                    'service': service_name,
                    'error': str(e),
                    'timestamp': datetime.now().isoformat()
                }
                socketio.emit('request_completed', error_result)
                system_stats['total_failures'] += 1
        
        threading.Thread(target=handle_completion, daemon=True).start()
        
        return jsonify({
            'success': True,
            'message': f'Request submitted to {service_name}',
            'work_type': work_type
        })
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/services/<service_name>/failure_rate', methods=['POST'])
def set_service_failure_rate(service_name):
    """Set failure rate for a service"""
    if service_name not in services:
        return jsonify({'error': 'Service not found'}), 404
    
    data = request.get_json()
    failure_rate = data.get('failure_rate', 0.0) / 100.0  # Convert percentage to decimal
    
    services[service_name].set_failure_rate(failure_rate)
    
    return jsonify({
        'success': True,
        'service': service_name,
        'failure_rate': failure_rate * 100
    })

@app.route('/api/load_test', methods=['POST'])
def run_load_test():
    """Run a load test across all services"""
    data = request.get_json() or {}
    requests_per_service = data.get('requests_per_service', 10)
    work_type = data.get('work_type', 'normal')
    
    def submit_load():
        for service_name in services:
            for i in range(requests_per_service):
                try:
                    service = services[service_name]
                    future = service.process_request_async(work_type)
                    
                    def handle_result(f):
                        try:
                            result = f.result(timeout=30)
                            socketio.emit('request_completed', result)
                            system_stats['total_requests'] += 1
                            if not result['success']:
                                system_stats['total_failures'] += 1
                        except Exception as e:
                            error_result = {
                                'success': False,
                                'service': service_name,
                                'error': str(e),
                                'timestamp': datetime.now().isoformat()
                            }
                            socketio.emit('request_completed', error_result)
                            system_stats['total_failures'] += 1
                    
                    threading.Thread(target=lambda: handle_result(future), daemon=True).start()
                    
                except Exception as e:
                    logging.error(f"Load test error for {service_name}: {e}")
                
                # Small delay between requests
                time.sleep(0.1)
    
    threading.Thread(target=submit_load, daemon=True).start()
    
    return jsonify({
        'success': True,
        'message': f'Load test started: {requests_per_service} requests per service'
    })

@socketio.on('connect')
def handle_connect():
    """Handle client connection"""
    emit('connected', {'message': 'Connected to Bulkheads Demo'})
    
    # Start periodic status updates
    def send_status_updates():
        while True:
            try:
                status = {}
                for name, service in services.items():
                    status[name] = service.get_health_status()
                
                # Add system metrics
                process = psutil.Process()
                status['system'] = {
                    'cpu_percent': psutil.cpu_percent(),
                    'memory_percent': psutil.virtual_memory().percent,
                    'process_memory_mb': round(process.memory_info().rss / 1024 / 1024, 2),
                    'thread_count': threading.active_count(),
                    'total_requests': system_stats['total_requests'],
                    'total_failures': system_stats['total_failures'],
                    'uptime_seconds': (datetime.now() - system_stats['start_time']).total_seconds()
                }
                
                socketio.emit('status_update', status)
                time.sleep(2)  # Update every 2 seconds
            except:
                break
    
    threading.Thread(target=send_status_updates, daemon=True).start()

if __name__ == '__main__':
    # Ensure data directory exists
    os.makedirs('data', exist_ok=True)
    os.makedirs('logs', exist_ok=True)
    
    print("🔧 Starting Bulkheads and Isolation Demo...")
    print("📊 Open http://localhost:5000 to view the dashboard")
    print("📝 Logs are written to logs/system.log")
    
    # Handle graceful shutdown
    def signal_handler(sig, frame):
        print("\n🛑 Shutting down gracefully...")
        for service in services.values():
            service.thread_pool.shutdown(wait=True)
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Start the application
    socketio.run(app, host='0.0.0.0', port=5000, debug=False, allow_unsafe_werkzeug=True)
