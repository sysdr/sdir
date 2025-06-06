#!/bin/bash

# Raft Consensus Algorithm Demonstration Script
# This script creates a simple 5-node Raft cluster simulation
# Author: System Design Interview Roadmap
# Issue #57: Raft Consensus Algorithm Visualized

set -e

# Configuration
CLUSTER_SIZE=5
BASE_PORT=8000
LOG_DIR="./raft_demo_logs"
PID_FILE="./raft_demo.pid"
WEB_PORT=3000

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    # Check if Node.js is installed
    if ! command -v node &> /dev/null; then
        log_error "Node.js is required but not installed. Please install Node.js v14+ and try again."
        exit 1
    fi
    
    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        log_error "npm is required but not installed. Please install npm and try again."
        exit 1
    fi
    
    log_success "All dependencies are available"
}

# Setup project structure
setup_project() {
    log_info "Setting up Raft demonstration project..."
    
    # Create project directory structure
    mkdir -p raft-demo/{src,public,logs}
    cd raft-demo
    
    # Initialize npm project if package.json doesn't exist
    if [ ! -f package.json ]; then
        npm init -y > /dev/null 2>&1
        npm install express ws uuid chalk@4 --save > /dev/null 2>&1
        log_success "Project initialized with dependencies"
    fi
}

