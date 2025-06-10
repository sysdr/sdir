#!/bin/bash

# =============================================================================
# Bloom Filter Production Demo Script
# Demonstrates distributed caching with Bloom filters for system design learning
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="bloom-filter-demo"
DEMO_PORT=8080
REDIS_PORT=6379

echo -e "${BLUE}=== Bloom Filter Production Demo Setup ===${NC}"
echo "This demo showcases Bloom filters in a distributed caching architecture"
echo ""

# Function to print colored status
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is required but not installed"
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi
    
    print_status "Prerequisites check passed"
}

# Create project structure
create_project_structure() {
    print_status "Creating project structure..."
    
    # Clean up existing directory
    if [ -d "$PROJECT_NAME" ]; then
        print_warning "Removing existing $PROJECT_NAME directory..."
        rm -rf "$PROJECT_NAME"
    fi
    
    # Create proper Flask directory structure
    mkdir -p "$PROJECT_NAME"/{src,templates,static,tests,docker,logs}
    cd "$PROJECT_NAME"
    
    print_status "Project structure created with Flask-compatible layout"
}

# Create Dockerfile
create_dockerfile() {
    print_status "Creating Dockerfile..."
    
cat > docker/Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first for better caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code and maintain directory structure
COPY src/ ./src/
COPY templates/ ./templates/
COPY static/ ./static/
COPY tests/ ./tests/

# Create logs directory
RUN mkdir -p /app/logs

# Debug: List directory structure for troubleshooting
RUN echo "=== Directory Structure ===" && \
    find /app -type f -name "*.py" -o -name "*.html" | head -20 && \
    echo "=== Template Directory ===" && \
    ls -la /app/templates/ || echo "Templates directory not found"

EXPOSE 8080

# Set Python path to include src directory
ENV PYTHONPATH="/app/src:${PYTHONPATH}"

CMD ["python", "src/app.py"]
EOF
}

# Create docker-compose file
create_docker_compose() {
    print_status "Creating docker-compose.yml..."
    
cat > docker-compose.yml << EOF
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: docker/Dockerfile
    ports:
      - "${DEMO_PORT}:8080"
    depends_on:
      - redis
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - FLASK_ENV=development
    volumes:
      - ./logs:/app/logs

  redis:
    image: redis:7-alpine
    ports:
      - "${REDIS_PORT}:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data

volumes:
  redis_data:
EOF
}

# Create requirements.txt
create_requirements() {
    print_status "Creating requirements.txt..."
    
cat > requirements.txt << 'EOF'
Flask==3.0.0
redis==5.0.1
mmh3==4.1.0
numpy==1.26.2
matplotlib==3.8.2
plotly==5.17.0
gunicorn==21.2.0
pytest==7.4.3
requests==2.31.0
faker==20.1.0
EOF
}

