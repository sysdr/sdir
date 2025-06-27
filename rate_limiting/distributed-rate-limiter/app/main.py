import time
import json
import redis
import threading
from flask import Flask, request, jsonify, render_template
from flask_cors import CORS
import logging
from datetime import datetime, timedelta
from collections import defaultdict
import math

app = Flask(__name__, template_folder='../templates', static_folder='../static')
CORS(app)

# Redis connection
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

# In-memory fallback for local testing
local_storage = defaultdict(dict)

class TokenBucketRateLimiter:
    """Production-grade token bucket implementation with Redis backend"""
    
    def __init__(self, redis_client, capacity=100, refill_rate=10):
        self.redis = redis_client
        self.capacity = capacity
        self.refill_rate = refill_rate
    
    def is_allowed(self, key, tokens_requested=1):
        """Check if request is allowed and consume tokens"""
        lua_script = """
        local key = KEYS[1]
        local capacity = tonumber(ARGV[1])
        local refill_rate = tonumber(ARGV[2])
        local tokens_requested = tonumber(ARGV[3])
        local now = tonumber(ARGV[4])
        
        local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
        local tokens = tonumber(bucket[1]) or capacity
        local last_refill = tonumber(bucket[2]) or now
        
        -- Calculate tokens to add based on time elapsed
        local time_passed = math.max(0, now - last_refill)
        local tokens_to_add = time_passed * refill_rate / 1000
        tokens = math.min(capacity, tokens + tokens_to_add)
        
        if tokens >= tokens_requested then
            tokens = tokens - tokens_requested
            redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
            redis.call('EXPIRE', key, 3600)
            return {1, tokens}
        else
            redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
            redis.call('EXPIRE', key, 3600)
            return {0, tokens}
        end
        """
        
        try:
            result = self.redis.eval(lua_script, 1, key, 
                                   self.capacity, self.refill_rate, 
                                   tokens_requested, int(time.time() * 1000))
            return bool(result[0]), result[1]
        except:
            # Fallback to local storage
            return self._local_fallback(key, tokens_requested)
    
    def _local_fallback(self, key, tokens_requested):
        """Local fallback when Redis is unavailable"""
        now = time.time() * 1000
        if key not in local_storage:
            local_storage[key] = {'tokens': self.capacity, 'last_refill': now}
        
        bucket = local_storage[key]
        time_passed = max(0, now - bucket['last_refill'])
        tokens_to_add = time_passed * self.refill_rate / 1000
        bucket['tokens'] = min(self.capacity, bucket['tokens'] + tokens_to_add)
        bucket['last_refill'] = now
        
        if bucket['tokens'] >= tokens_requested:
            bucket['tokens'] -= tokens_requested
            return True, bucket['tokens']
        return False, bucket['tokens']

class SlidingWindowRateLimiter:
    """Memory-efficient sliding window implementation"""
    
    def __init__(self, redis_client, window_size=60, max_requests=100):
        self.redis = redis_client
        self.window_size = window_size
        self.max_requests = max_requests
    
    def is_allowed(self, key):
        """Check if request is allowed using sliding window"""
        lua_script = """
        local key = KEYS[1]
        local window_size = tonumber(ARGV[1])
        local max_requests = tonumber(ARGV[2])
        local now = tonumber(ARGV[3])
        
        -- Remove old entries
        redis.call('ZREMRANGEBYSCORE', key, 0, now - window_size * 1000)
        
        -- Count current requests
        local current_requests = redis.call('ZCARD', key)
        
        if current_requests < max_requests then
            -- Add current request
            redis.call('ZADD', key, now, now)
            redis.call('EXPIRE', key, window_size + 1)
            return {1, current_requests + 1}
        else
            return {0, current_requests}
        end
        """
        
        try:
            result = self.redis.eval(lua_script, 1, key, 
                                   self.window_size, self.max_requests, 
                                   int(time.time() * 1000))
            return bool(result[0]), result[1]
        except:
            return True, 0  # Fail open on Redis failure

