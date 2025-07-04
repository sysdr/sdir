import os
import time
import json
import random
import threading
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor
import asyncio

import redis
import psycopg2
from psycopg2.extras import RealDictCursor
from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit
import numpy as np

app = Flask(__name__)
app.config['SECRET_KEY'] = 'read-write-demo-secret'
socketio = SocketIO(app, cors_allowed_origins="*")

# Configuration
REDIS_URL = os.getenv('REDIS_URL', 'redis://localhost:6379')
DATABASE_URL = os.getenv('DATABASE_URL', 'postgresql://demo:demo123@localhost:5432/readwrite_demo')

# Initialize Redis
redis_client = redis.from_url(REDIS_URL, decode_responses=True)

# Performance metrics storage
metrics = {
    'read_times': [],
    'write_times': [],
    'cache_hits': 0,
    'cache_misses': 0,
    'total_reads': 0,
    'total_writes': 0
}

class OptimizationStrategy:
    def __init__(self):
        self.mode = 'read-heavy'  # or 'write-heavy'
        self.cache_enabled = True
        self.batch_writes = True
        self.read_replicas = True
        
    def toggle_mode(self):
        self.mode = 'write-heavy' if self.mode == 'read-heavy' else 'read-heavy'
        return self.mode

strategy = OptimizationStrategy()

def get_db_connection():
    """Get database connection with retry logic"""
    max_retries = 3
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(DATABASE_URL)
            return conn
        except psycopg2.OperationalError as e:
            if attempt == max_retries - 1:
                raise e
            time.sleep(1)

def init_database():
    """Initialize database tables"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Create tables for demo
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS products (
            id SERIAL PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            description TEXT,
            price DECIMAL(10,2),
            category VARCHAR(100),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS user_activities (
            id SERIAL PRIMARY KEY,
            user_id INTEGER,
            activity_type VARCHAR(50),
            product_id INTEGER,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            metadata JSONB
        )
    """)
    
    # Create indexes for read optimization
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_products_category ON products(category)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_activities_user_id ON user_activities(user_id)")
    cursor.execute("CREATE INDEX IF NOT EXISTS idx_activities_timestamp ON user_activities(timestamp)")
    
    conn.commit()
    cursor.close()
    conn.close()

def seed_data():
    """Seed database with sample data"""
    conn = get_db_connection()
    cursor = conn.cursor()
    
    # Check if data already exists
    cursor.execute("SELECT COUNT(*) FROM products")
    if cursor.fetchone()[0] > 0:
        cursor.close()
        conn.close()
        return
    
    # Insert sample products
    categories = ['Electronics', 'Books', 'Clothing', 'Home', 'Sports']
    for i in range(1000):
        cursor.execute("""
            INSERT INTO products (name, description, price, category)
            VALUES (%s, %s, %s, %s)
        """, (
            f'Product {i}',
            f'Description for product {i}',
            round(random.uniform(10, 1000), 2),
            random.choice(categories)
        ))
    
    conn.commit()
    cursor.close()
    conn.close()

def read_optimized_query(product_id=None):
    """Demonstrate read-heavy optimization patterns"""
    start_time = time.time()
    
    # Try cache first if enabled
    if strategy.cache_enabled:
        cache_key = f"product:{product_id}" if product_id else "products:all"
        cached_data = redis_client.get(cache_key)
        
        if cached_data:
            metrics['cache_hits'] += 1
            metrics['read_times'].append(time.time() - start_time)
            metrics['total_reads'] += 1
            return json.loads(cached_data)
        else:
            metrics['cache_misses'] += 1
    
    # Database query with read optimizations
    conn = get_db_connection()
    cursor = conn.cursor(cursor_factory=RealDictCursor)
    
    if product_id:
        # Single product read with covering index
        cursor.execute("""
            SELECT id, name, description, price, category 
            FROM products 
            WHERE id = %s
        """, (product_id,))
        result = cursor.fetchone()
        data = dict(result) if result else None
    else:
        # Bulk read with pagination and caching
        cursor.execute("""
            SELECT id, name, price, category 
            FROM products 
            ORDER BY id 
            LIMIT 50
        """)
        results = cursor.fetchall()
        data = [dict(row) for row in results]
    
    cursor.close()
    conn.close()
    
    # Cache the result if caching is enabled
    if strategy.cache_enabled and data:
        cache_key = f"product:{product_id}" if product_id else "products:all"
        redis_client.setex(cache_key, 300, json.dumps(data, default=str))  # 5 minute TTL
    
    metrics['read_times'].append(time.time() - start_time)
    metrics['total_reads'] += 1
    return data

