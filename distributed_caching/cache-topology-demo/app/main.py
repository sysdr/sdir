import os
import time
import json
import random
import threading
from datetime import datetime, timedelta
from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit
from flask_cors import CORS
import redis
import logging

app = Flask(__name__, template_folder='../templates', static_folder='../static')
app.config['SECRET_KEY'] = 'cache_demo_secret_key'
CORS(app)
#socketio = SocketIO(app, cors_allowed_origins="*", async_mode='eventlet')
socketio = SocketIO(app, cors_allowed_origins="*")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Redis connections for different cache topologies
cache_configs = {
    'cache_aside': {'host': 'redis-primary', 'port': 6379, 'db': 0},
    'write_through': {'host': 'redis-primary', 'port': 6379, 'db': 1},
    'write_behind': {'host': 'redis-primary', 'port': 6379, 'db': 2},
    'read_through': {'host': 'redis-primary', 'port': 6379, 'db': 3}
}

redis_clients = {}
metrics = {
    'cache_hits': 0,
    'cache_misses': 0,
    'database_queries': 0,
    'write_operations': 0,
    'consistency_violations': 0
}

# Simulated database
database = {}
write_behind_queue = []

class CacheTopologyDemo:
    def __init__(self):
        self.connect_redis()
        self.start_background_tasks()
    
    def connect_redis(self):
        """Initialize Redis connections for different cache patterns"""
        for pattern, config in cache_configs.items():
            try:
                client = redis.Redis(
                    host=config['host'], 
                    port=config['port'], 
                    db=config['db'],
                    decode_responses=True,
                    socket_connect_timeout=5,
                    socket_timeout=5,
                    retry_on_timeout=True
                )
                client.ping()
                redis_clients[pattern] = client
                logger.info(f"Connected to Redis for {pattern}")
            except Exception as e:
                logger.error(f"Failed to connect to Redis for {pattern}: {e}")
                # Create mock client for demo
                redis_clients[pattern] = MockRedisClient()
    
    def start_background_tasks(self):
        """Start background tasks for write-behind and monitoring"""
        threading.Thread(target=self.write_behind_worker, daemon=True).start()
        threading.Thread(target=self.metrics_broadcaster, daemon=True).start()
    
    def write_behind_worker(self):
        """Process write-behind queue"""
        while True:
            try:
                if write_behind_queue:
                    item = write_behind_queue.pop(0)
                    # Simulate database write delay
                    time.sleep(0.1)
                    database[item['key']] = item['value']
                    logger.info(f"Write-behind: Persisted {item['key']} to database")
                time.sleep(0.5)
            except Exception as e:
                logger.error(f"Write-behind worker error: {e}")
    
    def metrics_broadcaster(self):
        """Broadcast metrics to connected clients"""
        while True:
            try:
                socketio.emit('metrics_update', metrics)
                time.sleep(1)
            except Exception as e:
                logger.error(f"Metrics broadcaster error: {e}")
    
    # Cache Pattern Implementations
    
    def cache_aside_get(self, key):
        """Cache-aside pattern with TTL jitter"""
        try:
            # Check cache first
            value = redis_clients['cache_aside'].get(key)
            if value:
                metrics['cache_hits'] += 1
                logger.info(f"Cache-aside HIT: {key}")
                return json.loads(value)
            
            # Cache miss - query database
            metrics['cache_misses'] += 1
            metrics['database_queries'] += 1
            
            # Simulate database query
            time.sleep(0.05)  # 50ms database latency
            
            if key in database:
                db_value = database[key]
            else:
                db_value = f"data_for_{key}_{int(time.time())}"
                database[key] = db_value
            
            # Store in cache with jitter (TTL between 30-36 seconds)
            ttl = 30 + random.randint(0, 6)
            redis_clients['cache_aside'].setex(key, ttl, json.dumps(db_value))
            
            logger.info(f"Cache-aside MISS: {key}, stored with TTL {ttl}s")
            return db_value
            
        except Exception as e:
            logger.error(f"Cache-aside error: {e}")
            return f"error_{key}"
    
    def write_through_set(self, key, value):
        """Write-through pattern - synchronous database update"""
        try:
            # Write to database first (synchronous)
            time.sleep(0.1)  # 100ms database write latency
            database[key] = value
            metrics['database_queries'] += 1
            
            # Then update cache
            redis_clients['write_through'].setex(key, 60, json.dumps(value))
            metrics['write_operations'] += 1
            
            logger.info(f"Write-through: {key} -> {value}")
            return True
            
        except Exception as e:
            logger.error(f"Write-through error: {e}")
            return False
    
    def write_behind_set(self, key, value):
        """Write-behind pattern - asynchronous database update"""
        try:
            # Update cache immediately
            redis_clients['write_behind'].setex(key, 60, json.dumps(value))
            metrics['write_operations'] += 1
            
            # Queue for background database write
            write_behind_queue.append({'key': key, 'value': value, 'timestamp': time.time()})
            
            logger.info(f"Write-behind: {key} cached, queued for DB write")
            return True
            
        except Exception as e:
            logger.error(f"Write-behind error: {e}")
            return False
    
    def simulate_cache_stampede(self, key, num_requests=10):
        """Simulate cache stampede scenario"""
        def stampede_request():
            self.cache_aside_get(f"popular_{key}")
        
        # Clear cache to force miss
        try:
            redis_clients['cache_aside'].delete(f"popular_{key}")
        except:
            pass
        
        # Launch concurrent requests
        threads = []
        for i in range(num_requests):
            thread = threading.Thread(target=stampede_request)
            threads.append(thread)
            thread.start()
        
        for thread in threads:
            thread.join()
        
        logger.info(f"Cache stampede simulation completed: {num_requests} concurrent requests")
    
    def inject_network_partition(self, duration=10):
        """Simulate network partition by disconnecting Redis"""
        logger.info(f"Injecting network partition for {duration} seconds")
        
        # Store original clients
        original_clients = redis_clients.copy()
        
        # Replace with mock clients (simulate network failure)
        for pattern in redis_clients:
            redis_clients[pattern] = MockRedisClient()
        
        def restore_connection():
            time.sleep(duration)
            redis_clients.update(original_clients)
            logger.info("Network partition resolved - connections restored")
        
        threading.Thread(target=restore_connection, daemon=True).start()