# Create Raft node implementation
create_raft_node() {
    log_info "Creating Raft node implementation..."
    
    cat > src/raft-node.js << 'EOF'
const EventEmitter = require('events');
const chalk = require('chalk').default || require('chalk');

class RaftNode extends EventEmitter {
    constructor(nodeId, cluster) {
        super();
        this.nodeId = nodeId;
        this.cluster = cluster;
        this.state = 'follower';
        this.currentTerm = 0;
        this.votedFor = null;
        this.logEntries = [];  // Renamed to avoid conflict with log method
        this.commitIndex = 0;
        this.lastApplied = 0;
        
        // Leader state
        this.nextIndex = {};
        this.matchIndex = {};
        
        // Timing
        this.electionTimeout = this.randomElectionTimeout();
        this.heartbeatInterval = 50; // 50ms heartbeat
        this.lastHeartbeat = Date.now();
        
        // Timers
        this.electionTimer = null;
        this.heartbeatTimer = null;
        
        this.startElectionTimer();
        this.logMessage(`Node ${this.nodeId} initialized as follower`);
    }
    
    randomElectionTimeout() {
        return 150 + Math.random() * 150; // 150-300ms
    }
    
    logMessage(message, level = 'info') {
        const timestamp = new Date().toISOString().substr(11, 12);
        let coloredMessage;
        switch (level) {
            case 'info':
                coloredMessage = chalk.blue(message);
                break;
            case 'warn':
                coloredMessage = chalk.yellow(message);
                break;
            case 'error':
                coloredMessage = chalk.red(message);
                break;
            case 'success':
                coloredMessage = chalk.green(message);
                break;
            default:
                coloredMessage = message;
        }
        console.log(`${timestamp} [Node-${this.nodeId}] ${coloredMessage}`);
        this.emit('log', { nodeId: this.nodeId, message, level, timestamp });
    }
    
    startElectionTimer() {
        this.clearElectionTimer();
        this.electionTimer = setTimeout(() => {
            this.startElection();
        }, this.electionTimeout);
    }
    
    clearElectionTimer() {
        if (this.electionTimer) {
            clearTimeout(this.electionTimer);
            this.electionTimer = null;
        }
    }
    
    startHeartbeatTimer() {
        this.clearHeartbeatTimer();
        this.heartbeatTimer = setInterval(() => {
            this.sendHeartbeats();
        }, this.heartbeatInterval);
    }
    
    clearHeartbeatTimer() {
        if (this.heartbeatTimer) {
            clearInterval(this.heartbeatTimer);
            this.heartbeatTimer = null;
        }
    }
    
    startElection() {
        this.state = 'candidate';
        this.currentTerm++;
        this.votedFor = this.nodeId;
        this.lastHeartbeat = Date.now();
        
        this.logMessage(`Starting election for term ${this.currentTerm}`, 'warn');
        this.emit('stateChange', { nodeId: this.nodeId, state: this.state, term: this.currentTerm });
        
        let votesReceived = 1; // Vote for self
        let votesNeeded = Math.floor(this.cluster.length / 2) + 1;
        
        // Request votes from other nodes
        this.cluster.forEach(node => {
            if (node.nodeId !== this.nodeId) {
                const response = node.requestVote(this.currentTerm, this.nodeId, this.logEntries.length - 1, 
                    this.logEntries.length > 0 ? this.logEntries[this.logEntries.length - 1].term : 0);
                
                if (response.voteGranted) {
                    votesReceived++;
                    this.logMessage(`Received vote from Node ${node.nodeId}`);
                }
            }
        });
        
        if (votesReceived >= votesNeeded) {
            this.becomeLeader();
        } else {
            this.becomeFollower();
            this.logMessage(`Election failed, got ${votesReceived}/${votesNeeded} votes`);
        }
    }
    
    becomeLeader() {
        this.state = 'leader';
        this.logMessage(`Became leader for term ${this.currentTerm}`, 'success');
        this.emit('stateChange', { nodeId: this.nodeId, state: this.state, term: this.currentTerm });
        
        // Initialize leader state
        this.cluster.forEach(node => {
            if (node.nodeId !== this.nodeId) {
                this.nextIndex[node.nodeId] = this.logEntries.length;
                this.matchIndex[node.nodeId] = 0;
            }
        });
        
        this.clearElectionTimer();
        this.startHeartbeatTimer();
        this.sendHeartbeats();
    }
    
    becomeFollower() {
        this.state = 'follower';
        this.clearHeartbeatTimer();
        this.startElectionTimer();
        this.emit('stateChange', { nodeId: this.nodeId, state: this.state, term: this.currentTerm });
    }
    
    requestVote(term, candidateId, lastLogIndex, lastLogTerm) {
        if (term < this.currentTerm) {
            return { term: this.currentTerm, voteGranted: false };
        }
        
        if (term > this.currentTerm) {
            this.currentTerm = term;
            this.votedFor = null;
            this.becomeFollower();
        }
        
        const logUpToDate = (lastLogTerm > (this.logEntries.length > 0 ? this.logEntries[this.logEntries.length - 1].term : 0)) ||
                           (lastLogTerm === (this.logEntries.length > 0 ? this.logEntries[this.logEntries.length - 1].term : 0) && 
                            lastLogIndex >= this.logEntries.length - 1);
        
        if ((this.votedFor === null || this.votedFor === candidateId) && logUpToDate) {
            this.votedFor = candidateId;
            this.lastHeartbeat = Date.now();
            this.startElectionTimer();
            this.logMessage(`Granted vote to Node ${candidateId} for term ${term}`);
            return { term: this.currentTerm, voteGranted: true };
        }
        
        return { term: this.currentTerm, voteGranted: false };
    }
    
    sendHeartbeats() {
        if (this.state !== 'leader') return;
        
        this.cluster.forEach(node => {
            if (node.nodeId !== this.nodeId) {
                node.receiveAppendEntries(this.currentTerm, this.nodeId, 
                    this.logEntries.length - 1, 
                    this.logEntries.length > 0 ? this.logEntries[this.logEntries.length - 1].term : 0,
                    [], this.commitIndex);
            }
        });
    }
    
    receiveAppendEntries(term, leaderId, prevLogIndex, prevLogTerm, entries, leaderCommit) {
        if (term < this.currentTerm) {
            return { term: this.currentTerm, success: false };
        }
        
        if (term > this.currentTerm) {
            this.currentTerm = term;
            this.votedFor = null;
        }
        
        this.lastHeartbeat = Date.now();
        this.becomeFollower();
        
        // Log consistency check would go here in full implementation
        // For demo purposes, we'll accept all entries
        
        return { term: this.currentTerm, success: true };
    }
    
    addEntry(data) {
        if (this.state !== 'leader') {
            return false;
        }
        
        const entry = {
            term: this.currentTerm,
            index: this.logEntries.length,
            data: data,
            timestamp: Date.now()
        };
        
        this.logEntries.push(entry);
        this.logMessage(`Added entry: ${data}`, 'success');
        this.emit('logEntry', { nodeId: this.nodeId, entry });
        
        return true;
    }
    
    getStatus() {
        return {
            nodeId: this.nodeId,
            state: this.state,
            term: this.currentTerm,
            logLength: this.logEntries.length,
            isAlive: true
        };
    }
    
    partition() {
        this.clearElectionTimer();
        this.clearHeartbeatTimer();
        this.logMessage(`Node partitioned from cluster`, 'error');
        this.emit('partition', { nodeId: this.nodeId });
    }
    
    reconnect() {
        this.becomeFollower();
        this.logMessage(`Node reconnected to cluster`, 'success');
        this.emit('reconnect', { nodeId: this.nodeId });
    }
}

module.exports = RaftNode;
EOF

    log_success "Raft node implementation created"
}

