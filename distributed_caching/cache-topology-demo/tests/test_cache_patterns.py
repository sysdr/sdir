import unittest
import requests
import time
import json
from concurrent.futures import ThreadPoolExecutor
import threading

class TestCachePatterns(unittest.TestCase):
    BASE_URL = "http://localhost:5000"
    
    def setUp(self):
        """Setup test environment"""
        # Wait for application to be ready
        max_retries = 30
        for i in range(max_retries):
            try:
                response = requests.get(f"{self.BASE_URL}/api/health", timeout=5)
                if response.status_code == 200:
                    break
            except requests.exceptions.RequestException:
                if i == max_retries - 1:
                    self.fail("Application not ready after 30 seconds")
                time.sleep(1)
    
    def test_cache_aside_pattern(self):
        """Test cache-aside pattern functionality"""
        print("\n🧪 Testing Cache-Aside Pattern...")
        
        # Test cache miss (first request)
        response = requests.get(f"{self.BASE_URL}/api/cache-aside/test_key_1")
        self.assertEqual(response.status_code, 200)
        
        result = response.json()
        self.assertEqual(result['pattern'], 'cache-aside')
        self.assertIn('value', result)
        self.assertIn('latency_ms', result)
        
        print(f"✅ Cache miss latency: {result['latency_ms']}ms")
        
        # Test cache hit (second request for same key)
        response = requests.get(f"{self.BASE_URL}/api/cache-aside/test_key_1")
        self.assertEqual(response.status_code, 200)
        
        result2 = response.json()
        self.assertEqual(result2['pattern'], 'cache-aside')
        
        # Cache hit should be faster than cache miss
        print(f"✅ Cache hit latency: {result2['latency_ms']}ms")
        
    def test_write_through_pattern(self):
        """Test write-through pattern functionality"""
        print("\n🧪 Testing Write-Through Pattern...")
        
        test_data = {
            "key": "write_through_test",
            "value": "test_value_123"
        }
        
        response = requests.post(
            f"{self.BASE_URL}/api/write-through",
            json=test_data,
            headers={'Content-Type': 'application/json'}
        )
        
        self.assertEqual(response.status_code, 200)
        result = response.json()
        
        self.assertEqual(result['pattern'], 'write-through')
        self.assertTrue(result['success'])
        self.assertIn('latency_ms', result)
        
        print(f"✅ Write-through latency: {result['latency_ms']}ms")
        
    def test_write_behind_pattern(self):
        """Test write-behind pattern functionality"""
        print("\n🧪 Testing Write-Behind Pattern...")
        
        test_data = {
            "key": "write_behind_test",
            "value": "async_test_value"
        }
        
        response = requests.post(
            f"{self.BASE_URL}/api/write-behind",
            json=test_data,
            headers={'Content-Type': 'application/json'}
        )
        
        self.assertEqual(response.status_code, 200)
        result = response.json()
        
        self.assertEqual(result['pattern'], 'write-behind')
        self.assertTrue(result['success'])
        self.assertIn('latency_ms', result)
        
        # Write-behind should be faster than write-through
        print(f"✅ Write-behind latency: {result['latency_ms']}ms")
        
    def test_cache_stampede_simulation(self):
        """Test cache stampede simulation"""
        print("\n🧪 Testing Cache Stampede Simulation...")
        
        response = requests.get(f"{self.BASE_URL}/api/stampede/stampede_test")
        self.assertEqual(response.status_code, 200)
        
        result = response.json()
        self.assertIn('message', result)
        
        print("✅ Cache stampede simulation started successfully")
        
    def test_network_partition_simulation(self):
        """Test network partition simulation"""
        print("\n🧪 Testing Network Partition Simulation...")
        
        response = requests.get(f"{self.BASE_URL}/api/partition/5")
        self.assertEqual(response.status_code, 200)
        
        result = response.json()
        self.assertIn('message', result)
        
        print("✅ Network partition simulation started successfully")
        
    def test_concurrent_access(self):
        """Test concurrent access patterns"""
        print("\n🧪 Testing Concurrent Access...")
        
        def make_request(i):
            response = requests.get(f"{self.BASE_URL}/api/cache-aside/concurrent_test_{i}")
            return response.status_code == 200
        
        # Test 10 concurrent requests
        with ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(make_request, i) for i in range(10)]
            results = [future.result() for future in futures]
        
        # All requests should succeed
        self.assertTrue(all(results))
        print("✅ All concurrent requests completed successfully")
        
    def test_metrics_endpoint(self):
        """Test metrics collection"""
        print("\n🧪 Testing Metrics Collection...")
        
        response = requests.get(f"{self.BASE_URL}/api/metrics")
        self.assertEqual(response.status_code, 200)
        
        metrics = response.json()
        required_metrics = ['cache_hits', 'cache_misses', 'database_queries', 'write_operations']
        
        for metric in required_metrics:
            self.assertIn(metric, metrics)
            self.assertIsInstance(metrics[metric], (int, float))
        
        print("✅ All required metrics are present and valid")

if __name__ == '__main__':
    print("🚀 Starting Cache Topology Tests...")
    unittest.main(verbosity=2)