# Create the core Bloom filter implementation
create_bloom_filter() {
    print_status "Creating Bloom filter implementation..."
    
cat > src/bloom_filter.py << 'EOF'
"""
Production-grade Bloom Filter implementation
Demonstrates key concepts from the System Design Interview Roadmap
"""

import mmh3
import numpy as np
import math
import time
import logging
from typing import List, Optional, Any
import json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ProductionBloomFilter:
    """
    Production-ready Bloom filter with advanced features:
    - Optimal parameter calculation
    - Multiple hash function strategies
    - Performance monitoring
    - Memory optimization
    """
    
    def __init__(self, expected_elements: int, false_positive_rate: float = 0.01):
        """
        Initialize Bloom filter with optimal parameters
        
        Args:
            expected_elements: Expected number of elements to insert
            false_positive_rate: Desired false positive rate (0.01 = 1%)
        """
        self.expected_elements = expected_elements
        self.false_positive_rate = false_positive_rate
        
        # Calculate optimal parameters using mathematical formulas
        self.bit_array_size = self._calculate_optimal_bit_array_size()
        self.num_hash_functions = self._calculate_optimal_hash_functions()
        
        # Initialize bit array using numpy for memory efficiency
        self.bit_array = np.zeros(self.bit_array_size, dtype=bool)
        
        # Performance tracking
        self.elements_added = 0
        self.lookup_count = 0
        self.false_positive_count = 0
        
        # Statistics
        self.creation_time = time.time()
        
        logger.info(f"Bloom filter created: {self.bit_array_size} bits, "
                   f"{self.num_hash_functions} hash functions, "
                   f"expected FP rate: {self.false_positive_rate:.3f}")
    
    def _calculate_optimal_bit_array_size(self) -> int:
        """
        Calculate optimal bit array size using the formula:
        m = -(n * ln(p)) / (ln(2)^2)
        where n = expected elements, p = false positive rate
        """
        m = -(self.expected_elements * math.log(self.false_positive_rate)) / (math.log(2) ** 2)
        return int(m)
    
    def _calculate_optimal_hash_functions(self) -> int:
        """
        Calculate optimal number of hash functions:
        k = (m/n) * ln(2)
        where m = bit array size, n = expected elements
        """
        k = (self.bit_array_size / self.expected_elements) * math.log(2)
        return max(1, int(round(k)))
    
    def _hash_functions(self, item: str) -> List[int]:
        """
        Generate multiple hash values using MMH3 with different seeds
        This approach provides good distribution and performance
        """
        hashes = []
        for i in range(self.num_hash_functions):
            # Use different seeds to create independent hash functions
            hash_value = mmh3.hash(item, seed=i) % self.bit_array_size
            hashes.append(abs(hash_value))  # Ensure positive index
        return hashes
    
    def add(self, item: str) -> None:
        """Add an item to the Bloom filter"""
        hash_values = self._hash_functions(item)
        
        for hash_val in hash_values:
            self.bit_array[hash_val] = True
        
        self.elements_added += 1
        
        if self.elements_added % 10000 == 0:
            logger.info(f"Added {self.elements_added} elements to Bloom filter")
    
    def contains(self, item: str) -> bool:
        """
        Check if an item might be in the set
        Returns: True if item might be present, False if definitely not present
        """
        self.lookup_count += 1
        hash_values = self._hash_functions(item)
        
        # All bits must be set for a potential match
        for hash_val in hash_values:
            if not self.bit_array[hash_val]:
                return False
        
        return True
    
    def get_current_false_positive_rate(self) -> float:
        """
        Calculate current theoretical false positive rate based on actual load
        Formula: (1 - e^(-kn/m))^k
        """
        if self.elements_added == 0:
            return 0.0
        
        # Calculate the probability that a bit is still 0
        prob_bit_zero = (1 - 1/self.bit_array_size) ** (self.num_hash_functions * self.elements_added)
        
        # False positive rate is (1 - prob_bit_zero)^k
        fp_rate = (1 - prob_bit_zero) ** self.num_hash_functions
        
        return fp_rate
    
    def get_memory_usage_mb(self) -> float:
        """Calculate memory usage in MB"""
        bits_in_mb = self.bit_array_size / (8 * 1024 * 1024)
        return bits_in_mb
    
    def get_statistics(self) -> dict:
        """Get comprehensive statistics about the filter"""
        current_fp_rate = self.get_current_false_positive_rate()
        bits_set = np.sum(self.bit_array)
        fill_ratio = bits_set / self.bit_array_size
        
        return {
            'bit_array_size': self.bit_array_size,
            'num_hash_functions': self.num_hash_functions,
            'expected_elements': self.expected_elements,
            'elements_added': self.elements_added,
            'expected_fp_rate': self.false_positive_rate,
            'current_fp_rate': current_fp_rate,
            'memory_usage_mb': self.get_memory_usage_mb(),
            'bits_set': int(bits_set),
            'fill_ratio': fill_ratio,
            'lookup_count': self.lookup_count,
            'uptime_seconds': time.time() - self.creation_time
        }
    
    def export_to_dict(self) -> dict:
        """Export filter state for serialization"""
        return {
            'bit_array': self.bit_array.tolist(),
            'config': {
                'expected_elements': self.expected_elements,
                'false_positive_rate': self.false_positive_rate,
                'bit_array_size': self.bit_array_size,
                'num_hash_functions': self.num_hash_functions
            },
            'stats': self.get_statistics()
        }

class DistributedBloomFilter:
    """
    Simulates distributed Bloom filter across multiple nodes
    Demonstrates enterprise architecture patterns
    """
    
    def __init__(self, num_nodes: int = 3, expected_elements_per_node: int = 100000):
        self.num_nodes = num_nodes
        self.nodes = {}
        
        # Create a Bloom filter for each node
        for i in range(num_nodes):
            node_id = f"node_{i}"
            self.nodes[node_id] = ProductionBloomFilter(
                expected_elements=expected_elements_per_node,
                false_positive_rate=0.01
            )
        
        # Global aggregated filter for cross-node queries
        self.global_filter = ProductionBloomFilter(
            expected_elements=num_nodes * expected_elements_per_node,
            false_positive_rate=0.001  # Lower FP rate for global filter
        )
    
    def _get_node_for_key(self, key: str) -> str:
        """Consistent hashing to determine which node handles the key"""
        hash_val = mmh3.hash(key)
        node_index = abs(hash_val) % self.num_nodes
        return f"node_{node_index}"
    
    def add(self, key: str) -> str:
        """Add key to appropriate node and global filter"""
        node_id = self._get_node_for_key(key)
        
        # Add to specific node
        self.nodes[node_id].add(key)
        
        # Add to global filter
        self.global_filter.add(key)
        
        return node_id
    
    def contains(self, key: str) -> dict:
        """Check if key exists with detailed results"""
        node_id = self._get_node_for_key(key)
        
        # Check local node first (faster)
        local_result = self.nodes[node_id].contains(key)
        
        # Check global filter
        global_result = self.global_filter.contains(key)
        
        return {
            'key': key,
            'assigned_node': node_id,
            'local_node_result': local_result,
            'global_filter_result': global_result,
            'recommendation': 'check_cache' if local_result else 'skip_cache'
        }
    
    def get_cluster_statistics(self) -> dict:
        """Get statistics for the entire cluster"""
        node_stats = {}
        total_elements = 0
        
        for node_id, bloom_filter in self.nodes.items():
            stats = bloom_filter.get_statistics()
            node_stats[node_id] = stats
            total_elements += stats['elements_added']
        
        global_stats = self.global_filter.get_statistics()
        
        return {
            'total_elements': total_elements,
            'num_nodes': self.num_nodes,
            'node_statistics': node_stats,
            'global_filter_statistics': global_stats,
            'average_elements_per_node': total_elements / self.num_nodes if self.num_nodes > 0 else 0
        }

# Testing and benchmarking functions
def run_performance_test(bloom_filter: ProductionBloomFilter, test_size: int = 100000):
    """Run comprehensive performance tests"""
    logger.info(f"Starting performance test with {test_size} operations...")
    
    # Test data generation
    test_items = [f"user_{i}@example.com" for i in range(test_size)]
    false_test_items = [f"fake_user_{i}@test.com" for i in range(test_size // 10)]
    
    # Insertion performance test
    start_time = time.time()
    for item in test_items:
        bloom_filter.add(item)
    insertion_time = time.time() - start_time
    
    # Lookup performance test (true positives)
    start_time = time.time()
    true_positive_count = 0
    for item in test_items[:1000]:  # Test subset for speed
        if bloom_filter.contains(item):
            true_positive_count += 1
    lookup_time_tp = time.time() - start_time
    
    # Lookup performance test (false positives)
    start_time = time.time()
    false_positive_count = 0
    for item in false_test_items:
        if bloom_filter.contains(item):
            false_positive_count += 1
    lookup_time_fp = time.time() - start_time
    
    # Calculate actual false positive rate
    actual_fp_rate = false_positive_count / len(false_test_items) if false_test_items else 0
    
    return {
        'test_size': test_size,
        'insertion_time_seconds': insertion_time,
        'insertions_per_second': test_size / insertion_time,
        'lookup_time_tp_seconds': lookup_time_tp,
        'lookup_time_fp_seconds': lookup_time_fp,
        'true_positive_count': true_positive_count,
        'false_positive_count': false_positive_count,
        'actual_fp_rate': actual_fp_rate,
        'theoretical_fp_rate': bloom_filter.get_current_false_positive_rate(),
        'memory_usage_mb': bloom_filter.get_memory_usage_mb()
    }

if __name__ == "__main__":
    # Example usage and testing
    print("=== Bloom Filter Demo ===")
    
    # Create and test a single filter
    bf = ProductionBloomFilter(expected_elements=50000, false_positive_rate=0.01)
    
    # Add some test data
    test_data = [
        "user123@example.com",
        "admin@company.com", 
        "test@test.com",
        "demo@demo.com"
    ]
    
    for item in test_data:
        bf.add(item)
        print(f"Added: {item}")
    
    # Test lookups
    print("\n=== Lookup Tests ===")
    test_queries = test_data + ["nonexistent@fake.com", "missing@nowhere.com"]
    
    for query in test_queries:
        result = bf.contains(query)
        print(f"Query '{query}': {'Might exist' if result else 'Definitely not present'}")
    
    # Print statistics
    print("\n=== Filter Statistics ===")
    stats = bf.get_statistics()
    for key, value in stats.items():
        print(f"{key}: {value}")
    
    # Run performance test
    print("\n=== Performance Test ===")
    perf_results = run_performance_test(bf, test_size=10000)
    for key, value in perf_results.items():
        print(f"{key}: {value}")
EOF
}

# Create Flask web application
create_web_app() {
    print_status "Creating Flask web application..."
    
cat > src/app.py << 'EOF'
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
EOF
}

# Create HTML template
create_html_template() {
    print_status "Creating HTML template..."
    
cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bloom Filter Production Demo</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #3498db, #2980b9);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .content {
            padding: 30px;
        }
        
        .section {
            margin-bottom: 30px;
            padding: 25px;
            background: #f8f9fa;
            border-radius: 10px;
            border-left: 5px solid #3498db;
        }
        
        .section h3 {
            color: #2c3e50;
            margin-bottom: 15px;
            font-size: 1.4em;
        }
        
        .input-group {
            display: flex;
            gap: 10px;
            margin-bottom: 15px;
        }
        
        input[type="text"], input[type="number"] {
            flex: 1;
            padding: 12px;
            border: 2px solid #ecf0f1;
            border-radius: 8px;
            font-size: 14px;
            transition: border-color 0.3s;
        }
        
        input[type="text"]:focus, input[type="number"]:focus {
            outline: none;
            border-color: #3498db;
        }
        
        .btn {
            padding: 12px 25px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 600;
            transition: all 0.3s;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #3498db, #2980b9);
            color: white;
        }
        
        .btn-primary:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 15px rgba(52, 152, 219, 0.3);
        }
        
        .btn-success {
            background: linear-gradient(135deg, #27ae60, #229954);
            color: white;
        }
        
        .btn-success:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 15px rgba(39, 174, 96, 0.3);
        }
        
        .btn-warning {
            background: linear-gradient(135deg, #f39c12, #e67e22);
            color: white;
        }
        
        .btn-warning:hover {
            transform: translateY(-2px);
            box-shadow: 0 8px 15px rgba(243, 156, 18, 0.3);
        }
        
        .result {
            margin-top: 15px;
            padding: 15px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
        }
        
        .result.success {
            background: #d4edda;
            border: 1px solid #c3e6cb;
            color: #155724;
        }
        
        .result.error {
            background: #f8d7da;
            border: 1px solid #f5c6cb;
            color: #721c24;
        }
        
        .result.info {
            background: #d1ecf1;
            border: 1px solid #bee5eb;
            color: #0c5460;
        }
        
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-top: 20px;
        }
        
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            border: 1px solid #ecf0f1;
            box-shadow: 0 4px 8px rgba(0,0,0,0.1);
        }
        
        .stat-card h4 {
            color: #2c3e50;
            margin-bottom: 15px;
            font-size: 1.2em;
            border-bottom: 2px solid #3498db;
            padding-bottom: 10px;
        }
        
        .stat-item {
            display: flex;
            justify-content: space-between;
            padding: 8px 0;
            border-bottom: 1px solid #ecf0f1;
        }
        
        .stat-item:last-child {
            border-bottom: none;
        }
        
        .stat-label {
            font-weight: 600;
            color: #7f8c8d;
        }
        
        .stat-value {
            color: #2c3e50;
            font-family: 'Courier New', monospace;
        }
        
        .highlight {
            background: linear-gradient(135deg, #fff3cd, #ffeaa7);
            padding: 20px;
            border-radius: 10px;
            border-left: 5px solid #f39c12;
            margin: 20px 0;
        }
        
        .highlight h4 {
            color: #856404;
            margin-bottom: 10px;
        }
        
        .loading {
            display: none;
            text-align: center;
            padding: 20px;
        }
        
        .spinner {
            border: 4px solid #f3f3f3;
            border-top: 4px solid #3498db;
            border-radius: 50%;
            width: 40px;
            height: 40px;
            animation: spin 1s linear infinite;
            margin: 0 auto 10px;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌸 Bloom Filter Production Demo</h1>
            <p>Interactive System Design Learning Platform</p>
        </div>
        
        <div class="content">
            <!-- Add Items Section -->
            <div class="section">
                <h3>📝 Add Items to Bloom Filter</h3>
                <p>Add items to both single and distributed Bloom filters. Items are automatically distributed across nodes using consistent hashing.</p>
                <div class="input-group">
                    <input type="text" id="addItem" placeholder="Enter item (e.g., user@example.com)" />
                    <button class="btn btn-primary" onclick="addItem()">Add Item</button>
                    <button class="btn btn-success" onclick="generateData()">Generate 100 Random Items</button>
                </div>
                <div id="addResult"></div>
            </div>
            
            <!-- Check Items Section -->
            <div class="section">
                <h3>🔍 Check Item Existence</h3>
                <p>Query the Bloom filter to check if an item might exist. Compare results between probabilistic and exact storage.</p>
                <div class="input-group">
                    <input type="text" id="checkItem" placeholder="Enter item to check" />
                    <button class="btn btn-primary" onclick="checkItem()">Check Item</button>
                </div>
                <div id="checkResult"></div>
            </div>
            
            <!-- Performance Test Section -->
            <div class="section">
                <h3>⚡ Performance Testing</h3>
                <p>Run performance tests to analyze insertion speed, lookup speed, and false positive rates.</p>
                <div class="input-group">
                    <input type="number" id="testSize" placeholder="Test size (max: 100,000)" value="10000" min="1000" max="100000" />
                    <button class="btn btn-warning" onclick="runPerformanceTest()">Run Performance Test</button>
                </div>
                <div id="performanceResult"></div>
                <div class="loading" id="performanceLoading">
                    <div class="spinner"></div>
                    <p>Running performance test...</p>
                </div>
            </div>
            
            <!-- Statistics Section -->
            <div class="section">
                <h3>📊 Real-time Statistics</h3>
                <button class="btn btn-primary" onclick="updateStatistics()">Refresh Statistics</button>
                <div class="stats-grid" id="statisticsContainer">
                    <!-- Statistics will be populated here -->
                </div>
            </div>
            
            <!-- Educational Insights -->
            <div class="highlight">
                <h4>🎓 Key Learning Points</h4>
                <ul>
                    <li><strong>Space Efficiency:</strong> Bloom filters use fixed memory regardless of elements added</li>
                    <li><strong>Probabilistic Nature:</strong> False positives possible, false negatives impossible</li>
                    <li><strong>Distributed Architecture:</strong> Multiple filters can work together for horizontal scaling</li>
                    <li><strong>Production Trade-offs:</strong> Memory vs accuracy vs query performance</li>
                </ul>
            </div>
        </div>
    </div>

    <script>
        // API helper function
        async function apiCall(endpoint, method = 'GET', data = null) {
            try {
                const options = {
                    method: method,
                    headers: {
                        'Content-Type': 'application/json',
                    }
                };
                
                if (data) {
                    options.body = JSON.stringify(data);
                }
                
                const response = await fetch(endpoint, options);
                const result = await response.json();
                
                if (!response.ok) {
                    throw new Error(result.error || 'API call failed');
                }
                
                return result;
            } catch (error) {
                console.error('API Error:', error);
                throw error;
            }
        }
        
        // Add item to filter
        async function addItem() {
            const item = document.getElementById('addItem').value.trim();
            const resultDiv = document.getElementById('addResult');
            
            if (!item) {
                resultDiv.innerHTML = '<div class="result error">Please enter an item</div>';
                return;
            }
            
            try {
                const result = await apiCall('/api/filter/add', 'POST', { item: item });
                resultDiv.innerHTML = `
                    <div class="result success">
                        <strong>✅ Added successfully!</strong><br>
                        Item: ${result.item}<br>
                        Assigned to: ${result.assigned_node}<br>
                        Timestamp: ${new Date(result.timestamp * 1000).toLocaleString()}
                    </div>
                `;
                document.getElementById('addItem').value = '';
            } catch (error) {
                resultDiv.innerHTML = `<div class="result error">❌ Error: ${error.message}</div>`;
            }
        }
        
        // Check item in filter
        async function checkItem() {
            const item = document.getElementById('checkItem').value.trim();
            const resultDiv = document.getElementById('checkResult');
            
            if (!item) {
                resultDiv.innerHTML = '<div class="result error">Please enter an item to check</div>';
                return;
            }
            
            try {
                const result = await apiCall('/api/filter/check', 'POST', { item: item });
                
                let resultClass = 'info';
                let icon = '🔍';
                let interpretation = '';
                
                if (result.is_false_positive) {
                    resultClass = 'error';
                    icon = '⚠️';
                    interpretation = 'FALSE POSITIVE detected! Bloom filter says "might exist" but item not in actual storage.';
                } else if (result.single_filter_result && result.redis_actual_exists) {
                    resultClass = 'success';
                    icon = '✅';
                    interpretation = 'TRUE POSITIVE: Item exists in both filter and actual storage.';
                } else if (!result.single_filter_result) {
                    resultClass = 'success';
                    icon = '❌';
                    interpretation = 'DEFINITE NEGATIVE: Item definitely not in the set.';
                }
                
                resultDiv.innerHTML = `
                    <div class="result ${resultClass}">
                        <strong>${icon} Check Result for "${result.item}"</strong><br><br>
                        <strong>Single Filter Result:</strong> ${result.single_filter_result ? 'Might exist' : 'Definitely not present'}<br>
                        <strong>Distributed Filter:</strong> Node ${result.distributed_filter_result.assigned_node}<br>
                        <strong>Actual Storage (Redis):</strong> ${result.redis_actual_exists ? 'EXISTS' : 'NOT EXISTS'}<br>
                        <strong>Recommendation:</strong> ${result.distributed_filter_result.recommendation}<br><br>
                        <em>${interpretation}</em>
                    </div>
                `;
                document.getElementById('checkItem').value = '';
            } catch (error) {
                resultDiv.innerHTML = `<div class="result error">❌ Error: ${error.message}</div>`;
            }
        }
        
        // Generate test data
        async function generateData() {
            const resultDiv = document.getElementById('addResult');
            
            try {
                resultDiv.innerHTML = '<div class="result info">🎲 Generating random test data...</div>';
                const result = await apiCall('/api/generate-data', 'POST', { count: 100 });
                
                resultDiv.innerHTML = `
                    <div class="result success">
                        <strong>✅ Generated ${result.generated_count} random items!</strong><br>
                        Sample items: ${result.items.join(', ')}...
                    </div>
                `;
            } catch (error) {
                resultDiv.innerHTML = `<div class="result error">❌ Error: ${error.message}</div>`;
            }
        }
        
        // Run performance test
        async function runPerformanceTest() {
            const testSize = parseInt(document.getElementById('testSize').value);
            const resultDiv = document.getElementById('performanceResult');
            const loadingDiv = document.getElementById('performanceLoading');
            
            if (testSize < 1000 || testSize > 100000) {
                resultDiv.innerHTML = '<div class="result error">Test size must be between 1,000 and 100,000</div>';
                return;
            }
            
            try {
                loadingDiv.style.display = 'block';
                resultDiv.innerHTML = '';
                
                const result = await apiCall('/api/performance-test', 'POST', { test_size: testSize });
                const perf = result.results;
                
                resultDiv.innerHTML = `
                    <div class="result success">
                        <strong>⚡ Performance Test Results (${perf.test_size} operations)</strong><br><br>
                        <strong>Insertion Performance:</strong><br>
                        • Total time: ${perf.insertion_time_seconds.toFixed(3)} seconds<br>
                        • Rate: ${Math.round(perf.insertions_per_second).toLocaleString()} insertions/second<br><br>
                        
                        <strong>Memory Efficiency:</strong><br>
                        • Memory usage: ${perf.memory_usage_mb.toFixed(2)} MB<br>
                        • Bytes per element: ${((perf.memory_usage_mb * 1024 * 1024) / perf.test_size).toFixed(1)} bytes<br><br>
                        
                        <strong>False Positive Analysis:</strong><br>
                        • Theoretical FP rate: ${(perf.theoretical_fp_rate * 100).toFixed(3)}%<br>
                        • Actual FP rate: ${(perf.actual_fp_rate * 100).toFixed(3)}%<br>
                        • False positives found: ${perf.false_positive_count}<br><br>
                        
                        <strong>Lookup Performance:</strong><br>
                        • True positive lookups: ${perf.lookup_time_tp_seconds.toFixed(3)}s<br>
                        • False positive lookups: ${perf.lookup_time_fp_seconds.toFixed(3)}s
                    </div>
                `;
                loadingDiv.style.display = 'none';
            } catch (error) {
                loadingDiv.style.display = 'none';
                resultDiv.innerHTML = `<div class="result error">❌ Error: ${error.message}</div>`;
            }
        }
        
        // Update statistics
        async function updateStatistics() {
            const container = document.getElementById('statisticsContainer');
            
            try {
                container.innerHTML = '<div class="result info">📊 Loading statistics...</div>';
                const result = await apiCall('/api/statistics');
                
                container.innerHTML = `
                    <div class="stat-card">
                        <h4>Single Bloom Filter</h4>
                        <div class="stat-item">
                            <span class="stat-label">Elements Added:</span>
                            <span class="stat-value">${result.single_filter.elements_added.toLocaleString()}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Bit Array Size:</span>
                            <span class="stat-value">${result.single_filter.bit_array_size.toLocaleString()}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Hash Functions:</span>
                            <span class="stat-value">${result.single_filter.num_hash_functions}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Memory Usage:</span>
                            <span class="stat-value">${result.single_filter.memory_usage_mb.toFixed(2)} MB</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Current FP Rate:</span>
                            <span class="stat-value">${(result.single_filter.current_fp_rate * 100).toFixed(3)}%</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Fill Ratio:</span>
                            <span class="stat-value">${(result.single_filter.fill_ratio * 100).toFixed(1)}%</span>
                        </div>
                    </div>
                    
                    <div class="stat-card">
                        <h4>Distributed Filter Cluster</h4>
                        <div class="stat-item">
                            <span class="stat-label">Total Elements:</span>
                            <span class="stat-value">${result.distributed_filter.total_elements.toLocaleString()}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Number of Nodes:</span>
                            <span class="stat-value">${result.distributed_filter.num_nodes}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Avg Elements/Node:</span>
                            <span class="stat-value">${Math.round(result.distributed_filter.average_elements_per_node).toLocaleString()}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Global Filter Memory:</span>
                            <span class="stat-value">${result.distributed_filter.global_filter_statistics.memory_usage_mb.toFixed(2)} MB</span>
                        </div>
                    </div>
                    
                    <div class="stat-card">
                        <h4>Storage Comparison</h4>
                        <div class="stat-item">
                            <span class="stat-label">Redis Items:</span>
                            <span class="stat-value">${result.redis.total_items || 'N/A'}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Redis Memory:</span>
                            <span class="stat-value">${result.redis.memory_usage ? (result.redis.memory_usage / 1024 / 1024).toFixed(2) + ' MB' : 'N/A'}</span>
                        </div>
                        <div class="stat-item">
                            <span class="stat-label">Space Savings:</span>
                            <span class="stat-value">${result.redis.memory_usage ? 
                                ((1 - (result.single_filter.memory_usage_mb * 1024 * 1024) / result.redis.memory_usage) * 100).toFixed(1) + '%' : 
                                'N/A'}</span>
                        </div>
                    </div>
                `;
            } catch (error) {
                container.innerHTML = `<div class="result error">❌ Error loading statistics: ${error.message}</div>`;
            }
        }
        
        // Auto-refresh statistics every 10 seconds
        setInterval(updateStatistics, 10000);
        
        // Load initial statistics
        updateStatistics();
        
        // Enter key support
        document.getElementById('addItem').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') addItem();
        });
        
        document.getElementById('checkItem').addEventListener('keypress', function(e) {
            if (e.key === 'Enter') checkItem();
        });
    </script>
