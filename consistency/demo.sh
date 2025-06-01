#!/bin/bash

# Consistency vs Availability Demonstration
# This script creates a distributed key-value store to demonstrate CAP theorem trade-offs
# Author: System Design Interview Roadmap
# Usage: ./consistency_demo.sh [start|stop|test|monitor]

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly DATA_DIR="${SCRIPT_DIR}/demo_data"
readonly LOG_DIR="${SCRIPT_DIR}/logs"
readonly NODE_COUNT=3
readonly BASE_PORT=8080
readonly CONSISTENCY_MODES=("strong" "eventual" "session")

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $*${NC}"
}

error() {
    echo -e "${RED}[ERROR] $*${NC}" >&2
}

warn() {
    echo -e "${YELLOW}[WARN] $*${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $*${NC}"
}

# Create directory structure
setup_environment() {
    log "Setting up demonstration environment..."
    
    mkdir -p "$DATA_DIR" "$LOG_DIR"
    
    # Create node directories
    for i in $(seq 0 $((NODE_COUNT - 1))); do
        mkdir -p "$DATA_DIR/node_$i"
        mkdir -p "$LOG_DIR/node_$i"
    done
    
    # Create web dashboard directory
    mkdir -p "$SCRIPT_DIR/dashboard"
    
    log "Environment setup complete"
}

# Generate node configuration
create_node_config() {
    local node_id=$1
    local port=$((BASE_PORT + node_id))

    echo '{' > "$DATA_DIR/node_$node_id/config.json"
    echo "    \"node_id\": $node_id," >> "$DATA_DIR/node_$node_id/config.json"
    echo "    \"port\": $port," >> "$DATA_DIR/node_$node_id/config.json"
    echo "    \"data_file\": \"$DATA_DIR/node_$node_id/data.json\"," >> "$DATA_DIR/node_$node_id/config.json"
    echo "    \"log_file\": \"$LOG_DIR/node_$node_id/node.log\"," >> "$DATA_DIR/node_$node_id/config.json"
    echo "    \"peers\": [" >> "$DATA_DIR/node_$node_id/config.json"

    local first=1
    for i in $(seq 0 $((NODE_COUNT - 1))); do
        if [ $i -ne $node_id ]; then
            if [ $first -eq 0 ]; then
                echo "," >> "$DATA_DIR/node_$node_id/config.json"
            fi
            echo -n "        {\"id\": $i, \"port\": $((BASE_PORT + i))}" >> "$DATA_DIR/node_$node_id/config.json"
            first=0
        fi
    done
    echo "
    ]," >> "$DATA_DIR/node_$node_id/config.json"
    echo "    \"consistency_mode\": \"strong\"," >> "$DATA_DIR/node_$node_id/config.json"
    echo "    \"partition_mode\": false," >> "$DATA_DIR/node_$node_id/config.json"
    echo "    \"replication_factor\": 2" >> "$DATA_DIR/node_$node_id/config.json"
    echo "}" >> "$DATA_DIR/node_$node_id/config.json"

    # Validate JSON
    if ! jq . "$DATA_DIR/node_$node_id/config.json" > /dev/null 2>&1; then
        error "Invalid JSON generated for node $node_id"
        exit 1
    fi
}

