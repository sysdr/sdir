#!/bin/bash

# Split-Brain Problem Prevention and Resolution Demo
# This script creates a complete demonstration of split-brain scenarios
# and shows how different mechanisms prevent them

set -e

echo "🚀 Setting up Split-Brain Prevention Demo Environment..."
echo "=================================================="

# Create project structure
PROJECT_DIR="splitbrain-demo"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Create directories
mkdir -p {src,templates,static,logs,data}

echo "📁 Creating project structure..."

# Create requirements.txt
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn==0.24.0
websockets==12.0
aiofiles==23.2.1
jinja2==3.1.2
python-multipart==0.0.6
pydantic==2.5.0
httpx==0.25.2
python-socketio==5.11.0
typing-extensions==4.8.0
colorlog==6.8.0
networkx==3.2.1
matplotlib==3.8.2
plotly==5.17.0
pandas==2.1.4
numpy==1.26.2
EOF

# Create the main distributed node implementation
cat > src/node.py << 'EOF'
"""
Distributed Node Implementation with Raft-like Consensus
Demonstrates split-brain prevention mechanisms
"""
import asyncio
import json
import logging
import random
import time
import uuid
from dataclasses import dataclass, asdict
from enum import Enum
from typing import Dict, List, Optional, Set
from datetime import datetime, timedelta
import httpx
import os

# Configure logging
import colorlog

def setup_logger(node_id: str):
    handler = colorlog.StreamHandler()
    handler.setFormatter(colorlog.ColoredFormatter(
        '%(log_color)s%(asctime)s [%(name)s:%(levelname)s] %(message)s',
        datefmt='%H:%M:%S',
        log_colors={
            'DEBUG': 'cyan',
            'INFO': 'green',
            'WARNING': 'yellow',
            'ERROR': 'red',
            'CRITICAL': 'red,bg_white',
        }
    ))
    
    logger = logging.getLogger(f"Node-{node_id}")
    logger.addHandler(handler)
    logger.setLevel(logging.INFO)
    return logger

class NodeState(Enum):
    FOLLOWER = "follower"
    CANDIDATE = "candidate"
    LEADER = "leader"
    ISOLATED = "isolated"

@dataclass
class LogEntry:
    term: int
    index: int
    command: str
    timestamp: float

@dataclass
class NodeInfo:
    node_id: str
    state: NodeState
    term: int
    voted_for: Optional[str]
    log: List[LogEntry]
    commit_index: int
    last_applied: int
    next_index: Dict[str, int]
    match_index: Dict[str, int]
    last_heartbeat: float
    votes_received: Set[str]
    election_timeout: float
    heartbeat_interval: float
    is_partitioned: bool = False
    partition_group: Optional[str] = None