</body>
</html>
EOF
}

# Create test files
create_tests() {
    print_status "Creating test files..."
    
cat > tests/test_bloom_filter.py << 'EOF'
"""
Comprehensive tests for Bloom filter implementation
Validates correctness and performance characteristics
"""

import pytest
import sys
import os

# Add src directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from bloom_filter import ProductionBloomFilter, DistributedBloomFilter, run_performance_test

class TestProductionBloomFilter:
    """Test cases for ProductionBloomFilter"""
    
    def test_initialization(self):
        """Test filter initialization with various parameters"""
        bf = ProductionBloomFilter(expected_elements=1000, false_positive_rate=0.01)
        
        assert bf.expected_elements == 1000
        assert bf.false_positive_rate == 0.01
        assert bf.bit_array_size > 0
        assert bf.num_hash_functions > 0
        assert bf.elements_added == 0
    
    def test_add_and_contains_basic(self):
        """Test basic add and contains operations"""
        bf = ProductionBloomFilter(expected_elements=100, false_positive_rate=0.01)
        
        # Test items that are added
        test_items = ["test1", "test2", "test3"]
        for item in test_items:
            bf.add(item)
        
        # All added items should return True (might exist)
        for item in test_items:
            assert bf.contains(item) == True
        
        # Test non-existent items (some might be false positives)
        non_existent = ["nonexistent1", "nonexistent2", "nonexistent3"]
        false_positives = 0
        for item in non_existent:
            if bf.contains(item):
                false_positives += 1
        
        # Should have some false positives but not all
        assert false_positives < len(non_existent)
    
    def test_no_false_negatives(self):
        """Verify that false negatives never occur"""
        bf = ProductionBloomFilter(expected_elements=1000, false_positive_rate=0.01)
        
        test_items = [f"user_{i}@example.com" for i in range(100)]
        
        # Add all items
        for item in test_items:
            bf.add(item)
        
        # Check that all added items return True
        for item in test_items:
            assert bf.contains(item) == True, f"False negative for item: {item}"
    
    def test_statistics(self):
        """Test statistics reporting"""
        bf = ProductionBloomFilter(expected_elements=1000, false_positive_rate=0.01)
        
        # Add some items
        for i in range(50):
            bf.add(f"item_{i}")
        
        stats = bf.get_statistics()
        
        assert stats['elements_added'] == 50
        assert stats['expected_elements'] == 1000
        assert stats['expected_fp_rate'] == 0.01
        assert stats['memory_usage_mb'] > 0
        assert 0 <= stats['fill_ratio'] <= 1
        assert stats['current_fp_rate'] >= 0

class TestDistributedBloomFilter:
    """Test cases for DistributedBloomFilter"""
    
    def test_initialization(self):
        """Test distributed filter initialization"""
        dbf = DistributedBloomFilter(num_nodes=3, expected_elements_per_node=1000)
        
        assert len(dbf.nodes) == 3
        assert dbf.num_nodes == 3
        assert dbf.global_filter is not None
    
    def test_consistent_hashing(self):
        """Test that same key always goes to same node"""
        dbf = DistributedBloomFilter(num_nodes=3, expected_elements_per_node=1000)
        
        test_key = "test_key_123"
        
        # Get node assignment multiple times
        node1 = dbf._get_node_for_key(test_key)
        node2 = dbf._get_node_for_key(test_key)
        node3 = dbf._get_node_for_key(test_key)
        
        assert node1 == node2 == node3
    
    def test_distributed_operations(self):
        """Test add and contains operations across nodes"""
        dbf = DistributedBloomFilter(num_nodes=3, expected_elements_per_node=100)
        
        test_items = [f"user_{i}@domain.com" for i in range(30)]
        
        # Add items and track which nodes they go to
        node_assignments = {}
        for item in test_items:
            node_id = dbf.add(item)
            node_assignments[item] = node_id
        
        # Verify all items can be found
        for item in test_items:
            result = dbf.contains(item)
            assert result['local_node_result'] == True
            assert result['global_filter_result'] == True
            assert result['assigned_node'] == node_assignments[item]

class TestPerformance:
    """Performance and scalability tests"""
    
    def test_performance_characteristics(self):
        """Test that performance meets expected characteristics"""
        bf = ProductionBloomFilter(expected_elements=10000, false_positive_rate=0.01)
        
        # Run performance test
        results = run_performance_test(bf, test_size=5000)
        
        # Verify performance characteristics
        assert results['insertions_per_second'] > 1000  # Should be fast
        assert results['memory_usage_mb'] < 10  # Should be memory efficient
        assert results['actual_fp_rate'] < 0.05  # FP rate should be reasonable
        
    def test_memory_efficiency(self):
        """Test memory usage is independent of element count"""
        # Create filters with same parameters but different element counts
        bf1 = ProductionBloomFilter(expected_elements=1000, false_positive_rate=0.01)
        bf2 = ProductionBloomFilter(expected_elements=1000, false_positive_rate=0.01)
        
        # Add different numbers of elements
        for i in range(100):
            bf1.add(f"item_{i}")
        
        for i in range(500):
            bf2.add(f"item_{i}")
        
        # Memory usage should be the same (bit array size is fixed)
        assert bf1.get_memory_usage_mb() == bf2.get_memory_usage_mb()

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
EOF
}

