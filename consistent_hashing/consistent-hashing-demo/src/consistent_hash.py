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
