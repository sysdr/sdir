from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import httpx
import redis
import time
import random
import asyncio
import logging
from enum import Enum
from prometheus_client import Counter, Histogram, Gauge, generate_latest
from fastapi.responses import Response
import os
import json

app = FastAPI(title="Gateway Service")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Redis connection
redis_client = redis.from_url(os.getenv("REDIS_URL", "redis://localhost:6379"))
backend_url = os.getenv("BACKEND_URL", "http://localhost:8001")

# Prometheus metrics
REQUEST_COUNT = Counter('gateway_requests_total', 'Total gateway requests', ['status', 'retry_attempt'])
RETRY_COUNT = Counter('gateway_retries_total', 'Total retry attempts', ['reason'])
CIRCUIT_BREAKER_STATE = Gauge('gateway_circuit_breaker_state', 'Circuit breaker state (0=closed, 1=open, 2=half_open)')
REQUEST_DURATION = Histogram('gateway_request_duration_seconds', 'Gateway request duration')

class CircuitBreakerState(Enum):
    CLOSED = 0
    OPEN = 1
    HALF_OPEN = 2

class RetryConfig(BaseModel):
    enabled: bool = True
    max_attempts: int = 3
    base_delay_ms: int = 100
    max_delay_ms: int = 5000
    exponential_backoff: bool = True
    jitter: bool = True

class CircuitBreakerConfig(BaseModel):
    enabled: bool = True
    failure_threshold: int = 5
    recovery_timeout_ms: int = 30000
    half_open_max_calls: int = 3

class GatewayConfig(BaseModel):
    retry: RetryConfig = RetryConfig()
    circuit_breaker: CircuitBreakerConfig = CircuitBreakerConfig()
    timeout_ms: int = 5000

# Global configuration
config = GatewayConfig()

class CircuitBreaker:
    def __init__(self, config: CircuitBreakerConfig):
        self.config = config
        self.state = CircuitBreakerState.CLOSED
        self.failure_count = 0
        self.last_failure_time = 0
        self.half_open_calls = 0
        
    def can_execute(self) -> bool:
        if not self.config.enabled:
            return True
            
        if self.state == CircuitBreakerState.CLOSED:
            return True
        elif self.state == CircuitBreakerState.OPEN:
            if time.time() * 1000 - self.last_failure_time > self.config.recovery_timeout_ms:
                self.state = CircuitBreakerState.HALF_OPEN
                self.half_open_calls = 0
                CIRCUIT_BREAKER_STATE.set(self.state.value)
                return True
            return False
        else:  # HALF_OPEN
            return self.half_open_calls < self.config.half_open_max_calls
    
    def record_success(self):
        if self.state == CircuitBreakerState.HALF_OPEN:
            self.half_open_calls += 1
            if self.half_open_calls >= self.config.half_open_max_calls:
                self.state = CircuitBreakerState.CLOSED
                self.failure_count = 0
                CIRCUIT_BREAKER_STATE.set(self.state.value)
        elif self.state == CircuitBreakerState.CLOSED:
            self.failure_count = max(0, self.failure_count - 1)
    
    def record_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time() * 1000
        
        if self.failure_count >= self.config.failure_threshold:
            self.state = CircuitBreakerState.OPEN
            CIRCUIT_BREAKER_STATE.set(self.state.value)

circuit_breaker = CircuitBreaker(config.circuit_breaker)

@app.get("/health")
async def health():
    return {"status": "healthy", "timestamp": time.time()}

@app.post("/config")
async def update_config(new_config: GatewayConfig):
    global config, circuit_breaker
    config = new_config
    circuit_breaker = CircuitBreaker(config.circuit_breaker)
    
    # Store in Redis
    redis_client.set("gateway:config", json.dumps(new_config.dict()))
    return config

@app.get("/config")
async def get_config():
    return config

@app.get("/status")
async def get_status():
    return {
        "circuit_breaker_state": circuit_breaker.state.name,
        "failure_count": circuit_breaker.failure_count,
        "config": config.dict()
    }

@app.post("/api/process")
async def process_with_retry(data: dict):
    start_time = time.time()
    
    if not circuit_breaker.can_execute():
        REQUEST_COUNT.labels(status='circuit_breaker_open', retry_attempt=0).inc()
        raise HTTPException(status_code=503, detail="Circuit breaker is open")
    
    last_exception = None
    
    for attempt in range(config.retry.max_attempts if config.retry.enabled else 1):
        try:
            async with httpx.AsyncClient(timeout=config.timeout_ms/1000) as client:
                response = await client.post(f"{backend_url}/process", json=data)
                
                if response.status_code == 200:
                    circuit_breaker.record_success()
                    REQUEST_COUNT.labels(status='success', retry_attempt=attempt).inc()
                    REQUEST_DURATION.observe(time.time() - start_time)
                    return response.json()
                else:
                    raise httpx.HTTPStatusError(f"HTTP {response.status_code}", request=None, response=response)
                    
        except Exception as e:
            last_exception = e
            circuit_breaker.record_failure()
            
            if attempt < config.retry.max_attempts - 1 and config.retry.enabled:
                RETRY_COUNT.labels(reason=type(e).__name__).inc()
                delay_ms = calculate_retry_delay(attempt)
                await asyncio.sleep(delay_ms / 1000)
            else:
                REQUEST_COUNT.labels(status='failed', retry_attempt=attempt).inc()
                REQUEST_DURATION.observe(time.time() - start_time)
                raise HTTPException(status_code=503, detail=f"Service unavailable after {attempt + 1} attempts")

def calculate_retry_delay(attempt: int) -> int:
    if not config.retry.exponential_backoff:
        delay_ms = config.retry.base_delay_ms
    else:
        delay_ms = min(config.retry.base_delay_ms * (2 ** attempt), config.retry.max_delay_ms)
    
    if config.retry.jitter:
        delay_ms = delay_ms * (0.5 + random.random() * 0.5)
    
    return int(delay_ms)

@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type="text/plain")

@app.on_event("startup")
async def startup():
    global config, circuit_breaker
    try:
        stored_config = redis_client.get("gateway:config")
        if stored_config:
            config_dict = json.loads(stored_config)
            config = GatewayConfig(**config_dict)
            circuit_breaker = CircuitBreaker(config.circuit_breaker)
    except Exception:
        pass

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