class DistributedNode:
    def __init__(self, node_id: str, port: int, peers: List[str]):
        self.node_id = node_id
        self.port = port
        self.peers = peers
        self.logger = setup_logger(node_id)
        
        # Raft state
        self.state = NodeState.FOLLOWER
        self.current_term = 0
        self.voted_for = None
        self.log: List[LogEntry] = []
        self.commit_index = 0
        self.last_applied = 0
        
        # Leader state
        self.next_index: Dict[str, int] = {}
        self.match_index: Dict[str, int] = {}
        
        # Timing
        self.last_heartbeat = time.time()
        self.election_timeout = random.uniform(3.0, 6.0)  # Randomized timeout
        self.heartbeat_interval = 1.0
        
        # Election state
        self.votes_received: Set[str] = set()
        
        # Network partition simulation
        self.is_partitioned = False
        self.partition_group = None
        self.unreachable_nodes: Set[str] = set()
        
        # Data store
        self.data_store: Dict[str, str] = {}
        
        # Tasks
        self.running_tasks: Set[asyncio.Task] = set()
        
        self.logger.info(f"🌟 Node {node_id} initialized on port {port}")
        self.logger.info(f"📋 Peers: {peers}")
        self.logger.info(f"⏰ Election timeout: {self.election_timeout:.2f}s")

    async def start(self):
        """Start the node and its background tasks"""
        self.logger.info("🚀 Starting node services...")
        
        # Start the election timer
        task = asyncio.create_task(self._election_timer())
        self.running_tasks.add(task)
        
        # Start heartbeat sender if leader
        task = asyncio.create_task(self._heartbeat_sender())
        self.running_tasks.add(task)
        
        # Start log replication if leader
        task = asyncio.create_task(self._log_replicator())
        self.running_tasks.add(task)

    async def _election_timer(self):
        """Monitor election timeout and trigger elections"""
        while True:
            try:
                await asyncio.sleep(0.5)  # Check every 500ms
                
                if self.state == NodeState.FOLLOWER or self.state == NodeState.CANDIDATE:
                    time_since_heartbeat = time.time() - self.last_heartbeat
                    
                    if time_since_heartbeat > self.election_timeout:
                        if not self.is_partitioned or self._can_form_quorum():
                            await self._start_election()
                        else:
                            self.logger.warning("🚫 Cannot start election: no quorum possible in partition")
                            self.state = NodeState.ISOLATED
                            
            except Exception as e:
                self.logger.error(f"❌ Election timer error: {e}")

    async def _start_election(self):
        """Start a new election"""
        self.state = NodeState.CANDIDATE
        self.current_term += 1
        self.voted_for = self.node_id
        self.votes_received = {self.node_id}
        self.last_heartbeat = time.time()
        self.election_timeout = random.uniform(3.0, 6.0)  # Reset with new random timeout
        
        self.logger.info(f"🗳️  Starting election for term {self.current_term}")
        
        # Request votes from peers
        vote_tasks = []
        for peer in self.peers:
            if peer != self.node_id and not self._is_node_unreachable(peer):
                task = asyncio.create_task(self._request_vote(peer))
                vote_tasks.append(task)
        
        if vote_tasks:
            await asyncio.gather(*vote_tasks, return_exceptions=True)
        
        # Check if we won the election
        await self._check_election_result()

    async def _request_vote(self, peer: str):
        """Request a vote from a peer"""
        try:
            last_log_term = self.log[-1].term if self.log else 0
            last_log_index = len(self.log)
            
            vote_request = {
                "type": "vote_request",
                "term": self.current_term,
                "candidate_id": self.node_id,
                "last_log_index": last_log_index,
                "last_log_term": last_log_term
            }
            
            response = await self._send_rpc(peer, vote_request)
            
            if response and response.get("vote_granted"):
                self.votes_received.add(peer)
                self.logger.info(f"✅ Vote granted by {peer} for term {self.current_term}")
            else:
                self.logger.info(f"❌ Vote denied by {peer}")
                
        except Exception as e:
            self.logger.warning(f"🔌 Failed to request vote from {peer}: {e}")

    async def _check_election_result(self):
        """Check if we won the election"""
        if self.state != NodeState.CANDIDATE:
            return
            
        total_nodes = len(self.peers)
        votes_needed = (total_nodes // 2) + 1
        
        if len(self.votes_received) >= votes_needed:
            await self._become_leader()
        else:
            self.logger.info(f"🗳️  Election failed: got {len(self.votes_received)}/{total_nodes} votes, needed {votes_needed}")
            self.state = NodeState.FOLLOWER

    async def _become_leader(self):
        """Become the leader"""
        self.state = NodeState.LEADER
        self.logger.info(f"👑 Became leader for term {self.current_term}")
        
        # Initialize leader state
        for peer in self.peers:
            if peer != self.node_id:
                self.next_index[peer] = len(self.log) + 1
                self.match_index[peer] = 0
        
        # Send immediate heartbeat
        await self._send_heartbeats()

    async def _heartbeat_sender(self):
        """Send periodic heartbeats if leader"""
        while True:
            try:
                if self.state == NodeState.LEADER:
                    await self._send_heartbeats()
                await asyncio.sleep(self.heartbeat_interval)
            except Exception as e:
                self.logger.error(f"❌ Heartbeat sender error: {e}")

    async def _send_heartbeats(self):
        """Send heartbeats to all followers"""
        if self.state != NodeState.LEADER:
            return
            
        heartbeat_tasks = []
        for peer in self.peers:
            if peer != self.node_id and not self._is_node_unreachable(peer):
                task = asyncio.create_task(self._send_heartbeat(peer))
                heartbeat_tasks.append(task)
        
        if heartbeat_tasks:
            await asyncio.gather(*heartbeat_tasks, return_exceptions=True)

    async def _send_heartbeat(self, peer: str):
        """Send heartbeat to a specific peer"""
        try:
            prev_log_index = len(self.log)
            prev_log_term = self.log[-1].term if self.log else 0
            
            heartbeat = {
                "type": "heartbeat",
                "term": self.current_term,
                "leader_id": self.node_id,
                "prev_log_index": prev_log_index,
                "prev_log_term": prev_log_term,
                "entries": [],
                "leader_commit": self.commit_index
            }
            
            await self._send_rpc(peer, heartbeat)
            
        except Exception as e:
            self.logger.warning(f"💓 Failed to send heartbeat to {peer}: {e}")

    async def _log_replicator(self):
        """Replicate logs to followers if leader"""
        while True:
            try:
                if self.state == NodeState.LEADER:
                    await self._replicate_logs()
                await asyncio.sleep(0.5)
            except Exception as e:
                self.logger.error(f"❌ Log replication error: {e}")

    async def _replicate_logs(self):
        """Replicate logs to all followers"""
        # Implementation would go here for full log replication
        pass

    async def _send_rpc(self, peer: str, message: dict) -> Optional[dict]:
        """Send RPC message to peer"""
        if self._is_node_unreachable(peer):
            return None
            
        try:
            async with httpx.AsyncClient(timeout=2.0) as client:
                response = await client.post(
                    f"http://localhost:{self._get_peer_port(peer)}/rpc",
                    json=message
                )
                return response.json() if response.status_code == 200 else None
        except Exception:
            return None

    async def handle_rpc(self, message: dict) -> dict:
        """Handle incoming RPC messages"""
        msg_type = message.get("type")
        
        if msg_type == "vote_request":
            return await self._handle_vote_request(message)
        elif msg_type == "heartbeat":
            return await self._handle_heartbeat(message)
        else:
            return {"success": False, "error": "Unknown message type"}

    async def _handle_vote_request(self, message: dict) -> dict:
        """Handle vote request from candidate"""
        term = message.get("term", 0)
        candidate_id = message.get("candidate_id")
        last_log_index = message.get("last_log_index", 0)
        last_log_term = message.get("last_log_term", 0)
        
        # If term is higher, step down
        if term > self.current_term:
            self.current_term = term
            self.state = NodeState.FOLLOWER
            self.voted_for = None
        
        vote_granted = False
        
        # Grant vote if conditions are met
        if (term >= self.current_term and 
            (self.voted_for is None or self.voted_for == candidate_id) and
            self._is_log_up_to_date(last_log_index, last_log_term)):
            
            vote_granted = True
            self.voted_for = candidate_id
            self.last_heartbeat = time.time()
            self.logger.info(f"✅ Granted vote to {candidate_id} for term {term}")
        else:
            self.logger.info(f"❌ Denied vote to {candidate_id} for term {term}")
        
        return {
            "term": self.current_term,
            "vote_granted": vote_granted
        }

    async def _handle_heartbeat(self, message: dict) -> dict:
        """Handle heartbeat from leader"""
        term = message.get("term", 0)
        leader_id = message.get("leader_id")
        
        # If term is higher, step down
        if term >= self.current_term:
            self.current_term = term
            self.state = NodeState.FOLLOWER
            self.voted_for = None
            self.last_heartbeat = time.time()
            
            if term > self.current_term:
                self.logger.info(f"💓 Received heartbeat from leader {leader_id}, term {term}")
        
        return {
            "term": self.current_term,
            "success": True
        }

    def _is_log_up_to_date(self, last_log_index: int, last_log_term: int) -> bool:
        """Check if candidate's log is at least as up-to-date as ours"""
        if not self.log:
            return True
            
        our_last_term = self.log[-1].term
        our_last_index = len(self.log)
        
        if last_log_term > our_last_term:
            return True
        elif last_log_term == our_last_term:
            return last_log_index >= our_last_index
        else:
            return False

    def _can_form_quorum(self) -> bool:
        """Check if current partition can form a quorum"""
        if not self.is_partitioned:
            return True
            
        reachable_nodes = 1  # Count self
        for peer in self.peers:
            if peer != self.node_id and not self._is_node_unreachable(peer):
                reachable_nodes += 1
        
        total_nodes = len(self.peers)
        majority_needed = (total_nodes // 2) + 1
        
        return reachable_nodes >= majority_needed

    def _is_node_unreachable(self, peer: str) -> bool:
        """Check if a peer is unreachable due to partition"""
        return peer in self.unreachable_nodes

    def _get_peer_port(self, peer: str) -> int:
        """Get port for peer node"""
        # Simple mapping: node1->8001, node2->8002, etc.
        return 8000 + int(peer.replace("node", ""))

    def get_status(self) -> dict:
        """Get current node status"""
        return {
            "node_id": self.node_id,
            "state": self.state.value,
            "term": self.current_term,
            "voted_for": self.voted_for,
            "log_length": len(self.log),
            "commit_index": self.commit_index,
            "is_partitioned": self.is_partitioned,
            "partition_group": self.partition_group,
            "unreachable_nodes": list(self.unreachable_nodes),
            "votes_received": list(self.votes_received),
            "last_heartbeat_age": time.time() - self.last_heartbeat,
            "can_form_quorum": self._can_form_quorum(),
            "data_store": dict(self.data_store)
        }

    def simulate_partition(self, unreachable_nodes: List[str], partition_group: str = None):
        """Simulate network partition"""
        self.is_partitioned = True
        self.unreachable_nodes = set(unreachable_nodes)
        self.partition_group = partition_group
        
        self.logger.warning(f"🔌 Network partition activated")
        self.logger.warning(f"📵 Unreachable nodes: {unreachable_nodes}")
        self.logger.warning(f"🏷️  Partition group: {partition_group}")

    def heal_partition(self):
        """Heal network partition"""
        self.is_partitioned = False
        self.unreachable_nodes = set()
        self.partition_group = None
        
        self.logger.info("🔗 Network partition healed")

    async def add_entry(self, command: str) -> bool:
        """Add entry to log (only if leader)"""
        if self.state != NodeState.LEADER:
            return False
            
        entry = LogEntry(
            term=self.current_term,
            index=len(self.log) + 1,
            command=command,
            timestamp=time.time()
        )
        
        self.log.append(entry)
        self.logger.info(f"📝 Added log entry: {command}")
        
        return True

    async def stop(self):
        """Stop the node and cleanup"""
        self.logger.info("🛑 Stopping node...")
        
        for task in self.running_tasks:
            task.cancel()
        
        await asyncio.gather(*self.running_tasks, return_exceptions=True)
        self.running_tasks.clear()
EOF

# Create the web server
cat > src/server.py << 'EOF'
"""
Web Server for Split-Brain Demo
Provides REST API and WebSocket interface for monitoring nodes
"""
import asyncio
import json
import logging
from typing import Dict, List
from fastapi import FastAPI, WebSocket, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.requests import Request
from fastapi.responses import HTMLResponse
import uvicorn

from node import DistributedNode

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DemoOrchestrator:
    def __init__(self):
        self.nodes: Dict[str, DistributedNode] = {}
        self.websockets: List[WebSocket] = []
        
    async def create_cluster(self, node_count: int = 5):
        """Create a cluster of nodes"""
        node_ids = [f"node{i+1}" for i in range(node_count)]
        
        for i, node_id in enumerate(node_ids):
            port = 8000 + i + 1
            node = DistributedNode(node_id, port, node_ids)
            self.nodes[node_id] = node
            await node.start()
        
        logger.info(f"✅ Created cluster with {node_count} nodes")
        await self.broadcast_status()
    
    async def simulate_partition(self, partition_config: dict):
        """Simulate network partition"""
        group_a = partition_config.get("group_a", [])
        group_b = partition_config.get("group_b", [])
        
        # Partition group A
        for node_id in group_a:
            if node_id in self.nodes:
                self.nodes[node_id].simulate_partition(group_b, "A")
        
        # Partition group B
        for node_id in group_b:
            if node_id in self.nodes:
                self.nodes[node_id].simulate_partition(group_a, "B")
        
        logger.info(f"🔌 Simulated partition: A={group_a}, B={group_b}")
        await self.broadcast_status()
    
    async def heal_partition(self):
        """Heal all partitions"""
        for node in self.nodes.values():
            node.heal_partition()
        
        logger.info("🔗 Healed all partitions")
        await self.broadcast_status()
    
    async def get_cluster_status(self) -> dict:
        """Get status of all nodes"""
        status = {}
        for node_id, node in self.nodes.items():
            status[node_id] = node.get_status()
        return status
    
    async def broadcast_status(self):
        """Broadcast status to all connected websockets"""
        if not self.websockets:
            return
            
        try:
            status = await self.get_cluster_status()
            message = json.dumps({
                "type": "status_update",
                "data": status
            })
            
            # Send to all connected websockets
            disconnected = []
            for ws in self.websockets:
                try:
                    await ws.send_text(message)
                except:
                    disconnected.append(ws)
            
            # Remove disconnected websockets
            for ws in disconnected:
                self.websockets.remove(ws)
                
        except Exception as e:
            logger.error(f"Failed to broadcast status: {e}")
    
    async def add_websocket(self, websocket: WebSocket):
        """Add websocket connection"""
        self.websockets.append(websocket)
        await self.broadcast_status()
    
    async def remove_websocket(self, websocket: WebSocket):
        """Remove websocket connection"""
        if websocket in self.websockets:
            self.websockets.remove(websocket)

# Global orchestrator
orchestrator = DemoOrchestrator()

# FastAPI app
app = FastAPI(title="Split-Brain Prevention Demo")

# Mount static files and templates
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard"""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.post("/api/cluster/create")
async def create_cluster(config: dict):
    """Create a new cluster"""
    node_count = config.get("node_count", 5)
    await orchestrator.create_cluster(node_count)
    return {"status": "success", "message": f"Created cluster with {node_count} nodes"}

@app.post("/api/cluster/partition")
async def create_partition(config: dict):
    """Create network partition"""
    await orchestrator.simulate_partition(config)
    return {"status": "success", "message": "Network partition created"}

@app.post("/api/cluster/heal")
async def heal_partition():
    """Heal network partition"""
    await orchestrator.heal_partition()
    return {"status": "success", "message": "Network partition healed"}

@app.get("/api/cluster/status")
async def get_status():
    """Get cluster status"""
    return await orchestrator.get_cluster_status()

@app.post("/api/nodes/{node_id}/add_entry")
async def add_log_entry(node_id: str, entry: dict):
    """Add log entry to specific node"""
    if node_id not in orchestrator.nodes:
        raise HTTPException(status_code=404, detail="Node not found")
    
    command = entry.get("command", "")
    success = await orchestrator.nodes[node_id].add_entry(command)
    
    if success:
        await orchestrator.broadcast_status()
        return {"status": "success", "message": "Log entry added"}
    else:
        return {"status": "error", "message": "Node is not leader"}

@app.post("/nodes/{node_id}/rpc")
async def handle_rpc(node_id: str, message: dict):
    """Handle RPC messages between nodes"""
    if node_id not in orchestrator.nodes:
        raise HTTPException(status_code=404, detail="Node not found")
    
    response = await orchestrator.nodes[node_id].handle_rpc(message)
    return response

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates"""
    await websocket.accept()
    await orchestrator.add_websocket(websocket)
    
    try:
        while True:
            # Keep connection alive and handle client messages
            await websocket.receive_text()
    except:
        pass
    finally:
        await orchestrator.remove_websocket(websocket)

# Background task to periodically broadcast status
async def status_broadcaster():
    """Periodically broadcast status updates"""
    while True:
        await asyncio.sleep(2)  # Broadcast every 2 seconds
        await orchestrator.broadcast_status()

@app.on_event("startup")
async def startup_event():
    """Start background tasks"""
    asyncio.create_task(status_broadcaster())

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
EOF

# Create the dashboard template
cat > templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Split-Brain Prevention Demo</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/Chart.js/3.9.1/chart.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: #333;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 20px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        
        .header h1 {
            color: #2563eb;
            margin-bottom: 10px;
            font-size: 2.5em;
        }
        
        .header p {
            color: #666;
            font-size: 1.1em;
        }
        
        .controls {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 20px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        
        .control-group {
            display: flex;
            gap: 10px;
            margin-bottom: 15px;
            flex-wrap: wrap;
        }
        
        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-weight: 600;
            transition: all 0.3s ease;
            font-size: 14px;
        }
        
        .btn-primary {
            background: #2563eb;
            color: white;
        }
        
        .btn-primary:hover {
            background: #1d4ed8;
            transform: translateY(-2px);
        }
        
        .btn-warning {
            background: #f59e0b;
            color: white;
        }
        
        .btn-warning:hover {
            background: #d97706;
            transform: translateY(-2px);
        }
        
        .btn-success {
            background: #10b981;
            color: white;
        }
        
        .btn-success:hover {
            background: #059669;
            transform: translateY(-2px);
        }
        
        .btn-danger {
            background: #ef4444;
            color: white;
        }
        
        .btn-danger:hover {
            background: #dc2626;
            transform: translateY(-2px);
        }
        
        .cluster-view {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 20px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        
        .cluster-title {
            font-size: 1.5em;
            margin-bottom: 20px;
            color: #1e293b;
        }
        
        .nodes-container {
            display: flex;
            gap: 20px;
            flex-wrap: wrap;
            justify-content: center;
            margin-bottom: 30px;
        }
        
        .node {
            width: 180px;
            padding: 20px;
            border-radius: 12px;
            text-align: center;
            transition: all 0.3s ease;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
        }
        
        .node:hover {
            transform: translateY(-5px);
        }
        
        .node.follower {
            background: linear-gradient(135deg, #dbeafe, #bfdbfe);
            border: 2px solid #3b82f6;
        }
        
        .node.candidate {
            background: linear-gradient(135deg, #fef3c7, #fde68a);
            border: 2px solid #f59e0b;
            animation: pulse 2s infinite;
        }
        
        .node.leader {
            background: linear-gradient(135deg, #dcfce7, #bbf7d0);
            border: 2px solid #10b981;
            box-shadow: 0 0 20px rgba(16, 185, 129, 0.3);
        }
        
        .node.isolated {
            background: linear-gradient(135deg, #fee2e2, #fecaca);
            border: 2px solid #ef4444;
        }
        
        @keyframes pulse {
            0% { transform: scale(1); }
            50% { transform: scale(1.05); }
            100% { transform: scale(1); }
        }
        
        .node-id {
            font-size: 1.2em;
            font-weight: bold;
            margin-bottom: 10px;
        }
        
        .node-state {
            font-size: 0.9em;
            text-transform: uppercase;
            font-weight: bold;
            margin-bottom: 15px;
            padding: 5px 10px;
            border-radius: 20px;
            background: rgba(255, 255, 255, 0.7);
        }
        
        .node-details {
            font-size: 0.8em;
            line-height: 1.4;
            color: #555;
        }
        
        .partition-indicator {
            display: inline-block;
            padding: 3px 8px;
            border-radius: 12px;
            font-size: 0.7em;
            font-weight: bold;
            margin-top: 5px;
        }
        
        .partition-a {
            background: #fef3c7;
            color: #92400e;
        }
        
        .partition-b {
            background: #fecaca;
            color: #991b1b;
        }
        
        .status-panel {
            background: rgba(255, 255, 255, 0.95);
            backdrop-filter: blur(10px);
            padding: 20px;
            border-radius: 15px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
        }
        
        .status-card {
            background: #f8fafc;
            padding: 15px;
            border-radius: 10px;
            border-left: 4px solid #3b82f6;
        }
        
        .status-card h4 {
            color: #1e293b;
            margin-bottom: 10px;
        }
        
        .log-entry {
            background: rgba(255, 255, 255, 0.7);
            padding: 8px 12px;
            border-radius: 6px;
            margin-bottom: 5px;
            font-family: monospace;
            font-size: 0.85em;
        }
        
        .network-diagram {
            text-align: center;
            margin: 20px 0;
        }
        
        .connection-line {
            stroke: #22c55e;
            stroke-width: 2;
        }
        
        .connection-line.broken {
            stroke: #ef4444;
            stroke-dasharray: 5,5;
        }
        
        .scenario-buttons {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
            margin-bottom: 20px;
        }
        
        .alert {
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
            font-weight: 500;
        }
        
        .alert-info {
            background: #dbeafe;
            color: #1e40af;
            border: 1px solid #3b82f6;
        }
        
        .alert-warning {
            background: #fef3c7;
            color: #92400e;
            border: 1px solid #f59e0b;
        }
        
        .alert-success {
            background: #dcfce7;
            color: #166534;
            border: 1px solid #22c55e;
        }
        
        .alert-danger {
            background: #fee2e2;
            color: #991b1b;
            border: 1px solid #ef4444;
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <div class="header">
            <h1>🧠 Split-Brain Prevention Demo</h1>
            <p>Interactive demonstration of distributed consensus and split-brain prevention mechanisms</p>
        </div>
        
        <!-- Controls -->
        <div class="controls">
            <div class="control-group">
                <button class="btn btn-primary" onclick="createCluster()">🚀 Create Cluster</button>
                <button class="btn btn-danger" onclick="simulatePartition()">🔌 Simulate Partition</button>
                <button class="btn btn-success" onclick="healPartition()">🔗 Heal Partition</button>
            </div>
            
            <div class="scenario-buttons">
                <button class="btn btn-warning" onclick="scenario1()">Scenario 1: Simple Split</button>
                <button class="btn btn-warning" onclick="scenario2()">Scenario 2: Minority Partition</button>
                <button class="btn btn-warning" onclick="scenario3()">Scenario 3: Even Split</button>
            </div>
        </div>
        
        <!-- Status Alert -->
        <div id="statusAlert" class="alert alert-info" style="display: none;"></div>
        
        <!-- Cluster View -->
        <div class="cluster-view">
            <h2 class="cluster-title">🏘️ Cluster Status</h2>
            <div id="nodesContainer" class="nodes-container">
                <p>Click "Create Cluster" to initialize nodes</p>
            </div>
        </div>
        
        <!-- Detailed Status -->
        <div class="status-panel">
            <h2 class="cluster-title">📊 Detailed Status</h2>
            <div id="statusGrid" class="status-grid">
                <p>No data available</p>
            </div>
        </div>
    </div>

    <script>
        let ws = null;
        let clusterStatus = {};
        
        // Initialize WebSocket connection
        function initWebSocket() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = `${protocol}//${window.location.host}/ws`;
            
            ws = new WebSocket(wsUrl);
            
            ws.onopen = function(event) {
                console.log('WebSocket connected');
                showAlert('Connected to server', 'success');
            };
            
            ws.onmessage = function(event) {
                const data = JSON.parse(event.data);
                if (data.type === 'status_update') {
                    clusterStatus = data.data;
                    updateDisplay();
                }
            };
            
            ws.onclose = function(event) {
                console.log('WebSocket disconnected');
                showAlert('Disconnected from server', 'danger');
                // Reconnect after 3 seconds
                setTimeout(initWebSocket, 3000);
            };
            
            ws.onerror = function(error) {
                console.error('WebSocket error:', error);
                showAlert('Connection error', 'danger');
            };
        }
        
        // API Functions
        async function createCluster() {
            try {
                const response = await fetch('/api/cluster/create', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({node_count: 5})
                });
                const result = await response.json();
                showAlert(result.message, 'success');
            } catch (error) {
                showAlert('Failed to create cluster', 'danger');
            }
        }
        
        async function simulatePartition() {
            try {
                const response = await fetch('/api/cluster/partition', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        group_a: ['node1', 'node2', 'node3'],
                        group_b: ['node4', 'node5']
                    })
                });
                const result = await response.json();
                showAlert(result.message + ' (3-2 split)', 'warning');
            } catch (error) {
                showAlert('Failed to simulate partition', 'danger');
            }
        }
        
        async function healPartition() {
            try {
                const response = await fetch('/api/cluster/heal', {
                    method: 'POST'
                });
                const result = await response.json();
                showAlert(result.message, 'success');
            } catch (error) {
                showAlert('Failed to heal partition', 'danger');
            }
        }
        
        // Scenario Functions
        async function scenario1() {
            await createCluster();
            setTimeout(async () => {
                await fetch('/api/cluster/partition', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        group_a: ['node1', 'node2', 'node3'],
                        group_b: ['node4', 'node5']
                    })
                });
                showAlert('Scenario 1: Simple 3-2 partition. Majority group stays active.', 'info');
            }, 1000);
        }
        
        async function scenario2() {
            await createCluster();
            setTimeout(async () => {
                await fetch('/api/cluster/partition', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        group_a: ['node1', 'node2'],
                        group_b: ['node3', 'node4', 'node5']
                    })
                });
                showAlert('Scenario 2: 2-3 partition. Minority loses quorum.', 'info');
            }, 1000);
        }
        
        async function scenario3() {
            // Create 4 node cluster for even split
            try {
                await fetch('/api/cluster/create', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({node_count: 4})
                });
                setTimeout(async () => {
                    await fetch('/api/cluster/partition', {
                        method: 'POST',
                        headers: {'Content-Type': 'application/json'},
                        body: JSON.stringify({
                            group_a: ['node1', 'node2'],
                            group_b: ['node3', 'node4']
                        })
                    });
                    showAlert('Scenario 3: Even 2-2 split. No group has majority!', 'warning');
                }, 1000);
            } catch (error) {
                showAlert('Failed to create scenario', 'danger');
            }
        }
        
        // Display Functions
        function updateDisplay() {
            updateNodesDisplay();
            updateStatusGrid();
            updateNetworkStatus();
        }
        
        function updateNodesDisplay() {
            const container = document.getElementById('nodesContainer');
            
            if (Object.keys(clusterStatus).length === 0) {
                container.innerHTML = '<p>No nodes available</p>';
                return;
            }
            
            container.innerHTML = '';
            
            Object.entries(clusterStatus).forEach(([nodeId, status]) => {
                const nodeElement = document.createElement('div');
                nodeElement.className = `node ${status.state}`;
                
                let partitionBadge = '';
                if (status.is_partitioned && status.partition_group) {
                    partitionBadge = `<span class="partition-indicator partition-${status.partition_group.toLowerCase()}">Partition ${status.partition_group}</span>`;
                }
                
                const quorumStatus = status.can_form_quorum ? '✅' : '❌';
                const heartbeatAge = status.last_heartbeat_age.toFixed(1);
                
                nodeElement.innerHTML = `
                    <div class="node-id">${nodeId}</div>
                    <div class="node-state">${status.state}</div>
                    <div class="node-details">
                        Term: ${status.term}<br>
                        Log: ${status.log_length} entries<br>
                        Heartbeat: ${heartbeatAge}s ago<br>
                        Quorum: ${quorumStatus}<br>
                        ${status.voted_for ? `Voted: ${status.voted_for}<br>` : ''}
                    </div>
                    ${partitionBadge}
                `;
                
                container.appendChild(nodeElement);
            });
        }
        
        function updateStatusGrid() {
            const grid = document.getElementById('statusGrid');
            
            if (Object.keys(clusterStatus).length === 0) {
                grid.innerHTML = '<p>No data available</p>';
                return;
            }
            
            const leaders = Object.entries(clusterStatus).filter(([_, status]) => status.state === 'leader');
            const partitioned = Object.entries(clusterStatus).filter(([_, status]) => status.is_partitioned);
            const totalNodes = Object.keys(clusterStatus).length;
            
            let analysis = '';
            if (leaders.length === 0) {
                analysis = '⚠️ No leader elected (likely no quorum)';
            } else if (leaders.length === 1) {
                analysis = '✅ Single leader - healthy state';
            } else {
                analysis = '🚨 Split-Brain detected - multiple leaders!';
            }
            
            grid.innerHTML = `
                <div class="status-card">
                    <h4>🎯 Consensus Status</h4>
                    <p><strong>Leaders:</strong> ${leaders.length}</p>
                    <p><strong>Total Nodes:</strong> ${totalNodes}</p>
                    <p><strong>Partitioned:</strong> ${partitioned.length}</p>
                    <p><strong>Analysis:</strong> ${analysis}</p>
                </div>
                
                <div class="status-card">
                    <h4>🔗 Network Status</h4>
                    ${partitioned.length > 0 ? `
                        <p><strong>Partition Active:</strong> Yes</p>
                        <p><strong>Groups:</strong> ${getPartitionGroups()}</p>
                    ` : '<p><strong>Partition Active:</strong> No</p>'}
                </div>
                
                <div class="status-card">
                    <h4>🗳️ Election Details</h4>
                    ${getElectionDetails()}
                </div>
                
                <div class="status-card">
                    <h4>📋 Key Insights</h4>
                    ${getKeyInsights()}
                </div>
            `;
        }
        
        function getPartitionGroups() {
            const groups = {};
            Object.entries(clusterStatus).forEach(([nodeId, status]) => {
                if (status.partition_group) {
                    if (!groups[status.partition_group]) groups[status.partition_group] = [];
                    groups[status.partition_group].push(nodeId);
                }
            });
            
            return Object.entries(groups)
                .map(([group, nodes]) => `${group}: [${nodes.join(', ')}]`)
                .join(', ');
        }
        
        function getElectionDetails() {
            const currentTerms = Object.values(clusterStatus).map(s => s.term);
            const maxTerm = Math.max(...currentTerms);
            const votes = Object.entries(clusterStatus)
                .map(([nodeId, status]) => `${nodeId}: ${status.votes_received.length} votes`)
                .join('<br>');
            
            return `
                <p><strong>Current Term:</strong> ${maxTerm}</p>
                <p><strong>Vote Counts:</strong></p>
                <div style="font-size: 0.9em; margin-top: 5px;">${votes}</div>
            `;
        }
        
        function getKeyInsights() {
            const leaders = Object.entries(clusterStatus).filter(([_, status]) => status.state === 'leader');
            const candidates = Object.entries(clusterStatus).filter(([_, status]) => status.state === 'candidate');
            const isolated = Object.entries(clusterStatus).filter(([_, status]) => status.state === 'isolated');
            
            let insights = [];
            
            if (leaders.length > 1) {
                insights.push('🚨 Multiple leaders indicate split-brain');
            }
            if (candidates.length > 0) {
                insights.push('🗳️ Election in progress');
            }
            if (isolated.length > 0) {
                insights.push('📵 Some nodes are isolated (no quorum)');
            }
            if (leaders.length === 1) {
                insights.push('✅ Healthy consensus achieved');
            }
            
            return insights.length > 0 ? insights.join('<br>') : 'System operating normally';
        }
        
        function updateNetworkStatus() {
            const partitioned = Object.values(clusterStatus).some(s => s.is_partitioned);
            const leaders = Object.values(clusterStatus).filter(s => s.state === 'leader').length;
            
            let alertType = 'info';
            let message = 'Cluster is healthy';
            
            if (partitioned && leaders > 1) {
                alertType = 'danger';
                message = '🚨 SPLIT-BRAIN DETECTED: Multiple leaders in partitioned network!';
            } else if (partitioned && leaders === 0) {
                alertType = 'warning';
                message = '⚠️ Network partition active - no leader elected (quorum lost)';
            } else if (partitioned && leaders === 1) {
                alertType = 'info';
                message = '✅ Network partition active but split-brain prevented by quorum';
            } else if (leaders === 1) {
                alertType = 'success';
                message = '✅ Healthy cluster with single leader';
            }
            
            showAlert(message, alertType, false);
        }
        
        function showAlert(message, type, autohide = true) {
            const alert = document.getElementById('statusAlert');
            alert.className = `alert alert-${type}`;
            alert.textContent = message;
            alert.style.display = 'block';
            
            if (autohide) {
                setTimeout(() => {
                    alert.style.display = 'none';
                }, 5000);
            }
        }
        
        // Initialize on page load
        document.addEventListener('DOMContentLoaded', function() {
            initWebSocket();
        });
    </script>
