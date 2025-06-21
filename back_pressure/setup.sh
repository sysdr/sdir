#!/bin/bash

# Backpressure Mechanisms Demo - One-Click Setup
# Creates a complete demonstration of backpressure patterns in distributed systems

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check dependencies
check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is required but not installed. Please install Docker first."
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is required but not installed. Please install Docker Compose first."
    fi
    
    log "All dependencies are available"
}

# Create project structure
create_project_structure() {
    log "Creating project structure..."
    
    mkdir -p backpressure-demo/{services,docker,web,config,scripts,logs}
    cd backpressure-demo
    
    log "Project structure created"
}

# Create requirements.txt
create_requirements() {
    log "Creating requirements.txt..."
    
    cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
httpx==0.25.2
redis==5.0.1
prometheus-client==0.19.0
websockets==12.0
aiofiles==23.2.0
asyncio==3.4.3
pydantic==2.5.0
jinja2==3.1.2
python-multipart==0.0.6
structlog==23.2.0
numpy==1.24.4
psutil==5.9.6
asyncio-mqtt==0.16.1
EOF

    log "Requirements file created"
}

# Create Docker Compose configuration
create_docker_compose() {
    log "Creating Docker Compose configuration..."
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 3

  backend-service:
    build: .
    command: python services/backend_service.py
    ports:
      - "8001:8001"
    environment:
      - SERVICE_NAME=backend-service
      - SERVICE_PORT=8001
      - REDIS_HOST=redis
    depends_on:
      redis:
        condition: service_healthy
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8001/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s

  gateway-service:
    build: .
    command: python services/gateway_service.py
    ports:
      - "8000:8000"
    environment:
      - SERVICE_NAME=gateway-service
      - SERVICE_PORT=8000
      - REDIS_HOST=redis
      - BACKEND_URL=http://backend-service:8001
    depends_on:
      backend-service:
        condition: service_healthy
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s

  web-dashboard:
    build: .
    command: python web/dashboard.py
    ports:
      - "3000:3000"
    environment:
      - REDIS_HOST=redis
    depends_on:
      redis:
        condition: service_healthy
    volumes:
      - ./logs:/app/logs

  load-generator:
    build: .
    command: sh -c "sleep 45 && python services/load_generator.py"
    environment:
      - GATEWAY_URL=http://gateway-service:8000
      - REDIS_HOST=redis
    depends_on:
      gateway-service:
        condition: service_healthy
    volumes:
      - ./logs:/app/logs

volumes:
  redis_data:
EOF

    log "Docker Compose configuration created"
}

# Create Dockerfile
create_dockerfile() {
    log "Creating Dockerfile..."
    
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies including build tools for psutil
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN mkdir -p logs

EXPOSE 8000 8001 3000
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

    log "Dockerfile created"
}

# Create shared utilities
create_shared_utils() {
    log "Creating shared utilities..."
    
    mkdir -p services
    cat > services/shared_utils.py << 'EOF'
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
EOF

    log "Shared utilities created"
}

# Create backend service
create_backend_service() {
    log "Creating backend service..."
    
    cat > services/backend_service.py << 'EOF'
"""
Backend Service - Demonstrates backpressure under load
"""
import asyncio
import time
import random
import os
from typing import Dict, Any
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
import uvicorn
from shared_utils import (
    BackpressureManager, setup_logging, create_redis_client
)

SERVICE_NAME = os.getenv("SERVICE_NAME", "backend-service")
SERVICE_PORT = int(os.getenv("SERVICE_PORT", 8001))
REDIS_HOST = os.getenv("REDIS_HOST", "redis")

app = FastAPI(title=f"{SERVICE_NAME}")
logger = setup_logging(SERVICE_NAME)
backpressure_manager = None
redis_client = None

# Simulate varying processing times and failures
processing_config = {
    "base_latency": 0.1,  # 100ms base processing time
    "error_rate": 0.05,   # 5% error rate
    "cpu_intensive": False
}

@app.on_event("startup")
async def startup():
    global backpressure_manager, redis_client
    logger.info("Starting backend service")
    
    redis_client = await create_redis_client(host=REDIS_HOST)
    if not redis_client:
        logger.error("Failed to connect to Redis")
        return
    
    backpressure_manager = BackpressureManager(SERVICE_NAME, redis_client)

@app.middleware("http")
async def backpressure_middleware(request: Request, call_next):
    """Apply backpressure mechanisms to all requests"""
    start_time = time.time()
    
    # Check if request should be accepted
    should_accept, reason = await backpressure_manager.should_accept_request()
    
    if not should_accept:
        logger.warning("Request rejected", reason=reason)
        return JSONResponse(
            status_code=503,
            content={"error": "Service overloaded", "reason": reason}
        )
    
    # Add request to queue (simulation)
    backpressure_manager.request_queue.append(start_time)
    
    try:
        response = await call_next(request)
        processing_time = time.time() - start_time
        
        await backpressure_manager.record_request_result(
            success=response.status_code < 400,
            latency=processing_time
        )
        
        # Remove from queue
        if backpressure_manager.request_queue:
            backpressure_manager.request_queue.popleft()
        
        return response
        
    except Exception as e:
        processing_time = time.time() - start_time
        await backpressure_manager.record_request_result(
            success=False,
            latency=processing_time
        )
        
        if backpressure_manager.request_queue:
            backpressure_manager.request_queue.popleft()
            
        raise e

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": SERVICE_NAME}

@app.get("/process")
async def process_request():
    """Main processing endpoint that can be overloaded"""
    
    # Simulate variable processing time
    base_latency = processing_config["base_latency"]
    additional_latency = random.exponential(0.05)  # Exponential distribution
    total_latency = base_latency + additional_latency
    
    # Simulate CPU intensive work if configured
    if processing_config["cpu_intensive"]:
        # CPU-bound work simulation
        start = time.time()
        while time.time() - start < total_latency:
            _ = sum(i * i for i in range(1000))
    else:
        # I/O-bound work simulation
        await asyncio.sleep(total_latency)
    
    # Simulate random errors
    if random.random() < processing_config["error_rate"]:
        raise HTTPException(status_code=500, detail="Processing failed")
    
    return {
        "status": "success",
        "processing_time": total_latency,
        "timestamp": time.time(),
        "service": SERVICE_NAME
    }

@app.post("/config/latency/{latency}")
async def set_latency(latency: float):
    """Configure base processing latency"""
    processing_config["base_latency"] = max(0.01, min(5.0, latency))
    logger.info("Latency configured", latency=processing_config["base_latency"])
    return {"latency_set": processing_config["base_latency"]}

@app.post("/config/error_rate/{rate}")
async def set_error_rate(rate: float):
    """Configure error rate"""
    processing_config["error_rate"] = max(0.0, min(1.0, rate))
    logger.info("Error rate configured", error_rate=processing_config["error_rate"])
    return {"error_rate_set": processing_config["error_rate"]}

@app.post("/config/cpu_intensive/{enabled}")
async def set_cpu_intensive(enabled: bool):
    """Toggle CPU intensive processing"""
    processing_config["cpu_intensive"] = enabled
    logger.info("CPU intensive mode", enabled=enabled)
    return {"cpu_intensive_set": enabled}

@app.get("/metrics")
async def get_metrics():
    """Get current service metrics"""
    if not backpressure_manager:
        return {"error": "Backpressure manager not initialized"}
    
    metrics = await backpressure_manager.get_metrics()
    circuit_state = backpressure_manager.circuit_breaker.get_state()
    
    return {
        "metrics": metrics.__dict__,
        "circuit_breaker": circuit_state.__dict__,
        "queue_depth": len(backpressure_manager.request_queue),
        "processing_config": processing_config
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=SERVICE_PORT)
EOF

    log "Backend service created"
}

