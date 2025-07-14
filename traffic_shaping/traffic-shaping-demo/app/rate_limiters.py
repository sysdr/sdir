import time
import json
import math
from typing import Tuple, Dict, Any, Optional
import redis.asyncio as redis
import logging

logger = logging.getLogger(__name__)

class BaseLimiter:
    """Base class for rate limiters"""
    
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
    
    async def is_allowed(self, user_id: str) -> Tuple[bool, Dict[str, Any]]:
        """Check if request is allowed. Returns (allowed, metadata)"""
        raise NotImplementedError
    
    async def get_status(self, user_id: str) -> Dict[str, Any]:
        """Get current status of the rate limiter for user"""
        raise NotImplementedError
    
    async def reset(self, user_id: str) -> None:
        """Reset rate limiter for user"""
        raise NotImplementedError

class TokenBucketLimiter(BaseLimiter):
    """Token bucket rate limiter implementation"""
    
    def __init__(self, redis_client: redis.Redis, capacity: int = 10, refill_rate: float = 1.0):
        super().__init__(redis_client)
        self.capacity = capacity
        self.refill_rate = refill_rate  # tokens per second
    
    def _get_key(self, user_id: str) -> str:
        return f"token_bucket:{user_id}"
    
    async def is_allowed(self, user_id: str) -> Tuple[bool, Dict[str, Any]]:
        """Check if request is allowed using token bucket algorithm"""
        key = self._get_key(user_id)
        now = time.time()
        
        # Lua script for atomic token bucket operation
        lua_script = """
        local key = KEYS[1]
        local capacity = tonumber(ARGV[1])
        local refill_rate = tonumber(ARGV[2])
        local now = tonumber(ARGV[3])
        
        local bucket = redis.call('HMGET', key, 'tokens', 'last_refill')
        local tokens = tonumber(bucket[1]) or capacity
        local last_refill = tonumber(bucket[2]) or now
        
        -- Calculate tokens to add based on time elapsed
        local time_elapsed = now - last_refill
        local tokens_to_add = time_elapsed * refill_rate
        tokens = math.min(capacity, tokens + tokens_to_add)
        
        local allowed = false
        if tokens >= 1 then
            tokens = tokens - 1
            allowed = true
        end
        
        -- Update bucket state
        redis.call('HMSET', key, 'tokens', tokens, 'last_refill', now)
        redis.call('EXPIRE', key, 3600)  -- Expire after 1 hour of inactivity
        
        return {allowed and 1 or 0, tokens, time_elapsed}
        """
        
        try:
            result = await self.redis.eval(
                lua_script, 1, key, 
                self.capacity, self.refill_rate, now
            )
            
            allowed = bool(result[0])
            current_tokens = float(result[1])
            time_elapsed = float(result[2])
            
            metadata = {
                "algorithm": "token_bucket",
                "capacity": self.capacity,
                "current_tokens": current_tokens,
                "refill_rate": self.refill_rate,
                "time_elapsed": time_elapsed,
                "retry_after": 1 / self.refill_rate if not allowed else 0
            }
            
            return allowed, metadata
            
        except Exception as e:
            logger.error(f"Token bucket error: {e}")
            # Fail open
            return True, {"error": str(e)}
    
    async def get_status(self, user_id: str) -> Dict[str, Any]:
        """Get current token bucket status"""
        key = self._get_key(user_id)
        now = time.time()
        
        try:
            bucket = await self.redis.hmget(key, 'tokens', 'last_refill')
            tokens = float(bucket[0]) if bucket[0] else self.capacity
            last_refill = float(bucket[1]) if bucket[1] else now
            
            # Calculate current tokens
            time_elapsed = now - last_refill
            tokens_to_add = time_elapsed * self.refill_rate
            current_tokens = min(self.capacity, tokens + tokens_to_add)
            
            return {
                "algorithm": "token_bucket",
                "capacity": self.capacity,
                "current_tokens": current_tokens,
                "refill_rate": self.refill_rate,
                "last_refill": last_refill,
                "time_elapsed": time_elapsed
            }
        except Exception as e:
            logger.error(f"Status check error: {e}")
            return {"error": str(e)}
    
    async def reset(self, user_id: str) -> None:
        """Reset token bucket to full capacity"""
        key = self._get_key(user_id)
        await self.redis.delete(key)