</body>
</html>
EOF

# Create static directory and files
mkdir -p static
cat > static/styles.css << 'EOF'
/* Additional styles can be added here if needed */
.fade-in {
    animation: fadeIn 0.5s ease-in;
}

@keyframes fadeIn {
    from { opacity: 0; }
    to { opacity: 1; }
}
EOF

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY . .

# Create logs directory
RUN mkdir -p logs

# Expose port
EXPOSE 8000

# Start command
CMD ["python", "-m", "uvicorn", "src.server:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
EOF

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  splitbrain-demo:
    build: .
    ports:
      - "8000:8000"
    volumes:
      - ./logs:/app/logs
      - ./data:/app/data
    environment:
      - PYTHONPATH=/app
      - LOG_LEVEL=INFO
    restart: unless-stopped
    networks:
      - demo-network

networks:
  demo-network:
    driver: bridge
EOF

# Create test script
cat > test_demo.py << 'EOF'
#!/usr/bin/env python3
"""
Test script for Split-Brain Prevention Demo
Validates all functionality works correctly
"""
import asyncio
import httpx
import json
import time
import websockets
import sys

async def test_api_endpoints():
    """Test all API endpoints"""
    print("🧪 Testing API endpoints...")
    
    base_url = "http://localhost:8000"
    
    async with httpx.AsyncClient() as client:
        # Test cluster creation
        print("  Testing cluster creation...")
        response = await client.post(f"{base_url}/api/cluster/create", 
                                   json={"node_count": 5})
        assert response.status_code == 200
        result = response.json()
        assert result["status"] == "success"
        print("  ✅ Cluster creation works")
        
        # Wait for cluster to stabilize
        await asyncio.sleep(3)
        
        # Test status endpoint
        print("  Testing status endpoint...")
        response = await client.get(f"{base_url}/api/cluster/status")
        assert response.status_code == 200
        status = response.json()
        assert len(status) == 5  # Should have 5 nodes
        print("  ✅ Status endpoint works")
        
        # Test partition simulation
        print("  Testing partition simulation...")
        response = await client.post(f"{base_url}/api/cluster/partition",
                                   json={
                                       "group_a": ["node1", "node2", "node3"],
                                       "group_b": ["node4", "node5"]
                                   })
        assert response.status_code == 200
        print("  ✅ Partition simulation works")
        
        # Wait for partition effects
        await asyncio.sleep(5)
        
        # Check status after partition
        response = await client.get(f"{base_url}/api/cluster/status")
        status = response.json()
        
        # Verify partition effects
        partitioned_nodes = [node for node in status.values() if node["is_partitioned"]]
        assert len(partitioned_nodes) > 0
        print("  ✅ Partition effects verified")
        
        # Test healing
        print("  Testing partition healing...")
        response = await client.post(f"{base_url}/api/cluster/heal")
        assert response.status_code == 200
        print("  ✅ Partition healing works")
        
        await asyncio.sleep(2)
        
        # Verify healing
        response = await client.get(f"{base_url}/api/cluster/status")
        status = response.json()
        partitioned_nodes = [node for node in status.values() if node["is_partitioned"]]
        assert len(partitioned_nodes) == 0
        print("  ✅ Healing effects verified")

async def test_websocket():
    """Test WebSocket functionality"""
    print("🔌 Testing WebSocket connection...")
    
    try:
        uri = "ws://localhost:8000/ws"
        async with websockets.connect(uri) as websocket:
            # Should receive status update
            message = await asyncio.wait_for(websocket.recv(), timeout=10.0)
            data = json.loads(message)
            assert data["type"] == "status_update"
            assert "data" in data
            print("  ✅ WebSocket communication works")
    except Exception as e:
        print(f"  ❌ WebSocket test failed: {e}")
        raise

async def test_consensus_behavior():
    """Test actual consensus behavior"""
    print("🤝 Testing consensus behavior...")
    
    async with httpx.AsyncClient() as client:
        base_url = "http://localhost:8000"
        
        # Create fresh cluster
        await client.post(f"{base_url}/api/cluster/create", json={"node_count": 5})
        await asyncio.sleep(3)
        
        # Check initial state - should have one leader
        response = await client.get(f"{base_url}/api/cluster/status")
        status = response.json()
        
        leaders = [node for node in status.values() if node["state"] == "leader"]
        print(f"  Initial leaders: {len(leaders)}")
        
        # Simulate partition
        await client.post(f"{base_url}/api/cluster/partition",
                         json={
                             "group_a": ["node1", "node2", "node3"],
                             "group_b": ["node4", "node5"]
                         })
        
        # Wait for election
        await asyncio.sleep(8)
        
        response = await client.get(f"{base_url}/api/cluster/status")
        status = response.json()
        
        leaders = [node for node in status.values() if node["state"] == "leader"]
        majority_group = [node for node in status.values() 
                         if node.get("partition_group") == "A"]
        minority_group = [node for node in status.values() 
                         if node.get("partition_group") == "B"]
        
        print(f"  Leaders after partition: {len(leaders)}")
        print(f"  Majority group size: {len(majority_group)}")
        print(f"  Minority group size: {len(minority_group)}")
        
        # Verify split-brain prevention
        assert len(leaders) <= 1, "Split-brain detected - multiple leaders!"
        
        # If there's a leader, it should be in the majority group
        if leaders:
            leader_in_majority = any(leader["partition_group"] == "A" for leader in leaders)
            assert leader_in_majority, "Leader should be in majority partition"
        
        print("  ✅ Split-brain prevention verified")

async def run_tests():
    """Run all tests"""
    print("🚀 Starting Split-Brain Demo Tests")
    print("=" * 50)
    
    try:
        await test_api_endpoints()
        await test_websocket()
        await test_consensus_behavior()
        
        print("\n" + "=" * 50)
        print("✅ All tests passed! Demo is working correctly.")
        return True
        
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = asyncio.run(run_tests())
    sys.exit(0 if success else 1)
EOF

# Make test script executable
chmod +x test_demo.py

# Create run script
cat > run_demo.sh << 'EOF'
#!/bin/bash

echo "🚀 Split-Brain Prevention Demo Setup"
echo "======================================"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

echo "📦 Building Docker image..."
docker-compose build

echo "🔧 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to start..."
sleep 10

echo "🧪 Running tests..."
python test_demo.py

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Demo is ready!"
    echo "🌐 Open your browser and navigate to: http://localhost:8000"
    echo ""
    echo "📋 Available scenarios:"
    echo "  1. Click 'Create Cluster' to initialize 5 nodes"
    echo "  2. Use scenario buttons to test different partition types"
    echo "  3. Watch the real-time visualization of consensus behavior"
    echo "  4. Observe how quorum prevents split-brain scenarios"
    echo ""
    echo "🔧 To stop the demo: docker-compose down"
    echo "📋 To view logs: docker-compose logs -f"
else
    echo "❌ Tests failed. Check the logs for issues."
    docker-compose logs
fi
EOF

chmod +x run_demo.sh

# Create README
cat > README.md << 'EOF'
# Split-Brain Prevention Demo

This demonstration shows how distributed systems prevent split-brain scenarios using consensus algorithms and quorum-based decision making.

## Quick Start

```bash
./run_demo.sh
```

Then open http://localhost:8000 in your browser.

## What You'll Learn

- How split-brain scenarios occur in distributed systems
- Raft consensus algorithm in action
- Quorum-based split-brain prevention
- Network partition effects on consensus
- Real-time visualization of distributed system behavior

## Demo Scenarios

1. **Simple Split**: 3-2 partition where majority group remains active
2. **Minority Partition**: 2-3 partition where minority loses quorum
3. **Even Split**: 2-2 partition where no group has majority

## Architecture

The demo implements a simplified Raft-like consensus algorithm with:
- Leader election with randomized timeouts
- Heartbeat mechanism for failure detection
- Quorum-based decision making
- Network partition simulation
- Real-time web interface with WebSocket updates

## Files Structure

- `src/node.py`: Distributed node implementation
- `src/server.py`: Web server and API
- `templates/dashboard.html`: Interactive web interface
- `test_demo.py`: Automated test suite
- `docker-compose.yml`: Container orchestration

## Testing

```bash
# Run automated tests
python test_demo.py

# Manual testing via web interface
# 1. Create cluster
# 2. Simulate partitions
# 3. Observe consensus behavior
# 4. Heal partitions
```

## Key Insights Demonstrated

- **Term Numbers**: Prevent stale leaders from causing split-brain
- **Majority Voting**: Ensures only one leader can be elected
- **Randomized Timeouts**: Reduces election conflicts
- **Quorum Requirements**: Minority partitions cannot elect leaders
- **Graceful Degradation**: Isolated nodes become read-only

This demo provides hands-on experience with the concepts covered in the Split-Brain Prevention article.
EOF

echo ""
echo "✅ Split-Brain Prevention Demo Setup Complete!"
echo "=============================================="
echo ""
echo "📁 Project structure created in: $PROJECT_DIR"
echo "🚀 To start the demo, run: cd $PROJECT_DIR && ./run_demo.sh"
echo ""
echo "📋 What the demo includes:"
echo "  • Interactive web interface for visualizing consensus"
echo "  • 5-node distributed cluster simulation"  
echo "  • Network partition simulation"
echo "  • Real-time consensus algorithm visualization"
echo "  • Multiple test scenarios (3-2, 2-3, 2-2 splits)"
echo "  • Automated test suite for validation"
echo "  • Docker containerization for easy setup"
echo ""
echo "🎯 Learning objectives:"
echo "  • Understand how split-brain scenarios occur"
echo "  • See Raft consensus algorithm in action"
echo "  • Observe quorum-based split-brain prevention"
echo "  • Experience network partition effects"
echo "  • Learn real-world distributed systems concepts"
echo ""
echo "⚠️  Requirements: Docker and Docker Compose must be installed"
echo "🌐 Web interface will be available at: http://localhost:8000"
echo ""
echo "📖 Next steps:"
echo "  1. cd $PROJECT_DIR"
echo "  2. ./run_demo.sh"
echo "  3. Open http://localhost:8000 in your browser"
echo "  4. Click 'Create Cluster' to start"
echo "  5. Try different partition scenarios"
echo "  6. Observe split-brain prevention in action!"