# Create a simple Python-based distributed node
create_node_server() {
    cat > "$SCRIPT_DIR/node_server.py" << 'EOF'
#!/usr/bin/env python3
import json
import time
import threading
import http.server
import socketserver
import urllib.request
import urllib.parse
from datetime import datetime
import sys
import os

class DistributedNode:
    def __init__(self, config_file):
        with open(config_file, 'r') as f:
            self.config = json.load(f)
        
        self.node_id = self.config['node_id']
        self.port = self.config['port']
        self.data = {}
        self.vector_clock = {}
        self.partition_mode = False
        self.load_data()
        
        # Initialize vector clock
        for peer in self.config['peers']:
            self.vector_clock[peer['id']] = 0
        self.vector_clock[self.node_id] = 0
    
    def load_data(self):
        """Load existing data from disk"""
        try:
            with open(self.config['data_file'], 'r') as f:
                content = f.read().strip()
                if content:  # Check if file has content
                    self.data = json.loads(content)
                else:
                    self.data = {}  # Empty file, initialize with empty dict
        except (FileNotFoundError, json.JSONDecodeError):
            self.data = {}  # Handle both missing file and invalid JSON
    
    def save_data(self):
        """Persist data to disk"""
        with open(self.config['data_file'], 'w') as f:
            json.dump(self.data, f, indent=2)
    
    def log(self, message):
        """Log message with timestamp"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log_entry = f"[{timestamp}] Node {self.node_id}: {message}\n"
        
        with open(self.config['log_file'], 'a') as f:
            f.write(log_entry)
        
        print(log_entry.strip())
    
    def increment_clock(self):
        """Increment local vector clock"""
        self.vector_clock[self.node_id] += 1
    
    def merge_clocks(self, remote_clock):
        """Merge vector clocks for causality"""
        for node_id, timestamp in remote_clock.items():
            if node_id in self.vector_clock:
                self.vector_clock[node_id] = max(self.vector_clock[node_id], timestamp)
    
    def get_available_peers(self):
        """Get list of reachable peers"""
        if self.partition_mode:
            # Simulate partition by making some peers unreachable
            return [peer for peer in self.config['peers'] if peer['id'] % 2 == self.node_id % 2]
        return self.config['peers']
    
    def replicate_to_peers(self, key, value, operation):
        """Replicate operation to peer nodes"""
        available_peers = self.get_available_peers()
        successful_replications = 0
        
        for peer in available_peers:
            try:
                data = {
                    'key': key,
                    'value': value,
                    'operation': operation,
                    'vector_clock': self.vector_clock,
                    'source_node': self.node_id
                }
                
                req = urllib.request.Request(
                    f"http://localhost:{peer['port']}/replicate",
                    data=json.dumps(data).encode('utf-8'),
                    headers={'Content-Type': 'application/json'}
                )
                
                with urllib.request.urlopen(req, timeout=2) as response:
                    if response.getcode() == 200:
                        successful_replications += 1
                        self.log(f"Replicated {operation} {key} to node {peer['id']}")
            
            except Exception as e:
                self.log(f"Failed to replicate to node {peer['id']}: {str(e)}")
        
        return successful_replications
    
    def strong_consistency_write(self, key, value):
        """Write with strong consistency (requires majority)"""
        self.increment_clock()
        
        # Calculate required replicas for majority
        total_nodes = len(self.config['peers']) + 1  # Including self
        required_replicas = (total_nodes // 2) + 1
        
        # Attempt replication
        successful_replications = self.replicate_to_peers(key, value, 'write')
        
        if successful_replications >= (required_replicas - 1):  # -1 because we count local write
            self.data[key] = {
                'value': value,
                'vector_clock': self.vector_clock.copy(),
                'timestamp': time.time()
            }
            self.save_data()
            self.log(f"Strong write successful: {key}={value}")
            return True, "Write successful"
        else:
            self.log(f"Strong write failed: {key}={value} (insufficient replicas)")
            return False, "Insufficient replicas for strong consistency"
    
    def eventual_consistency_write(self, key, value):
        """Write with eventual consistency (best effort)"""
        self.increment_clock()
        
        # Always accept local write
        self.data[key] = {
            'value': value,
            'vector_clock': self.vector_clock.copy(),
            'timestamp': time.time()
        }
        self.save_data()
        
        # Replicate in background (fire and forget)
        threading.Thread(
            target=self.replicate_to_peers,
            args=(key, value, 'write'),
            daemon=True
        ).start()
        
        self.log(f"Eventual write successful: {key}={value}")
        return True, "Write successful (eventual consistency)"
    
    def read_value(self, key):
        """Read value with current consistency mode"""
        if key in self.data:
            return True, self.data[key]['value']
        return False, "Key not found"

class NodeHTTPHandler(http.server.BaseHTTPRequestHandler):
    def __init__(self, node, *args, **kwargs):
        self.node = node
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        """Handle GET requests"""
        if self.path.startswith('/get/'):
            key = self.path[5:]  # Remove '/get/' prefix
            success, value = self.node.read_value(key)
            
            response = {
                'success': success,
                'value': value if success else None,
                'node_id': self.node.node_id,
                'vector_clock': self.node.vector_clock
            }
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        
        elif self.path == '/status':
            status = {
                'node_id': self.node.node_id,
                'data_count': len(self.node.data),
                'vector_clock': self.node.vector_clock,
                'partition_mode': self.node.partition_mode,
                'consistency_mode': self.node.config['consistency_mode']
            }
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(status).encode())
        
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        """Handle POST requests"""
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')
        data = json.loads(post_data)
        
        if self.path == '/put':
            key = data['key']
            value = data['value']
            consistency_mode = data.get('consistency_mode', 'strong')
            
            if consistency_mode == 'strong':
                success, message = self.node.strong_consistency_write(key, value)
            else:
                success, message = self.node.eventual_consistency_write(key, value)
            
            response = {
                'success': success,
                'message': message,
                'node_id': self.node.node_id
            }
            
            self.send_response(200 if success else 500)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        
        elif self.path == '/replicate':
            # Handle replication from other nodes
            key = data['key']
            value = data['value']
            remote_clock = data['vector_clock']
            
            self.node.merge_clocks(remote_clock)
            self.node.data[key] = {
                'value': value,
                'vector_clock': remote_clock,
                'timestamp': time.time()
            }
            self.node.save_data()
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'success': True}).encode())
        
        elif self.path == '/partition':
            # Toggle partition mode
            self.node.partition_mode = data.get('enabled', False)
            self.node.log(f"Partition mode {'enabled' if self.node.partition_mode else 'disabled'}")
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'success': True}).encode())

def create_handler(node):
    def handler(*args, **kwargs):
        return NodeHTTPHandler(node, *args, **kwargs)
    return handler

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 node_server.py <config_file>")
        sys.exit(1)
    
    config_file = sys.argv[1]
    node = DistributedNode(config_file)
    
    handler = create_handler(node)
    with socketserver.TCPServer(("", node.port), handler) as httpd:
        node.log(f"Node {node.node_id} started on port {node.port}")
        httpd.serve_forever()
EOF

    chmod +x "$SCRIPT_DIR/node_server.py"
}

# Create web dashboard for monitoring
create_web_dashboard() {
    cat > "$SCRIPT_DIR/dashboard/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Consistency vs Availability Demo</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
        }
        .container { 
            max-width: 1200px; 
            margin: 0 auto; 
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        h1 { 
            color: #2c3e50; 
            text-align: center; 
            margin-bottom: 30px;
            font-size: 2.5em;
        }
        .controls { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); 
            gap: 20px; 
            margin-bottom: 30px;
        }
        .control-group {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }
        .control-group h3 {
            margin-top: 0;
            color: #2c3e50;
        }
        input, select, button {
            padding: 10px;
            margin: 5px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 14px;
        }
        button {
            background: #667eea;
            color: white;
            border: none;
            cursor: pointer;
            transition: background 0.3s;
        }
        button:hover {
            background: #5a6fd8;
        }
        .status { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); 
            gap: 15px; 
            margin-bottom: 30px;
        }
        .node {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 8px;
            border: 2px solid #e9ecef;
        }
        .node.partitioned {
            border-color: #dc3545;
            background: #f8d7da;
        }
        .node h4 {
            margin-top: 0;
            color: #495057;
        }
        .logs {
            background: #2c3e50;
            color: #ecf0f1;
            padding: 20px;
            border-radius: 8px;
            max-height: 400px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 12px;
        }
        .success { color: #28a745; }
        .error { color: #dc3545; }
        .warning { color: #ffc107; }
        .metric {
            background: white;
            padding: 10px;
            margin: 5px 0;
            border-radius: 5px;
            border-left: 3px solid #667eea;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔄 Consistency vs Availability Demo</h1>
        
        <div class="controls">
            <div class="control-group">
                <h3>📝 Data Operations</h3>
                <input type="text" id="key" placeholder="Key" />
                <input type="text" id="value" placeholder="Value" />
                <select id="consistency">
                    <option value="strong">Strong Consistency</option>
                    <option value="eventual">Eventual Consistency</option>
                </select>
                <button onclick="putData()">PUT</button>
                <button onclick="getData()">GET</button>
            </div>
            
            <div class="control-group">
                <h3>🌐 Network Control</h3>
                <button onclick="togglePartition()">Toggle Partition</button>
                <button onclick="refreshStatus()">Refresh Status</button>
                <button onclick="clearLogs()">Clear Logs</button>
            </div>
        </div>
        
        <div class="status" id="nodeStatus"></div>
        
        <div class="logs" id="logs">
            <div>🚀 Demo started. Try writing some data with different consistency modes!</div>
        </div>
    </div>

    <script>
        const nodes = [8080, 8081, 8082];
        let partitionEnabled = false;

        function log(message, type = 'info') {
            const logs = document.getElementById('logs');
            const timestamp = new Date().toLocaleTimeString();
            const className = type === 'error' ? 'error' : type === 'success' ? 'success' : '';
            logs.innerHTML += `<div class="${className}">[${timestamp}] ${message}</div>`;
            logs.scrollTop = logs.scrollHeight;
        }

        async function putData() {
            const key = document.getElementById('key').value;
            const value = document.getElementById('value').value;
            const consistency = document.getElementById('consistency').value;
            
            if (!key || !value) {
                log('Please provide both key and value', 'error');
                return;
            }

            log(`Attempting to write: ${key} = ${value} (${consistency} consistency)`);
            
            try {
                const response = await fetch(`http://localhost:8080/put`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ key, value, consistency_mode: consistency })
                });
                
                const result = await response.json();
                if (result.success) {
                    log(`✅ Write successful: ${key} = ${value}`, 'success');
                } else {
                    log(`❌ Write failed: ${result.message}`, 'error');
                }
            } catch (error) {
                log(`❌ Network error: ${error.message}`, 'error');
            }
            
            setTimeout(refreshStatus, 1000);
        }

        async function getData() {
            const key = document.getElementById('key').value;
            if (!key) {
                log('Please provide a key to read', 'error');
                return;
            }

            log(`Reading key: ${key} from all nodes`);
            
            for (const port of nodes) {
                try {
                    const response = await fetch(`http://localhost:${port}/get/${key}`);
                    const result = await response.json();
                    
                    if (result.success) {
                        log(`📖 Node ${result.node_id}: ${key} = ${result.value}`, 'success');
                    } else {
                        log(`📖 Node ${result.node_id}: ${key} not found`, 'warning');
                    }
                } catch (error) {
                    log(`📖 Node on port ${port}: Network error`, 'error');
                }
            }
        }

        async function togglePartition() {
            partitionEnabled = !partitionEnabled;
            log(`${partitionEnabled ? 'Enabling' : 'Disabling'} network partition simulation`);
            
            for (const port of nodes) {
                try {
                    await fetch(`http://localhost:${port}/partition`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({ enabled: partitionEnabled })
                    });
                } catch (error) {
                    log(`Failed to toggle partition on port ${port}`, 'error');
                }
            }
            
            setTimeout(refreshStatus, 500);
        }

        async function refreshStatus() {
            const statusDiv = document.getElementById('nodeStatus');
            statusDiv.innerHTML = '';
            
            for (const port of nodes) {
                try {
                    const response = await fetch(`http://localhost:${port}/status`);
                    const status = await response.json();
                    
                    const nodeDiv = document.createElement('div');
                    nodeDiv.className = `node ${status.partition_mode ? 'partitioned' : ''}`;
                    nodeDiv.innerHTML = `
                        <h4>Node ${status.node_id} (Port ${port})</h4>
                        <div class="metric">Data Items: ${status.data_count}</div>
                        <div class="metric">Consistency: ${status.consistency_mode}</div>
                        <div class="metric">Partitioned: ${status.partition_mode ? 'Yes' : 'No'}</div>
                        <div class="metric">Vector Clock: ${JSON.stringify(status.vector_clock)}</div>
                    `;
                    statusDiv.appendChild(nodeDiv);
                } catch (error) {
                    const nodeDiv = document.createElement('div');
                    nodeDiv.className = 'node partitioned';
                    nodeDiv.innerHTML = `
                        <h4>Node ${nodes.indexOf(port)} (Port ${port})</h4>
                        <div class="metric">Status: Unreachable</div>
                    `;
                    statusDiv.appendChild(nodeDiv);
                }
            }
        }

        function clearLogs() {
            document.getElementById('logs').innerHTML = '<div>📝 Logs cleared</div>';
        }

        // Auto-refresh status every 5 seconds
        setInterval(refreshStatus, 5000);
        
        // Initial status load
        refreshStatus();
    </script>
</body>
</html>
EOF
}

# Start all nodes
start_nodes() {
    log "Starting distributed nodes..."
    
    # Check if Python 3 is available
    if ! command -v python3 &> /dev/null; then
        error "Python 3 is required but not installed"
        exit 1
    fi
    
    # Check if required ports are free before starting nodes
    for i in $(seq 0 $((NODE_COUNT - 1))); do
        local port=$((BASE_PORT + i))
        if lsof -i :$port | grep LISTEN > /dev/null; then
            warn "Port $port is already in use. Attempting to kill the process..."
            lsof -i :$port | grep LISTEN | awk '{print $2}' | xargs kill -9
            sleep 1
        fi
    done
    
    # Start each node in background
    for i in $(seq 0 $((NODE_COUNT - 1))); do
        local config_file="$DATA_DIR/node_$i/config.json"
        local log_file="$LOG_DIR/node_$i/server.log"
        
        log "Starting node $i on port $((BASE_PORT + i))"
        
        python3 "$SCRIPT_DIR/node_server.py" "$config_file" > "$log_file" 2>&1 &
        local pid=$!
        echo $pid > "$DATA_DIR/node_$i/server.pid"
        
        # Wait a moment for the server to start
        sleep 3
        
        # Check if the server is running
        if ps -p $pid > /dev/null; then
            info "Node $i started successfully (PID: $pid)"
        else
            error "Failed to start node $i"
        fi
    done
    
    # Start simple HTTP server for dashboard
    cd "$SCRIPT_DIR/dashboard"
    python3 -m http.server 9000 > "$LOG_DIR/dashboard.log" 2>&1 &
    echo $! > "$DATA_DIR/dashboard.pid"
    cd "$SCRIPT_DIR"
    
    log "All nodes started successfully!"
    log "Dashboard available at: http://localhost:9000"
    log "Node APIs available at: http://localhost:8080-8082"
}

# Stop all nodes
stop_nodes() {
    log "Stopping all nodes..."
    
    # Stop dashboard
    if [ -f "$DATA_DIR/dashboard.pid" ]; then
        local dashboard_pid=$(cat "$DATA_DIR/dashboard.pid")
        if ps -p $dashboard_pid > /dev/null; then
            kill $dashboard_pid
            rm "$DATA_DIR/dashboard.pid"
            log "Dashboard stopped"
        fi
    fi
    
    # Stop all node servers
    for i in $(seq 0 $((NODE_COUNT - 1))); do
        local pid_file="$DATA_DIR/node_$i/server.pid"
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file")
            if ps -p $pid > /dev/null; then
                kill $pid
                log "Stopped node $i (PID: $pid)"
            fi
            rm "$pid_file"
        fi
    done
    
    log "All nodes stopped"
}

# Wait for nodes to be ready with proper health checking
wait_for_nodes() {
    log "Waiting for all nodes to be ready..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local ready_nodes=0
        
        for port in $(seq $BASE_PORT $((BASE_PORT + NODE_COUNT - 1))); do
            if curl -s --max-time 2 "http://localhost:${port}/status" > /dev/null 2>&1; then
                ready_nodes=$((ready_nodes + 1))
            fi
        done
        
        if [ $ready_nodes -eq $NODE_COUNT ]; then
            log "All $NODE_COUNT nodes are ready!"
            return 0
        fi
        
        info "Waiting for nodes... ($ready_nodes/$NODE_COUNT ready)"
        sleep 2
        attempt=$((attempt + 1))
    done
    
    error "Timeout waiting for nodes to be ready"
    return 1
}

# Safe curl wrapper that handles errors gracefully
safe_curl() {
    local url="$1"
    local method="${2:-GET}"
    local data="${3:-}"
    
    local curl_opts=(-s --max-time 10 --fail)
    
    if [ "$method" = "POST" ]; then
        curl_opts+=(-X POST -H "Content-Type: application/json")
        if [ -n "$data" ]; then
            curl_opts+=(-d "$data")
        fi
    fi
    
    local response
    if response=$(curl "${curl_opts[@]}" "$url" 2>/dev/null); then
        # Validate JSON before passing to jq
        if echo "$response" | jq empty 2>/dev/null; then
            echo "$response" | jq '.'
        else
            error "Received non-JSON response: $response"
            return 1
        fi
    else
        error "Failed to connect to $url (method: $method)"
        return 1
    fi
}

# Run test scenarios
run_tests() {
    log "Running consistency vs availability test scenarios..."
    
    # Wait for nodes to be ready with proper health checking
    if ! wait_for_nodes; then
        error "Cannot run tests - nodes are not ready"
        return 1
    fi
    
    info "=== Test 1: Strong Consistency (Normal Operation) ==="
    safe_curl "http://localhost:8080/put" "POST" '{"key":"test1","value":"strong_value","consistency_mode":"strong"}'
    
    info "=== Test 2: Eventual Consistency (Normal Operation) ==="
    safe_curl "http://localhost:8080/put" "POST" '{"key":"test2","value":"eventual_value","consistency_mode":"eventual"}'
    
    sleep 2
    
    info "=== Test 3: Simulating Network Partition ==="
    for port in 8080 8081 8082; do
        safe_curl "http://localhost:${port}/partition" "POST" '{"enabled":true}'
    done
    
    sleep 1
    
    info "=== Test 4: Strong Consistency During Partition ==="
    safe_curl "http://localhost:8080/put" "POST" '{"key":"test3","value":"partition_strong","consistency_mode":"strong"}'
    
    info "=== Test 5: Eventual Consistency During Partition ==="
    safe_curl "http://localhost:8080/put" "POST" '{"key":"test4","value":"partition_eventual","consistency_mode":"eventual"}'
    
    sleep 2
    
    info "=== Test 6: Reading Data From All Nodes ==="
    for port in 8080 8081 8082; do
        echo "Node on port $port:"
        safe_curl "http://localhost:${port}/get/test1"
        safe_curl "http://localhost:${port}/get/test2"
    done
    
    info "=== Test 7: Healing Partition ==="
    for port in 8080 8081 8082; do
        safe_curl "http://localhost:${port}/partition" "POST" '{"enabled":false}'
    done
    
    log "Test scenarios completed! Check the dashboard for visual results."
}

# Monitor system status
monitor_system() {
    log "Monitoring system status (Press Ctrl+C to stop)..."
    
    while true; do
        echo -e "\n${BLUE}=== System Status $(date) ===${NC}"
        
        for i in $(seq 0 $((NODE_COUNT - 1))); do
            local port=$((BASE_PORT + i))
            echo -e "\n${YELLOW}Node $i (Port $port):${NC}"
            
            if curl -s --max-time 2 http://localhost:${port}/status > /dev/null; then
                curl -s http://localhost:${port}/status | jq '.'
            else
                echo -e "${RED}  Status: Unreachable${NC}"
            fi
        done
        
        sleep 5
    done
}

# Display usage
show_usage() {
    cat << EOF
Consistency vs Availability Demonstration

This script demonstrates the trade-offs between consistency and availability
in distributed systems as described by the CAP theorem.

USAGE:
    $0 <command>

COMMANDS:
    start     - Set up environment and start all nodes
    stop      - Stop all running nodes
    test      - Run automated test scenarios
    monitor   - Monitor system status in real-time
    clean     - Clean up all generated files

DEMONSTRATION FLOW:
    1. Run '$0 start' to set up and start the demo
    2. Open http://localhost:9000 in your browser for the dashboard
    3. Run '$0 test' to see automated scenarios
    4. Use the web interface to try different operations
    5. Run '$0 stop' when finished

The demo creates a 3-node distributed key-value store where you can:
- Write data with strong or eventual consistency
- Simulate network partitions
- Observe how different consistency models behave under failure
- Monitor system status and data replication in real-time

EOF
}

# Clean up function
cleanup() {
    log "Cleaning up demonstration files..."
    
    stop_nodes
    
    rm -rf "$DATA_DIR" "$LOG_DIR" "$SCRIPT_DIR/dashboard"
    rm -f "$SCRIPT_DIR/node_server.py"
    
    log "Cleanup complete"
}

# Main execution
main() {
    case "${1:-}" in
        "start")
            setup_environment
            create_node_server
            create_web_dashboard
            
            # Create node configurations
            for i in $(seq 0 $((NODE_COUNT - 1))); do
                create_node_config $i
            done
            
            start_nodes
            ;;
        "stop")
            stop_nodes
            ;;
        "test")
            # Check if jq is available for JSON parsing
            if ! command -v jq &> /dev/null; then
                warn "jq not found. Install it for better JSON output formatting."
                warn "On Ubuntu/Debian: sudo apt-get install jq"
                warn "On macOS: brew install jq"
            fi
            run_tests
            ;;
        "monitor")
            monitor_system
            ;;
        "clean")
            cleanup
            ;;
        "help"|"--help"|"-h"|*)
            show_usage
            ;;
    esac
}

# Handle Ctrl+C gracefully
trap 'echo -e "\n${YELLOW}Interrupted. Run \"$0 stop\" to clean up running processes.${NC}"; exit 1' INT

# Run main function with all arguments
main "$@"