# Create cluster manager
create_cluster_manager() {
    log_info "Creating cluster manager..."
    
    cat > src/cluster.js << 'EOF'
const RaftNode = require('./raft-node');
const EventEmitter = require('events');

class RaftCluster extends EventEmitter {
    constructor(size) {
        super();
        this.nodes = [];
        this.partitions = new Set();
        
        // Create nodes
        for (let i = 0; i < size; i++) {
            const node = new RaftNode(i, []);
            this.nodes.push(node);
            
            // Forward events
            node.on('stateChange', (data) => this.emit('stateChange', data));
            node.on('log', (data) => this.emit('log', data));
            node.on('logEntry', (data) => this.emit('logEntry', data));
            node.on('partition', (data) => this.emit('partition', data));
            node.on('reconnect', (data) => this.emit('reconnect', data));
        }
        
        // Set cluster reference for each node
        this.nodes.forEach(node => {
            node.cluster = this.nodes.filter(n => !this.partitions.has(n.nodeId));
        });
    }
    
    getLeader() {
        return this.nodes.find(node => node.state === 'leader' && !this.partitions.has(node.nodeId));
    }
    
    addEntry(data) {
        const leader = this.getLeader();
        if (leader) {
            return leader.addEntry(data);
        }
        return false;
    }
    
    partitionNode(nodeId) {
        this.partitions.add(nodeId);
        const node = this.nodes[nodeId];
        if (node) {
            node.partition();
            // Update cluster view for all nodes
            this.nodes.forEach(n => {
                n.cluster = this.nodes.filter(node => !this.partitions.has(node.nodeId));
            });
        }
    }
    
    reconnectNode(nodeId) {
        this.partitions.delete(nodeId);
        const node = this.nodes[nodeId];
        if (node) {
            node.reconnect();
            // Update cluster view for all nodes
            this.nodes.forEach(n => {
                n.cluster = this.nodes.filter(node => !this.partitions.has(node.nodeId));
            });
        }
    }
    
    getStatus() {
        return this.nodes.map(node => ({
            ...node.getStatus(),
            isPartitioned: this.partitions.has(node.nodeId)
        }));
    }
    
    stop() {
        this.nodes.forEach(node => {
            node.clearElectionTimer();
            node.clearHeartbeatTimer();
        });
    }
}

module.exports = RaftCluster;
EOF

    log_success "Cluster manager created"
}

# Create web interface
create_web_interface() {
    log_info "Creating web interface..."
    
    cat > src/web-server.js << 'EOF'
const express = require('express');
const WebSocket = require('ws');
const path = require('path');
const RaftCluster = require('./cluster');

const app = express();
const port = process.env.PORT || 3000;

// Serve static files
app.use(express.static(path.join(__dirname, '../public')));
app.use(express.json());

// Create Raft cluster
const cluster = new RaftCluster(5);

// WebSocket server
const server = require('http').createServer(app);
const wss = new WebSocket.Server({ server });

// Broadcast to all connected clients
function broadcast(data) {
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify(data));
        }
    });
}

// Forward cluster events to web clients
cluster.on('stateChange', (data) => {
    broadcast({ type: 'stateChange', data });
});

cluster.on('log', (data) => {
    broadcast({ type: 'log', data });
});

cluster.on('logEntry', (data) => {
    broadcast({ type: 'logEntry', data });
});

cluster.on('partition', (data) => {
    broadcast({ type: 'partition', data });
});

cluster.on('reconnect', (data) => {
    broadcast({ type: 'reconnect', data });
});

// API endpoints
app.get('/api/status', (req, res) => {
    res.json(cluster.getStatus());
});

app.post('/api/entry', (req, res) => {
    const { data } = req.body;
    const success = cluster.addEntry(data);
    res.json({ success });
});

