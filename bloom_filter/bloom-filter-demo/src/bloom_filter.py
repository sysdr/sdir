"""
Production-grade Bloom Filter implementation
Demonstrates key concepts from the System Design Interview Roadmap
"""

import mmh3
import numpy as np
import math
import time
import logging
from typing import List, Optional, Any
import json

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ProductionBloomFilter:
    """
    Production-ready Bloom filter with advanced features:
    - Optimal parameter calculation
    - Multiple hash function strategies
    - Performance monitoring
    - Memory optimization
    """
    
    def __init__(self, expected_elements: int, false_positive_rate: float = 0.01):
        """
        Initialize Bloom filter with optimal parameters
        
        Args:
            expected_elements: Expected number of elements to insert
            false_positive_rate: Desired false positive rate (0.01 = 1%)
        """
        self.expected_elements = expected_elements
        self.false_positive_rate = false_positive_rate
        
        # Calculate optimal parameters using mathematical formulas
        self.bit_array_size = self._calculate_optimal_bit_array_size()
        self.num_hash_functions = self._calculate_optimal_hash_functions()
        
        # Initialize bit array using numpy for memory efficiency
        self.bit_array = np.zeros(self.bit_array_size, dtype=bool)
        
        # Performance tracking
        self.elements_added = 0
        self.lookup_count = 0
        self.false_positive_count = 0
        
        # Statistics
        self.creation_time = time.time()
        
        logger.info(f"Bloom filter created: {self.bit_array_size} bits, "
                   f"{self.num_hash_functions} hash functions, "
                   f"expected FP rate: {self.false_positive_rate:.3f}")
    
    def _calculate_optimal_bit_array_size(self) -> int:
        """
        Calculate optimal bit array size using the formula:
        m = -(n * ln(p)) / (ln(2)^2)
        where n = expected elements, p = false positive rate
        """
        m = -(self.expected_elements * math.log(self.false_positive_rate)) / (math.log(2) ** 2)
        return int(m)
    
    def _calculate_optimal_hash_functions(self) -> int:
        """
        Calculate optimal number of hash functions:
        k = (m/n) * ln(2)
        where m = bit array size, n = expected elements
        """
        k = (self.bit_array_size / self.expected_elements) * math.log(2)
        return max(1, int(round(k)))
    
    def _hash_functions(self, item: str) -> List[int]:
        """
        Generate multiple hash values using MMH3 with different seeds
        This approach provides good distribution and performance
        """
        hashes = []
        for i in range(self.num_hash_functions):
            # Use different seeds to create independent hash functions
            hash_value = mmh3.hash(item, seed=i) % self.bit_array_size
            hashes.append(abs(hash_value))  # Ensure positive index
        return hashes
    
    def add(self, item: str) -> None:
        """Add an item to the Bloom filter"""
        hash_values = self._hash_functions(item)
        
        for hash_val in hash_values:
            self.bit_array[hash_val] = True
        
        self.elements_added += 1
        
        if self.elements_added % 10000 == 0:
            logger.info(f"Added {self.elements_added} elements to Bloom filter")
    
    def contains(self, item: str) -> bool:
        """
        Check if an item might be in the set
        Returns: True if item might be present, False if definitely not present
        """
        self.lookup_count += 1
        hash_values = self._hash_functions(item)
        
        # All bits must be set for a potential match
        for hash_val in hash_values:
            if not self.bit_array[hash_val]:
                return False
        
        return True
    
    def get_current_false_positive_rate(self) -> float:
        """
        Calculate current theoretical false positive rate based on actual load
        Formula: (1 - e^(-kn/m))^k
        """
        if self.elements_added == 0:
            return 0.0
        
        # Calculate the probability that a bit is still 0
        prob_bit_zero = (1 - 1/self.bit_array_size) ** (self.num_hash_functions * self.elements_added)
        
        # False positive rate is (1 - prob_bit_zero)^k
        fp_rate = (1 - prob_bit_zero) ** self.num_hash_functions
        
        return fp_rate
    
    def get_memory_usage_mb(self) -> float:
        """Calculate memory usage in MB"""
        bits_in_mb = self.bit_array_size / (8 * 1024 * 1024)
        return bits_in_mb
    
    def get_statistics(self) -> dict:
        """Get comprehensive statistics about the filter"""
        current_fp_rate = self.get_current_false_positive_rate()
        bits_set = np.sum(self.bit_array)
        fill_ratio = bits_set / self.bit_array_size
        
        return {
            'bit_array_size': self.bit_array_size,
            'num_hash_functions': self.num_hash_functions,
            'expected_elements': self.expected_elements,
            'elements_added': self.elements_added,
            'expected_fp_rate': self.false_positive_rate,
            'current_fp_rate': current_fp_rate,
            'memory_usage_mb': self.get_memory_usage_mb(),
            'bits_set': int(bits_set),
            'fill_ratio': fill_ratio,
            'lookup_count': self.lookup_count,
            'uptime_seconds': time.time() - self.creation_time
        }
    
    def export_to_dict(self) -> dict:
        """Export filter state for serialization"""
        return {
            'bit_array': self.bit_array.tolist(),
            'config': {
                'expected_elements': self.expected_elements,
                'false_positive_rate': self.false_positive_rate,
                'bit_array_size': self.bit_array_size,
                'num_hash_functions': self.num_hash_functions
            },
            'stats': self.get_statistics()
        }