# Create startup script
create_startup_script() {
    print_status "Creating startup and test script..."
    
cat > run_demo.sh << 'EOF'
#!/bin/bash

# Bloom Filter Demo Startup Script with Enhanced Debugging

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Starting Bloom Filter Demo ===${NC}"

# Function to check if port is available
check_port() {
    if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${YELLOW}Port $1 is already in use. Attempting to free it...${NC}"
        # Try to kill processes using the port
        lsof -ti:$1 | xargs kill -9 >/dev/null 2>&1 || true
        sleep 2
    fi
}

# Function to debug directory structure
debug_structure() {
    echo -e "${BLUE}=== Debugging Directory Structure ===${NC}"
    echo "Current directory: $(pwd)"
    echo "Directory contents:"
    ls -la
    echo ""
    echo "Templates directory:"
    if [ -d "templates" ]; then
        ls -la templates/
    else
        echo -e "${RED}Templates directory not found!${NC}"
    fi
    echo ""
    echo "Source directory:"
    if [ -d "src" ]; then
        ls -la src/
    else
        echo -e "${RED}Source directory not found!${NC}"
    fi
}

# Function to fix common issues
fix_common_issues() {
    echo -e "${YELLOW}=== Checking and fixing common issues ===${NC}"
    
    # Ensure templates directory exists with correct file
    if [ ! -d "templates" ]; then
        echo -e "${RED}Templates directory missing, creating it...${NC}"
        mkdir -p templates
    fi
    
    if [ ! -f "templates/index.html" ]; then
        echo -e "${RED}index.html missing, recreating it...${NC}"
        # Create a minimal HTML file as fallback
        cat > templates/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html><head><title>Bloom Filter Demo</title></head>
<body><h1>Bloom Filter Demo</h1><p>Demo is starting up...</p></body></html>
HTML_EOF
    fi
    
    # Ensure src directory exists
    if [ ! -d "src" ]; then
        echo -e "${RED}Source directory missing!${NC}"
        echo "Please run the setup script again."
        exit 1
    fi
}

# Check if required ports are available
check_port 8080
check_port 6379

# Debug current structure
debug_structure

# Fix common issues
fix_common_issues

echo -e "${GREEN}[1/6] Building and starting services with Docker Compose...${NC}"
docker-compose down -v >/dev/null 2>&1 || true  # Clean start
docker-compose up --build -d

echo -e "${GREEN}[2/6] Waiting for services to be ready...${NC}"
sleep 15

# Enhanced health check with debugging
echo -e "${GREEN}[3/6] Running health checks with debugging...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Application is healthy!${NC}"
        break
    fi
    echo "Waiting for application to start... ($i/30)"
    
    # Show container logs if failing
    if [ $i -eq 10 ] || [ $i -eq 20 ]; then
        echo -e "${YELLOW}=== Container Status ===${NC}"
        docker-compose ps
        echo -e "${YELLOW}=== Application Logs ===${NC}"
        docker-compose logs app | tail -20
    fi
    
    sleep 2
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ Application failed to start properly${NC}"
        echo -e "${YELLOW}=== Final Debug Information ===${NC}"
        echo "Container status:"
        docker-compose ps
        echo ""
        echo "Application logs:"
        docker-compose logs app
        echo ""
        echo "Redis logs:"
        docker-compose logs redis
        echo -e "${YELLOW}You can still try accessing the demo at http://localhost:8080${NC}"
    fi
done

echo -e "${GREEN}[4/6] Testing API endpoints...${NC}"
# Test basic API endpoints
if curl -s http://localhost:8080/api/statistics > /dev/null 2>&1; then
    echo -e "${GREEN}✅ API endpoints are responding${NC}"
else
    echo -e "${YELLOW}⚠️  API endpoints may not be fully ready${NC}"
fi

echo -e "${GREEN}[5/6] Running automated tests...${NC}"
docker-compose exec -T app python -m pytest tests/ -v || echo -e "${YELLOW}Some tests failed, but demo will continue...${NC}"

echo -e "${GREEN}[6/6] Demo is ready!${NC}"
echo ""
echo -e "${BLUE}=== Demo URLs ===${NC}"
echo -e "🌐 Web Interface: ${GREEN}http://localhost:8080${NC}"
echo -e "🔍 Health Check: ${GREEN}http://localhost:8080/health${NC}"
echo -e "📊 API Statistics: ${GREEN}http://localhost:8080/api/statistics${NC}"
echo ""
echo -e "${BLUE}=== Demo Features ===${NC}"
echo "✅ Interactive Bloom filter operations"
echo "✅ False positive rate analysis"
echo "✅ Performance testing"
echo "✅ Distributed architecture simulation"
echo "✅ Real-time statistics"
echo ""
echo -e "${BLUE}=== Useful Commands ===${NC}"
echo "📊 View logs: docker-compose logs -f"
echo "🔧 Stop demo: docker-compose down"
echo "🧹 Clean up: docker-compose down -v"
echo "🐛 Debug structure: docker-compose exec app ls -la /app/"
echo "🔍 Check templates: docker-compose exec app ls -la /app/templates/"
echo ""
echo -e "${GREEN}🎉 Open your browser to http://localhost:8080 to start exploring!${NC}"

# Final check
echo -e "${BLUE}=== Final Verification ===${NC}"
if curl -s http://localhost:8080 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Demo is accessible and ready for use!${NC}"
else
    echo -e "${RED}❌ Demo may have issues. Check the troubleshooting section below.${NC}"
    echo ""
    echo -e "${YELLOW}=== Troubleshooting Steps ===${NC}"
    echo "1. Check container status: docker-compose ps"
    echo "2. View application logs: docker-compose logs app"
    echo "3. Restart services: docker-compose restart"
    echo "4. Rebuild from scratch: docker-compose down -v && docker-compose up --build"
    echo "5. Check file structure: docker-compose exec app find /app -name '*.html'"
fi
EOF

chmod +x run_demo.sh
}