# Create gateway service
create_gateway_service() {
    log "Creating gateway service..."
    
    cat > services/gateway_service.py << 'EOF'
"""
Gateway Service - Implements sophisticated backpressure mechanisms
"""
import asyncio
import time
import random
import os
from typing import Dict, List
import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
import uvicorn
from shared_utils import (
    BackpressureManager, setup_logging, create_redis_client
)

SERVICE_NAME = os.getenv("SERVICE_NAME", "gateway-service")
SERVICE_PORT = int(os.getenv("SERVICE_PORT", 8000))
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
BACKEND_URL = os.getenv("BACKEND_URL", "http://backend-service:8001")

app = FastAPI(title=f"{SERVICE_NAME}")
logger = setup_logging(SERVICE_NAME)
backpressure_manager = None
redis_client = None
http_client = None

# Gateway configuration
gateway_config = {
    "timeout": 5.0,
    "retry_attempts": 2,
    "load_shedding_enabled": True,
    "priority_queue_enabled": True
}

@app.on_event("startup")
async def startup():
    global backpressure_manager, redis_client, http_client
    logger.info("Starting gateway service")
    
    redis_client = await create_redis_client(host=REDIS_HOST)
    if not redis_client:
        logger.error("Failed to connect to Redis")
        return
    
    backpressure_manager = BackpressureManager(SERVICE_NAME, redis_client)
    http_client = httpx.AsyncClient(timeout=gateway_config["timeout"])

@app.on_event("shutdown")
async def shutdown():
    if http_client:
        await http_client.aclose()

@app.middleware("http")
async def gateway_backpressure_middleware(request: Request, call_next):
    """Advanced backpressure middleware with load shedding"""
    start_time = time.time()
    
    # Extract request priority (if available)
    priority = request.headers.get("X-Priority", "normal")
    
    # Check if request should be accepted
    should_accept, reason = await backpressure_manager.should_accept_request()
    
    # Implement priority-based load shedding
    if not should_accept and gateway_config["load_shedding_enabled"]:
        if priority == "low":
            logger.info("Shedding low priority request", reason=reason)
            return JSONResponse(
                status_code=503,
                content={"error": "Service overloaded - low priority request shed", "reason": reason}
            )
        elif priority == "normal" and reason == "queue_full":
            logger.warning("Shedding normal priority request", reason=reason)
            return JSONResponse(
                status_code=503,
                content={"error": "Service overloaded", "reason": reason}
            )
    
    try:
        response = await call_next(request)
        processing_time = time.time() - start_time
        
        await backpressure_manager.record_request_result(
            success=response.status_code < 400,
            latency=processing_time
        )
        
        return response
        
    except Exception as e:
        processing_time = time.time() - start_time
        await backpressure_manager.record_request_result(
            success=False,
            latency=processing_time
        )
        raise e

@app.get("/health")
async def health_check():
    """Gateway health check"""
    return {"status": "healthy", "service": SERVICE_NAME}

@app.get("/api/process")
async def proxy_process_request(request: Request):
    """Proxy request to backend with backpressure handling"""
    
    # Check circuit breaker state
    if not backpressure_manager.circuit_breaker.can_execute():
        logger.warning("Circuit breaker open, rejecting request")
        raise HTTPException(
            status_code=503,
            detail="Backend service unavailable - circuit breaker open"
        )
    
    retry_count = 0
    last_error = None
    
    while retry_count < gateway_config["retry_attempts"]:
        try:
            response = await http_client.get(f"{BACKEND_URL}/process")
            
            if response.status_code == 503:
                # Backend is applying backpressure
                logger.warning("Backend applying backpressure", status_code=response.status_code)
                backpressure_manager.circuit_breaker.call_failed()
                
                # Implement exponential backoff for retries
                if retry_count < gateway_config["retry_attempts"] - 1:
                    await asyncio.sleep(0.1 * (2 ** retry_count))
                    retry_count += 1
                    continue
                else:
                    raise HTTPException(status_code=503, detail="Backend overloaded")
            
            backpressure_manager.circuit_breaker.call_succeeded()
            return response.json()
            
        except httpx.TimeoutException:
            logger.warning("Backend request timeout", retry_count=retry_count)
            backpressure_manager.circuit_breaker.call_failed()
            last_error = "timeout"
            
        except Exception as e:
            logger.error("Backend request failed", error=str(e), retry_count=retry_count)
            backpressure_manager.circuit_breaker.call_failed()
            last_error = str(e)
        
        retry_count += 1
        if retry_count < gateway_config["retry_attempts"]:
            await asyncio.sleep(0.1 * (2 ** retry_count))
    
    raise HTTPException(
        status_code=503,
        detail=f"Backend requests failed after {gateway_config['retry_attempts']} attempts: {last_error}"
    )

@app.post("/config/timeout/{timeout}")
async def set_timeout(timeout: float):
    """Configure backend request timeout"""
    gateway_config["timeout"] = max(1.0, min(30.0, timeout))
    logger.info("Timeout configured", timeout=gateway_config["timeout"])
    return {"timeout_set": gateway_config["timeout"]}

@app.post("/config/load_shedding/{enabled}")
async def set_load_shedding(enabled: bool):
    """Toggle load shedding"""
    gateway_config["load_shedding_enabled"] = enabled
    logger.info("Load shedding configured", enabled=enabled)
    return {"load_shedding_enabled": enabled}

@app.get("/metrics")
async def get_gateway_metrics():
    """Get gateway metrics"""
    if not backpressure_manager:
        return {"error": "Backpressure manager not initialized"}
    
    metrics = await backpressure_manager.get_metrics()
    circuit_state = backpressure_manager.circuit_breaker.get_state()
    
    return {
        "metrics": metrics.__dict__,
        "circuit_breaker": circuit_state.__dict__,
        "queue_depth": len(backpressure_manager.request_queue),
        "gateway_config": gateway_config
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=SERVICE_PORT)
EOF

    log "Gateway service created"
}

