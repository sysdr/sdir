"""
Comprehensive test suite for cache invalidation strategies
"""

import asyncio
import json
import pytest
import redis.asyncio as redis
from datetime import datetime, timedelta

from src.main import CacheInvalidationManager

@pytest.fixture
async def redis_client():
    """Create test Redis client"""
    client = redis.from_url("redis://redis:6379", decode_responses=True)
    await client.ping()
    # Clean test database
    await client.flushdb()
    yield client
    await client.close()

@pytest.fixture
async def cache_manager(redis_client):
    """Create cache manager for testing"""
    return CacheInvalidationManager(redis_client)

class TestTTLStrategy:
    """Test TTL-based cache invalidation"""
    
    async def test_ttl_basic_functionality(self, cache_manager):
        """Test basic TTL functionality"""
        key = "test:ttl:basic"
        data = {"value": "test_data", "type": "user_profile"}
        
        # Set with TTL
        ttl_used = await cache_manager._ttl_strategy(key, data, 60)
        assert ttl_used > 0
        
        # Verify data exists
        retrieved = await cache_manager.get_cache_data(key, 'ttl')
        assert retrieved == data
        
    async def test_ttl_jitter_application(self, cache_manager):
        """Test that TTL jitter is applied correctly"""
        key = "test:ttl:jitter"
        data = {"value": "test_data"}
        base_ttl = 100
        
        ttl_used = await cache_manager._ttl_strategy(key, data, base_ttl)
        
        # TTL should be between 85% and 100% of base TTL due to jitter
        assert 85 <= ttl_used <= 100
        
    async def test_dynamic_ttl_calculation(self, cache_manager):
        """Test dynamic TTL based on content type"""
        # User profile should get 2x TTL
        user_data = {"value": "profile", "type": "user_profile"}
        user_ttl = await cache_manager._ttl_strategy("user:123", user_data, 60)
        
        # Real-time data should get 0.25x TTL  
        realtime_data = {"value": "stock_price", "type": "real_time_data"}
        realtime_ttl = await cache_manager._ttl_strategy("stock:AAPL", realtime_data, 60)
        
        # User profile TTL should be longer than real-time data TTL
        assert user_ttl > realtime_ttl

class TestEventDrivenStrategy:
    """Test event-driven cache invalidation"""
    
    async def test_event_driven_basic(self, cache_manager):
        """Test basic event-driven functionality"""
        key = "test:event:basic"
        data = {"value": "test_data"}
        
        # Set with event-driven strategy
        await cache_manager._event_driven_strategy(key, data)
        
        # Verify data exists (no TTL)
        retrieved = await cache_manager.get_cache_data(key, 'event_driven')
        assert retrieved == data
        
    async def test_event_invalidation(self, cache_manager):
        """Test explicit invalidation"""
        key = "test:event:invalidate"
        data = {"value": "test_data"}
        
        # Set data
        await cache_manager._event_driven_strategy(key, data)
        
        # Verify exists
        assert await cache_manager.get_cache_data(key, 'event_driven') == data
        
        # Invalidate
        await cache_manager.invalidate_cache(key, 'event_driven')
        
        # Verify removed
        assert await cache_manager.get_cache_data(key, 'event_driven') is None

class TestLazyStrategy:
    """Test lazy invalidation strategy"""
    
    async def test_lazy_basic_functionality(self, cache_manager):
        """Test basic lazy invalidation"""
        key = "test:lazy:basic"
        data = {"value": "test_data"}
        
        # Set with lazy strategy
        await cache_manager._lazy_strategy(key, data, 300)
        
        # Retrieve and verify structure
        retrieved = await cache_manager.get_cache_data(key, 'lazy')
        assert retrieved == data
        
    async def test_lazy_validation_timing(self, cache_manager):
        """Test lazy validation timing logic"""
        key = "test:lazy:validation"
        data = {"value": "test_data"}
        
        # Set with short TTL for testing
        await cache_manager._lazy_strategy(key, data, 10)
        
        # Immediate retrieval should work
        retrieved = await cache_manager.get_cache_data(key, 'lazy')
        assert retrieved == data
        
        # Wait for validation window to pass
        await asyncio.sleep(6)  # Half of 10 second TTL
        
        # Should still retrieve but trigger validation check
        retrieved = await cache_manager.get_cache_data(key, 'lazy')
        assert retrieved == data

