"""
Shared utilities for backpressure demonstration
"""
import time
import asyncio
import logging
import json
from typing import Dict, Optional, List
from dataclasses import dataclass, asdict
from collections import deque
import redis.asyncio as redis
import structlog

# Configure logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

@dataclass
class BackpressureMetrics:
    timestamp: float
    service_name: str
    queue_depth: int
    processing_rate: float
    error_rate: float
    latency_p99: float
    cpu_usage: float
    memory_usage: float
    active_connections: int

@dataclass
class CircuitBreakerState:
    state: str  # closed, open, half-open
    failure_count: int
    last_failure_time: float
    success_count: int

class TokenBucket:
    """Rate limiting using token bucket algorithm with backpressure awareness"""
    
    def __init__(self, capacity: int, refill_rate: float):
        self.capacity = capacity
        self.refill_rate = refill_rate
        self.tokens = capacity
        self.last_refill = time.time()
        self.adaptive_factor = 1.0
        
    def try_consume(self, tokens: int = 1) -> bool:
        now = time.time()
        elapsed = now - self.last_refill
        
        # Refill tokens based on adaptive rate
        self.tokens = min(
            self.capacity,
            self.tokens + elapsed * self.refill_rate * self.adaptive_factor
        )
        self.last_refill = now
        
        if self.tokens >= tokens:
            self.tokens -= tokens
            return True
        return False
    
    def adapt_to_backpressure(self, health_score: float):
        """Adapt token generation rate based on downstream health"""
        self.adaptive_factor = max(0.1, min(1.0, health_score))

class CircuitBreaker:
    """Circuit breaker with backpressure integration"""
    
    def __init__(self, failure_threshold: int = 5, recovery_timeout: float = 30,
                 half_open_max_calls: int = 3):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.half_open_max_calls = half_open_max_calls
        
        self.state = "closed"
        self.failure_count = 0
        self.last_failure_time = None
        self.half_open_calls = 0
        
    def call_succeeded(self):
        if self.state == "half-open":
            self.half_open_calls += 1
            if self.half_open_calls >= self.half_open_max_calls:
                self.state = "closed"
                self.failure_count = 0
                self.half_open_calls = 0
        elif self.state == "closed":
            self.failure_count = max(0, self.failure_count - 1)
    
    def call_failed(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        
        if self.failure_count >= self.failure_threshold:
            self.state = "open"
    
    def can_execute(self) -> bool:
        if self.state == "closed":
            return True
        elif self.state == "open":
            if (self.last_failure_time and 
                time.time() - self.last_failure_time > self.recovery_timeout):
                self.state = "half-open"
                self.half_open_calls = 0
                return True
            return False
        elif self.state == "half-open":
            return True
        
        return False
    
    def get_state(self) -> CircuitBreakerState:
        return CircuitBreakerState(
            state=self.state,
            failure_count=self.failure_count,
            last_failure_time=self.last_failure_time or 0,
            success_count=0
        )

class BackpressureManager:
    """Manages multiple backpressure mechanisms"""
    
    def __init__(self, service_name: str, redis_client):
        self.service_name = service_name
        self.redis_client = redis_client
        self.token_bucket = TokenBucket(capacity=100, refill_rate=10)
        self.circuit_breaker = CircuitBreaker()
        self.request_queue = deque(maxlen=1000)
        self.metrics_history = deque(maxlen=100)
        self.logger = structlog.get_logger()
        
    async def should_accept_request(self) -> tuple[bool, str]:
        """Determine if request should be accepted based on backpressure"""
        
        # Check circuit breaker
        if not self.circuit_breaker.can_execute():
            return False, "circuit_breaker_open"
        
        # Check rate limit
        if not self.token_bucket.try_consume():
            return False, "rate_limited"
        
        # Check queue capacity
        if len(self.request_queue) > 800:  # 80% of max capacity
            return False, "queue_full"
        
        return True, "accepted"
    
    async def record_request_result(self, success: bool, latency: float):
        """Record request result for backpressure adaptation"""
        if success:
            self.circuit_breaker.call_succeeded()
        else:
            self.circuit_breaker.call_failed()
        
        # Adapt token bucket based on performance
        if latency > 1.0:  # High latency indicates stress
            health_score = max(0.1, 1.0 - (latency - 1.0) / 10.0)
            self.token_bucket.adapt_to_backpressure(health_score)
    
    async def get_metrics(self) -> BackpressureMetrics:
        """Get current backpressure metrics"""
        import psutil
        
        cpu_usage = psutil.cpu_percent()
        memory_usage = psutil.virtual_memory().percent
        
        metrics = BackpressureMetrics(
            timestamp=time.time(),
            service_name=self.service_name,
            queue_depth=len(self.request_queue),
            processing_rate=len(self.request_queue) / 10.0,  # Simplified
            error_rate=self.circuit_breaker.failure_count / 100.0,
            latency_p99=0.5,  # Simplified
            cpu_usage=cpu_usage,
            memory_usage=memory_usage,
            active_connections=10  # Simplified
        )
        
        # Store metrics in Redis for dashboard
        await self.redis_client.lpush(
            f"metrics:{self.service_name}",
            json.dumps(asdict(metrics))
        )
        await self.redis_client.ltrim(f"metrics:{self.service_name}", 0, 99)
        
        return metrics

async def create_redis_client(host: str = "redis", port: int = 6379):
    """Create Redis client with proper error handling"""
    try:
        client = redis.Redis(host=host, port=port, decode_responses=True)
        await client.ping()
        return client
    except Exception as e:
        print(f"Failed to connect to Redis: {e}")
        return None

def setup_logging(service_name: str):
    """Setup structured logging for service"""
    logger = structlog.get_logger()
    logger = logger.bind(service=service_name)
    return logger
