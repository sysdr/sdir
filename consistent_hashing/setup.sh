#!/bin/bash

# Consistent Hashing Demo Setup Script
# This script creates a complete consistent hashing demonstration with web interface

set -e

echo "🔧 Setting up Consistent Hashing Demo Environment..."

# Create project directory structure
mkdir -p consistent-hashing-demo/{src,static,templates,tests}
cd consistent-hashing-demo

# Create requirements.txt
cat > requirements.txt << 'EOF'
flask==3.0.0
redis==5.0.1
xxhash==3.4.1
numpy==1.24.3
matplotlib==3.7.2
plotly==5.17.0
requests==2.31.0
python-dotenv==1.0.0
gunicorn==21.2.0
pytest==7.4.3
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    redis-server \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 5000 6379

CMD ["sh", "-c", "redis-server --daemonize yes && python src/app.py"]
EOF

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  consistent-hash-demo:
    build: .
    ports:
      - "5000:5000"
      - "6379:6379"
    volumes:
      - ./logs:/app/logs
    environment:
      - FLASK_ENV=development
      - REDIS_URL=redis://localhost:6379

  redis:
    image: redis:7-alpine
    ports:
      - "6380:6379"
    volumes:
      - redis_data:/data

volumes:
  redis_data:
EOF

# Create main consistent hashing implementation
cat > src/consistent_hash.py << 'EOF'
import hashlib
import xxhash
from typing import Dict, List, Optional, Set, Tuple
import bisect
import json
import time
import logging
from collections import defaultdict

