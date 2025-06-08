#!/bin/bash

# Leader Election Demonstration Script
# This script creates a multi-node cluster demonstrating Raft leader election

set -e

echo "🚀 Leader Election Algorithm Demonstration"
echo "=========================================="

# Create project directory
PROJECT_DIR="leader-election-demo"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Create Python requirements
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
httpx==0.25.2
pydantic==2.5.0
jinja2==3.1.2
python-multipart==0.0.6
aiofiles==23.2.1
asyncio-mqtt==0.16.1
colorlog==6.8.0
EOF

# Create main node implementation
cat > node.py << 'EOF'
import asyncio
import random
import time
import logging
import json
import httpx
from enum import Enum
from typing import Dict, List, Optional, Set
from dataclasses import dataclass, asdict
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import uvicorn
import colorlog

# Configure colored logging
def setup_logging(node_id: str):
    handler = colorlog.StreamHandler()
    handler.setFormatter(colorlog.ColoredFormatter(
        '%(log_color)s%(asctime)s [%(levelname)s] Node-%(name)s: %(message)s',
        datefmt='%H:%M:%S',
        log_colors={
            'DEBUG': 'cyan',
            'INFO': 'green',
            'WARNING': 'yellow',
            'ERROR': 'red',
            'CRITICAL': 'red,bg_white',
        }
    ))
    
    logger = logging.getLogger(node_id)
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger

class NodeState(Enum):
    FOLLOWER = "follower"
    CANDIDATE = "candidate"
    LEADER = "leader"

@dataclass
class VoteRequest:
    term: int
    candidate_id: str
    last_log_index: int
    last_log_term: int

@dataclass
class VoteResponse:
    term: int
    vote_granted: bool

@dataclass
class HeartbeatRequest:
    term: int
    leader_id: str
    prev_log_index: int
    prev_log_term: int
    entries: List = None
    leader_commit: int = 0

@dataclass
class HeartbeatResponse:
    term: int
    success: bool