class TestHybridStrategy:
    """Test hybrid multi-tier strategy"""
    
    async def test_hybrid_multi_tier_setup(self, cache_manager):
        """Test that hybrid strategy creates multiple tiers"""
        key = "test:hybrid:basic"
        data = {"value": "test_data"}
        
        # Set with hybrid strategy
        await cache_manager._hybrid_strategy(key, data)
        
        # Should be able to retrieve from hybrid strategy
        retrieved = await cache_manager.get_cache_data(key, 'hybrid')
        assert retrieved == data
        
    async def test_hybrid_tier_fallback(self, cache_manager):
        """Test fallback between tiers"""
        key = "test:hybrid:fallback"
        data = {"value": "test_data"}
        
        # Set data
        await cache_manager._hybrid_strategy(key, data)
        
        # Remove L1 cache manually
        await cache_manager.redis.delete(f"l1:{key}")
        
        # Should still retrieve from L2/L3
        retrieved = await cache_manager.get_cache_data(key, 'hybrid')
        assert retrieved == data

class TestConcurrencyAndPerformance:
    """Test concurrency and performance characteristics"""
    
    async def test_concurrent_cache_operations(self, cache_manager):
        """Test concurrent cache operations"""
        keys = [f"concurrent:test:{i}" for i in range(10)]
        data = {"value": "concurrent_test"}
        
        # Perform concurrent cache sets
        tasks = []
        for key in keys:
            tasks.append(cache_manager._ttl_strategy(key, data, 60))
            
        await asyncio.gather(*tasks)
        
        # Verify all keys exist
        for key in keys:
            retrieved = await cache_manager.get_cache_data(key, 'ttl')
            assert retrieved == data
            
    async def test_performance_under_load(self, cache_manager):
        """Test performance under load"""
        num_operations = 100
        data = {"value": "load_test"}
        
        start_time = asyncio.get_event_loop().time()
        
        # Perform many cache operations
        tasks = []
        for i in range(num_operations):
            key = f"load:test:{i}"
            tasks.append(cache_manager._ttl_strategy(key, data, 60))
            
        await asyncio.gather(*tasks)
        
        end_time = asyncio.get_event_loop().time()
        duration = end_time - start_time
        
        # Should complete 100 operations in reasonable time (less than 5 seconds)
        assert duration < 5.0
        
        # Calculate operations per second
        ops_per_second = num_operations / duration
        assert ops_per_second > 20  # At least 20 ops/second

class TestFailureScenarios:
    """Test failure scenarios and edge cases"""
    
    async def test_invalid_json_handling(self, cache_manager):
        """Test handling of invalid JSON data"""
        key = "test:invalid:json"
        
        # Manually insert invalid JSON
        await cache_manager.redis.set(key, "invalid json data")
        
        # Should handle gracefully and return None
        retrieved = await cache_manager.get_cache_data(key, 'ttl')
        assert retrieved is None
        
    async def test_redis_connection_failure(self, cache_manager):
        """Test behavior during Redis connection issues"""
        # Close Redis connection to simulate failure
        await cache_manager.redis.close()
        
        # Operations should not raise exceptions
        result = await cache_manager.get_cache_data("nonexistent", 'ttl')
        assert result is None

# Performance benchmark
async def benchmark_cache_strategies():
    """Benchmark different cache strategies"""
    redis_client = redis.from_url("redis://redis:6379", decode_responses=True)
    cache_manager = CacheInvalidationManager(redis_client)
    
    strategies = ['ttl', 'event_driven', 'lazy', 'hybrid']
    num_ops = 50
    
    results = {}
    
    for strategy in strategies:
        start_time = asyncio.get_event_loop().time()
        
        # Run operations for each strategy
        for i in range(num_ops):
            key = f"benchmark:{strategy}:{i}"
            data = {"value": f"benchmark_data_{i}", "strategy": strategy}
            
            if strategy == 'ttl':
                await cache_manager._ttl_strategy(key, data, 60)
            elif strategy == 'event_driven':
                await cache_manager._event_driven_strategy(key, data)
            elif strategy == 'lazy':
                await cache_manager._lazy_strategy(key, data, 300)
            elif strategy == 'hybrid':
                await cache_manager._hybrid_strategy(key, data)
                
        end_time = asyncio.get_event_loop().time()
        results[strategy] = end_time - start_time
        
    await redis_client.close()
    return results

if __name__ == "__main__":
    # Run benchmark if executed directly
    async def main():
        results = await benchmark_cache_strategies()
        print("\nCache Strategy Performance Benchmark:")
        print("=" * 50)
        for strategy, duration in results.items():
            ops_per_second = 50 / duration
            print(f"{strategy:15}: {duration:.3f}s ({ops_per_second:.1f} ops/sec)")
            
    asyncio.run(main())