class ConsistentHashRing:
    """
    Production-grade consistent hashing implementation with virtual nodes,
    weighted distribution, and comprehensive metrics collection.
    """
    
    def __init__(self, virtual_nodes: int = 150, hash_func: str = 'xxhash'):
        self.virtual_nodes = virtual_nodes
        self.hash_func = hash_func
        self.ring: Dict[int, str] = {}  # hash_value -> server_id
        self.nodes: Set[str] = set()
        self.sorted_hashes: List[int] = []
        self.node_weights: Dict[str, float] = {}
        self.metrics = {
            'lookups': 0,
            'rebalances': 0,
            'key_movements': 0,
            'load_distribution': defaultdict(int)
        }
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('logs/consistent_hash.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
    
    def _hash(self, key: str) -> int:
        """Hash function with support for multiple algorithms."""
        if self.hash_func == 'xxhash':
            return xxhash.xxh64(key.encode()).intdigest()
        elif self.hash_func == 'sha1':
            return int(hashlib.sha1(key.encode()).hexdigest(), 16)
        else:  # md5 fallback
            return int(hashlib.md5(key.encode()).hexdigest(), 16)
    
    def add_node(self, node_id: str, weight: float = 1.0) -> Dict:
        """
        Add a node to the ring with optional weight for capacity-based distribution.
        Returns metrics about the rebalancing operation.
        """
        if node_id in self.nodes:
            self.logger.warning(f"Node {node_id} already exists in ring")
            return {'status': 'exists', 'keys_moved': 0}
        
        start_time = time.time()
        self.nodes.add(node_id)
        self.node_weights[node_id] = weight
        
        # Calculate virtual nodes based on weight
        vnode_count = int(self.virtual_nodes * weight)
        keys_before = set(self.ring.keys())
        
        # Add virtual nodes to ring
        for i in range(vnode_count):
            virtual_key = f"{node_id}:{i}"
            hash_value = self._hash(virtual_key)
            self.ring[hash_value] = node_id
        
        # Rebuild sorted hash list
        self.sorted_hashes = sorted(self.ring.keys())
        
        # Calculate key movement impact
        keys_after = set(self.ring.keys())
        keys_moved = len(keys_after - keys_before)
        
        self.metrics['rebalances'] += 1
        self.metrics['key_movements'] += keys_moved
        
        operation_time = time.time() - start_time
        
        self.logger.info(
            f"Added node {node_id} (weight: {weight}, vnodes: {vnode_count}, "
            f"keys_moved: {keys_moved}, time: {operation_time:.4f}s)"
        )
        
        return {
            'status': 'added',
            'node_id': node_id,
            'weight': weight,
            'virtual_nodes': vnode_count,
            'keys_moved': keys_moved,
            'operation_time': operation_time,
            'total_nodes': len(self.nodes)
        }
    
    def remove_node(self, node_id: str) -> Dict:
        """Remove a node from the ring and return rebalancing metrics."""
        if node_id not in self.nodes:
            return {'status': 'not_found', 'keys_moved': 0}
        
        start_time = time.time()
        
        # Count virtual nodes being removed
        vnodes_removed = sum(1 for server in self.ring.values() if server == node_id)
        
        # Remove all virtual nodes for this physical node
        self.ring = {h: server for h, server in self.ring.items() if server != node_id}
        self.sorted_hashes = sorted(self.ring.keys())
        
        self.nodes.remove(node_id)
        del self.node_weights[node_id]
        
        operation_time = time.time() - start_time
        
        self.logger.info(
            f"Removed node {node_id} ({vnodes_removed} virtual nodes, "
            f"time: {operation_time:.4f}s)"
        )
        
        return {
            'status': 'removed',
            'node_id': node_id,
            'virtual_nodes_removed': vnodes_removed,
            'operation_time': operation_time,
            'remaining_nodes': len(self.nodes)
        }
    
    def get_node(self, key: str) -> Optional[str]:
        """Get the node responsible for a given key."""
        if not self.ring:
            return None
        
        self.metrics['lookups'] += 1
        hash_value = self._hash(key)
        
        # Find the first node clockwise from the hash value
        idx = bisect.bisect_right(self.sorted_hashes, hash_value)
        if idx == len(self.sorted_hashes):
            idx = 0
        
        node = self.ring[self.sorted_hashes[idx]]
        self.metrics['load_distribution'][node] += 1
        
        return node
    
    def get_nodes_for_replication(self, key: str, replicas: int = 3) -> List[str]:
        """Get multiple nodes for replication, ensuring they're on different physical servers."""
        if not self.ring or replicas <= 0:
            return []
        
        hash_value = self._hash(key)
        nodes = []
        seen_nodes = set()
        
        # Start from the primary node position
        idx = bisect.bisect_right(self.sorted_hashes, hash_value)
        
        for _ in range(len(self.sorted_hashes)):
            if idx == len(self.sorted_hashes):
                idx = 0
            
            node = self.ring[self.sorted_hashes[idx]]
            if node not in seen_nodes:
                nodes.append(node)
                seen_nodes.add(node)
                if len(nodes) >= replicas:
                    break
            
            idx += 1
        
        return nodes
    
    def get_load_distribution(self) -> Dict:
        """Analyze current load distribution across nodes."""
        if not self.metrics['load_distribution']:
            return {}
        
        total_requests = sum(self.metrics['load_distribution'].values())
        expected_load = total_requests / len(self.nodes) if self.nodes else 0
        
        distribution = {}
        for node in self.nodes:
            actual_load = self.metrics['load_distribution'][node]
            load_ratio = actual_load / expected_load if expected_load > 0 else 0
            distribution[node] = {
                'requests': actual_load,
                'load_ratio': load_ratio,
                'percentage': (actual_load / total_requests * 100) if total_requests > 0 else 0
            }
        
        return distribution
    
    def get_ring_info(self) -> Dict:
        """Get comprehensive information about the current ring state."""
        return {
            'nodes': list(self.nodes),
            'total_virtual_nodes': len(self.ring),
            'hash_function': self.hash_func,
            'virtual_nodes_per_server': self.virtual_nodes,
            'node_weights': self.node_weights.copy(),
            'metrics': self.metrics.copy(),
            'load_distribution': self.get_load_distribution()
        }
    
    def reset_metrics(self):
        """Reset all collected metrics."""
        self.metrics = {
            'lookups': 0,
            'rebalances': 0,
            'key_movements': 0,
            'load_distribution': defaultdict(int)
        }
        self.logger.info("Metrics reset")
EOF

# Create Flask web application
cat > src/app.py << 'EOF'
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
EOF

# Create HTML template
cat > templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Consistent Hashing Demo</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/plotly.js/2.26.0/plotly.min.js"></script>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            padding: 30px;
        }
        h1 {
            color: #2c3e50;
            text-align: center;
            margin-bottom: 30px;
        }
        .section {
            margin-bottom: 30px;
            padding: 20px;
            border: 1px solid #ddd;
            border-radius: 8px;
            background: #fafafa;
        }
        .section h2 {
            color: #34495e;
            margin-top: 0;
        }
        .controls {
            display: flex;
            gap: 10px;
            margin-bottom: 15px;
            flex-wrap: wrap;
        }
        input, button, select {
            padding: 8px 12px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
        }
        button {
            background-color: #3498db;
            color: white;
            border: none;
            cursor: pointer;
            transition: background-color 0.3s;
        }
        button:hover {
            background-color: #2980b9;
        }
        button.danger {
            background-color: #e74c3c;
        }
        button.danger:hover {
            background-color: #c0392b;
        }
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin: 20px 0;
        }
        .metric-card {
            background: white;
            padding: 15px;
            border-radius: 6px;
            border-left: 4px solid #3498db;
        }
        .metric-value {
            font-size: 24px;
            font-weight: bold;
            color: #2c3e50;
        }
        .metric-label {
            color: #7f8c8d;
            font-size: 12px;
            text-transform: uppercase;
        }
        .log-output {
            background: #2c3e50;
            color: #ecf0f1;
            padding: 15px;
            border-radius: 6px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            max-height: 200px;
            overflow-y: auto;
            white-space: pre-wrap;
        }
        .node-list {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
            margin: 15px 0;
        }
        .node-item {
            background: #ecf0f1;
            padding: 8px 12px;
            border-radius: 20px;
            font-size: 12px;
            border: 2px solid #bdc3c7;
        }
        .node-item.active {
            background: #2ecc71;
            color: white;
            border-color: #27ae60;
        }
        #chart {
            margin: 20px 0;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-good { background-color: #2ecc71; }
        .status-warning { background-color: #f39c12; }
        .status-error { background-color: #e74c3c; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔄 Consistent Hashing Interactive Demo</h1>
        
        <div class="section">
            <h2>📊 Ring Status</h2>
            <div class="metrics" id="metrics">
                <!-- Metrics will be populated here -->
            </div>
            <div class="node-list" id="nodeList">
                <!-- Node list will be populated here -->
            </div>
        </div>

        <div class="section">
            <h2>⚙️ Node Management</h2>
            <div class="controls">
                <input type="text" id="nodeId" placeholder="Node ID (e.g., server-4)" value="server-4">
                <input type="number" id="nodeWeight" placeholder="Weight" value="1.0" step="0.1" min="0.1" max="10">
                <button onclick="addNode()">Add Node</button>
                <button onclick="removeNode()" class="danger">Remove Node</button>
                <button onclick="resetDemo()">Reset Demo</button>
            </div>
        </div>

        <div class="section">
            <h2>🔍 Key Lookup</h2>
            <div class="controls">
                <input type="text" id="lookupKey" placeholder="Enter key to lookup" value="user:12345">
                <button onclick="lookupKey()">Find Node</button>
                <button onclick="simulateLoad()">Simulate Load (1000 keys)</button>
                <button onclick="runBenchmark()">Run Benchmark</button>
            </div>
            <div id="lookupResult" class="log-output" style="margin-top: 15px; min-height: 60px;">
                Ready for key lookups...
            </div>
        </div>

        <div class="section">
            <h2>📈 Load Distribution Visualization</h2>
            <button onclick="updateVisualization()">Update Chart</button>
            <div id="chart"></div>
        </div>

        <div class="section">
            <h2>📋 Operation Log</h2>
            <div id="operationLog" class="log-output">
                Demo initialized. Ready for operations...
            </div>
        </div>
    </div>

    <script>
        let operationCounter = 0;

        function log(message) {
            const logElement = document.getElementById('operationLog');
            const timestamp = new Date().toLocaleTimeString();
            logElement.textContent += `[${timestamp}] ${message}\n`;
            logElement.scrollTop = logElement.scrollHeight;
        }

        async function updateMetrics() {
            try {
                const response = await fetch('/api/ring/info');
                const data = await response.json();
                
                const metricsHtml = `
                    <div class="metric-card">
                        <div class="metric-value">${data.nodes.length}</div>
                        <div class="metric-label">Active Nodes</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">${data.total_virtual_nodes}</div>
                        <div class="metric-label">Virtual Nodes</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">${data.metrics.lookups}</div>
                        <div class="metric-label">Total Lookups</div>
                    </div>
                    <div class="metric-card">
                        <div class="metric-value">${data.metrics.rebalances}</div>
                        <div class="metric-label">Rebalances</div>
                    </div>
                `;
                document.getElementById('metrics').innerHTML = metricsHtml;
                
                // Update node list
                const nodeListHtml = data.nodes.map(node => 
                    `<div class="node-item active">
                        <span class="status-indicator status-good"></span>
                        ${node} (weight: ${data.node_weights[node] || 1.0})
                    </div>`
                ).join('');
                document.getElementById('nodeList').innerHTML = nodeListHtml;
                
            } catch (error) {
                log(`Error updating metrics: ${error.message}`);
            }
        }

        async function addNode() {
            const nodeId = document.getElementById('nodeId').value;
            const weight = parseFloat(document.getElementById('nodeWeight').value) || 1.0;
            
            if (!nodeId) {
                alert('Please enter a node ID');
                return;
            }

            try {
                const response = await fetch('/api/ring/add_node', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ node_id: nodeId, weight: weight })
                });
                
                const result = await response.json();
                
                if (result.status === 'added') {
                    log(`✅ Added node ${nodeId} (weight: ${weight}, virtual nodes: ${result.virtual_nodes}, operation time: ${result.operation_time.toFixed(4)}s)`);
                    document.getElementById('nodeId').value = `server-${Date.now() % 10000}`;
                } else {
                    log(`⚠️ Node ${nodeId} already exists`);
                }
                
                await updateMetrics();
            } catch (error) {
                log(`❌ Error adding node: ${error.message}`);
            }
        }

        async function removeNode() {
            const nodeId = document.getElementById('nodeId').value;
            
            if (!nodeId) {
                alert('Please enter a node ID to remove');
                return;
            }

            try {
                const response = await fetch('/api/ring/remove_node', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ node_id: nodeId })
                });
                
                const result = await response.json();
                
                if (result.status === 'removed') {
                    log(`🗑️ Removed node ${nodeId} (${result.virtual_nodes_removed} virtual nodes, operation time: ${result.operation_time.toFixed(4)}s)`);
                } else {
                    log(`⚠️ Node ${nodeId} not found`);
                }
                
                await updateMetrics();
            } catch (error) {
                log(`❌ Error removing node: ${error.message}`);
            }
        }

        async function lookupKey() {
            const key = document.getElementById('lookupKey').value;
            
            if (!key) {
                alert('Please enter a key to lookup');
                return;
            }

            try {
                const response = await fetch('/api/ring/lookup', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ key: key })
                });
                
                const result = await response.json();
                
                const resultHtml = `
Key: ${result.key}
Primary Node: ${result.primary_node || 'No nodes available'}
Replica Nodes: ${result.replica_nodes.join(', ') || 'No replicas'}
                `;
                
                document.getElementById('lookupResult').textContent = resultHtml;
                log(`🔍 Lookup: ${key} → ${result.primary_node}`);
                
                await updateMetrics();
            } catch (error) {
                log(`❌ Error during lookup: ${error.message}`);
            }
        }

        async function simulateLoad() {
            log('📈 Starting load simulation (1000 keys)...');
            
            try {
                const response = await fetch('/api/demo/simulate_load?keys=1000');
                const result = await response.json();
                
                const distribution = Object.entries(result.distribution)
                    .map(([node, count]) => `${node}: ${count} keys`)
                    .join(', ');
                
                log(`📊 Load simulation complete: ${distribution}`);
                await updateMetrics();
                await updateVisualization();
            } catch (error) {
                log(`❌ Error during load simulation: ${error.message}`);
            }
        }

        async function runBenchmark() {
            log('⚡ Running performance benchmark...');
            
            try {
                const response = await fetch('/api/demo/benchmark?operations=10000');
                const result = await response.json();
                
                log(`⚡ Benchmark results: ${result.lookups_per_second.toFixed(0)} lookups/sec, node add time: ${(result.node_add_time_seconds * 1000).toFixed(2)}ms`);
                await updateMetrics();
            } catch (error) {
                log(`❌ Error during benchmark: ${error.message}`);
            }
        }

        async function updateVisualization() {
            try {
                const response = await fetch('/api/visualization/load_distribution');
                const result = await response.json();
                
                if (result.chart_data) {
                    Plotly.newPlot('chart', result.chart_data.data, result.chart_data.layout);
                } else {
                    document.getElementById('chart').innerHTML = '<p>No data available for visualization. Try simulating some load first.</p>';
                }
            } catch (error) {
                log(`❌ Error updating visualization: ${error.message}`);
            }
        }

        async function resetDemo() {
            try {
                const response = await fetch('/api/demo/reset');
                const result = await response.json();
                
                log('🔄 Demo reset to initial state');
                document.getElementById('lookupResult').textContent = 'Ready for key lookups...';
                document.getElementById('chart').innerHTML = '';
                
                await updateMetrics();
            } catch (error) {
                log(`❌ Error resetting demo: ${error.message}`);
            }
        }

        // Initialize the demo
        document.addEventListener('DOMContentLoaded', function() {
            updateMetrics();
            log('🚀 Consistent Hashing Demo loaded');
        });

        // Auto-update metrics every 5 seconds
        setInterval(updateMetrics, 5000);
    </script>