class DistributedBloomFilter:
    """
    Simulates distributed Bloom filter across multiple nodes
    Demonstrates enterprise architecture patterns
    """
    
    def __init__(self, num_nodes: int = 3, expected_elements_per_node: int = 100000):
        self.num_nodes = num_nodes
        self.nodes = {}
        
        # Create a Bloom filter for each node
        for i in range(num_nodes):
            node_id = f"node_{i}"
            self.nodes[node_id] = ProductionBloomFilter(
                expected_elements=expected_elements_per_node,
                false_positive_rate=0.01
            )
        
        # Global aggregated filter for cross-node queries
        self.global_filter = ProductionBloomFilter(
            expected_elements=num_nodes * expected_elements_per_node,
            false_positive_rate=0.001  # Lower FP rate for global filter
        )
    
    def _get_node_for_key(self, key: str) -> str:
        """Consistent hashing to determine which node handles the key"""
        hash_val = mmh3.hash(key)
        node_index = abs(hash_val) % self.num_nodes
        return f"node_{node_index}"
    
    def add(self, key: str) -> str:
        """Add key to appropriate node and global filter"""
        node_id = self._get_node_for_key(key)
        
        # Add to specific node
        self.nodes[node_id].add(key)
        
        # Add to global filter
        self.global_filter.add(key)
        
        return node_id
    
    def contains(self, key: str) -> dict:
        """Check if key exists with detailed results"""
        node_id = self._get_node_for_key(key)
        
        # Check local node first (faster)
        local_result = self.nodes[node_id].contains(key)
        
        # Check global filter
        global_result = self.global_filter.contains(key)
        
        return {
            'key': key,
            'assigned_node': node_id,
            'local_node_result': local_result,
            'global_filter_result': global_result,
            'recommendation': 'check_cache' if local_result else 'skip_cache'
        }
    
    def get_cluster_statistics(self) -> dict:
        """Get statistics for the entire cluster"""
        node_stats = {}
        total_elements = 0
        
        for node_id, bloom_filter in self.nodes.items():
            stats = bloom_filter.get_statistics()
            node_stats[node_id] = stats
            total_elements += stats['elements_added']
        
        global_stats = self.global_filter.get_statistics()
        
        return {
            'total_elements': total_elements,
            'num_nodes': self.num_nodes,
            'node_statistics': node_stats,
            'global_filter_statistics': global_stats,
            'average_elements_per_node': total_elements / self.num_nodes if self.num_nodes > 0 else 0
        }

# Testing and benchmarking functions
def run_performance_test(bloom_filter: ProductionBloomFilter, test_size: int = 100000):
    """Run comprehensive performance tests"""
    logger.info(f"Starting performance test with {test_size} operations...")
    
    # Test data generation
    test_items = [f"user_{i}@example.com" for i in range(test_size)]
    false_test_items = [f"fake_user_{i}@test.com" for i in range(test_size // 10)]
    
    # Insertion performance test
    start_time = time.time()
    for item in test_items:
        bloom_filter.add(item)
    insertion_time = time.time() - start_time
    
    # Lookup performance test (true positives)
    start_time = time.time()
    true_positive_count = 0
    for item in test_items[:1000]:  # Test subset for speed
        if bloom_filter.contains(item):
            true_positive_count += 1
    lookup_time_tp = time.time() - start_time
    
    # Lookup performance test (false positives)
    start_time = time.time()
    false_positive_count = 0
    for item in false_test_items:
        if bloom_filter.contains(item):
            false_positive_count += 1
    lookup_time_fp = time.time() - start_time
    
    # Calculate actual false positive rate
    actual_fp_rate = false_positive_count / len(false_test_items) if false_test_items else 0
    
    return {
        'test_size': test_size,
        'insertion_time_seconds': insertion_time,
        'insertions_per_second': test_size / insertion_time,
        'lookup_time_tp_seconds': lookup_time_tp,
        'lookup_time_fp_seconds': lookup_time_fp,
        'true_positive_count': true_positive_count,
        'false_positive_count': false_positive_count,
        'actual_fp_rate': actual_fp_rate,
        'theoretical_fp_rate': bloom_filter.get_current_false_positive_rate(),
        'memory_usage_mb': bloom_filter.get_memory_usage_mb()
    }

if __name__ == "__main__":
    # Example usage and testing
    print("=== Bloom Filter Demo ===")
    
    # Create and test a single filter
    bf = ProductionBloomFilter(expected_elements=50000, false_positive_rate=0.01)
    
    # Add some test data
    test_data = [
        "user123@example.com",
        "admin@company.com", 
        "test@test.com",
        "demo@demo.com"
    ]
    
    for item in test_data:
        bf.add(item)
        print(f"Added: {item}")
    
    # Test lookups
    print("\n=== Lookup Tests ===")
    test_queries = test_data + ["nonexistent@fake.com", "missing@nowhere.com"]
    
    for query in test_queries:
        result = bf.contains(query)
        print(f"Query '{query}': {'Might exist' if result else 'Definitely not present'}")
    
    # Print statistics
    print("\n=== Filter Statistics ===")
    stats = bf.get_statistics()
    for key, value in stats.items():
        print(f"{key}: {value}")
    
    # Run performance test
    print("\n=== Performance Test ===")
    perf_results = run_performance_test(bf, test_size=10000)
    for key, value in perf_results.items():
        print(f"{key}: {value}")