# Create comprehensive documentation
create_documentation() {
    print_status "Creating comprehensive documentation..."
    
cat > README.md << 'EOF'
# Bloom Filter Production Demo

A comprehensive hands-on demonstration of Bloom filters in distributed systems, designed for the System Design Interview Roadmap series.

## 🎯 Learning Objectives

After completing this demo, you will understand:

- **Core Concepts**: How Bloom filters achieve probabilistic membership testing
- **Mathematical Foundations**: Optimal parameter calculation for production systems
- **Distributed Architecture**: How Bloom filters scale in multi-node environments
- **Performance Trade-offs**: Memory efficiency vs accuracy vs query speed
- **Production Considerations**: False positive handling, monitoring, and optimization

## 🚀 Quick Start

### Prerequisites
- Docker and Docker Compose
- Python 3.12+ (for local development)
- Bash shell

### One-Click Demo
```bash
git clone <this-repo>
cd bloom-filter-demo
./run_demo.sh
```

The script will:
1. Build and start all services (Flask app + Redis)
2. Run health checks
3. Execute automated tests
4. Open the demo at http://localhost:8080

## 🏗️ Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Web Interface │────│  Flask App       │────│   Redis Cache   │
│   (Interactive) │    │  (Bloom Filters) │    │   (Ground Truth)│
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                       ┌────────┴────────┐
                       │                 │
               ┌───────▼────────┐ ┌──────▼─────────┐
               │ Single Filter  │ │ Distributed    │
               │ (Learning)     │ │ Filter Cluster │
               └────────────────┘ └────────────────┘
```

## 📋 Demo Components

### 1. Interactive Web Interface
- **Add Items**: Insert data into Bloom filters with real-time feedback
- **Check Membership**: Query items and observe false positive behavior  
- **Generate Data**: Create random datasets for testing
- **Performance Testing**: Benchmark insertion/lookup speeds
- **Real-time Statistics**: Monitor filter performance and accuracy

### 2. Production Bloom Filter Implementation
```python
class ProductionBloomFilter:
    """
    Features:
    - Optimal parameter calculation (m, k values)
    - Multiple hash function strategies  
    - Performance monitoring
    - Memory optimization with NumPy
    - False positive rate tracking
    """
```

### 3. Distributed Architecture Simulation
```python
class DistributedBloomFilter:
    """
    Demonstrates:
    - Consistent hashing for key distribution
    - Multi-node filter coordination
    - Global vs local filter strategies
    - Cross-node query optimization
    """
```

## 🔬 Experiments You Can Run

### Experiment 1: False Positive Rate Analysis
1. Add 1,000 known items to the filter
2. Query 1,000 random items that were NOT added
3. Observe how many false positives occur
4. Compare with theoretical false positive rate

**Expected Learning**: Understanding the probabilistic nature and how to tune parameters.

### Experiment 2: Memory Efficiency Comparison
1. Run performance test with 50,000 items
2. Compare Bloom filter memory (few MB) vs Redis memory (much larger)
3. Calculate space savings percentage

**Expected Learning**: Bloom filters provide massive memory savings for membership testing.

### Experiment 3: Distributed Performance
1. Add items across the distributed filter cluster
2. Check how consistent hashing distributes load
3. Compare local vs global filter query times

**Expected Learning**: How Bloom filters scale in distributed architectures.

### Experiment 4: Parameter Optimization
1. Modify `false_positive_rate` in the code (0.1%, 1%, 5%)
2. Observe how bit array size and hash function count change
3. Run performance tests to see the trade-offs

**Expected Learning**: How to optimize Bloom filters for different use cases.

## 📊 Key Metrics Monitored

### Performance Metrics
- **Insertions/Second**: Throughput for adding elements
- **Lookups/Second**: Query performance
- **Memory Usage**: Total memory footprint
- **Bytes per Element**: Memory efficiency ratio

### Accuracy Metrics  
- **Theoretical FP Rate**: Mathematical expectation
- **Actual FP Rate**: Measured in real tests
- **Fill Ratio**: Percentage of bits set in array
- **Elements Added**: Total items inserted

### Distributed Metrics
- **Node Distribution**: How evenly items spread across nodes
- **Cross-Node Queries**: Performance of distributed lookups
- **Consistency**: Verification that same key always maps to same node

## 🔧 Advanced Configuration

### Tuning False Positive Rate
```python
# Low memory, higher FP rate (good for caching)
bf = ProductionBloomFilter(expected_elements=100000, false_positive_rate=0.05)

# High memory, lower FP rate (good for security)  
bf = ProductionBloomFilter(expected_elements=100000, false_positive_rate=0.001)
```

### Scaling the Distributed Cluster
```python
# Modify in app.py
distributed_filter = DistributedBloomFilter(
    num_nodes=5,  # Scale to 5 nodes
    expected_elements_per_node=200000  # Handle more load per node
)
```

## 🏭 Production Patterns Demonstrated

### 1. Caching Layer Optimization
```
Client Request → Check Local Bloom Filter → If "might exist" → Check Redis
                                         → If "definitely not" → Return empty
```

### 2. Database Query Reduction
- 90%+ reduction in unnecessary database queries
- Sub-millisecond negative lookups
- Graceful degradation under high load

### 3. Rate Limiting with Bloom Filters
- Detect suspicious patterns probabilistically
- Memory usage independent of user count
- Natural protection against DDoS attacks

## 🧪 Testing Framework

### Automated Tests
```bash
# Run all tests
docker-compose exec app python -m pytest tests/ -v

# Run specific test categories
pytest tests/test_bloom_filter.py::TestPerformance -v
```

### Test Categories
- **Correctness Tests**: Verify no false negatives occur
- **Performance Tests**: Benchmark speed and memory usage
- **Distributed Tests**: Validate consistent hashing and node coordination
- **Statistics Tests**: Ensure monitoring accuracy

## 📈 Expected Results

### Performance Benchmarks
- **Insertion Rate**: 50,000+ operations/second
- **Memory Efficiency**: <1MB per 100,000 elements
- **Query Latency**: <1ms for membership testing

### Accuracy Expectations
- **False Negatives**: 0% (mathematical guarantee)
- **False Positives**: ~1% (configurable)
- **Memory Savings**: 70-90% vs exact storage

## 🎓 Educational Value

This demo teaches production-grade system design through:

1. **Hands-on Experimentation**: Interactive interface for immediate feedback
2. **Real Performance Data**: Actual benchmarks, not theoretical examples
3. **Distributed Thinking**: Multi-node coordination patterns
4. **Production Patterns**: Battle-tested architectural approaches
5. **Trade-off Analysis**: Memory vs accuracy vs performance decisions

## 🔍 Troubleshooting

### Common Issues

**Port Already in Use**
```bash
# Kill processes on ports 8080 and 6379
sudo lsof -ti:8080 | xargs kill -9
sudo lsof -ti:6379 | xargs kill -9
```

**Docker Issues**
```bash
# Reset Docker environment
docker-compose down -v
docker system prune -f
docker-compose up --build
```

**Redis Connection Failed**
```bash
# Check Redis container
docker-compose logs redis
# Restart Redis
docker-compose restart redis
```

### Monitoring and Debugging

**View Application Logs**
```bash
docker-compose logs -f app
```

**Monitor Redis**
```bash
docker-compose exec redis redis-cli monitor
```

**Check Container Health**
```bash
docker-compose ps
curl http://localhost:8080/health
```

## 🌟 Next Steps

After mastering this demo:

1. **Implement Custom Hash Functions**: Try different hashing strategies
2. **Add Persistence**: Store Bloom filter state to disk
3. **Create Counting Bloom Filters**: Support deletion operations
4. **Build Network Bloom Filters**: Distribute across actual network nodes
5. **Integrate with Real Systems**: Add to your existing cache layer

## 📚 Further Reading

- [Bloom Filter Wikipedia](https://en.wikipedia.org/wiki/Bloom_filter)
- [Network Applications of Bloom Filters](https://www.eecs.harvard.edu/~michaelm/postscripts/im2005b.pdf)
- [Scalable Bloom Filters](https://gsd.di.uminho.pt/members/cbm/ps/dbloom.pdf)
- [Redis Bloom Module](https://redis.io/docs/stack/bloom/)

---

**Built for System Design Interview Roadmap | Issue #61: Bloom Filters**
EOF
}

# Main execution function
main() {
    print_status "Starting Bloom Filter Demo Setup..."
    
    check_prerequisites
    create_project_structure
    create_dockerfile
    create_docker_compose
    create_requirements
    create_bloom_filter
    create_web_app
    create_html_template
    create_tests
    create_startup_script
    create_documentation
    
    print_status "Creating logs directory..."
    mkdir -p logs
    
    echo ""
    print_status "✅ Bloom Filter Demo Setup Complete!"
    echo ""
    echo -e "${BLUE}=== Quick Start Instructions ===${NC}"
    echo -e "1. ${GREEN}Start the demo:${NC} ./run_demo.sh"
    echo -e "2. ${GREEN}Open browser:${NC} http://localhost:8080"
    echo -e "3. ${GREEN}Stop demo:${NC} docker-compose down"
    echo ""
    echo -e "${BLUE}=== What You'll Learn ===${NC}"
    echo "• Probabilistic data structures in action"
    echo "• False positive vs false negative behavior"
    echo "• Memory efficiency of Bloom filters"
    echo "• Distributed system design patterns"
    echo "• Production optimization techniques"
    echo ""
    echo -e "${YELLOW}💡 Tip: Read the README.md for detailed experiments and learning objectives${NC}"
}

# Execute main function
main

# Final instructions
echo ""
print_status "🎯 Demo is ready! Run './run_demo.sh' to start the interactive learning experience."
print_status "📖 Don't forget to read README.md for comprehensive learning exercises."
echo ""
EOF