</body>
</html>
EOF

# Create test file
cat > tests/test_consistent_hash.py << 'EOF'
import pytest
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'src'))

from consistent_hash import ConsistentHashRing

class TestConsistentHashRing:
    
    def test_basic_operations(self):
        """Test basic ring operations."""
        ring = ConsistentHashRing(virtual_nodes=100)
        
        # Test adding nodes
        result = ring.add_node('server-1')
        assert result['status'] == 'added'
        assert 'server-1' in ring.nodes
        
        # Test key lookup
        node = ring.get_node('test-key')
        assert node == 'server-1'
        
        # Test removing nodes
        result = ring.remove_node('server-1')
        assert result['status'] == 'removed'
        assert 'server-1' not in ring.nodes
    
    def test_load_distribution(self):
        """Test that load distributes reasonably across nodes."""
        ring = ConsistentHashRing(virtual_nodes=150)
        
        # Add multiple nodes
        for i in range(5):
            ring.add_node(f'server-{i}')
        
        # Generate many keys and check distribution
        node_counts = {}
        for i in range(1000):
            node = ring.get_node(f'key-{i}')
            node_counts[node] = node_counts.get(node, 0) + 1
        
        # Check that no node gets more than 40% of the load (should be ~20% each)
        for count in node_counts.values():
            assert count < 400, "Load distribution is too uneven"
    
    def test_consistency_after_rebalancing(self):
        """Test that keys remain consistent after adding/removing nodes."""
        ring = ConsistentHashRing(virtual_nodes=100)
        
        # Add initial nodes
        ring.add_node('server-1')
        ring.add_node('server-2')
        
        # Record initial mappings
        initial_mappings = {}
        for i in range(100):
            key = f'key-{i}'
            initial_mappings[key] = ring.get_node(key)
        
        # Add a new node
        ring.add_node('server-3')
        
        # Check that most keys still map to the same nodes
        unchanged_keys = 0
        for key, original_node in initial_mappings.items():
            if ring.get_node(key) == original_node:
                unchanged_keys += 1
        
        # At least 60% of keys should remain unchanged
        assert unchanged_keys >= 60, f"Too many keys moved: {unchanged_keys}/100 remained"
    
    def test_weighted_nodes(self):
        """Test weighted node distribution."""
        ring = ConsistentHashRing(virtual_nodes=100)
        
        ring.add_node('small-server', weight=0.5)
        ring.add_node('large-server', weight=2.0)
        
        # The large server should have more virtual nodes
        small_vnodes = sum(1 for node in ring.ring.values() if node == 'small-server')
        large_vnodes = sum(1 for node in ring.ring.values() if node == 'large-server')
        
        assert large_vnodes > small_vnodes * 2, "Weight distribution not working correctly"
    
    def test_replication(self):
        """Test replication node selection."""
        ring = ConsistentHashRing(virtual_nodes=50)
        
        for i in range(5):
            ring.add_node(f'server-{i}')
        
        replicas = ring.get_nodes_for_replication('test-key', 3)
        
        # Should return 3 different nodes
        assert len(replicas) == 3
        assert len(set(replicas)) == 3, "Replicas should be on different nodes"