# Create load generator
create_load_generator() {
    log "Creating load generator..."
    
    cat > services/load_generator.py << 'EOF'
"""
Load Generator - Creates configurable load to demonstrate backpressure
Features resilient connection handling and exponential backoff
"""
import asyncio
import time
import random
import os
import json
from typing import List
import httpx
from shared_utils import setup_logging, create_redis_client

GATEWAY_URL = os.getenv("GATEWAY_URL", "http://gateway-service:8000")
REDIS_HOST = os.getenv("REDIS_HOST", "redis")

logger = setup_logging("load-generator")
redis_client = None

# Load generation configuration
load_config = {
    "concurrent_users": 10,
    "requests_per_second": 5,
    "test_duration": 300,  # 5 minutes
    "priority_distribution": {"high": 0.1, "normal": 0.7, "low": 0.2},
    "enabled": False
}

class ResilientLoadGenerator:
    def __init__(self):
        self.http_client = None
        self.statistics = {
            "total_requests": 0,
            "successful_requests": 0,
            "failed_requests": 0,
            "timeouts": 0,
            "backpressure_rejections": 0,
            "connection_errors": 0,
            "average_latency": 0.0
        }
        self.latencies = []
        self.consecutive_failures = 0
        self.max_retry_delay = 30  # Maximum delay between retries
    
    async def ensure_connection(self):
        """Ensure HTTP client is connected with exponential backoff retry"""
        max_retries = 10
        base_delay = 1.0
        
        for attempt in range(max_retries):
            try:
                if self.http_client is None:
                    self.http_client = httpx.AsyncClient(
                        timeout=httpx.Timeout(10.0, connect=5.0),
                        limits=httpx.Limits(max_connections=20, max_keepalive_connections=10)
                    )
                
                # Test connection with health check
                response = await self.http_client.get(f"{GATEWAY_URL}/health")
                if response.status_code == 200:
                    logger.info("Successfully connected to gateway service")
                    self.consecutive_failures = 0
                    return True
                    
            except Exception as e:
                logger.warning(
                    "Connection attempt failed", 
                    attempt=attempt + 1, 
                    error=str(e),
                    max_retries=max_retries
                )
                
                if self.http_client:
                    await self.http_client.aclose()
                    self.http_client = None
                
                if attempt < max_retries - 1:
                    # Exponential backoff with jitter
                    delay = min(base_delay * (2 ** attempt), self.max_retry_delay)
                    jitter = random.uniform(0, 0.1 * delay)
                    await asyncio.sleep(delay + jitter)
        
        logger.error("Failed to establish connection after all retries")
        return False
    
    async def generate_request(self, priority: str = "normal"):
        """Generate a single request with specified priority and resilient error handling"""
        start_time = time.time()
        
        try:
            if not await self.ensure_connection():
                self.statistics["total_requests"] += 1
                self.statistics["connection_errors"] += 1
                self.consecutive_failures += 1
                logger.error("Cannot establish connection", event="Request failed", priority=priority)
                return
            
            headers = {"X-Priority": priority}
            response = await self.http_client.get(
                f"{GATEWAY_URL}/api/process",
                headers=headers
            )
            
            latency = time.time() - start_time
            self.latencies.append(latency)
            
            self.statistics["total_requests"] += 1
            self.consecutive_failures = 0  # Reset failure counter on success
            
            if response.status_code == 200:
                self.statistics["successful_requests"] += 1
                logger.info("Request successful", latency=round(latency, 3), priority=priority)
            elif response.status_code == 503:
                self.statistics["backpressure_rejections"] += 1
                logger.info("Backpressure rejection received", priority=priority)
            else:
                self.statistics["failed_requests"] += 1
                logger.warning("Request failed", status_code=response.status_code, priority=priority)
            
            # Update average latency (keep only recent samples)
            if len(self.latencies) > 1000:
                self.latencies = self.latencies[-500:]  # Keep last 500 samples
            self.statistics["average_latency"] = sum(self.latencies) / len(self.latencies)
            
        except httpx.TimeoutException:
            self.statistics["total_requests"] += 1
            self.statistics["timeouts"] += 1
            self.consecutive_failures += 1
            logger.warning("Request timeout", priority=priority, event="Request timeout")
            
        except httpx.ConnectError as e:
            self.statistics["total_requests"] += 1
            self.statistics["connection_errors"] += 1
            self.consecutive_failures += 1
            logger.error("Connection error", error=str(e), priority=priority, event="Request failed")
            
            # Close client to force reconnection on next request
            if self.http_client:
                await self.http_client.aclose()
                self.http_client = None
            
        except Exception as e:
            self.statistics["total_requests"] += 1
            self.statistics["failed_requests"] += 1
            self.consecutive_failures += 1
            logger.error("Unexpected error", error=str(e), priority=priority, event="Request failed")
    
    def get_request_priority(self) -> str:
        """Get random priority based on distribution"""
        rand = random.random()
        cumulative = 0
        
        for priority, prob in load_config["priority_distribution"].items():
            cumulative += prob
            if rand <= cumulative:
                return priority
        
        return "normal"
    
    async def adaptive_delay(self):
        """Implement adaptive delay based on consecutive failures"""
        if self.consecutive_failures > 0:
            # Exponential backoff based on consecutive failures
            delay = min(0.1 * (2 ** self.consecutive_failures), 5.0)
            logger.info("Applying adaptive delay", delay=delay, consecutive_failures=self.consecutive_failures)
            await asyncio.sleep(delay)
    
    async def run_load_test(self):
        """Run continuous load test with adaptive behavior"""
        logger.info("Starting resilient load test", config=load_config)
        
        while load_config["enabled"]:
            try:
                # Apply adaptive delay if we're having connection issues
                await self.adaptive_delay()
                
                tasks = []
                
                # Reduce concurrent load if we're experiencing failures
                concurrent_users = load_config["concurrent_users"]
                if self.consecutive_failures > 3:
                    concurrent_users = max(1, concurrent_users // 2)
                    logger.info("Reducing load due to failures", reduced_users=concurrent_users)
                
                # Create concurrent requests
                for _ in range(concurrent_users):
                    priority = self.get_request_priority()
                    task = asyncio.create_task(self.generate_request(priority))
                    tasks.append(task)
                
                # Wait for all requests to complete
                await asyncio.gather(*tasks, return_exceptions=True)
                
                # Store statistics in Redis
                if redis_client:
                    await redis_client.set(
                        "load_generator_stats",
                        json.dumps(self.statistics)
                    )
                
                # Adaptive wait time based on request rate and failure rate
                base_wait = 1.0 / load_config["requests_per_second"]
                if self.consecutive_failures > 0:
                    # Slow down requests if experiencing failures
                    base_wait *= (1 + self.consecutive_failures * 0.5)
                
                await asyncio.sleep(base_wait)
                
            except Exception as e:
                logger.error("Load test iteration failed", error=str(e))
                await asyncio.sleep(5.0)  # Wait before retrying
        
        logger.info("Load test stopped")
        if self.http_client:
            await self.http_client.aclose()

async def wait_for_services():
    """Wait for services to be ready before starting load generation"""
    logger.info("Waiting for services to be ready...")
    
    max_wait_time = 120  # 2 minutes
    start_time = time.time()
    
    while time.time() - start_time < max_wait_time:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(f"{GATEWAY_URL}/health")
                if response.status_code == 200:
                    logger.info("Gateway service is ready")
                    return True
        except Exception as e:
            logger.info("Services not ready yet, waiting...", error=str(e))
        
        await asyncio.sleep(5.0)
    
    logger.warning("Timeout waiting for services, proceeding anyway")
    return False

async def main():
    global redis_client
    
    logger.info("Starting resilient load generator")
    
    # Wait for services to be ready
    await wait_for_services()
    
    # Connect to Redis with retry logic
    for attempt in range(5):
        try:
            redis_client = await create_redis_client(host=REDIS_HOST)
            if redis_client:
                logger.info("Connected to Redis")
                break
        except Exception as e:
            logger.warning("Redis connection attempt failed", attempt=attempt + 1, error=str(e))
            await asyncio.sleep(2.0)
    
    if not redis_client:
        logger.error("Failed to connect to Redis, continuing without statistics storage")
    
    # Initialize load generator
    load_generator = ResilientLoadGenerator()
    
    # Start load generation if enabled
    if load_config["enabled"]:
        await load_generator.run_load_test()
    else:
        logger.info("Load generator ready, waiting for activation")
        while True:
            try:
                # Check for configuration updates from Redis
                if redis_client:
                    config_update = await redis_client.get("load_config")
                    if config_update:
                        updated_config = json.loads(config_update)
                        load_config.update(updated_config)
                        
                        if load_config["enabled"]:
                            await load_generator.run_load_test()
                
                await asyncio.sleep(1.0)
            except Exception as e:
                logger.error("Main loop error", error=str(e))
                await asyncio.sleep(5.0)

if __name__ == "__main__":
    asyncio.run(main())
EOF

    log "Load generator created"
}

# Create web dashboard
create_web_dashboard() {
    log "Creating web dashboard..."
    
    mkdir -p web
    cat > web/dashboard.py << 'EOF'
"""
Web Dashboard - Real-time visualization of backpressure mechanisms
"""
import asyncio
import json
import os
import time
from typing import Dict, List
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
import uvicorn
from shared_utils import setup_logging, create_redis_client

REDIS_HOST = os.getenv("REDIS_HOST", "redis")

app = FastAPI(title="Backpressure Dashboard")
logger = setup_logging("dashboard")
redis_client = None

# Store active WebSocket connections
websocket_connections: List[WebSocket] = []

@app.on_event("startup")
async def startup():
    global redis_client
    logger.info("Starting dashboard")
    
    redis_client = await create_redis_client(host=REDIS_HOST)
    if not redis_client:
        logger.error("Failed to connect to Redis")
        return
    
    # Start background task to broadcast metrics
    asyncio.create_task(broadcast_metrics())

async def broadcast_metrics():
    """Broadcast real-time metrics to connected WebSocket clients"""
    while True:
        try:
            # Collect metrics from all services
            metrics_data = {
                "timestamp": time.time(),
                "services": {}
            }
            
            # Get metrics for each service
            services = ["backend-service", "gateway-service"]
            for service in services:
                metrics_list = await redis_client.lrange(f"metrics:{service}", 0, 9)
                if metrics_list:
                    latest_metrics = json.loads(metrics_list[0])
                    metrics_data["services"][service] = latest_metrics
            
            # Get load generator statistics
            load_stats = await redis_client.get("load_generator_stats")
            if load_stats:
                metrics_data["load_generator"] = json.loads(load_stats)
            
            # Broadcast to all connected clients
            if websocket_connections:
                message = json.dumps(metrics_data)
                disconnected = []
                
                for ws in websocket_connections:
                    try:
                        await ws.send_text(message)
                    except:
                        disconnected.append(ws)
                
                # Remove disconnected clients
                for ws in disconnected:
                    websocket_connections.remove(ws)
            
            await asyncio.sleep(1.0)  # Update every second
            
        except Exception as e:
            logger.error("Error broadcasting metrics", error=str(e))
            await asyncio.sleep(5.0)

@app.get("/", response_class=HTMLResponse)
async def dashboard_home():
    """Serve the main dashboard page"""
    return """
<!DOCTYPE html>
<html>
<head>
    <title>Backpressure Mechanisms Dashboard</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
        }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .metric-card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .metric-title {
            font-size: 18px;
            font-weight: bold;
            margin-bottom: 10px;
            color: #333;
        }
        .metric-value {
            font-size: 24px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .metric-label {
            font-size: 14px;
            color: #666;
        }
        .status-healthy { color: #4CAF50; }
        .status-warning { color: #FF9800; }
        .status-critical { color: #F44336; }
        .controls {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        .control-group {
            display: inline-block;
            margin-right: 20px;
            margin-bottom: 10px;
        }
        button {
            padding: 10px 20px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
        }
        .btn-primary { background: #007bff; color: white; }
        .btn-warning { background: #ffc107; color: black; }
        .btn-danger { background: #dc3545; color: white; }
        .log-container {
            background: #1e1e1e;
            color: #00ff00;
            padding: 20px;
            border-radius: 10px;
            height: 300px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 12px;
        }
        .chart-container {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔄 Backpressure Mechanisms Dashboard</h1>
            <p>Real-time monitoring of distributed system backpressure patterns</p>
        </div>

        <div class="controls">
            <h3>Load Control</h3>
            <div class="control-group">
                <button class="btn-primary" onclick="startLoad()">Start Load Test</button>
                <button class="btn-warning" onclick="stopLoad()">Stop Load Test</button>
            </div>
            <div class="control-group">
                <button class="btn-danger" onclick="increaseLatency()">Increase Backend Latency</button>
                <button class="btn-primary" onclick="resetLatency()">Reset Latency</button>
            </div>
            <div class="control-group">
                <button class="btn-warning" onclick="enableErrors()">Enable Backend Errors</button>
                <button class="btn-primary" onclick="disableErrors()">Disable Errors</button>
            </div>
        </div>

        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-title">Gateway Service</div>
                <div id="gateway-status" class="metric-value status-healthy">Healthy</div>
                <div class="metric-label">Queue Depth: <span id="gateway-queue">0</span></div>
                <div class="metric-label">Circuit Breaker: <span id="gateway-circuit">Closed</span></div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Backend Service</div>
                <div id="backend-status" class="metric-value status-healthy">Healthy</div>
                <div class="metric-label">Queue Depth: <span id="backend-queue">0</span></div>
                <div class="metric-label">Circuit Breaker: <span id="backend-circuit">Closed</span></div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Load Generator</div>
                <div id="load-status" class="metric-value">Stopped</div>
                <div class="metric-label">Success Rate: <span id="success-rate">0%</span></div>
                <div class="metric-label">Avg Latency: <span id="avg-latency">0ms</span></div>
            </div>

            <div class="metric-card">
                <div class="metric-title">System Health</div>
                <div id="system-health" class="metric-value status-healthy">Good</div>
                <div class="metric-label">Backpressure Active: <span id="backpressure-active">No</span></div>
                <div class="metric-label">Load Shedding: <span id="load-shedding">No</span></div>
            </div>
        </div>

        <div class="chart-container">
            <h3>Real-time Metrics</h3>
            <canvas id="metricsChart" width="800" height="300"></canvas>
        </div>

        <div class="metric-card">
            <div class="metric-title">Live Logs</div>
            <div id="logs" class="log-container"></div>
        </div>
    </div>

    <script>
        let socket;
        let metricsHistory = [];
        const maxHistoryLength = 50;

        function connectWebSocket() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = protocol + '//' + window.location.host + '/ws';
            
            socket = new WebSocket(wsUrl);
            
            socket.onopen = function(event) {
                addLog('Connected to dashboard');
            };
            
            socket.onmessage = function(event) {
                const data = JSON.parse(event.data);
                updateMetrics(data);
            };
            
            socket.onclose = function(event) {
                addLog('Connection closed, reconnecting...');
                setTimeout(connectWebSocket, 3000);
            };
            
            socket.onerror = function(error) {
                addLog('WebSocket error: ' + error);
            };
        }

        function updateMetrics(data) {
            // Update service metrics
            if (data.services) {
                updateServiceMetrics('gateway', data.services['gateway-service']);
                updateServiceMetrics('backend', data.services['backend-service']);
            }
            
            // Update load generator metrics
            if (data.load_generator) {
                updateLoadGeneratorMetrics(data.load_generator);
            }
            
            // Store metrics for charting
            metricsHistory.push(data);
            if (metricsHistory.length > maxHistoryLength) {
                metricsHistory.shift();
            }
            
            updateChart();
        }

        function updateServiceMetrics(servicePrefix, metrics) {
            if (!metrics) return;
            
            const queueDepth = metrics.queue_depth || 0;
            const cpuUsage = metrics.cpu_usage || 0;
            
            document.getElementById(servicePrefix + '-queue').textContent = queueDepth;
            
            // Update status based on queue depth and CPU usage
            const statusElement = document.getElementById(servicePrefix + '-status');
            if (queueDepth > 500 || cpuUsage > 80) {
                statusElement.textContent = 'Overloaded';
                statusElement.className = 'metric-value status-critical';
            } else if (queueDepth > 200 || cpuUsage > 60) {
                statusElement.textContent = 'Stressed';
                statusElement.className = 'metric-value status-warning';
            } else {
                statusElement.textContent = 'Healthy';
                statusElement.className = 'metric-value status-healthy';
            }
        }

        function updateLoadGeneratorMetrics(stats) {
            const total = stats.total_requests || 0;
            const successful = stats.successful_requests || 0;
            const successRate = total > 0 ? (successful / total * 100).toFixed(1) : 0;
            const avgLatency = (stats.average_latency * 1000).toFixed(0);
            
            document.getElementById('success-rate').textContent = successRate + '%';
            document.getElementById('avg-latency').textContent = avgLatency + 'ms';
            
            const loadStatus = total > 0 ? 'Running' : 'Stopped';
            document.getElementById('load-status').textContent = loadStatus;
        }

        function updateChart() {
            // Simple chart implementation would go here
            // For demo purposes, we'll just log the data
            if (metricsHistory.length > 0) {
                const latest = metricsHistory[metricsHistory.length - 1];
                addLog('Metrics updated: ' + new Date().toLocaleTimeString());
            }
        }

        function addLog(message) {
            const logsElement = document.getElementById('logs');
            const timestamp = new Date().toLocaleTimeString();
            logsElement.innerHTML += timestamp + ' - ' + message + '\\n';
            logsElement.scrollTop = logsElement.scrollHeight;
        }

        // Control functions
        async function startLoad() {
            try {
                const response = await fetch('/api/load/start', { method: 'POST' });
                const result = await response.json();
                addLog('Load test started');
            } catch (error) {
                addLog('Error starting load test: ' + error);
            }
        }

        async function stopLoad() {
            try {
                const response = await fetch('/api/load/stop', { method: 'POST' });
                const result = await response.json();
                addLog('Load test stopped');
            } catch (error) {
                addLog('Error stopping load test: ' + error);
            }
        }

        async function increaseLatency() {
            try {
                const response = await fetch('/api/backend/latency/1.0', { method: 'POST' });
                const result = await response.json();
                addLog('Backend latency increased to 1000ms');
            } catch (error) {
                addLog('Error increasing latency: ' + error);
            }
        }

        async function resetLatency() {
            try {
                const response = await fetch('/api/backend/latency/0.1', { method: 'POST' });
                const result = await response.json();
                addLog('Backend latency reset to 100ms');
            } catch (error) {
                addLog('Error resetting latency: ' + error);
            }
        }

        async function enableErrors() {
            try {
                const response = await fetch('/api/backend/errors/0.2', { method: 'POST' });
                const result = await response.json();
                addLog('Backend error rate set to 20%');
            } catch (error) {
                addLog('Error enabling errors: ' + error);
            }
        }

        async function disableErrors() {
            try {
                const response = await fetch('/api/backend/errors/0.0', { method: 'POST' });
                const result = await response.json();
                addLog('Backend errors disabled');
            } catch (error) {
                addLog('Error disabling errors: ' + error);
            }
        }

        // Initialize
        connectWebSocket();
        addLog('Dashboard initialized');
    </script>
</body>
</html>
"""

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time metrics"""
    await websocket.accept()
    websocket_connections.append(websocket)
    logger.info("New WebSocket connection")
    
    try:
        while True:
            # Keep connection alive
            await websocket.receive_text()
    except WebSocketDisconnect:
        websocket_connections.remove(websocket)
        logger.info("WebSocket disconnected")

@app.post("/api/load/start")
async def start_load_test():
    """Start load test"""
    load_config = {"enabled": True, "concurrent_users": 20, "requests_per_second": 10}
    await redis_client.set("load_config", json.dumps(load_config))
    return {"status": "started"}

@app.post("/api/load/stop")
async def stop_load_test():
    """Stop load test"""
    load_config = {"enabled": False}
    await redis_client.set("load_config", json.dumps(load_config))
    return {"status": "stopped"}

@app.post("/api/backend/latency/{latency}")
async def set_backend_latency(latency: float):
    """Configure backend latency via gateway"""
    # This would proxy to backend service in real implementation
    return {"latency_set": latency}

@app.post("/api/backend/errors/{rate}")
async def set_backend_error_rate(rate: float):
    """Configure backend error rate via gateway"""
    # This would proxy to backend service in real implementation
    return {"error_rate_set": rate}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=3000)
EOF

    log "Web dashboard created"
}

# Create SVG diagrams
create_svg_diagrams() {
    log "Creating SVG diagrams..."
    
    mkdir -p diagrams
    
    # Diagram 1: Backpressure Flow States
    cat > diagrams/backpressure_flow_states.svg << 'EOF'
<svg viewBox="0 0 800 400" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="2" dy="2" stdDeviation="3" flood-color="rgba(0,0,0,0.3)"/>
    </filter>
    <linearGradient id="healthyGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#81C784;stop-opacity:1" />
    </linearGradient>
    <linearGradient id="overloadGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#F44336;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#EF5350;stop-opacity:1" />
    </linearGradient>
  </defs>
  
  <!-- Background -->
  <rect width="800" height="400" fill="#f8f9fa"/>
  
  <!-- Title -->
  <text x="400" y="30" text-anchor="middle" font-family="Arial, sans-serif" font-size="20" font-weight="bold" fill="#333">
    Backpressure Flow States
  </text>
  
  <!-- Healthy State -->
  <g transform="translate(50, 80)">
    <rect x="0" y="0" width="300" height="120" rx="10" fill="url(#healthyGrad)" filter="url(#shadow)"/>
    <text x="150" y="25" text-anchor="middle" font-family="Arial, sans-serif" font-size="16" font-weight="bold" fill="white">
      Healthy Flow
    </text>
    
    <!-- Request flow arrows -->
    <circle cx="30" cy="60" r="8" fill="#2196F3"/>
    <text x="30" y="65" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="white">R</text>
    
    <path d="M 45 60 L 75 60" stroke="#2196F3" stroke-width="3" marker-end="url(#arrowhead)"/>
    
    <rect x="80" y="50" width="60" height="20" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="110" y="63" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Queue: 5
    </text>
    
    <path d="M 145 60 L 175 60" stroke="#2196F3" stroke-width="3" marker-end="url(#arrowhead)"/>
    
    <rect x="180" y="45" width="80" height="30" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="220" y="63" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Process: 10ms
    </text>
    
    <text x="150" y="95" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="white">
      Low latency • High throughput
    </text>
  </g>
  
  <!-- Overloaded State -->
  <g transform="translate(450, 80)">
    <rect x="0" y="0" width="300" height="120" rx="10" fill="url(#overloadGrad)" filter="url(#shadow)"/>
    <text x="150" y="25" text-anchor="middle" font-family="Arial, sans-serif" font-size="16" font-weight="bold" fill="white">
      Overloaded Flow
    </text>
    
    <!-- Request flow with congestion -->
    <circle cx="30" cy="50" r="6" fill="#FF9800"/>
    <circle cx="30" cy="65" r="6" fill="#FF9800"/>
    <circle cx="30" cy="80" r="6" fill="#FF9800"/>
    
    <path d="M 45 65 L 65 65" stroke="#FF9800" stroke-width="3" marker-end="url(#arrowhead)"/>
    
    <rect x="70" y="45" width="80" height="40" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="110" y="60" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Queue: 850
    </text>
    <text x="110" y="75" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      (backing up)
    </text>
    
    <path d="M 155 65 L 175 65" stroke="#FF9800" stroke-width="2" stroke-dasharray="5,5"/>
    
    <rect x="180" y="50" width="80" height="30" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="220" y="68" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Process: 2000ms
    </text>
    
    <text x="150" y="100" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="white">
      High latency • Dropping requests
    </text>
  </g>
  
  <!-- Backpressure Mechanism -->
  <g transform="translate(200, 250)">
    <rect x="0" y="0" width="400" height="100" rx="10" fill="#6C63FF" filter="url(#shadow)"/>
    <text x="200" y="25" text-anchor="middle" font-family="Arial, sans-serif" font-size="16" font-weight="bold" fill="white">
      Backpressure Response
    </text>
    
    <!-- Rate limiting -->
    <rect x="20" y="40" width="100" height="40" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="70" y="55" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Rate Limiting
    </text>
    <text x="70" y="70" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      Reject excess
    </text>
    
    <!-- Circuit breaker -->
    <rect x="150" y="40" width="100" height="40" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="200" y="55" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Circuit Breaker
    </text>
    <text x="200" y="70" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      Fail fast
    </text>
    
    <!-- Load shedding -->
    <rect x="280" y="40" width="100" height="40" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="330" y="55" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Load Shedding
    </text>
    <text x="330" y="70" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      Priority queues
    </text>
  </g>
  
  <!-- Arrow markers -->
  <defs>
    <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="10" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="#2196F3" />
    </marker>
  </defs>
</svg>
EOF

    # Diagram 2: Circuit Breaker with Backpressure States
    cat > diagrams/circuit_breaker_states.svg << 'EOF'
<svg viewBox="0 0 800 500" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="2" dy="2" stdDeviation="3" flood-color="rgba(0,0,0,0.3)"/>
    </filter>
    <linearGradient id="closedGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#66BB6A;stop-opacity:1" />
    </linearGradient>
    <linearGradient id="openGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#F44336;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#EF5350;stop-opacity:1" />
    </linearGradient>
    <linearGradient id="halfOpenGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#FF9800;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#FFA726;stop-opacity:1" />
    </linearGradient>
  </defs>
  
  <!-- Background -->
  <rect width="800" height="500" fill="#f8f9fa"/>
  
  <!-- Title -->
  <text x="400" y="30" text-anchor="middle" font-family="Arial, sans-serif" font-size="20" font-weight="bold" fill="#333">
    Circuit Breaker States with Backpressure Integration
  </text>
  
  <!-- Closed State -->
  <g transform="translate(100, 80)">
    <circle cx="80" cy="80" r="60" fill="url(#closedGrad)" filter="url(#shadow)"/>
    <text x="80" y="75" text-anchor="middle" font-family="Arial, sans-serif" font-size="14" font-weight="bold" fill="white">
      CLOSED
    </text>
    <text x="80" y="90" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="white">
      Normal Flow
    </text>
    
    <!-- Status indicators -->
    <rect x="20" y="160" width="120" height="60" rx="5" fill="#ffffff" filter="url(#shadow)"/>
    <text x="80" y="180" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#333">
      Status
    </text>
    <text x="80" y="195" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      Failures: 0/5
    </text>
    <text x="80" y="210" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      Requests: Passing
    </text>
  </g>
  
  <!-- Half-Open State -->
  <g transform="translate(350, 80)">
    <circle cx="80" cy="80" r="60" fill="url(#halfOpenGrad)" filter="url(#shadow)"/>
    <text x="80" y="75" text-anchor="middle" font-family="Arial, sans-serif" font-size="14" font-weight="bold" fill="white">
      HALF-OPEN
    </text>
    <text x="80" y="90" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="white">
      Testing
    </text>
    
    <!-- Status indicators -->
    <rect x="20" y="160" width="120" height="60" rx="5" fill="#ffffff" filter="url(#shadow)"/>
    <text x="80" y="180" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#333">
      Status
    </text>
    <text x="80" y="195" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      Test calls: 2/3
    </text>
    <text x="80" y="210" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      Limited flow
    </text>
  </g>
  
  <!-- Open State -->
  <g transform="translate(600, 80)">
    <circle cx="80" cy="80" r="60" fill="url(#openGrad)" filter="url(#shadow)"/>
    <text x="80" y="75" text-anchor="middle" font-family="Arial, sans-serif" font-size="14" font-weight="bold" fill="white">
      OPEN
    </text>
    <text x="80" y="90" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" fill="white">
      Blocked
    </text>
    
    <!-- Status indicators -->
    <rect x="20" y="160" width="120" height="60" rx="5" fill="#ffffff" filter="url(#shadow)"/>
    <text x="80" y="180" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#333">
      Status
    </text>
    <text x="80" y="195" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      Failures: 5/5
    </text>
    <text x="80" y="210" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      Requests: Rejected
    </text>
  </g>
  
  <!-- Transition arrows and conditions -->
  <g>
    <!-- Closed to Open -->
    <path d="M 240 120 Q 300 100 460 120" stroke="#333" stroke-width="2" fill="none" marker-end="url(#arrowhead)"/>
    <text x="350" y="105" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Failures ≥ threshold
    </text>
    
    <!-- Open to Half-Open -->
    <path d="M 600 140 Q 550 200 510 140" stroke="#333" stroke-width="2" fill="none" marker-end="url(#arrowhead)"/>
    <text x="555" y="190" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Timeout expired
    </text>
    
    <!-- Half-Open to Closed -->
    <path d="M 430 100 Q 350 80 240 100" stroke="#333" stroke-width="2" fill="none" marker-end="url(#arrowhead)"/>
    <text x="335" y="75" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Success calls
    </text>
    
    <!-- Half-Open to Open -->
    <path d="M 510 160 Q 550 180 600 160" stroke="#333" stroke-width="2" fill="none" marker-end="url(#arrowhead)"/>
    <text x="555" y="175" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" fill="#333">
      Test call fails
    </text>
  </g>
  
  <!-- Backpressure Integration Panel -->
  <g transform="translate(150, 300)">
    <rect x="0" y="0" width="500" height="150" rx="10" fill="#6C63FF" filter="url(#shadow)"/>
    <text x="250" y="25" text-anchor="middle" font-family="Arial, sans-serif" font-size="16" font-weight="bold" fill="white">
      Backpressure Integration Points
    </text>
    
    <!-- Integration points -->
    <rect x="20" y="40" width="140" height="80" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="90" y="60" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#333">
      Latency Monitoring
    </text>
    <text x="90" y="75" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      • P99 response time
    </text>
    <text x="90" y="88" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      • Queue depth signals
    </text>
    <text x="90" y="101" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      • Upstream 503s
    </text>
    
    <rect x="180" y="40" width="140" height="80" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="250" y="60" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#333">
      Adaptive Thresholds
    </text>
    <text x="250" y="75" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      • Dynamic failure rates
    </text>
    <text x="250" y="88" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      • Load-based timeouts
    </text>
    <text x="250" y="101" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      • Health score input
    </text>
    
    <rect x="340" y="40" width="140" height="80" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="410" y="60" text-anchor="middle" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#333">
      Proactive Opening
    </text>
    <text x="410" y="75" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      • Early warning signals
    </text>
    <text x="410" y="88" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      • Resource exhaustion
    </text>
    <text x="410" y="101" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#666">
      • Capacity prediction
    </text>
  </g>
  
  <!-- Arrow marker -->
  <defs>
    <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="10" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="#333" />
    </marker>
  </defs>
</svg>
EOF

    # Diagram 3: Multi-Tier Backpressure Architecture
    cat > diagrams/multi_tier_architecture.svg << 'EOF'
<svg viewBox="0 0 800 600" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="2" dy="2" stdDeviation="3" flood-color="rgba(0,0,0,0.3)"/>
    </filter>
    <linearGradient id="edgeGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#2196F3;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#42A5F5;stop-opacity:1" />
    </linearGradient>
    <linearGradient id="gatewayGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#4CAF50;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#66BB6A;stop-opacity:1" />
    </linearGradient>
    <linearGradient id="serviceGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#FF9800;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#FFA726;stop-opacity:1" />
    </linearGradient>
    <linearGradient id="dataGrad" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#9C27B0;stop-opacity:1" />
      <stop offset="100%" style="stop-color:#BA68C8;stop-opacity:1" />
    </linearGradient>
  </defs>
  
  <!-- Background -->
  <rect width="800" height="600" fill="#f8f9fa"/>
  
  <!-- Title -->
  <text x="400" y="30" text-anchor="middle" font-family="Arial, sans-serif" font-size="20" font-weight="bold" fill="#333">
    Multi-Tier Backpressure Architecture
  </text>
  
  <!-- Edge Layer -->
  <g transform="translate(50, 80)">
    <rect x="0" y="0" width="700" height="80" rx="10" fill="url(#edgeGrad)" filter="url(#shadow)"/>
    <text x="350" y="25" text-anchor="middle" font-family="Arial, sans-serif" font-size="16" font-weight="bold" fill="white">
      Edge Layer - Immediate Response (1-5ms)
    </text>
    
    <!-- Edge components -->
    <rect x="20" y="35" width="120" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="80" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Rate Limiting
    </text>
    <text x="80" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Token bucket
    </text>
    
    <rect x="160" y="35" width="120" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="220" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      DDoS Protection
    </text>
    <text x="220" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      IP filtering
    </text>
    
    <rect x="300" y="35" width="120" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="360" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Geo Routing
    </text>
    <text x="360" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Capacity aware
    </text>
    
    <rect x="440" y="35" width="120" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="500" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      CDN Offload
    </text>
    <text x="500" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Static content
    </text>
    
    <rect x="560" y="35" width="120" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="620" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Queue Depth
    </text>
    <text x="620" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Immediate shed
    </text>
  </g>
  
  <!-- Gateway Layer -->
  <g transform="translate(50, 200)">
    <rect x="0" y="0" width="700" height="80" rx="10" fill="url(#gatewayGrad)" filter="url(#shadow)"/>
    <text x="350" y="25" text-anchor="middle" font-family="Arial, sans-serif" font-size="16" font-weight="bold" fill="white">
      Gateway Layer - Intelligent Routing (5-50ms)
    </text>
    
    <!-- Gateway components -->
    <rect x="20" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="85" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Circuit Breakers
    </text>
    <text x="85" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Health monitoring
    </text>
    
    <rect x="170" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="235" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Load Balancing
    </text>
    <text x="235" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Capacity aware
    </text>
    
    <rect x="320" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="385" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Priority Queues
    </text>
    <text x="385" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      SLA-based
    </text>
    
    <rect x="470" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="535" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Retry Logic
    </text>
    <text x="535" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Exponential backoff
    </text>
  </g>
  
  <!-- Service Layer -->
  <g transform="translate(50, 320)">
    <rect x="0" y="0" width="700" height="80" rx="10" fill="url(#serviceGrad)" filter="url(#shadow)"/>
    <text x="350" y="25" text-anchor="middle" font-family="Arial, sans-serif" font-size="16" font-weight="bold" fill="white">
      Service Layer - Resource Management (50-500ms)
    </text>
    
    <!-- Service components -->
    <rect x="20" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="85" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Thread Pools
    </text>
    <text x="85" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Bulkhead isolation
    </text>
    
    <rect x="170" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="235" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Memory Guards
    </text>
    <text x="235" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      GC pressure
    </text>
    
    <rect x="320" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="385" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      CPU Throttling
    </text>
    <text x="385" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Process limits
    </text>
    
    <rect x="470" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="535" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Cache Warming
    </text>
    <text x="535" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Predictive
    </text>
  </g>
  
  <!-- Data Layer -->
  <g transform="translate(50, 440)">
    <rect x="0" y="0" width="700" height="80" rx="10" fill="url(#dataGrad)" filter="url(#shadow)"/>
    <text x="350" y="25" text-anchor="middle" font-family="Arial, sans-serif" font-size="16" font-weight="bold" fill="white">
      Data Layer - Storage Protection (100ms+)
    </text>
    
    <!-- Data components -->
    <rect x="20" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="85" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Connection Pools
    </text>
    <text x="85" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Max connections
    </text>
    
    <rect x="170" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="235" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Query Timeouts
    </text>
    <text x="235" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Statement limits
    </text>
    
    <rect x="320" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="385" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Read Replicas
    </text>
    <text x="385" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Load distribution
    </text>
    
    <rect x="470" y="35" width="130" height="35" rx="5" fill="#ffffff" opacity="0.9"/>
    <text x="535" y="50" text-anchor="middle" font-family="Arial, sans-serif" font-size="11" font-weight="bold" fill="#333">
      Sharding Logic
    </text>
    <text x="535" y="62" text-anchor="middle" font-family="Arial, sans-serif" font-size="9" fill="#666">
      Hot spot avoidance
    </text>
  </g>
  
  <!-- Backpressure signal flows -->
  <g>
    <!-- Upward signals -->
    <path d="M 200 440 L 200 400" stroke="#E91E63" stroke-width="3" marker-end="url(#arrowhead)" stroke-dasharray="5,5"/>
    <path d="M 400 320 L 400 280" stroke="#E91E63" stroke-width="3" marker-end="url(#arrowhead)" stroke-dasharray="5,5"/>
    <path d="M 600 200 L 600 160" stroke="#E91E63" stroke-width="3" marker-end="url(#arrowhead)" stroke-dasharray="5,5"/>
    
    <text x="50" y="560" font-family="Arial, sans-serif" font-size="12" font-weight="bold" fill="#E91E63">
      ⬆ Backpressure Signals: Queue depth, error rates, latency spikes
    </text>
  </g>
  
  <!-- Arrow marker -->
  <defs>
    <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="10" refY="3.5" orient="auto">
      <polygon points="0 0, 10 3.5, 0 7" fill="#E91E63" />
    </marker>
  </defs>
</svg>
EOF

    log "SVG diagrams created"
}

# Create test scripts
create_test_scripts() {
    log "Creating test scripts..."
    
    mkdir -p scripts
    
    cat > scripts/test_demo.sh << 'EOF'
#!/bin/bash

# Test script for backpressure demo
echo "🧪 Testing Backpressure Demo..."

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Test 1: Health checks
echo "✅ Testing service health..."
curl -f http://localhost:8000/health || echo "❌ Gateway health check failed"
curl -f http://localhost:8001/health || echo "❌ Backend health check failed"
curl -f http://localhost:3000/ || echo "❌ Dashboard health check failed"

# Test 2: Normal operation
echo "✅ Testing normal operation..."
response=$(curl -s http://localhost:8000/api/process)
if echo "$response" | grep -q "success"; then
    echo "✅ Normal operation test passed"
else
    echo "❌ Normal operation test failed"
fi

# Test 3: Backpressure activation
echo "✅ Testing backpressure activation..."
curl -s -X POST http://localhost:8001/config/latency/2.0
sleep 5

# Generate some load
for i in {1..10}; do
    curl -s http://localhost:8000/api/process &
done
wait

echo "✅ Backpressure demo tests completed"
EOF

    chmod +x scripts/test_demo.sh
    
    cat > scripts/cleanup.sh << 'EOF'
#!/bin/bash

# Cleanup script
echo "🧹 Cleaning up backpressure demo..."

docker-compose down -v
docker system prune -f

echo "✅ Cleanup completed"
EOF

    chmod +x scripts/cleanup.sh
    
    log "Test scripts created"
}

# Main setup function
setup_demo() {
    log "Setting up Backpressure Mechanisms Demo..."
    
    check_dependencies
    create_project_structure
    create_requirements
    create_dockerfile
    create_docker_compose
    create_shared_utils
    create_backend_service
    create_gateway_service
    create_load_generator
    create_web_dashboard
    create_svg_diagrams
    create_test_scripts
    
    log "Demo setup completed successfully!"
    
    info "To start the demo:"
    info "1. cd backpressure-demo"
    info "2. docker-compose up --build -d"
    info "3. Open http://localhost:3000 in your browser"
    info "4. Run ./scripts/test_demo.sh to verify functionality"
    
    warn "Note: Wait 30 seconds after startup for all services to be ready"
}

# Build and start function
build_and_start() {
    log "Building and starting backpressure demo..."
    
    docker-compose down -v 2>/dev/null || true
    docker-compose up --build -d
    
    log "Demo started successfully!"
    log "Dashboard: http://localhost:3000"
    log "Gateway API: http://localhost:8000"
    log "Backend API: http://localhost:8001"
    
    info "Running tests in 30 seconds..."
    sleep 30
    ./scripts/test_demo.sh
}

# Stop function
stop_demo() {
    log "Stopping backpressure demo..."
    docker-compose down
    log "Demo stopped"
}

# Help function
show_help() {
    echo "Backpressure Mechanisms Demo Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  setup     - Setup the demo environment"
    echo "  start     - Build and start the demo"
    echo "  stop      - Stop the demo"
    echo "  test      - Run functionality tests"
    echo "  clean     - Clean up all resources"
    echo "  help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 setup     # Initial setup"
    echo "  $0 start     # Start the demo"
    echo "  $0 test      # Test functionality"
    echo "  $0 clean     # Complete cleanup"
}

# Main script logic
case "${1:-setup}" in
    "setup")
        setup_demo
        ;;
    "start")
        build_and_start
        ;;
    "stop")
        stop_demo
        ;;
    "test")
        if [ -f "scripts/test_demo.sh" ]; then
            ./scripts/test_demo.sh
        else
            error "Test script not found. Run setup first."
        fi
        ;;
    "clean")
        if [ -f "scripts/cleanup.sh" ]; then
            ./scripts/cleanup.sh
        else
            docker-compose down -v 2>/dev/null || true
            log "Basic cleanup completed"
        fi
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        error "Unknown command: $1. Use 'help' to see available commands."
        ;;
esac