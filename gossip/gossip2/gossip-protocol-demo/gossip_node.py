import asyncio
import json
import time
import random
import threading
import logging
from typing import Dict, List, Set, Optional, Tuple
from dataclasses import dataclass, asdict
from collections import defaultdict
import requests
from flask import Flask, render_template_string, jsonify, request
from flask_socketio import SocketIO, emit
import uuid

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')

@dataclass
class GossipMessage:
    """Represents a gossip message with metadata"""
    id: str
    data: Dict
    timestamp: float
    sender_id: str
    excitement_level: int = 5  # 0-10 scale
    propagation_count: int = 0
    recipients_seen: Set[str] = None
    
    def __post_init__(self):
        if self.recipients_seen is None:
            self.recipients_seen = set()

@dataclass
class NodeState:
    """Represents the state of a gossip node"""
    id: str
    host: str
    port: int
    is_alive: bool = True
    last_seen: float = 0
    vector_clock: Dict[str, int] = None
    
    def __post_init__(self):
        if self.vector_clock is None:
            self.vector_clock = defaultdict(int)

class GossipNode:
    """Implementation of a SWIM-based gossip protocol node"""
    
    def __init__(self, node_id: str, host: str, port: int, web_port: int):
        self.node_id = node_id
        self.host = host
        self.port = port
        self.web_port = web_port
        
        # Node state
        self.is_running = False
        self.members: Dict[str, NodeState] = {}
        self.gossip_queue: List[GossipMessage] = []
        self.local_data: Dict[str, any] = {}
        self.vector_clock: Dict[str, int] = defaultdict(int)
        
        # Gossip parameters
        self.gossip_interval = 2.0  # seconds
        self.fanout = 3  # number of nodes to gossip with per round
        self.max_excitement = 10
        self.excitement_threshold = 2
        
        # SWIM parameters
        self.ping_timeout = 1.0
        self.ping_interval = 5.0
        self.suspect_timeout = 10.0
        
        # Statistics
        self.stats = {
            'messages_sent': 0,
            'messages_received': 0,
            'gossip_rounds': 0,
            'failed_pings': 0
        }
        
        # Flask app for web interface
        self.app = Flask(__name__)
        self.app.config['SECRET_KEY'] = 'gossip-demo'
        self.socketio = SocketIO(self.app, cors_allowed_origins="*")
        
        self.setup_routes()
        self.logger = logging.getLogger(f"GossipNode-{node_id}")

    def setup_routes(self):
        """Setup Flask routes for web interface and API"""
        
        @self.app.route('/')
        def index():
            return render_template_string(self.get_web_template())
        
        @self.app.route('/api/status')
        def status():
            def member_to_dict(v):
                return {
                    'id': v.id,
                    'host': v.host,
                    'port': v.port,
                    'is_alive': v.is_alive,
                    'last_seen': v.last_seen,
                    'vector_clock': dict(v.vector_clock)
                }
            return jsonify({
                'node_id': self.node_id,
                'members': {k: member_to_dict(v) for k, v in self.members.items()},
                'gossip_queue_size': len(self.gossip_queue),
                'local_data': self.local_data,
                'stats': self.stats,
                'vector_clock': dict(self.vector_clock)
            })
        
        @self.app.route('/api/gossip', methods=['POST'])
        def receive_gossip():
            try:
                data = request.json
                message = GossipMessage(**data)
                self.handle_gossip_message(message)
                return jsonify({'status': 'success'})
            except Exception as e:
                self.logger.error(f"Error handling gossip: {e}")
                return jsonify({'status': 'error', 'message': str(e)}), 400
        
        @self.app.route('/api/ping', methods=['POST'])
        def ping():
            return jsonify({
                'status': 'alive',
                'node_id': self.node_id,
                'timestamp': time.time()
            })
        
        @self.app.route('/api/add_data', methods=['POST'])
        def add_data():
            try:
                data = request.json
                key = data.get('key')
                value = data.get('value')
                
                # Update local data and vector clock
                self.local_data[key] = value
                self.vector_clock[self.node_id] += 1
                
                # Create gossip message
                gossip_msg = GossipMessage(
                    id=str(uuid.uuid4()),
                    data={'key': key, 'value': value, 'operation': 'update'},
                    timestamp=time.time(),
                    sender_id=self.node_id,
                    excitement_level=self.max_excitement
                )
                
                self.gossip_queue.append(gossip_msg)
                self.logger.info(f"Added data: {key}={value}, queued for gossip")
                
                return jsonify({'status': 'success', 'key': key, 'value': value})
            except Exception as e:
                return jsonify({'status': 'error', 'message': str(e)}), 400

    def join_cluster(self, seed_nodes: List[Tuple[str, int]]):
        """Join the gossip cluster using seed nodes"""
        for host, port in seed_nodes:
            try:
                # Register with seed node
                response = requests.post(
                    f"http://{host}:{port}/api/join",
                    json={
                        'node_id': self.node_id,
                        'host': self.host,
                        'port': self.web_port
                    },
                    timeout=2.0
                )
                
                if response.status_code == 200:
                    # Add seed node to members
                    seed_id = f"{host}:{port}"
                    self.members[seed_id] = NodeState(
                        id=seed_id,
                        host=host,
                        port=port,
                        last_seen=time.time()
                    )
                    self.logger.info(f"Successfully joined cluster via {host}:{port}")
                    break
                    
            except Exception as e:
                self.logger.warning(f"Failed to connect to seed {host}:{port}: {e}")
                continue

    def start(self):
        """Start the gossip node"""
        self.is_running = True
        self.logger.info(f"Starting gossip node {self.node_id} on {self.host}:{self.web_port}")
        
        # Start background threads
        threading.Thread(target=self.gossip_loop, daemon=True).start()
        threading.Thread(target=self.ping_loop, daemon=True).start()
        threading.Thread(target=self.web_server, daemon=True).start()
        
        # Add self to members
        self.members[self.node_id] = NodeState(
            id=self.node_id,
            host=self.host,
            port=self.web_port,
            last_seen=time.time()
        )

    def web_server(self):
        """Run the web server"""
        self.socketio.run(self.app, host='0.0.0.0', port=self.web_port, debug=False)

    def gossip_loop(self):
        """Main gossip loop - runs periodically to spread information"""
        while self.is_running:
            try:
                self.perform_gossip_round()
                time.sleep(self.gossip_interval)
            except Exception as e:
                self.logger.error(f"Error in gossip loop: {e}")

    def perform_gossip_round(self):
        """Perform one round of gossip"""
        if not self.gossip_queue:
            return
        
        # Select gossip targets
        alive_members = [m for m in self.members.values() 
                        if m.is_alive and m.id != self.node_id]
        
        if not alive_members:
            return
        
        # Select up to fanout nodes
        targets = random.sample(alive_members, min(self.fanout, len(alive_members)))
        
        # Process gossip queue
        messages_to_remove = []
        for i, message in enumerate(self.gossip_queue):
            
            # Check if message is still "exciting"
            if message.excitement_level <= self.excitement_threshold:
                messages_to_remove.append(i)
                continue
            
            # Send to targets
            for target in targets:
                if target.id not in message.recipients_seen:
                    success = self.send_gossip_message(target, message)
                    if success:
                        message.recipients_seen.add(target.id)
                        message.propagation_count += 1
            
            # Reduce excitement based on how many already knew
            known_ratio = len(message.recipients_seen) / max(len(self.members), 1)
            if known_ratio > 0.8:  # If 80% already know, cool down rapidly
                message.excitement_level = max(0, message.excitement_level - 3)
            else:
                message.excitement_level = max(0, message.excitement_level - 1)
        
        # Remove cooled messages
        for i in reversed(messages_to_remove):
            removed = self.gossip_queue.pop(i)
            self.logger.info(f"Removed cooled gossip message: {removed.id}")
        
        self.stats['gossip_rounds'] += 1
        
        # Emit status update via WebSocket
        self.socketio.emit('status_update', {
            'node_id': self.node_id,
            'stats': self.stats,
            'queue_size': len(self.gossip_queue),
            'members_count': len([m for m in self.members.values() if m.is_alive])
        })

    def send_gossip_message(self, target: NodeState, message: GossipMessage) -> bool:
        """Send a gossip message to a target node"""
        try:
            # Prepare message data
            message_data = {
                'id': message.id,
                'data': message.data,
                'timestamp': message.timestamp,
                'sender_id': message.sender_id,
                'excitement_level': message.excitement_level,
                'propagation_count': message.propagation_count,
                'recipients_seen': list(message.recipients_seen)
            }
            
            response = requests.post(
                f"http://{target.host}:{target.port}/api/gossip",
                json=message_data,
                timeout=1.0
            )
            
            if response.status_code == 200:
                self.stats['messages_sent'] += 1
                self.logger.debug(f"Sent gossip to {target.id}: {message.data}")
                return True
            else:
                self.logger.warning(f"Failed to send gossip to {target.id}: {response.status_code}")
                return False
                
        except Exception as e:
            self.logger.warning(f"Error sending gossip to {target.id}: {e}")
            # Mark node as potentially failed
            target.is_alive = False
            return False

    def handle_gossip_message(self, message: GossipMessage):
        """Handle incoming gossip message"""
        self.stats['messages_received'] += 1
        
        # Update vector clock
        if message.sender_id in self.vector_clock:
            self.vector_clock[message.sender_id] = max(
                self.vector_clock[message.sender_id],
                message.propagation_count
            )
        
        # Process the message data
        if message.data.get('operation') == 'update':
            key = message.data.get('key')
            value = message.data.get('value')
            
            # Check if this is new information
            if key not in self.local_data or self.local_data[key] != value:
                self.local_data[key] = value
                self.logger.info(f"Updated local data via gossip: {key}={value}")
                
                # Add to our gossip queue with reduced excitement
                new_message = GossipMessage(
                    id=message.id,
                    data=message.data,
                    timestamp=message.timestamp,
                    sender_id=message.sender_id,
                    excitement_level=max(1, message.excitement_level - 1),
                    propagation_count=message.propagation_count,
                    recipients_seen=set(message.recipients_seen)
                )
                
                # Avoid duplicate messages
                if not any(m.id == message.id for m in self.gossip_queue):
                    self.gossip_queue.append(new_message)

    def ping_loop(self):
        """SWIM ping loop for failure detection"""
        while self.is_running:
            try:
                self.perform_ping_round()
                time.sleep(self.ping_interval)
            except Exception as e:
                self.logger.error(f"Error in ping loop: {e}")

    def perform_ping_round(self):
        """Perform SWIM ping round for failure detection"""
        alive_members = [m for m in self.members.values() 
                        if m.is_alive and m.id != self.node_id]
        
        if not alive_members:
            return
        
        # Select random member to ping
        target = random.choice(alive_members)
        
        try:
            response = requests.post(
                f"http://{target.host}:{target.port}/api/ping",
                json={'sender': self.node_id},
                timeout=self.ping_timeout
            )
            
            if response.status_code == 200:
                target.last_seen = time.time()
                self.logger.debug(f"Ping successful: {target.id}")
            else:
                self.handle_ping_failure(target)
                
        except Exception as e:
            self.logger.warning(f"Ping failed to {target.id}: {e}")
            self.handle_ping_failure(target)

    def handle_ping_failure(self, target: NodeState):
        """Handle ping failure - implement indirect ping"""
        self.stats['failed_pings'] += 1
        
        # Try indirect ping through other nodes
        other_members = [m for m in self.members.values() 
                        if m.is_alive and m.id not in [self.node_id, target.id]]
        
        if len(other_members) >= 2:
            # Select 2 random nodes for indirect ping
            witnesses = random.sample(other_members, min(2, len(other_members)))
            indirect_success = False
            
            for witness in witnesses:
                try:
                    # Ask witness to ping target
                    response = requests.post(
                        f"http://{witness.host}:{witness.port}/api/indirect_ping",
                        json={'target': target.id, 'requester': self.node_id},
                        timeout=self.ping_timeout
                    )
                    
                    if response.status_code == 200 and response.json().get('success'):
                        indirect_success = True
                        break
                        
                except Exception:
                    continue
            
            if not indirect_success:
                # Mark as suspected/dead
                target.is_alive = False
                self.logger.warning(f"Declared node {target.id} as failed")
                
                # Gossip the failure
                failure_msg = GossipMessage(
                    id=str(uuid.uuid4()),
                    data={'operation': 'node_failed', 'node_id': target.id},
                    timestamp=time.time(),
                    sender_id=self.node_id,
                    excitement_level=self.max_excitement
                )
                self.gossip_queue.append(failure_msg)

    def get_web_template(self):
        """Return HTML template for web interface"""
        return '''
<!DOCTYPE html>
<html>
<head>
    <title>Gossip Node {{ node_id }}</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/socket.io/4.0.1/socket.io.js"></script>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .stats { display: flex; gap: 20px; margin-bottom: 20px; }
        .stat-card { background: white; padding: 15px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); flex: 1; }
        .controls { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .data-section { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .log { background: #2c3e50; color: #ecf0f1; padding: 15px; border-radius: 8px; font-family: monospace; height: 200px; overflow-y: scroll; }
        button { background: #3498db; color: white; border: none; padding: 10px 20px; border-radius: 4px; cursor: pointer; }
        button:hover { background: #2980b9; }
        input { padding: 8px; border: 1px solid #ddd; border-radius: 4px; margin: 5px; }
        .excitement-bar { width: 100%; height: 20px; background: #ecf0f1; border-radius: 10px; overflow: hidden; }
        .excitement-fill { height: 100%; transition: width 0.3s ease; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🗣️ Gossip Node: ''' + "{{ node_id }}" + '''</h1>
            <p>Real-time Gossip Protocol Demonstration</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <h3>Messages Sent</h3>
                <div id="messages-sent">0</div>
            </div>
            <div class="stat-card">
                <h3>Messages Received</h3>
                <div id="messages-received">0</div>
            </div>
            <div class="stat-card">
                <h3>Gossip Rounds</h3>
                <div id="gossip-rounds">0</div>
            </div>
            <div class="stat-card">
                <h3>Active Members</h3>
                <div id="active-members">0</div>
            </div>
        </div>
        
        <div class="controls">
            <h3>Add Data to Gossip Network</h3>
            <input type="text" id="data-key" placeholder="Key" />
            <input type="text" id="data-value" placeholder="Value" />
            <button onclick="addData()">Add Data</button>
        </div>
        
        <div class="data-section">
            <h3>Local Data Store</h3>
            <div id="local-data"></div>
        </div>
        
        <div class="data-section">
            <h3>Gossip Queue Status</h3>
            <div id="gossip-queue"></div>
        </div>
        
        <div class="data-section">
            <h3>Network Topology</h3>
            <div id="network-plot" style="height: 400px;"></div>
        </div>
        
        <div class="log" id="log">
            <div>Gossip Node Log - Waiting for updates...</div>
        </div>
    </div>

    <script>
        const socket = io();
        
        socket.on('status_update', function(data) {
            updateStats(data);
            logMessage(`Gossip round completed. Queue: ${data.queue_size}, Members: ${data.members_count}`);
        });
        
        function updateStats(data) {
            document.getElementById('messages-sent').textContent = data.stats.messages_sent || 0;
            document.getElementById('messages-received').textContent = data.stats.messages_received || 0;
            document.getElementById('gossip-rounds').textContent = data.stats.gossip_rounds || 0;
            document.getElementById('active-members').textContent = data.members_count || 0;
        }
        
        function addData() {
            const key = document.getElementById('data-key').value;
            const value = document.getElementById('data-value').value;
            
            if (!key || !value) {
                alert('Please enter both key and value');
                return;
            }
            
            fetch('/api/add_data', {
                method: 'POST',
                headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({key: key, value: value})
            })
            .then(response => response.json())
            .then(data => {
                if (data.status === 'success') {
                    logMessage(`Added data: ${key} = ${value}`);
                    document.getElementById('data-key').value = '';
                    document.getElementById('data-value').value = '';
                    refreshData();
                }
            });
        }
        
        function refreshData() {
            fetch('/api/status')
            .then(response => response.json())
            .then(data => {
                updateLocalData(data.local_data);
                updateGossipQueue(data);
                updateNetworkPlot(data.members);
            });
        }
        
        function updateLocalData(localData) {
            const container = document.getElementById('local-data');
            container.innerHTML = '';
            
            for (const [key, value] of Object.entries(localData)) {
                const item = document.createElement('div');
                item.innerHTML = `<strong>${key}:</strong> ${value}`;
                item.style.padding = '5px';
                item.style.border = '1px solid #ddd';
                item.style.margin = '2px';
                item.style.borderRadius = '4px';
                container.appendChild(item);
            }
        }
        
        function updateGossipQueue(data) {
            const container = document.getElementById('gossip-queue');
            container.innerHTML = `
                <p>Queue Size: ${data.gossip_queue_size}</p>
                <p>Vector Clock: ${JSON.stringify(data.vector_clock)}</p>
            `;
        }
        
        function updateNetworkPlot(members) {
            const nodes = Object.values(members).map(member => ({
                x: Math.random(),
                y: Math.random(),
                text: member.id,
                mode: 'markers+text',
                marker: {
                    size: member.is_alive ? 20 : 10,
                    color: member.is_alive ? '#2ecc71' : '#e74c3c'
                }
            }));
            
            Plotly.newPlot('network-plot', [{
                x: nodes.map(n => n.x),
                y: nodes.map(n => n.y),
                text: nodes.map(n => n.text),
                mode: 'markers+text',
                marker: {
                    size: nodes.map(n => n.marker.size),
                    color: nodes.map(n => n.marker.color)
                }
            }], {
                title: 'Gossip Network Topology',
                showlegend: false
            });
        }
        
        function logMessage(message) {
            const log = document.getElementById('log');
            const timestamp = new Date().toLocaleTimeString();
            log.innerHTML += `<div>[${timestamp}] ${message}</div>`;
            log.scrollTop = log.scrollHeight;
        }
        
        // Refresh data every 3 seconds
        setInterval(refreshData, 3000);
        refreshData(); // Initial load
    </script>
</body>
</html>
        '''

if __name__ == "__main__":
    import sys
    if len(sys.argv) < 4:
        print("Usage: python gossip_node.py <node_id> <host> <web_port>")
        sys.exit(1)
    
    node_id = sys.argv[1]
    host = sys.argv[2]
    web_port = int(sys.argv[3])
    
    node = GossipNode(node_id, host, web_port, web_port)
    node.start()
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print(f"\nShutting down node {node_id}")
        node.is_running = False