if __name__ == '__main__':
    pytest.main([__file__])
EOF

# Create logs directory
mkdir -p logs

# Create run script
cat > run_demo.sh << 'EOF'
#!/bin/bash

echo "🔧 Setting up Consistent Hashing Demo..."

# Check if Docker is available
if command -v docker &> /dev/null; then
    echo "🐳 Docker detected. Building and running with Docker..."
    
    # Build and run with Docker Compose
    docker-compose down 2>/dev/null || true
    docker-compose up --build -d
    
    echo "⏳ Waiting for services to start..."
    sleep 10
    
    echo "✅ Demo is running!"
    echo "🌐 Web Interface: http://localhost:5000"
    echo "📊 Redis: localhost:6379"
    echo ""
    echo "To stop: docker-compose down"
    
else
    echo "🐍 Docker not found. Running with local Python..."
    
    # Install dependencies
    pip install -r requirements.txt
    
    # Start Redis if available
    if command -v redis-server &> /dev/null; then
        echo "🔴 Starting Redis server..."
        redis-server --daemonize yes --port 6379
    fi
    
    # Run the application
    cd src && python app.py
fi
EOF

chmod +x run_demo.sh

# Create README
cat > README.md << 'EOF'
# Consistent Hashing Interactive Demo

This demo demonstrates consistent hashing concepts with a fully interactive web interface.