class MockRedisClient:
    """Mock Redis client for simulating network failures"""
    def __init__(self):
        self.data = {}
    
    def get(self, key):
        return None  # Simulate cache miss during partition
    
    def setex(self, key, ttl, value):
        pass  # Simulate failed write during partition
    
    def delete(self, key):
        pass

# Initialize demo
demo = CacheTopologyDemo()

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/cache-aside/<key>')
def cache_aside_api(key):
    start_time = time.time()
    value = demo.cache_aside_get(key)
    latency = (time.time() - start_time) * 1000
    
    return jsonify({
        'pattern': 'cache-aside',
        'key': key,
        'value': value,
        'latency_ms': round(latency, 2),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/write-through', methods=['POST'])
def write_through_api():
    data = request.get_json()
    key = data.get('key')
    value = data.get('value')
    
    start_time = time.time()
    success = demo.write_through_set(key, value)
    latency = (time.time() - start_time) * 1000
    
    return jsonify({
        'pattern': 'write-through',
        'success': success,
        'latency_ms': round(latency, 2),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/write-behind', methods=['POST'])
def write_behind_api():
    data = request.get_json()
    key = data.get('key')
    value = data.get('value')
    
    start_time = time.time()
    success = demo.write_behind_set(key, value)
    latency = (time.time() - start_time) * 1000
    
    return jsonify({
        'pattern': 'write-behind',
        'success': success,
        'latency_ms': round(latency, 2),
        'timestamp': datetime.now().isoformat()
    })

@app.route('/api/stampede/<key>')
def simulate_stampede(key):
    threading.Thread(target=demo.simulate_cache_stampede, args=(key, 20), daemon=True).start()
    return jsonify({'message': f'Cache stampede simulation started for key: {key}'})

@app.route('/api/partition/<int:duration>')
def simulate_partition(duration):
    threading.Thread(target=demo.inject_network_partition, args=(duration,), daemon=True).start()
    return jsonify({'message': f'Network partition injected for {duration} seconds'})

@app.route('/api/metrics')
def get_metrics():
    return jsonify(metrics)

@app.route('/api/health')
def health_check():
    return jsonify({'status': 'healthy', 'timestamp': datetime.now().isoformat()})

if __name__ == '__main__':
    #socketio.run(app, host='0.0.0.0', port=5000, debug=True)
    socketio.run(app, host='0.0.0.0', port=5000, debug=True, allow_unsafe_werkzeug=True)
