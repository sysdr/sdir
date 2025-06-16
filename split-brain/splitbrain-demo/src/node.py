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