def write_optimized_operation(user_id, activity_type, product_id, metadata=None):
    """Demonstrate write-heavy optimization patterns"""
    start_time = time.time()
    
    if strategy.mode == 'write-heavy' and strategy.batch_writes:
        # Use write batching for better performance
        batch_key = f"write_batch:{int(time.time())}"
        write_data = {
            'user_id': user_id,
            'activity_type': activity_type,
            'product_id': product_id,
            'metadata': metadata,
            'timestamp': time.time()
        }
        redis_client.lpush(batch_key, json.dumps(write_data))
        redis_client.expire(batch_key, 60)  # Process within 1 minute
        
        # Trigger batch processing (simulated)
        process_write_batch()
    else:
        # Direct write to database
        conn = get_db_connection()
        cursor = conn.cursor()
        
        cursor.execute("""
            INSERT INTO user_activities (user_id, activity_type, product_id, metadata)
            VALUES (%s, %s, %s, %s)
        """, (user_id, activity_type, product_id, json.dumps(metadata) if metadata else None))
        
        conn.commit()
        cursor.close()
        conn.close()
        
        # Invalidate related caches
        if strategy.cache_enabled:
            redis_client.delete(f"user_activities:{user_id}")
    
    metrics['write_times'].append(time.time() - start_time)
    metrics['total_writes'] += 1

def process_write_batch():
    """Process batched writes for write-heavy optimization"""
    # This would typically run in a background worker
    pass

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/products/<int:product_id>')
def get_product(product_id):
    """API endpoint for single product read"""
    data = read_optimized_query(product_id)
    return jsonify(data)

@app.route('/api/products')
def get_products():
    """API endpoint for bulk product read"""
    data = read_optimized_query()
    return jsonify(data)

@app.route('/api/activity', methods=['POST'])
def create_activity():
    """API endpoint for write operations"""
    data = request.json
    write_optimized_operation(
        data.get('user_id'),
        data.get('activity_type'),
        data.get('product_id'),
        data.get('metadata')
    )
    return jsonify({'status': 'success'})

@app.route('/api/strategy/toggle', methods=['POST'])
def toggle_strategy():
    """Toggle between read-heavy and write-heavy optimization"""
    new_mode = strategy.toggle_mode()
    return jsonify({'mode': new_mode})

@app.route('/api/strategy/cache/<enabled>')
def toggle_cache(enabled):
    """Enable or disable caching"""
    strategy.cache_enabled = enabled.lower() == 'true'
    return jsonify({'cache_enabled': strategy.cache_enabled})

@app.route('/api/metrics')
def get_metrics():
    """Get current performance metrics"""
    return jsonify({
        'mode': strategy.mode,
        'cache_enabled': strategy.cache_enabled,
        'avg_read_time': np.mean(metrics['read_times'][-100:]) if metrics['read_times'] else 0,
        'avg_write_time': np.mean(metrics['write_times'][-100:]) if metrics['write_times'] else 0,
        'cache_hit_ratio': metrics['cache_hits'] / (metrics['cache_hits'] + metrics['cache_misses']) if (metrics['cache_hits'] + metrics['cache_misses']) > 0 else 0,
        'total_reads': metrics['total_reads'],
        'total_writes': metrics['total_writes']
    })

@app.route('/api/load-test', methods=['POST'])
def run_load_test():
    """Run load test to demonstrate performance differences"""
    test_type = request.json.get('type', 'read')
    duration = request.json.get('duration', 10)
    concurrent_users = request.json.get('concurrent_users', 10)
    
    def load_test_worker():
        results = []
        end_time = time.time() + duration
        
        while time.time() < end_time:
            start = time.time()
            
            if test_type == 'read':
                product_id = random.randint(1, 100)
                read_optimized_query(product_id)
            else:  # write
                write_optimized_operation(
                    random.randint(1, 1000),
                    'view',
                    random.randint(1, 100)
                )
            
            results.append(time.time() - start)
            time.sleep(0.01)  # Small delay to prevent overwhelming
        
        return results
    
    # Run concurrent load test
    with ThreadPoolExecutor(max_workers=concurrent_users) as executor:
        futures = [executor.submit(load_test_worker) for _ in range(concurrent_users)]
        all_results = []
        for future in futures:
            all_results.extend(future.result())
    
    return jsonify({
        'total_operations': len(all_results),
        'avg_latency': np.mean(all_results),
        'p95_latency': np.percentile(all_results, 95),
        'p99_latency': np.percentile(all_results, 99),
        'operations_per_second': len(all_results) / duration
    })

@socketio.on('connect')
def handle_connect():
    emit('status', {'msg': 'Connected to Read-Write Demo'})

if __name__ == '__main__':
    # Initialize database and seed data
    time.sleep(2)  # Wait for database to be ready
    init_database()
    seed_data()
    
    print("🎯 Read-Heavy vs Write-Heavy Systems Demo Starting...")
    print("📊 Dashboard: http://localhost:5000")
    print("🔧 Mode: Read-Heavy (default)")
    
    socketio.run(app, host='0.0.0.0', port=5000, debug=True, allow_unsafe_werkzeug=True)