## Features

- ✅ Interactive consistent hashing implementation with virtual nodes
- ✅ Real-time load distribution visualization
- ✅ Node addition/removal with rebalancing metrics
- ✅ Performance benchmarking
- ✅ Web-based interface with charts
- ✅ Docker support for easy deployment
- ✅ Comprehensive test suite

## Quick Start

### Option 1: Docker (Recommended)
```bash
./run_demo.sh
```

### Option 2: Local Python
```bash
pip install -r requirements.txt
cd src && python app.py
```

## Access the Demo

- **Web Interface**: http://localhost:5000
- **API Endpoints**: http://localhost:5000/api/

## Key Features to Try

1. **Add/Remove Nodes**: See how the ring rebalances
2. **Load Simulation**: Generate 1000 random keys and see distribution
3. **Key Lookup**: Find which node handles specific keys
4. **Performance Benchmark**: Test lookup performance
5. **Load Visualization**: Interactive charts showing distribution

## API Endpoints

- `GET /api/ring/info` - Get current ring state
- `POST /api/ring/add_node` - Add a new node
- `POST /api/ring/remove_node` - Remove a node  
- `POST /api/ring/lookup` - Find node for a key
- `GET /api/demo/simulate_load` - Simulate random load
- `GET /api/demo/benchmark` - Run performance tests

## Testing

```bash
cd tests && python test_consistent_hash.py
```

## Architecture

The demo implements:
- Consistent hashing with configurable virtual nodes
- xxHash for fast, high-quality hashing
- Weighted node distribution
- Replication support
- Comprehensive metrics collection
- Real-time load balancing visualization
EOF

echo "✅ Consistent Hashing Demo Setup Complete!"
echo ""
echo "📁 Project structure created in: $(pwd)"
echo "🚀 To start the demo, run: ./run_demo.sh"
echo ""
echo "🎯 Demo Features:"
echo "   • Interactive web interface with real-time charts"
echo "   • Add/remove nodes and see rebalancing in action"
echo "   • Load simulation with distribution visualization"  
echo "   • Performance benchmarking tools"
echo "   • Comprehensive API for programmatic access"
echo ""
echo "🌐 Once running, access the demo at: http://localhost:5000"