class FixedWindowRateLimiter:
    """Simple fixed window counter implementation"""
    
    def __init__(self, redis_client, window_size=60, max_requests=100):
        self.redis = redis_client
        self.window_size = window_size
        self.max_requests = max_requests
    
    def is_allowed(self, key):
        """Check if request is allowed using fixed window"""
        current_window = int(time.time() // self.window_size)
        window_key = f"{key}:{current_window}"
        
        try:
            current_count = self.redis.incr(window_key)
            if current_count == 1:
                self.redis.expire(window_key, self.window_size)
            
            return current_count <= self.max_requests, current_count
        except:
            return True, 0  # Fail open on Redis failure

# Initialize rate limiters
token_bucket = TokenBucketRateLimiter(redis_client, capacity=50, refill_rate=5)
sliding_window = SlidingWindowRateLimiter(redis_client, window_size=60, max_requests=100)
fixed_window = FixedWindowRateLimiter(redis_client, window_size=60, max_requests=100)

def get_client_id():
    """Extract client identifier for rate limiting"""
    return request.headers.get('X-Client-ID', request.remote_addr)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/token-bucket')
def test_token_bucket():
    """Test endpoint for token bucket algorithm"""
    client_id = get_client_id()
    allowed, remaining = token_bucket.is_allowed(f"tb:{client_id}")
    
    response = {
        'algorithm': 'token_bucket',
        'allowed': allowed,
        'remaining_tokens': remaining,
        'timestamp': datetime.now().isoformat(),
        'client_id': client_id
    }
    
    status_code = 200 if allowed else 429
    return jsonify(response), status_code

@app.route('/api/sliding-window')
def test_sliding_window():
    """Test endpoint for sliding window algorithm"""
    client_id = get_client_id()
    allowed, current_requests = sliding_window.is_allowed(f"sw:{client_id}")
    
    response = {
        'algorithm': 'sliding_window',
        'allowed': allowed,
        'current_requests': current_requests,
        'max_requests': sliding_window.max_requests,
        'window_size': sliding_window.window_size,
        'timestamp': datetime.now().isoformat(),
        'client_id': client_id
    }
    
    status_code = 200 if allowed else 429
    return jsonify(response), status_code

@app.route('/api/fixed-window')
def test_fixed_window():
    """Test endpoint for fixed window algorithm"""
    client_id = get_client_id()
    allowed, current_requests = fixed_window.is_allowed(f"fw:{client_id}")
    
    response = {
        'algorithm': 'fixed_window',
        'allowed': allowed,
        'current_requests': current_requests,
        'max_requests': fixed_window.max_requests,
        'window_size': fixed_window.window_size,
        'timestamp': datetime.now().isoformat(),
        'client_id': client_id
    }
    
    status_code = 200 if allowed else 429
    return jsonify(response), status_code

@app.route('/api/stats')
def get_stats():
    """Get overall rate limiting statistics"""
    try:
        redis_info = redis_client.info()
        stats = {
            'redis_connected': True,
            'total_keys': redis_info.get('db0', {}).get('keys', 0),
            'memory_usage': redis_info.get('used_memory_human', 'Unknown'),
            'uptime': redis_info.get('uptime_in_seconds', 0)
        }
    except:
        stats = {
            'redis_connected': False,
            'total_keys': len(local_storage),
            'memory_usage': 'Local fallback',
            'uptime': 0
        }
    
    return jsonify(stats)

@app.route('/api/load-test')
def load_test():
    """Endpoint for load testing rate limiters"""
    import threading
    import requests
    import time
    
    def make_request(endpoint, client_id):
        try:
            response = requests.get(f"http://localhost:5000/api/{endpoint}", 
                                  headers={'X-Client-ID': client_id},
                                  timeout=1)
            return response.status_code
        except:
            return 500
    
    results = {'token_bucket': [], 'sliding_window': [], 'fixed_window': []}
    threads = []
    
    # Simulate concurrent requests from multiple clients
    for i in range(20):
        for algorithm in ['token-bucket', 'sliding-window', 'fixed-window']:
            t = threading.Thread(target=lambda: results[algorithm.replace('-', '_')].append(
                make_request(algorithm, f"client_{i % 5}")
            ))
            threads.append(t)
            t.start()
    
    for t in threads:
        t.join()
    
    summary = {}
    for alg, codes in results.items():
        summary[alg] = {
            'total_requests': len(codes),
            'successful': codes.count(200),
            'rate_limited': codes.count(429),
            'errors': codes.count(500)
        }
    
    return jsonify(summary)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
