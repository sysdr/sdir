"""
Comprehensive tests for Bloom filter implementation
Validates correctness and performance characteristics
"""

import pytest
import sys
import os

# Add src directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from bloom_filter import ProductionBloomFilter, DistributedBloomFilter, run_performance_test

class TestProductionBloomFilter:
    """Test cases for ProductionBloomFilter"""
    
    def test_initialization(self):
        """Test filter initialization with various parameters"""
        bf = ProductionBloomFilter(expected_elements=1000, false_positive_rate=0.01)
        
        assert bf.expected_elements == 1000
        assert bf.false_positive_rate == 0.01
        assert bf.bit_array_size > 0
        assert bf.num_hash_functions > 0
        assert bf.elements_added == 0
    
    def test_add_and_contains_basic(self):
        """Test basic add and contains operations"""
        bf = ProductionBloomFilter(expected_elements=100, false_positive_rate=0.01)
        
        # Test items that are added
        test_items = ["test1", "test2", "test3"]
        for item in test_items:
            bf.add(item)
        
        # All added items should return True (might exist)
        for item in test_items:
            assert bf.contains(item) == True
        
        # Test non-existent items (some might be false positives)
        non_existent = ["nonexistent1", "nonexistent2", "nonexistent3"]
        false_positives = 0
        for item in non_existent:
            if bf.contains(item):
                false_positives += 1
        
        # Should have some false positives but not all
        assert false_positives < len(non_existent)
    
    def test_no_false_negatives(self):
        """Verify that false negatives never occur"""
        bf = ProductionBloomFilter(expected_elements=1000, false_positive_rate=0.01)
        
        test_items = [f"user_{i}@example.com" for i in range(100)]
        
        # Add all items
        for item in test_items:
            bf.add(item)
        
        # Check that all added items return True
        for item in test_items:
            assert bf.contains(item) == True, f"False negative for item: {item}"
    
    def test_statistics(self):
        """Test statistics reporting"""
        bf = ProductionBloomFilter(expected_elements=1000, false_positive_rate=0.01)
        
        # Add some items
        for i in range(50):
            bf.add(f"item_{i}")
        
        stats = bf.get_statistics()
        
        assert stats['elements_added'] == 50
        assert stats['expected_elements'] == 1000
        assert stats['expected_fp_rate'] == 0.01
        assert stats['memory_usage_mb'] > 0
        assert 0 <= stats['fill_ratio'] <= 1
        assert stats['current_fp_rate'] >= 0

class TestDistributedBloomFilter:
    """Test cases for DistributedBloomFilter"""
    
    def test_initialization(self):
        """Test distributed filter initialization"""
        dbf = DistributedBloomFilter(num_nodes=3, expected_elements_per_node=1000)
        
        assert len(dbf.nodes) == 3
        assert dbf.num_nodes == 3
        assert dbf.global_filter is not None
    
    def test_consistent_hashing(self):
        """Test that same key always goes to same node"""
        dbf = DistributedBloomFilter(num_nodes=3, expected_elements_per_node=1000)
        
        test_key = "test_key_123"
        
        # Get node assignment multiple times
        node1 = dbf._get_node_for_key(test_key)
        node2 = dbf._get_node_for_key(test_key)
        node3 = dbf._get_node_for_key(test_key)
        
        assert node1 == node2 == node3
    
    def test_distributed_operations(self):
        """Test add and contains operations across nodes"""
        dbf = DistributedBloomFilter(num_nodes=3, expected_elements_per_node=100)
        
        test_items = [f"user_{i}@domain.com" for i in range(30)]
        
        # Add items and track which nodes they go to
        node_assignments = {}
        for item in test_items:
            node_id = dbf.add(item)
            node_assignments[item] = node_id
        
        # Verify all items can be found
        for item in test_items:
            result = dbf.contains(item)
            assert result['local_node_result'] == True
            assert result['global_filter_result'] == True
            assert result['assigned_node'] == node_assignments[item]

class TestPerformance:
    """Performance and scalability tests"""
    
    def test_performance_characteristics(self):
        """Test that performance meets expected characteristics"""
        bf = ProductionBloomFilter(expected_elements=10000, false_positive_rate=0.01)
        
        # Run performance test
        results = run_performance_test(bf, test_size=5000)
        
        # Verify performance characteristics
        assert results['insertions_per_second'] > 1000  # Should be fast
        assert results['memory_usage_mb'] < 10  # Should be memory efficient
        assert results['actual_fp_rate'] < 0.05  # FP rate should be reasonable
        
    def test_memory_efficiency(self):
        """Test memory usage is independent of element count"""
        # Create filters with same parameters but different element counts
        bf1 = ProductionBloomFilter(expected_elements=1000, false_positive_rate=0.01)
        bf2 = ProductionBloomFilter(expected_elements=1000, false_positive_rate=0.01)
        
        # Add different numbers of elements
        for i in range(100):
            bf1.add(f"item_{i}")
        
        for i in range(500):
            bf2.add(f"item_{i}")
        
        # Memory usage should be the same (bit array size is fixed)
        assert bf1.get_memory_usage_mb() == bf2.get_memory_usage_mb()

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
