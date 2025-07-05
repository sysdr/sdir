import pytest
import time
import threading
from src.pool_manager import ConnectionPoolManager, PoolMetrics
import os

# Test configuration
TEST_DB_URL = os.getenv('TEST_DATABASE_URL', 'postgresql://demo:demo123@localhost:5432/connection_demo')

class TestConnectionPoolManager:
    """Test suite for Connection Pool Manager"""
    
    @pytest.fixture
    def pool_manager(self):
        """Create a test pool manager instance"""
        manager = ConnectionPoolManager(
            database_url=TEST_DB_URL,
            max_pool_size=5,
            min_pool_size=2,
            pool_timeout=10
        )
        yield manager
        manager.close()
    
    def test_pool_initialization(self, pool_manager):
        """Test that pool initializes correctly"""
        assert pool_manager.max_pool_size == 5
        assert pool_manager.min_pool_size == 2
        assert pool_manager.pool_timeout == 10
        assert pool_manager.test_connection() == True
    
    def test_basic_query_execution(self, pool_manager):
        """Test basic query execution"""
        result = pool_manager.execute_query("SELECT 1 as test")
        
        assert result.success == True
        assert result.duration_ms > 0
        assert result.error is None
    
    def test_metrics_collection(self, pool_manager):
        """Test metrics collection"""
        # Execute some queries to generate metrics
        for _ in range(3):
            pool_manager.execute_query("SELECT * FROM demo_data LIMIT 1")
        
        metrics = pool_manager.get_metrics()
        
        assert isinstance(metrics, PoolMetrics)
        assert metrics.pool_size >= 0
        assert metrics.avg_response_time_ms >= 0
    
    def test_concurrent_access(self, pool_manager):
        """Test concurrent database access"""
        results = []
        
        def worker():
            result = pool_manager.execute_query("SELECT COUNT(*) FROM demo_data")
            results.append(result)
        
        # Create multiple threads
        threads = []
        for _ in range(10):
            thread = threading.Thread(target=worker)
            threads.append(thread)
            thread.start()
        
        # Wait for all threads to complete
        for thread in threads:
            thread.join()
        
        # Verify all queries succeeded
        assert len(results) == 10
        assert all(result.success for result in results)
    
    def test_pool_exhaustion_simulation(self, pool_manager):
        """Test pool exhaustion scenario"""
        result = pool_manager.simulate_pool_exhaustion()
        
        assert 'message' in result
        assert 'workers' in result
        assert result['workers'] > pool_manager.max_pool_size
    
    def test_normal_load_simulation(self, pool_manager):
        """Test normal load simulation"""
        result = pool_manager.simulate_normal_load()
        
        assert 'message' in result
        assert 'workers' in result
        assert 'queries_per_worker' in result
    
    def test_high_load_simulation(self, pool_manager):
        """Test high load simulation"""
        result = pool_manager.simulate_high_load()
        
        assert 'message' in result
        assert 'workers' in result
        assert 'queries_per_worker' in result
    
    def test_error_handling(self, pool_manager):
        """Test error handling for invalid queries"""
        result = pool_manager.execute_query("SELECT * FROM nonexistent_table")
        
        assert result.success == False
        assert result.error is not None
        assert result.duration_ms > 0

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
