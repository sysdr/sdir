"""
Flask web application demonstrating Bloom filters in action
Provides interactive interface for learning system design concepts
"""

from flask import Flask, render_template, request, jsonify
import redis
import json
import time
import logging
from bloom_filter import ProductionBloomFilter, DistributedBloomFilter, run_performance_test
from faker import Faker
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Flask app with explicit template folder
# This ensures Flask can find templates regardless of working directory
template_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'templates'))
app = Flask(__name__, template_folder=template_dir)

fake = Faker()

# Debug: Print template directory for troubleshooting
logger.info(f"Template directory: {template_dir}")
logger.info(f"Template directory exists: {os.path.exists(template_dir)}")
if os.path.exists(template_dir):
    logger.info(f"Templates found: {os.listdir(template_dir)}")

# Redis connection
try:
    redis_host = os.getenv('REDIS_HOST', 'localhost')
    redis_port = int(os.getenv('REDIS_PORT', 6379))
    redis_client = redis.Redis(host=redis_host, port=redis_port, decode_responses=True)
    redis_client.ping()
    logger.info(f"Connected to Redis at {redis_host}:{redis_port}")
except Exception as e:
    logger.warning(f"Redis connection failed: {e}. Using in-memory storage.")
    redis_client = None

# Global objects
bloom_filter = None
distributed_filter = None

def initialize_filters():
    """Initialize Bloom filters with default parameters"""
    global bloom_filter, distributed_filter
    
    bloom_filter = ProductionBloomFilter(
        expected_elements=100000,
        false_positive_rate=0.01
    )
    
    distributed_filter = DistributedBloomFilter(
        num_nodes=3,
        expected_elements_per_node=50000
    )
    
    # Pre-populate with some data
    sample_data = [
        f"{fake.user_name()}@{fake.domain_name()}" 
        for _ in range(1000)
    ]
    
    for email in sample_data:
        bloom_filter.add(email)
        distributed_filter.add(email)
    
    logger.info("Bloom filters initialized with sample data")

@app.route('/')
def index():
    """Main dashboard page"""
    return render_template('index.html')

@app.route('/api/filter/add', methods=['POST'])
def add_to_filter():
    """Add item to Bloom filter"""
    try:
        data = request.get_json()
        item = data.get('item', '').strip()
        
        if not item:
            return jsonify({'error': 'Item cannot be empty'}), 400
        
        # Add to both filters
        bloom_filter.add(item)
        node_id = distributed_filter.add(item)
        
        # Store in Redis if available
        if redis_client:
            redis_client.sadd('added_items', item)
        
        return jsonify({
            'success': True,
            'item': item,
            'assigned_node': node_id,
            'timestamp': time.time()
        })
    
    except Exception as e:
        logger.error(f"Error adding item: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/filter/check', methods=['POST'])
def check_filter():
    """Check if item exists in Bloom filter"""
    try:
        data = request.get_json()
        item = data.get('item', '').strip()
        
        if not item:
            return jsonify({'error': 'Item cannot be empty'}), 400
        
        # Check single filter
        single_result = bloom_filter.contains(item)
        
        # Check distributed filter
        distributed_result = distributed_filter.contains(item)
        
        # Check Redis if available
        redis_exists = False
        if redis_client:
            redis_exists = redis_client.sismember('added_items', item)
        
        return jsonify({
            'item': item,
            'single_filter_result': single_result,
            'distributed_filter_result': distributed_result,
            'redis_actual_exists': redis_exists,
            'is_false_positive': single_result and not redis_exists,
            'timestamp': time.time()
        })
    
    except Exception as e:
        logger.error(f"Error checking item: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/statistics')
def get_statistics():
    """Get comprehensive filter statistics"""
    try:
        single_stats = bloom_filter.get_statistics()
        distributed_stats = distributed_filter.get_cluster_statistics()
        
        # Redis stats
        redis_stats = {}
        if redis_client:
            try:
                redis_stats = {
                    'total_items': redis_client.scard('added_items'),
                    'memory_usage': redis_client.memory_usage('added_items') if redis_client.exists('added_items') else 0
                }
            except Exception as e:
                redis_stats = {'error': str(e)}
        
        return jsonify({
            'single_filter': single_stats,
            'distributed_filter': distributed_stats,
            'redis': redis_stats,
            'timestamp': time.time()
        })
    
    except Exception as e:
        logger.error(f"Error getting statistics: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/performance-test', methods=['POST'])
def run_performance_test_api():
    """Run performance test"""
    try:
        data = request.get_json()
        test_size = data.get('test_size', 10000)
        
        if test_size > 100000:
            return jsonify({'error': 'Test size too large (max: 100,000)'}), 400
        
        # Create new filter for testing
        test_filter = ProductionBloomFilter(
            expected_elements=test_size,
            false_positive_rate=0.01
        )
        
        # Run performance test
        results = run_performance_test(test_filter, test_size)
        
        return jsonify({
            'success': True,
            'results': results,
            'timestamp': time.time()
        })
    
    except Exception as e:
        logger.error(f"Error running performance test: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/generate-data', methods=['POST'])
def generate_test_data():
    """Generate random test data"""
    try:
        data = request.get_json()
        count = min(data.get('count', 100), 1000)  # Limit to 1000
        
        generated_items = []
        for _ in range(count):
            email = f"{fake.user_name()}@{fake.domain_name()}"
            bloom_filter.add(email)
            distributed_filter.add(email)
            
            if redis_client:
                redis_client.sadd('added_items', email)
            
            generated_items.append(email)
        
        return jsonify({
            'success': True,
            'generated_count': len(generated_items),
            'items': generated_items[:10],  # Return first 10 for display
            'timestamp': time.time()
        })
    
    except Exception as e:
        logger.error(f"Error generating test data: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'timestamp': time.time(),
        'redis_connected': redis_client is not None
    })

if __name__ == '__main__':
    # Create logs directory
    os.makedirs('logs', exist_ok=True)
    
    # Initialize filters
    initialize_filters()
    
    # Run the application
    app.run(host='0.0.0.0', port=8080, debug=True)
