from flask import Flask, render_template, request, jsonify
import redis
import json
import random
import string
import time
from consistent_hash import ConsistentHashRing
import plotly.graph_objs as go
import plotly.utils

app = Flask(__name__, template_folder='../templates', static_folder='../static')

# Initialize consistent hash ring
hash_ring = ConsistentHashRing(virtual_nodes=150, hash_func='xxhash')

# Initialize Redis for demonstration data storage
try:
    redis_client = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)
    redis_client.ping()
except:
    redis_client = None
    print("Redis not available - demo will work without persistence")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/ring/info')
def get_ring_info():
    """Get current ring state and metrics."""
    return jsonify(hash_ring.get_ring_info())

@app.route('/api/ring/add_node', methods=['POST'])
def add_node():
    """Add a new node to the ring."""
    data = request.get_json()
    node_id = data.get('node_id')
    weight = float(data.get('weight', 1.0))
    
    if not node_id:
        return jsonify({'error': 'node_id required'}), 400
    
    result = hash_ring.add_node(node_id, weight)
    return jsonify(result)

@app.route('/api/ring/remove_node', methods=['POST'])
def remove_node():
    """Remove a node from the ring."""
    data = request.get_json()
    node_id = data.get('node_id')
    
    if not node_id:
        return jsonify({'error': 'node_id required'}), 400
    
    result = hash_ring.remove_node(node_id)
    return jsonify(result)

@app.route('/api/ring/lookup', methods=['POST'])
def lookup_key():
    """Find which node should handle a given key."""
    data = request.get_json()
    key = data.get('key')
    
    if not key:
        return jsonify({'error': 'key required'}), 400
    
    node = hash_ring.get_node(key)
    replicas = hash_ring.get_nodes_for_replication(key, 3)
    
    return jsonify({
        'key': key,
        'primary_node': node,
        'replica_nodes': replicas
    })

@app.route('/api/demo/simulate_load')
def simulate_load():
    """Simulate random load to demonstrate distribution."""
    key_count = int(request.args.get('keys', 1000))
    
    # Generate random keys and track distribution
    results = {}
    for _ in range(key_count):
        key = ''.join(random.choices(string.ascii_letters + string.digits, k=10))
        node = hash_ring.get_node(key)
        if node:
            results[node] = results.get(node, 0) + 1
    
    return jsonify({
        'total_keys': key_count,
        'distribution': results,
        'ring_info': hash_ring.get_ring_info()
    })

@app.route('/api/demo/benchmark')
def benchmark_operations():
    """Benchmark lookup performance."""
    operations = int(request.args.get('operations', 10000))
    
    # Prepare test keys
    test_keys = [''.join(random.choices(string.ascii_letters, k=8)) for _ in range(1000)]
    
    # Benchmark lookups
    start_time = time.time()
    for _ in range(operations):
        key = random.choice(test_keys)
        hash_ring.get_node(key)
    lookup_time = time.time() - start_time
    
    # Benchmark node addition
    start_time = time.time()
    hash_ring.add_node(f"benchmark_node_{random.randint(1000, 9999)}")
    add_time = time.time() - start_time
    
    return jsonify({
        'lookup_operations': operations,
        'lookup_time_seconds': lookup_time,
        'lookups_per_second': operations / lookup_time,
        'node_add_time_seconds': add_time
    })

@app.route('/api/visualization/load_distribution')
def visualize_load_distribution():
    """Generate load distribution visualization data."""
    distribution = hash_ring.get_load_distribution()
    
    if not distribution:
        return jsonify({'error': 'No data available'})
    
    nodes = list(distribution.keys())
    load_ratios = [distribution[node]['load_ratio'] for node in nodes]
    request_counts = [distribution[node]['requests'] for node in nodes]
    
    # Create Plotly chart data
    fig = go.Figure(data=[
        go.Bar(
            x=nodes,
            y=load_ratios,
            text=[f"{count} requests" for count in request_counts],
            textposition='auto',
            marker_color=['red' if ratio > 1.5 else 'orange' if ratio > 1.2 else 'green' 
                         for ratio in load_ratios]
        )
    ])
    
    fig.update_layout(
        title='Load Distribution Across Nodes',
        xaxis_title='Node ID',
        yaxis_title='Load Ratio (1.0 = perfect distribution)',
        height=400
    )
    
    return jsonify({
        'chart_data': json.loads(plotly.utils.PlotlyJSONEncoder().encode(fig)),
        'distribution': distribution
    })

@app.route('/api/demo/reset')
def reset_demo():
    """Reset the demo to initial state."""
    global hash_ring
    hash_ring = ConsistentHashRing(virtual_nodes=150, hash_func='xxhash')
    
    # Add some initial nodes
    hash_ring.add_node('server-1', 1.0)
    hash_ring.add_node('server-2', 1.0)
    hash_ring.add_node('server-3', 1.0)
    
    return jsonify({'status': 'reset', 'message': 'Demo reset to initial state'})

if __name__ == '__main__':
    import os
    
    # Create logs directory
    os.makedirs('logs', exist_ok=True)
    
    # Initialize with some nodes
    hash_ring.add_node('server-1', 1.0)
    hash_ring.add_node('server-2', 1.0)
    hash_ring.add_node('server-3', 1.0)
    
    print("🚀 Starting Consistent Hashing Demo Server...")
    print("📊 Access the demo at: http://localhost:5000")
    print("📋 API endpoints available at: http://localhost:5000/api/")
    
    app.run(host='0.0.0.0', port=5000, debug=True)