class RaftNode:
    def __init__(self, node_id: str, port: int, peers: List[str]):
        self.node_id = node_id
        self.port = port
        self.peers = peers
        self.logger = setup_logging(node_id)
        
        # Persistent state
        self.current_term = 0
        self.voted_for: Optional[str] = None
        self.log: List[Dict] = []
        
        # Volatile state
        self.state = NodeState.FOLLOWER
        self.leader_id: Optional[str] = None
        self.votes_received: Set[str] = set()
        
        # Timing
        self.last_heartbeat = time.time()
        self.election_timeout = self._generate_election_timeout()
        self.heartbeat_interval = 0.1  # 100ms
        
        # Statistics
        self.stats = {
            'elections_participated': 0,
            'elections_won': 0,
            'heartbeats_sent': 0,
            'heartbeats_received': 0,
            'votes_cast': 0,
            'term_changes': 0
        }
        
        # FastAPI app
        self.app = FastAPI(title=f"Raft Node {node_id}")
        self._setup_routes()
        
        # Background tasks
        self._running = False
        self._tasks = []

    def _generate_election_timeout(self) -> float:
        """Generate randomized election timeout (150-300ms)"""
        return random.uniform(0.15, 0.3)

    def _setup_routes(self):
        @self.app.get("/", response_class=HTMLResponse)
        async def dashboard():
            return self._generate_dashboard_html()
        
        @self.app.post("/vote")
        async def request_vote(request: dict):
            return await self._handle_vote_request(VoteRequest(**request))
        
        @self.app.post("/heartbeat")
        async def append_entries(request: dict):
            return await self._handle_heartbeat(HeartbeatRequest(**request))
        
        @self.app.get("/status")
        async def get_status():
            return {
                "node_id": self.node_id,
                "state": self.state.value,
                "term": self.current_term,
                "leader_id": self.leader_id,
                "peers": self.peers,
                "stats": self.stats,
                "uptime": time.time() - getattr(self, 'start_time', time.time())
            }
        
        @self.app.post("/simulate_failure")
        async def simulate_failure():
            """Simulate node failure for testing"""
            self.logger.warning("🔥 SIMULATING NODE FAILURE")
            self.state = NodeState.FOLLOWER
            self.leader_id = None
            await asyncio.sleep(random.uniform(2, 5))  # Failure duration
            self.logger.info("🔄 Node recovered from failure")
            return {"status": "failure_simulated"}

    async def _handle_vote_request(self, request: VoteRequest) -> dict:
        """Handle incoming vote request (RequestVote RPC)"""
        self.logger.info(f"📩 Received vote request from {request.candidate_id} for term {request.term}")
        
        response = VoteResponse(term=self.current_term, vote_granted=False)
        
        # Update term if we see higher term
        if request.term > self.current_term:
            self.current_term = request.term
            self.voted_for = None
            self.state = NodeState.FOLLOWER
            self.leader_id = None
            self.stats['term_changes'] += 1
            self.logger.info(f"📈 Updated term to {self.current_term}")
        
        # Grant vote if conditions are met
        if (request.term >= self.current_term and 
            (self.voted_for is None or self.voted_for == request.candidate_id)):
            
            self.voted_for = request.candidate_id
            response.vote_granted = True
            self.last_heartbeat = time.time()  # Reset election timeout
            self.stats['votes_cast'] += 1
            self.logger.info(f"✅ Granted vote to {request.candidate_id}")
        else:
            self.logger.info(f"❌ Denied vote to {request.candidate_id}")
        
        response.term = self.current_term
        return asdict(response)

    async def _handle_heartbeat(self, request: HeartbeatRequest) -> dict:
        """Handle incoming heartbeat (AppendEntries RPC)"""
        self.logger.debug(f"💓 Received heartbeat from {request.leader_id}")
        
        response = HeartbeatResponse(term=self.current_term, success=False)
        
        # Update term if we see higher term
        if request.term > self.current_term:
            self.current_term = request.term
            self.voted_for = None
            self.state = NodeState.FOLLOWER
            self.stats['term_changes'] += 1
        
        # Accept heartbeat if term is current
        if request.term >= self.current_term:
            self.state = NodeState.FOLLOWER
            self.leader_id = request.leader_id
            self.last_heartbeat = time.time()
            response.success = True
            self.stats['heartbeats_received'] += 1
            
            if self.leader_id != request.leader_id:
                self.logger.info(f"👑 Recognized {request.leader_id} as leader for term {request.term}")
        
        response.term = self.current_term
        return asdict(response)

    async def _start_election(self):
        """Start leader election process"""
        self.logger.info("🗳️  Starting leader election")
        self.state = NodeState.CANDIDATE
        self.current_term += 1
        self.voted_for = self.node_id
        self.votes_received = {self.node_id}
        self.last_heartbeat = time.time()
        self.election_timeout = self._generate_election_timeout()
        self.stats['elections_participated'] += 1
        self.stats['term_changes'] += 1
        
        self.logger.info(f"📢 Requesting votes for term {self.current_term}")
        
        # Send vote requests to all peers
        vote_tasks = []
        for peer in self.peers:
            if peer != self.node_id:
                vote_tasks.append(self._request_vote_from_peer(peer))
        
        if vote_tasks:
            await asyncio.gather(*vote_tasks, return_exceptions=True)
        
        # Check if we won the election
        majority = (len(self.peers) + 1) // 2 + 1
        if len(self.votes_received) >= majority and self.state == NodeState.CANDIDATE:
            await self._become_leader()

    async def _request_vote_from_peer(self, peer: str):
        """Send vote request to a specific peer"""
        try:
            async with httpx.AsyncClient(timeout=0.5) as client:
                vote_request = VoteRequest(
                    term=self.current_term,
                    candidate_id=self.node_id,
                    last_log_index=len(self.log) - 1,
                    last_log_term=self.log[-1]['term'] if self.log else 0
                )
                
                response = await client.post(
                    f"http://{peer}/vote",
                    json=asdict(vote_request)
                )
                
                if response.status_code == 200:
                    vote_response = VoteResponse(**response.json())
                    
                    # Update term if we see higher term
                    if vote_response.term > self.current_term:
                        self.current_term = vote_response.term
                        self.state = NodeState.FOLLOWER
                        self.voted_for = None
                        self.leader_id = None
                        self.stats['term_changes'] += 1
                        self.logger.info(f"📉 Stepping down, discovered higher term {vote_response.term}")
                        return
                    
                    if vote_response.vote_granted:
                        self.votes_received.add(peer)
                        self.logger.info(f"✅ Received vote from {peer} ({len(self.votes_received)}/{len(self.peers)})")
                    else:
                        self.logger.info(f"❌ Vote denied by {peer}")
                        
        except Exception as e:
            self.logger.debug(f"Failed to get vote from {peer}: {e}")

    async def _become_leader(self):
        """Transition to leader state"""
        self.logger.info(f"👑 Became leader for term {self.current_term}!")
        self.state = NodeState.LEADER
        self.leader_id = self.node_id
        self.stats['elections_won'] += 1
        
        # Start sending heartbeats immediately
        await self._send_heartbeats()

    async def _send_heartbeats(self):
        """Send heartbeats to all followers"""
        if self.state != NodeState.LEADER:
            return
            
        heartbeat_tasks = []
        for peer in self.peers:
            if peer != self.node_id:
                heartbeat_tasks.append(self._send_heartbeat_to_peer(peer))
        
        if heartbeat_tasks:
            await asyncio.gather(*heartbeat_tasks, return_exceptions=True)
        
        self.stats['heartbeats_sent'] += len(heartbeat_tasks)

    async def _send_heartbeat_to_peer(self, peer: str):
        """Send heartbeat to a specific peer"""
        try:
            async with httpx.AsyncClient(timeout=0.5) as client:
                heartbeat = HeartbeatRequest(
                    term=self.current_term,
                    leader_id=self.node_id,
                    prev_log_index=len(self.log) - 1,
                    prev_log_term=self.log[-1]['term'] if self.log else 0,
                    entries=[],
                    leader_commit=0
                )
                
                response = await client.post(
                    f"http://{peer}/heartbeat",
                    json=asdict(heartbeat)
                )
                
                if response.status_code == 200:
                    heartbeat_response = HeartbeatResponse(**response.json())
                    
                    # Step down if we see higher term
                    if heartbeat_response.term > self.current_term:
                        self.current_term = heartbeat_response.term
                        self.state = NodeState.FOLLOWER
                        self.voted_for = None
                        self.leader_id = None
                        self.stats['term_changes'] += 1
                        self.logger.info(f"📉 Stepping down, discovered higher term {heartbeat_response.term}")
                        
        except Exception as e:
            self.logger.debug(f"Failed to send heartbeat to {peer}: {e}")

    async def _main_loop(self):
        """Main node loop handling timeouts and state transitions"""
        self.start_time = time.time()
        self.logger.info(f"🚀 Node {self.node_id} started")
        
        while self._running:
            try:
                current_time = time.time()
                
                if self.state == NodeState.LEADER:
                    # Send periodic heartbeats
                    await self._send_heartbeats()
                    await asyncio.sleep(self.heartbeat_interval)
                    
                elif self.state in [NodeState.FOLLOWER, NodeState.CANDIDATE]:
                    # Check for election timeout
                    if current_time - self.last_heartbeat > self.election_timeout:
                        await self._start_election()
                    
                    await asyncio.sleep(0.01)  # Small sleep to prevent busy waiting
                    
            except Exception as e:
                self.logger.error(f"Error in main loop: {e}")
                await asyncio.sleep(0.1)

    def _generate_dashboard_html(self) -> str:
        """Generate HTML dashboard for this node"""
        peers_status = []
        for peer in self.peers:
            if peer != self.node_id:
                peers_status.append(f'<span class="peer">Node {peer}</span>')
        
        state_color = {
            NodeState.FOLLOWER: "#3498db",
            NodeState.CANDIDATE: "#9b59b6", 
            NodeState.LEADER: "#2ecc71"
        }
        
        return f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>Raft Node {self.node_id}</title>
            <meta http-equiv="refresh" content="1">
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; background: #f8f9fa; }}
                .container {{ max-width: 800px; margin: 0 auto; }}
                .header {{ text-align: center; margin-bottom: 30px; }}
                .node-info {{ background: white; padding: 20px; border-radius: 10px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); margin-bottom: 20px; }}
                .state {{ font-size: 24px; font-weight: bold; color: {state_color.get(self.state, '#000')}; }}
                .metric {{ display: inline-block; margin: 10px; padding: 10px; background: #ecf0f1; border-radius: 5px; }}
                .peers {{ margin-top: 15px; }}
                .peer {{ display: inline-block; margin: 5px; padding: 5px 10px; background: #bdc3c7; border-radius: 3px; }}
                .leader {{ background: #2ecc71; color: white; }}
                .stats {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 10px; }}
                .actions {{ margin-top: 20px; text-align: center; }}
                .btn {{ padding: 10px 20px; margin: 5px; background: #e74c3c; color: white; border: none; border-radius: 5px; cursor: pointer; }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>🏛️ Raft Node {self.node_id}</h1>
                    <div class="state">State: {self.state.value.upper()}</div>
                </div>
                
                <div class="node-info">
                    <h3>📊 Node Status</h3>
                    <div class="metric">Term: <strong>{self.current_term}</strong></div>
                    <div class="metric">Leader: <strong>{self.leader_id or 'None'}</strong></div>
                    <div class="metric">Port: <strong>{self.port}</strong></div>
                    <div class="metric">Voted For: <strong>{self.voted_for or 'None'}</strong></div>
                    
                    <div class="peers">
                        <strong>Cluster Peers:</strong><br>
                        {''.join(peers_status)}
                    </div>
                </div>
                
                <div class="node-info">
                    <h3>📈 Statistics</h3>
                    <div class="stats">
                        <div class="metric">Elections: {self.stats['elections_participated']}</div>
                        <div class="metric">Elections Won: {self.stats['elections_won']}</div>
                        <div class="metric">Heartbeats Sent: {self.stats['heartbeats_sent']}</div>
                        <div class="metric">Heartbeats Received: {self.stats['heartbeats_received']}</div>
                        <div class="metric">Votes Cast: {self.stats['votes_cast']}</div>
                        <div class="metric">Term Changes: {self.stats['term_changes']}</div>
                    </div>
                </div>
                
                <div class="actions">
                    <button class="btn" onclick="fetch('/simulate_failure', {{method: 'POST'}})">
                        🔥 Simulate Failure
                    </button>
                </div>
                
                <div style="text-align: center; margin-top: 20px; color: #7f8c8d;">
                    Auto-refreshing every second | Time: {time.strftime('%H:%M:%S')}
                </div>
            </div>
        </body>
        </html>
        """

    async def start(self):
        """Start the node"""
        self._running = True
        
        # Start the main loop
        loop_task = asyncio.create_task(self._main_loop())
        self._tasks.append(loop_task)
        
        # Start the web server
        config = uvicorn.Config(
            self.app, 
            host="0.0.0.0", 
            port=self.port, 
            log_level="warning"
        )
        server = uvicorn.Server(config)
        server_task = asyncio.create_task(server.serve())
        self._tasks.append(server_task)
        
        await asyncio.gather(*self._tasks)

    async def stop(self):
        """Stop the node"""
        self._running = False
        for task in self._tasks:
            task.cancel()

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) != 4:
        print("Usage: python node.py <node_id> <port> <peer_ports>")
        print("Example: python node.py node1 8001 8001,8002,8003")
        sys.exit(1)
    
    node_id = sys.argv[1]
    port = int(sys.argv[2])
    peer_ports = [f"127.0.0.1:{p}" for p in sys.argv[3].split(",")]
    
    node = RaftNode(node_id, port, peer_ports)
    
    try:
        asyncio.run(node.start())
    except KeyboardInterrupt:
        print(f"\n🛑 Node {node_id} shutting down...")
EOF

# Create cluster management script
cat > cluster.py << 'EOF'
import asyncio
import subprocess
import time
import signal
import sys
import os
from typing import List

class ClusterManager:
    def __init__(self):
        self.processes: List[subprocess.Popen] = []
        self.running = False
    
    def start_cluster(self, num_nodes: int = 5):
        """Start a cluster of Raft nodes"""
        print(f"🚀 Starting {num_nodes}-node Raft cluster...")
        
        base_port = 8001
        ports = [base_port + i for i in range(num_nodes)]
        peer_list = ",".join(map(str, ports))
        
        for i in range(num_nodes):
            node_id = f"node{i+1}"
            port = ports[i]
            
            print(f"   Starting {node_id} on port {port}")
            
            process = subprocess.Popen([
                sys.executable, "node.py", 
                node_id, str(port), peer_list
            ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            
            self.processes.append(process)
            time.sleep(0.5)  # Stagger startup
        
        self.running = True
        print(f"\n✅ Cluster started successfully!")
        print(f"🌐 Web dashboards available at:")
        for i, port in enumerate(ports):
            print(f"   Node {i+1}: http://localhost:{port}")
        
        print(f"\n📊 Cluster status: http://localhost:{ports[0]}")
        print(f"💡 Press Ctrl+C to stop the cluster")
    
    def stop_cluster(self):
        """Stop all nodes in the cluster"""
        if not self.running:
            return
            
        print("\n🛑 Stopping cluster...")
        
        for i, process in enumerate(self.processes):
            try:
                process.terminate()
                process.wait(timeout=3)
                print(f"   Stopped node{i+1}")
            except subprocess.TimeoutExpired:
                process.kill()
                print(f"   Force killed node{i+1}")
            except Exception as e:
                print(f"   Error stopping node{i+1}: {e}")
        
        self.processes.clear()
        self.running = False
        print("✅ Cluster stopped")
    
    def wait_for_interrupt(self):
        """Wait for keyboard interrupt"""
        try:
            while self.running:
                time.sleep(1)
                # Check if any process died
                for i, process in enumerate(self.processes):
                    if process.poll() is not None:
                        print(f"⚠️  Node{i+1} process died unexpectedly")
        except KeyboardInterrupt:
            pass
        finally:
            self.stop_cluster()

def main():
    num_nodes = 5
    if len(sys.argv) > 1:
        try:
            num_nodes = int(sys.argv[1])
            if num_nodes < 3:
                print("❌ Minimum 3 nodes required for Raft consensus")
                sys.exit(1)
        except ValueError:
            print("❌ Invalid number of nodes")
            sys.exit(1)
    
    cluster = ClusterManager()
    
    # Setup signal handlers
    def signal_handler(signum, frame):
        cluster.stop_cluster()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    try:
        cluster.start_cluster(num_nodes)
        cluster.wait_for_interrupt()
    except Exception as e:
        print(f"❌ Error: {e}")
        cluster.stop_cluster()

if __name__ == "__main__":
    main()
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose port range for nodes
EXPOSE 8001-8010

# Default command
CMD ["python", "cluster.py"]
EOF

# Create Docker Compose file
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  raft-cluster:
    build: .
    ports:
      - "8001-8005:8001-8005"
    environment:
      - PYTHONUNBUFFERED=1
    volumes:
      - .:/app
    command: python cluster.py 5

  # Individual node services for advanced testing
  node1:
    build: .
    ports:
      - "8001:8001"
    environment:
      - PYTHONUNBUFFERED=1
    command: python node.py node1 8001 8001,8002,8003,8004,8005
    profiles: ["individual"]

  node2:
    build: .
    ports:
      - "8002:8002"
    environment:
      - PYTHONUNBUFFERED=1
    command: python node.py node2 8002 8001,8002,8003,8004,8005
    profiles: ["individual"]

  node3:
    build: .
    ports:
      - "8003:8003"
    environment:
      - PYTHONUNBUFFERED=1
    command: python node.py node3 8003 8001,8002,8003,8004,8005
    profiles: ["individual"]

  node4:
    build: .
    ports:
      - "8004:8004"
    environment:
      - PYTHONUNBUFFERED=1
    command: python node.py node4 8004 8001,8002,8003,8004,8005
    profiles: ["individual"]

  node5:
    build: .
    ports:
      - "8005:8005"
    environment:
      - PYTHONUNBUFFERED=1
    command: python node.py node5 8005 8001,8002,8003,8004,8005
    profiles: ["individual"]
EOF

# Create test script
cat > test_scenarios.py << 'EOF'
#!/usr/bin/env python3
"""
Test scenarios for leader election demonstration
"""
import asyncio
import httpx
import json
import time
from typing import List, Dict

class LeaderElectionTester:
    def __init__(self, nodes: List[str]):
        self.nodes = nodes
        self.client = httpx.AsyncClient(timeout=2.0)
    
    async def get_cluster_status(self) -> Dict:
        """Get status from all nodes"""
        status = {}
        for node in self.nodes:
            try:
                response = await self.client.get(f"http://{node}/status")
                if response.status_code == 200:
                    status[node] = response.json()
                else:
                    status[node] = {"error": "unreachable"}
            except Exception as e:
                status[node] = {"error": str(e)}
        return status
    
    async def find_leader(self) -> str:
        """Find the current leader"""
        status = await self.get_cluster_status()
        for node, data in status.items():
            if data.get("state") == "leader":
                return node
        return None
    
    async def simulate_leader_failure(self):
        """Simulate leader failure scenario"""
        print("\n🔥 SCENARIO: Leader Failure Simulation")
        print("="*50)
        
        leader = await self.find_leader()
        if not leader:
            print("❌ No leader found")
            return
        
        print(f"Current leader: {leader}")
        
        # Simulate failure
        try:
            response = await self.client.post(f"http://{leader}/simulate_failure")
            print(f"✅ Simulated failure on {leader}")
        except Exception as e:
            print(f"❌ Failed to simulate failure: {e}")
            return
        
        # Monitor election process
        print("\n📊 Monitoring election process...")
        for i in range(10):
            await asyncio.sleep(1)
            status = await self.get_cluster_status()
            
            # Count states
            states = {"follower": 0, "candidate": 0, "leader": 0}
            term_info = {}
            
            for node, data in status.items():
                if "error" not in data:
                    state = data.get("state", "unknown")
                    states[state] = states.get(state, 0) + 1
                    term_info[node] = data.get("term", 0)
            
            print(f"T+{i+1}s: Followers={states['follower']}, "
                  f"Candidates={states['candidate']}, Leaders={states['leader']}")
            
            # Check if new leader emerged
            new_leader = await self.find_leader()
            if new_leader and new_leader != leader:
                print(f"🎉 New leader elected: {new_leader}")
                break
        
        print(f"\n📈 Final cluster status:")
        await self.print_cluster_status()
    
    async def test_network_partition(self):
        """Test behavior during network partition"""
        print("\n🌐 SCENARIO: Network Partition Simulation")
        print("="*50)
        print("Note: This is simulated through failure injection")
        
        # Simulate partition by failing multiple nodes
        nodes_to_fail = self.nodes[:2]  # Fail first 2 nodes
        
        for node in nodes_to_fail:
            try:
                await self.client.post(f"http://{node}/simulate_failure")
                print(f"🔌 Disconnected {node}")
            except:
                pass
        
        print(f"\n📊 Remaining cluster should maintain leadership...")
        await asyncio.sleep(3)
        await self.print_cluster_status()
    
    async def print_cluster_status(self):
        """Print detailed cluster status"""
        status = await self.get_cluster_status()
        
        print("\n📋 Cluster Status:")
        print("-" * 80)
        print(f"{'Node':<12} {'State':<12} {'Term':<6} {'Leader':<12} {'Elections':<10} {'Uptime':<8}")
        print("-" * 80)
        
        for node, data in status.items():
            if "error" in data:
                print(f"{node:<12} {'ERROR':<12} {'-':<6} {'-':<12} {'-':<10} {'-':<8}")
            else:
                state = data.get("state", "unknown").upper()
                term = data.get("term", 0)
                leader = data.get("leader_id", "None")
                elections = data.get("stats", {}).get("elections_participated", 0)
                uptime = f"{data.get('uptime', 0):.1f}s"
                
                print(f"{node:<12} {state:<12} {term:<6} {leader:<12} {elections:<10} {uptime:<8}")
    
    async def run_all_tests(self):
        """Run all test scenarios"""
        print("🧪 Leader Election Test Suite")
        print("=" * 60)
        
        # Initial status
        print("\n📊 Initial cluster status:")
        await self.print_cluster_status()
        
        # Wait for stabilization
        await asyncio.sleep(3)
        
        # Test scenarios
        await self.simulate_leader_failure()
        await asyncio.sleep(5)
        
        await self.test_network_partition()
        
        print("\n✅ All tests completed!")
    
    async def close(self):
        await self.client.aclose()

async def main():
    nodes = [f"localhost:800{i}" for i in range(1, 6)]
    tester = LeaderElectionTester(nodes)
    
    try:
        await tester.run_all_tests()
    finally:
        await tester.close()

if __name__ == "__main__":
    asyncio.run(main())
EOF

# Create README with instructions
cat > README.md << 'EOF'
# 🏛️ Leader Election Algorithm Demonstration

This demonstration implements a simplified Raft consensus algorithm to showcase leader election behavior in distributed systems.

## 🚀 Quick Start

### Method 1: Using Python (Local Development)
```bash
# Install dependencies
pip install -r requirements.txt

# Start 5-node cluster
python cluster.py

# Or specify custom number of nodes (minimum 3)
python cluster.py 7
```

### Method 2: Using Docker
```bash
# Build and run cluster
docker-compose up --build

# Or run individual nodes for testing
docker-compose --profile individual up
```

## 🌐 Accessing the Demonstration

Once started, you can access:

- **Node Dashboards**: http://localhost:8001, http://localhost:8002, etc.
- **Each dashboard shows**:
  - Current node state (Follower/Candidate/Leader)
  - Current term and leader information
  - Real-time statistics
  - Ability to simulate failures

## 🧪 Testing Scenarios

### Automated Tests
```bash
# Run comprehensive test suite
python test_scenarios.py
```

### Manual Testing
1. **Leader Election**: Watch initial leader emerge
2. **Leader Failure**: Click "Simulate Failure" on leader node
3. **Network Partitions**: Simulate failures on multiple nodes
4. **Recovery**: Watch cluster heal after failures

## 📊 Key Observations

### What to Watch For:

1. **Election Process**:
   - Randomized timeouts prevent election storms
   - Candidates request votes from all peers
   - Majority votes required for leadership

2. **Heartbeat Mechanism**:
   - Leaders send periodic heartbeats (100ms)
   - Followers reset election timeouts on heartbeat
   - Failed heartbeats trigger new elections

3. **Term Management**:
   - Terms increase with each election
   - Higher terms always win
   - Prevents split-brain scenarios

4. **Fault Tolerance**:
   - System continues with majority nodes
   - Automatic recovery after failures
   - Consistent state across cluster

## 🔧 Configuration

Key parameters (in `node.py`):
- `heartbeat_interval`: 100ms (how often leader sends heartbeats)
- `election_timeout`: 150-300ms randomized (when to start election)
- Ports: 8001-8005 (can be customized)

## 📈 Monitoring

Each node provides:
- Real-time state transitions
- Election statistics
- Network communication metrics
- Performance counters

## 🐛 Troubleshooting

**No leader elected**: Check if majority of nodes are running
**Frequent elections**: Network issues or timeout configuration
**Split brain**: Impossible due to majority vote requirement

## 🏗️ Architecture

The implementation includes:
- **Raft state machine**: Follower → Candidate → Leader
- **RPC communication**: Vote requests and heartbeats
- **Fault injection**: Simulate real-world failures
- **Web interface**: Real-time monitoring
- **Docker support**: Easy deployment

## 📚 Learning Outcomes

After running this demonstration, you'll understand:
- How distributed consensus works
- Why randomization prevents election storms
- How term numbers provide ordering
- Why majority votes prevent split-brain
- How systems heal after network partitions

## 🔗 Production Considerations

This demo simplifies several aspects for clarity:
- No persistent storage (logs reset on restart)
- No log replication (focus on leader election)
- Simplified network failure simulation
- No Byzantine fault tolerance

For production use, consider mature implementations like:
- HashiCorp Raft
- etcd Raft
- Consul Consensus

---

🎓 **Educational Note**: This implementation prioritizes clarity over performance. Real production systems include optimizations like batching, pipelining, and advanced failure detection.
EOF

# Make scripts executable
chmod +x test_scenarios.py

echo ""
echo "✅ Leader Election demonstration created successfully!"
echo ""
echo "📁 Project structure:"
echo "   - node.py: Core Raft node implementation"
echo "   - cluster.py: Cluster management script"
echo "   - test_scenarios.py: Automated testing scenarios"
echo "   - Dockerfile & docker-compose.yml: Container support"
echo "   - requirements.txt: Python dependencies"
echo "   - README.md: Detailed instructions"
echo ""
echo "🚀 To start the demonstration:"
echo ""
echo "   Method 1 (Python):"
echo "   $ cd $PROJECT_DIR"
echo "   $ pip install -r requirements.txt"
echo "   $ python cluster.py"
echo ""
echo "   Method 2 (Docker):"
echo "   $ cd $PROJECT_DIR"
echo "   $ docker-compose up --build"
echo ""
echo "🌐 Then visit: http://localhost:8001"
echo ""
echo "🧪 Run tests with: python test_scenarios.py"
echo ""
echo "📖 See README.md for detailed instructions and learning outcomes"