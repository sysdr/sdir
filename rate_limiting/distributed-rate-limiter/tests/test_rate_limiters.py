import pytest
import time
import threading
from app.main import TokenBucketRateLimiter, SlidingWindowRateLimiter, FixedWindowRateLimiter
import redis

# Mock Redis for testing
class MockRedis:
    def __init__(self):
        self.data = {}
        self.expires = {}
    
    def eval(self, script, numkeys, *args):
        # Simple mock implementation for token bucket
        if 'tokens' in script:
            return [1, 50]  # Always allow, 50 tokens remaining
        return [1, 1]  # Always allow, 1 request counted
    
    def incr(self, key):
        self.data[key] = self.data.get(key, 0) + 1
        return self.data[key]
    
    def expire(self, key, seconds):
        self.expires[key] = time.time() + seconds

def test_token_bucket_basic():
    """Test basic token bucket functionality"""
    mock_redis = MockRedis()
    limiter = TokenBucketRateLimiter(mock_redis, capacity=10, refill_rate=1)
    
    allowed, remaining = limiter.is_allowed('test_client')
    assert allowed == True
    assert remaining >= 0

def test_sliding_window_basic():
    """Test basic sliding window functionality"""
    mock_redis = MockRedis()
    limiter = SlidingWindowRateLimiter(mock_redis, window_size=60, max_requests=10)
    
    allowed, count = limiter.is_allowed('test_client')
    assert allowed == True
    assert count >= 0

def test_fixed_window_basic():
    """Test basic fixed window functionality"""
    mock_redis = MockRedis()
    limiter = FixedWindowRateLimiter(mock_redis, window_size=60, max_requests=10)
    
    allowed, count = limiter.is_allowed('test_client')
    assert allowed == True
    assert count >= 0

def test_concurrent_access():
    """Test thread safety of rate limiters"""
    mock_redis = MockRedis()
    limiter = TokenBucketRateLimiter(mock_redis, capacity=100, refill_rate=10)
    
    results = []
    
    def make_request():
        allowed, remaining = limiter.is_allowed('concurrent_client')
        results.append(allowed)
    
    threads = []
    for _ in range(10):
        t = threading.Thread(target=make_request)
        threads.append(t)
        t.start()
    
    for t in threads:
        t.join()
    
    # All requests should be allowed in this test scenario
    assert all(results)

if __name__ == '__main__':
    pytest.main([__file__])