class SlidingWindowLimiter(BaseLimiter):
    """Sliding window rate limiter implementation"""
    
    def __init__(self, redis_client: redis.Redis, window_size: int = 60, max_requests: int = 100):
        super().__init__(redis_client)
        self.window_size = window_size  # seconds
        self.max_requests = max_requests
    
    def _get_key(self, user_id: str) -> str:
        return f"sliding_window:{user_id}"
    
    async def is_allowed(self, user_id: str) -> Tuple[bool, Dict[str, Any]]:
        """Check if request is allowed using sliding window algorithm"""
        key = self._get_key(user_id)
        now = time.time()
        window_start = now - self.window_size
        
        # Lua script for atomic sliding window operation
        lua_script = """
        local key = KEYS[1]
        local window_start = tonumber(ARGV[1])
        local now = tonumber(ARGV[2])
        local max_requests = tonumber(ARGV[3])
        
        -- Remove old entries
        redis.call('ZREMRANGEBYSCORE', key, '-inf', window_start)
        
        -- Count current requests in window
        local current_requests = redis.call('ZCARD', key)
        
        local allowed = false
        if current_requests < max_requests then
            -- Add current request
            redis.call('ZADD', key, now, now .. ':' .. math.random())
            allowed = true
            current_requests = current_requests + 1
        end
        
        -- Set expiration
        redis.call('EXPIRE', key, math.ceil(ARGV[4]))
        
        return {allowed and 1 or 0, current_requests}
        """
        
        try:
            result = await self.redis.eval(
                lua_script, 1, key,
                window_start, now, self.max_requests, self.window_size + 10
            )
            
            allowed = bool(result[0])
            current_requests = int(result[1])
            
            metadata = {
                "algorithm": "sliding_window",
                "window_size": self.window_size,
                "max_requests": self.max_requests,
                "current_requests": current_requests,
                "window_start": window_start,
                "requests_remaining": max(0, self.max_requests - current_requests),
                "retry_after": self.window_size if not allowed else 0
            }
            
            return allowed, metadata
            
        except Exception as e:
            logger.error(f"Sliding window error: {e}")
            return True, {"error": str(e)}
    
    async def get_status(self, user_id: str) -> Dict[str, Any]:
        """Get current sliding window status"""
        key = self._get_key(user_id)
        now = time.time()
        window_start = now - self.window_size
        
        try:
            # Clean up old entries
            await self.redis.zremrangebyscore(key, '-inf', window_start)
            current_requests = await self.redis.zcard(key)
            
            return {
                "algorithm": "sliding_window",
                "window_size": self.window_size,
                "max_requests": self.max_requests,
                "current_requests": current_requests,
                "requests_remaining": max(0, self.max_requests - current_requests),
                "window_start": window_start
            }
        except Exception as e:
            logger.error(f"Status check error: {e}")
            return {"error": str(e)}
    
    async def reset(self, user_id: str) -> None:
        """Reset sliding window"""
        key = self._get_key(user_id)
        await self.redis.delete(key)

class FixedWindowLimiter(BaseLimiter):
    """Fixed window rate limiter implementation"""
    
    def __init__(self, redis_client: redis.Redis, window_size: int = 60, max_requests: int = 50):
        super().__init__(redis_client)
        self.window_size = window_size  # seconds
        self.max_requests = max_requests
    
    def _get_key(self, user_id: str, window_start: int) -> str:
        return f"fixed_window:{user_id}:{window_start}"
    
    def _get_window_start(self, now: float) -> int:
        """Get the start of the current window"""
        return int(now // self.window_size) * self.window_size
    
    async def is_allowed(self, user_id: str) -> Tuple[bool, Dict[str, Any]]:
        """Check if request is allowed using fixed window algorithm"""
        now = time.time()
        window_start = self._get_window_start(now)
        key = self._get_key(user_id, window_start)
        
        try:
            # Get current count and increment atomically
            current_count = await self.redis.incr(key)
            
            # Set expiration on first request in window
            if current_count == 1:
                await self.redis.expire(key, self.window_size + 10)
            
            allowed = current_count <= self.max_requests
            
            if not allowed:
                # Decrement if over limit
                await self.redis.decr(key)
                current_count -= 1
            
            # Calculate time until next window
            window_end = window_start + self.window_size
            time_until_reset = window_end - now
            
            metadata = {
                "algorithm": "fixed_window",
                "window_size": self.window_size,
                "max_requests": self.max_requests,
                "current_requests": current_count,
                "window_start": window_start,
                "window_end": window_end,
                "time_until_reset": time_until_reset,
                "requests_remaining": max(0, self.max_requests - current_count),
                "retry_after": time_until_reset if not allowed else 0
            }
            
            return allowed, metadata
            
        except Exception as e:
            logger.error(f"Fixed window error: {e}")
            return True, {"error": str(e)}
    
    async def get_status(self, user_id: str) -> Dict[str, Any]:
        """Get current fixed window status"""
        now = time.time()
        window_start = self._get_window_start(now)
        key = self._get_key(user_id, window_start)
        
        try:
            current_count = await self.redis.get(key)
            current_count = int(current_count) if current_count else 0
            
            window_end = window_start + self.window_size
            time_until_reset = window_end - now
            
            return {
                "algorithm": "fixed_window",
                "window_size": self.window_size,
                "max_requests": self.max_requests,
                "current_requests": current_count,
                "requests_remaining": max(0, self.max_requests - current_count),
                "window_start": window_start,
                "window_end": window_end,
                "time_until_reset": time_until_reset
            }
        except Exception as e:
            logger.error(f"Status check error: {e}")
            return {"error": str(e)}
    
    async def reset(self, user_id: str) -> None:
        """Reset fixed window"""
        now = time.time()
        window_start = self._get_window_start(now)
        key = self._get_key(user_id, window_start)
        await self.redis.delete(key)
