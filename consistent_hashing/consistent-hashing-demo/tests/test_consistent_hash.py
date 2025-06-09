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