app.post('/api/partition/:nodeId', (req, res) => {
    const nodeId = parseInt(req.params.nodeId);
    cluster.partitionNode(nodeId);
    res.json({ success: true });
});

app.post('/api/reconnect/:nodeId', (req, res) => {
    const nodeId = parseInt(req.params.nodeId);
    cluster.reconnectNode(nodeId);
    res.json({ success: true });
});

// WebSocket connection handling
wss.on('connection', (ws) => {
    console.log('Client connected');
    
    // Send initial status
    ws.send(JSON.stringify({
        type: 'status',
        data: cluster.getStatus()
    }));
    
    ws.on('close', () => {
        console.log('Client disconnected');
    });
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\nShutting down Raft cluster...');
    cluster.stop();
    process.exit(0);
});

server.listen(port, () => {
    console.log(`Raft demo server running at http://localhost:${port}`);
});
EOF

    log_success "Web server created"
}

# Create HTML interface
create_html_interface() {
    log_info "Creating HTML interface..."
    
    cat > public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Raft Consensus Algorithm Demo</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f7fa; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .header { text-align: center; margin-bottom: 30px; }
        .title { color: #2c3e50; font-size: 2.5em; margin-bottom: 10px; }
        .subtitle { color: #7f8c8d; font-size: 1.2em; }
        
        .cluster-view { display: flex; justify-content: space-around; margin-bottom: 30px; flex-wrap: wrap; }
        .node { 
            background: white; border-radius: 15px; padding: 20px; margin: 10px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1); min-width: 180px; text-align: center;
            transition: all 0.3s ease;
        }
        .node.leader { background: linear-gradient(135deg, #e8f8e8, #b8e6b8); border: 2px solid #27ae60; }
        .node.candidate { background: linear-gradient(135deg, #fff3cd, #ffe69c); border: 2px solid #f39c12; }
        .node.follower { background: linear-gradient(135deg, #e8f4fd, #b3d9f7); border: 2px solid #3498db; }
        .node.partitioned { background: linear-gradient(135deg, #ffebee, #ffcdd2); border: 2px dashed #e74c3c; opacity: 0.7; }
        
        .node-id { font-size: 1.4em; font-weight: bold; margin-bottom: 10px; }
        .node-state { font-size: 1em; text-transform: uppercase; margin-bottom: 5px; }
        .node-term { font-size: 0.9em; color: #666; margin-bottom: 10px; }
        .node-controls { margin-top: 15px; }
        .btn { 
            padding: 8px 16px; margin: 2px; border: none; border-radius: 5px; 
            cursor: pointer; font-size: 0.85em; transition: all 0.2s;
        }
        .btn.partition { background: #e74c3c; color: white; }
        .btn.reconnect { background: #27ae60; color: white; }
        .btn:hover { transform: translateY(-1px); box-shadow: 0 2px 5px rgba(0,0,0,0.2); }
        
        .controls { background: white; border-radius: 10px; padding: 20px; margin-bottom: 20px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .control-group { margin-bottom: 15px; }
        .control-group label { display: block; margin-bottom: 5px; font-weight: bold; }
        .control-group input { padding: 10px; border: 1px solid #ddd; border-radius: 5px; width: 200px; }
        .btn.primary { background: #3498db; color: white; padding: 10px 20px; font-size: 1em; }
        
        .logs { background: #2c3e50; color: #ecf0f1; border-radius: 10px; padding: 20px; height: 300px; overflow-y: auto; font-family: 'Courier New', monospace; font-size: 0.9em; }
        .log-entry { margin-bottom: 5px; }
        .log-info { color: #3498db; }
        .log-warn { color: #f39c12; }
        .log-error { color: #e74c3c; }
        .log-success { color: #27ae60; }
        
        .status { margin-top: 20px; }
        .status-item { background: white; padding: 15px; margin-bottom: 10px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1 class="title">Raft Consensus Algorithm Demo</h1>
            <p class="subtitle">Interactive visualization of leader election and log replication</p>
        </div>
        
        <div class="cluster-view" id="cluster-view">
            <!-- Nodes will be dynamically generated -->
        </div>
        
        <div class="controls">
            <div class="control-group">
                <label for="log-entry">Add Log Entry:</label>
                <input type="text" id="log-entry" placeholder="Enter data to replicate">
                <button class="btn primary" onclick="addEntry()">Add Entry</button>
            </div>
        </div>
        
        <div class="status">
            <h3>System Status</h3>
            <div id="status-display"></div>
        </div>
        
        <div class="logs">
            <div id="log-output"></div>
        </div>
    </div>

    <script>
        const ws = new WebSocket(`ws://${window.location.host}`);
        let nodes = [];
        
        ws.onmessage = (event) => {
            const message = JSON.parse(event.data);
            
            switch (message.type) {
                case 'status':
                    nodes = message.data;
                    updateDisplay();
                    break;
                case 'stateChange':
                    updateNodeState(message.data);
                    break;
                case 'log':
                    addLogEntry(message.data);
                    break;
                case 'logEntry':
                    updateStatus();
                    break;
                case 'partition':
                case 'reconnect':
                    updateStatus();
                    break;
            }
        };
        
        function updateDisplay() {
            const clusterView = document.getElementById('cluster-view');
            clusterView.innerHTML = '';
            
            nodes.forEach(node => {
                const nodeEl = document.createElement('div');
                nodeEl.className = `node ${node.state} ${node.isPartitioned ? 'partitioned' : ''}`;
                nodeEl.innerHTML = `
                    <div class="node-id">Node ${node.nodeId}</div>
                    <div class="node-state">${node.state}</div>
                    <div class="node-term">Term: ${node.term}</div>
                    <div class="node-controls">
                        ${!node.isPartitioned ? 
                            `<button class="btn partition" onclick="partitionNode(${node.nodeId})">Partition</button>` :
                            `<button class="btn reconnect" onclick="reconnectNode(${node.nodeId})">Reconnect</button>`
                        }
                    </div>
                `;
                clusterView.appendChild(nodeEl);
            });
            
            updateStatus();
        }
        
        function updateNodeState(data) {
            const node = nodes.find(n => n.nodeId === data.nodeId);
            if (node) {
                node.state = data.state;
                node.term = data.term;
                updateDisplay();
            }
        }
        
        function updateStatus() {
            const statusDisplay = document.getElementById('status-display');
            const leader = nodes.find(n => n.state === 'leader' && !n.isPartitioned);
            const followers = nodes.filter(n => n.state === 'follower' && !n.isPartitioned);
            const candidates = nodes.filter(n => n.state === 'candidate' && !n.isPartitioned);
            const partitioned = nodes.filter(n => n.isPartitioned);
            
            statusDisplay.innerHTML = `
                <div class="status-item">
                    <strong>Leader:</strong> ${leader ? `Node ${leader.nodeId} (Term ${leader.term})` : 'None'}
                </div>
                <div class="status-item">
                    <strong>Followers:</strong> ${followers.map(n => `Node ${n.nodeId}`).join(', ') || 'None'}
                </div>
                <div class="status-item">
                    <strong>Candidates:</strong> ${candidates.map(n => `Node ${n.nodeId}`).join(', ') || 'None'}
                </div>
                <div class="status-item">
                    <strong>Partitioned:</strong> ${partitioned.map(n => `Node ${n.nodeId}`).join(', ') || 'None'}
                </div>
            `;
        }
        
        function addLogEntry(data) {
            const logOutput = document.getElementById('log-output');
            const entry = document.createElement('div');
            entry.className = `log-entry log-${data.level}`;
            entry.textContent = `${data.timestamp} [Node-${data.nodeId}] ${data.message}`;
            logOutput.appendChild(entry);
            logOutput.scrollTop = logOutput.scrollHeight;
        }
        
        function addEntry() {
            const input = document.getElementById('log-entry');
            const data = input.value.trim();
            if (data) {
                fetch('/api/entry', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ data })
                });
                input.value = '';
            }
        }
        
        function partitionNode(nodeId) {
            fetch(`/api/partition/${nodeId}`, { method: 'POST' });
        }
        
        function reconnectNode(nodeId) {
            fetch(`/api/reconnect/${nodeId}`, { method: 'POST' });
        }
        
        // Initial load
        updateStatus();
    </script>
</body>
</html>
EOF

    log_success "HTML interface created"
}

# Main setup function
setup_demo() {
    log_info "Setting up Raft Consensus Algorithm demonstration..."
    
    check_dependencies
    setup_project
    create_raft_node
    create_cluster_manager
    create_web_interface
    create_html_interface
    
    log_success "Raft demo setup complete!"
}

# Kill processes holding required ports
kill_ports() {
    echo "DEBUG: Entering kill_ports function"
    PORTS=(3000 8000 8001 8002 8003 8004)
    for PORT in "${PORTS[@]}"; do
        echo "DEBUG: Checking port $PORT"
        PID=$(lsof -ti tcp:$PORT 2>/dev/null || true)
        if [ ! -z "$PID" ]; then
            log_warning "Killing process $PID on port $PORT..."
            kill -9 $PID 2>/dev/null || true
        fi
    done
    echo "DEBUG: Exiting kill_ports function"
}

# Start the demo
start_demo() {
    echo "DEBUG: Entering start_demo function"
    echo "DEBUG: Current directory: $(pwd)"
    echo "DEBUG: Directory contents:"
    ls -la
    
    log_info "Starting Raft demonstration..."
    kill_ports
    
    # Ensure we're in the correct directory
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    cd "$SCRIPT_DIR"
    
    echo "DEBUG: After cd to script directory: $(pwd)"
    echo "DEBUG: Directory contents:"
    ls -la
    
    if [ ! -d "raft-demo" ]; then
        log_error "Demo not set up. Run './setup.sh setup' first."
        exit 1
    fi
    
    cd raft-demo
    
    echo "DEBUG: After cd to raft-demo: $(pwd)"
    echo "DEBUG: Directory contents:"
    ls -la
    
    log_info "Starting web server on port $WEB_PORT..."
    log_success "Demo started! Open http://localhost:$WEB_PORT in your browser"
    log_info "The server will run in the foreground. Press Ctrl+C to stop the demo."
    
    # Open browser if available
    if command -v open &> /dev/null; then
        open "http://localhost:$WEB_PORT"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "http://localhost:$WEB_PORT"
    fi
    
    # Run server in foreground
    echo "DEBUG: About to start server"
    exec node src/web-server.js
}

# Stop the demo
stop_demo() {
    log_info "Stopping Raft demonstration..."
    
    if [ -f $PID_FILE ]; then
        PID=$(cat $PID_FILE)
        if kill -0 $PID 2>/dev/null; then
            kill $PID
            rm $PID_FILE
            log_success "Demo stopped"
        else
            log_warning "Demo was not running"
            rm $PID_FILE
        fi
    else
        log_warning "No PID file found"
    fi
}

# Clean up demo files
clean_demo() {
    log_warning "Cleaning up demo files..."
    rm -rf raft-demo $PID_FILE $LOG_DIR
    log_success "Demo files cleaned up"
}

# Show usage
show_usage() {
    cat << EOF
Raft Consensus Algorithm Demonstration Script

Usage: $0 [command]

Commands:
    setup    - Set up the demonstration environment
    start    - Start the Raft cluster demonstration
    stop     - Stop the running demonstration
    clean    - Clean up all demo files
    help     - Show this help message

Examples:
    $0 setup && $0 start    # Set up and start the demo
    $0 stop                 # Stop the demo
    $0 clean                # Clean up files

The demonstration includes:
    - 5-node Raft cluster simulation
    - Web interface for visualization
    - Interactive controls for partitioning nodes
    - Real-time log viewing
    - Leader election simulation
    - Log replication demonstration

Access the demo at: http://localhost:$WEB_PORT
EOF
}

# Test and verify
test_demo() {
    log_info "Testing Raft demonstration setup..."
    
    # Test Node.js availability
    if ! command -v node &> /dev/null; then
        log_error "Node.js not found"
        return 1
    fi
    
    # Test if demo directory exists
    if [ ! -d "raft-demo" ]; then
        log_error "Demo directory not found. Run setup first."
        return 1
    fi
    
    # Test if all required files exist
    local required_files=(
        "raft-demo/src/raft-node.js"
        "raft-demo/src/cluster.js"
        "raft-demo/src/web-server.js"
        "raft-demo/public/index.html"
        "raft-demo/package.json"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_error "Required file missing: $file"
            return 1
        fi
    done
    
    log_success "All tests passed! Demo is ready to run."
    return 0
}

# Main command dispatcher
case "${1:-help}" in
    setup)
        setup_demo
        ;;
    start)
        start_demo
        ;;
    stop)
        stop_demo
        ;;
    clean)
        clean_demo
        ;;
    test)
        test_demo
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        show_usage
        exit 1
        ;;
esac