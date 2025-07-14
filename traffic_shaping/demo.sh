#!/bin/bash

# Traffic Shaping and Rate Limiting Demo Setup
# System Design Interview Roadmap - Issue #95

set -e

PROJECT_NAME="traffic-shaping-demo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}  Traffic Shaping and Rate Limiting Demo${NC}"
    echo -e "${BLUE}  System Design Interview Roadmap - Issue #95${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    print_step "Checking dependencies..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is required but not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is required but not installed. Please install Docker Compose first."
        exit 1
    fi
    
    print_info "All dependencies are available"
}

create_project_structure() {
    print_step "Creating project structure..."
    
    mkdir -p "$PROJECT_NAME"
    cd "$PROJECT_NAME"
    
    mkdir -p {app,tests,config,static,templates,logs}
    mkdir -p static/{css,js,images}
    
    print_info "Project structure created"
}

create_requirements() {
    print_step "Creating requirements.txt..."
    
    cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
redis==5.0.1
aioredis==2.0.1
python-multipart==0.0.6
jinja2==3.1.2
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
httpx==0.25.2
asyncio-mqtt==0.16.1
prometheus-client==0.19.0
numpy==1.24.4
pandas==2.1.3
plotly==5.17.0
websockets==12.0
aiofiles==23.2.0
structlog==23.2.0
pydantic==2.5.0
psutil==5.9.6
locust==2.17.0
EOF
    
    print_info "Requirements file created"
}

create_docker_files() {
    print_step "Creating Docker configuration..."
    
    # Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000 8001 8002

CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
EOF

    # Docker Compose
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

  rate-limiter-app:
    build: .
    ports:
      - "8000:8000"
    environment:
      - REDIS_URL=redis://redis:6379
      - APP_ENV=development
    depends_on:
      redis:
        condition: service_healthy
    volumes:
      - ./app:/app/app
      - ./templates:/app/templates
      - ./static:/app/static
      - ./logs:/app/logs

  load-tester:
    build: .
    command: python tests/load_test.py
    environment:
      - TARGET_URL=http://rate-limiter-app:8000
      - REDIS_URL=redis://redis:6379
    depends_on:
      - rate-limiter-app
    profiles:
      - testing

volumes:
  redis_data:
EOF

    print_info "Docker configuration created"
}

create_main_app() {
    print_step "Creating main application..."
    
    cat > app/__init__.py << 'EOF'
# Empty init file
EOF

    cat > app/main.py << 'EOF'
from fastapi import FastAPI, Request, HTTPException, BackgroundTasks
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, JSONResponse
import redis.asyncio as redis
import time
import json
import asyncio
import logging
from typing import Dict, Any, Optional
import os
from contextlib import asynccontextmanager

from .rate_limiters import TokenBucketLimiter, SlidingWindowLimiter, FixedWindowLimiter
from .metrics import MetricsCollector

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global variables
redis_client: Optional[redis.Redis] = None
metrics_collector: Optional[MetricsCollector] = None
rate_limiters: Dict[str, Any] = {}

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global redis_client, metrics_collector, rate_limiters
    
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
    redis_client = redis.from_url(redis_url, decode_responses=True)
    
    # Test Redis connection
    try:
        await redis_client.ping()
        logger.info("Redis connection established")
    except Exception as e:
        logger.error(f"Redis connection failed: {e}")
        raise
    
    # Initialize metrics collector
    metrics_collector = MetricsCollector(redis_client)
    
    # Initialize rate limiters
    rate_limiters = {
        "token_bucket": TokenBucketLimiter(redis_client, capacity=10, refill_rate=2),
        "sliding_window": SlidingWindowLimiter(redis_client, window_size=60, max_requests=100),
        "fixed_window": FixedWindowLimiter(redis_client, window_size=60, max_requests=50)
    }
    
    logger.info("Application startup complete")
    
    yield
    
    # Shutdown
    if redis_client:
        await redis_client.close()
    logger.info("Application shutdown complete")

app = FastAPI(
    title="Traffic Shaping and Rate Limiting Demo",
    description="Production-grade rate limiting demonstration",
    version="1.0.0",
    lifespan=lifespan
)

# Mount static files
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard page"""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.get("/api/health")
async def health_check():
    """Health check endpoint"""
    try:
        await redis_client.ping()
        return {"status": "healthy", "redis": "connected", "timestamp": time.time()}
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"Redis connection failed: {str(e)}")

@app.post("/api/request/{limiter_type}")
async def make_request(limiter_type: str, request: Request):
    """Process a request through the specified rate limiter"""
    if limiter_type not in rate_limiters:
        raise HTTPException(status_code=400, detail="Invalid limiter type")
    
    client_ip = request.client.host
    user_id = f"user_{client_ip}"
    
    limiter = rate_limiters[limiter_type]
    start_time = time.time()
    
    try:
        # Check rate limit
        allowed, metadata = await limiter.is_allowed(user_id)
        processing_time = (time.time() - start_time) * 1000  # Convert to ms
        
        # Record metrics
        await metrics_collector.record_request(
            limiter_type=limiter_type,
            user_id=user_id,
            allowed=allowed,
            processing_time=processing_time,
            metadata=metadata
        )
        
        if allowed:
            return {
                "allowed": True,
                "limiter_type": limiter_type,
                "user_id": user_id,
                "processing_time_ms": processing_time,
                "metadata": metadata,
                "timestamp": time.time()
            }
        else:
            response = JSONResponse(
                status_code=429,
                content={
                    "allowed": False,
                    "limiter_type": limiter_type,
                    "user_id": user_id,
                    "processing_time_ms": processing_time,
                    "metadata": metadata,
                    "timestamp": time.time(),
                    "retry_after": metadata.get("retry_after", 60)
                }
            )
            response.headers["Retry-After"] = str(metadata.get("retry_after", 60))
            return response
            
    except Exception as e:
        logger.error(f"Rate limiting error: {e}")
        # Fail open - allow request if rate limiter fails
        return {
            "allowed": True,
            "limiter_type": limiter_type,
            "user_id": user_id,
            "error": "Rate limiter unavailable - failing open",
            "timestamp": time.time()
        }

@app.get("/api/metrics")
async def get_metrics():
    """Get current metrics and statistics"""
    try:
        metrics = await metrics_collector.get_metrics()
        return metrics
    except Exception as e:
        logger.error(f"Metrics collection error: {e}")
        return {"error": "Metrics unavailable"}

@app.get("/api/limiter/{limiter_type}/status")
async def get_limiter_status(limiter_type: str, user_id: str = "default_user"):
    """Get current status of a specific rate limiter"""
    if limiter_type not in rate_limiters:
        raise HTTPException(status_code=400, detail="Invalid limiter type")
    
    limiter = rate_limiters[limiter_type]
    try:
        status = await limiter.get_status(user_id)
        return {
            "limiter_type": limiter_type,
            "user_id": user_id,
            "status": status,
            "timestamp": time.time()
        }
    except Exception as e:
        logger.error(f"Status check error: {e}")
        return {"error": "Status unavailable"}

@app.post("/api/reset/{limiter_type}")
async def reset_limiter(limiter_type: str, user_id: str = "default_user"):
    """Reset rate limiter for a specific user"""
    if limiter_type not in rate_limiters:
        raise HTTPException(status_code=400, detail="Invalid limiter type")
    
    limiter = rate_limiters[limiter_type]
    try:
        await limiter.reset(user_id)
        return {
            "message": f"Rate limiter {limiter_type} reset for user {user_id}",
            "timestamp": time.time()
        }
    except Exception as e:
        logger.error(f"Reset error: {e}")
        raise HTTPException(status_code=500, detail="Reset failed")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    print_info "Main application created"
}

create_rate_limiters() {
    print_step "Creating rate limiter implementations..."
    
    cat > app/rate_limiters.py << 'EOF'
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
EOF

    print_info "Rate limiter implementations created"
}

create_metrics() {
    print_step "Creating metrics collection..."
    
    cat > app/metrics.py << 'EOF'
import time
import json
from typing import Dict, Any, List
import redis.asyncio as redis
import logging

logger = logging.getLogger(__name__)

class MetricsCollector:
    """Collect and aggregate rate limiting metrics"""
    
    def __init__(self, redis_client: redis.Redis):
        self.redis = redis_client
        self.metrics_key = "rate_limiting_metrics"
        self.stats_key = "rate_limiting_stats"
    
    async def record_request(self, limiter_type: str, user_id: str, allowed: bool, 
                           processing_time: float, metadata: Dict[str, Any]) -> None:
        """Record a rate limiting request"""
        timestamp = time.time()
        
        metric_data = {
            "timestamp": timestamp,
            "limiter_type": limiter_type,
            "user_id": user_id,
            "allowed": allowed,
            "processing_time_ms": processing_time,
            "metadata": metadata
        }
        
        try:
            # Store individual metric
            await self.redis.lpush(self.metrics_key, json.dumps(metric_data))
            await self.redis.ltrim(self.metrics_key, 0, 999)  # Keep last 1000 metrics
            
            # Update aggregated stats
            await self._update_stats(limiter_type, allowed, processing_time)
            
        except Exception as e:
            logger.error(f"Failed to record metric: {e}")
    
    async def _update_stats(self, limiter_type: str, allowed: bool, processing_time: float) -> None:
        """Update aggregated statistics"""
        now = int(time.time())
        minute_bucket = now // 60  # Group by minute
        
        stats_key = f"{self.stats_key}:{limiter_type}:{minute_bucket}"
        
        # Increment counters
        pipe = self.redis.pipeline()
        pipe.hincrby(stats_key, "total_requests", 1)
        
        if allowed:
            pipe.hincrby(stats_key, "allowed_requests", 1)
        else:
            pipe.hincrby(stats_key, "blocked_requests", 1)
        
        # Track processing times (simple average)
        pipe.hincrbyfloat(stats_key, "total_processing_time", processing_time)
        
        # Set expiration (keep stats for 1 hour)
        pipe.expire(stats_key, 3600)
        
        await pipe.execute()
    
    async def get_metrics(self) -> Dict[str, Any]:
        """Get current metrics and statistics"""
        try:
            # Get recent individual metrics
            raw_metrics = await self.redis.lrange(self.metrics_key, 0, 99)
            recent_metrics = []
            
            for metric in raw_metrics:
                try:
                    recent_metrics.append(json.loads(metric))
                except json.JSONDecodeError:
                    continue
            
            # Get aggregated stats for last 10 minutes
            stats = await self._get_recent_stats(10)
            
            # Calculate real-time statistics
            realtime_stats = self._calculate_realtime_stats(recent_metrics)
            
            return {
                "recent_metrics": recent_metrics[:50],  # Last 50 requests
                "aggregated_stats": stats,
                "realtime_stats": realtime_stats,
                "timestamp": time.time()
            }
            
        except Exception as e:
            logger.error(f"Failed to get metrics: {e}")
            return {"error": str(e)}
    
    async def _get_recent_stats(self, minutes: int) -> Dict[str, Any]:
        """Get aggregated stats for recent time period"""
        now = int(time.time())
        current_minute = now // 60
        
        stats = {
            "token_bucket": {"total": 0, "allowed": 0, "blocked": 0, "avg_processing_time": 0},
            "sliding_window": {"total": 0, "allowed": 0, "blocked": 0, "avg_processing_time": 0},
            "fixed_window": {"total": 0, "allowed": 0, "blocked": 0, "avg_processing_time": 0}
        }
        
        try:
            for limiter_type in stats.keys():
                total_requests = 0
                total_allowed = 0
                total_blocked = 0
                total_processing_time = 0.0
                
                for i in range(minutes):
                    minute_bucket = current_minute - i
                    stats_key = f"{self.stats_key}:{limiter_type}:{minute_bucket}"
                    
                    minute_stats = await self.redis.hmget(
                        stats_key, 
                        "total_requests", "allowed_requests", "blocked_requests", "total_processing_time"
                    )
                    
                    if minute_stats[0]:  # If data exists
                        total_requests += int(minute_stats[0] or 0)
                        total_allowed += int(minute_stats[1] or 0)
                        total_blocked += int(minute_stats[2] or 0)
                        total_processing_time += float(minute_stats[3] or 0)
                
                stats[limiter_type] = {
                    "total": total_requests,
                    "allowed": total_allowed,
                    "blocked": total_blocked,
                    "block_rate": (total_blocked / total_requests * 100) if total_requests > 0 else 0,
                    "avg_processing_time": (total_processing_time / total_requests) if total_requests > 0 else 0
                }
        
        except Exception as e:
            logger.error(f"Failed to get recent stats: {e}")
        
        return stats
    
    def _calculate_realtime_stats(self, metrics: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Calculate real-time statistics from recent metrics"""
        if not metrics:
            return {}
        
        # Group by limiter type
        by_limiter = {}
        for metric in metrics:
            limiter_type = metric.get("limiter_type")
            if limiter_type not in by_limiter:
                by_limiter[limiter_type] = []
            by_limiter[limiter_type].append(metric)
        
        stats = {}
        for limiter_type, limiter_metrics in by_limiter.items():
            total = len(limiter_metrics)
            allowed = sum(1 for m in limiter_metrics if m.get("allowed"))
            blocked = total - allowed
            
            processing_times = [m.get("processing_time_ms", 0) for m in limiter_metrics]
            avg_processing_time = sum(processing_times) / len(processing_times) if processing_times else 0
            
            # Calculate requests per second (approximate)
            if total > 1:
                time_span = limiter_metrics[0]["timestamp"] - limiter_metrics[-1]["timestamp"]
                rps = total / time_span if time_span > 0 else 0
            else:
                rps = 0
            
            stats[limiter_type] = {
                "total": total,
                "allowed": allowed,
                "blocked": blocked,
                "block_rate": (blocked / total * 100) if total > 0 else 0,
                "avg_processing_time": avg_processing_time,
                "requests_per_second": rps
            }
        
        return stats
EOF

    print_info "Metrics collection created"
}

create_web_interface() {
    print_step "Creating web interface..."
    
    # HTML Template
    cat > templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Traffic Shaping and Rate Limiting Demo</title>
    <link rel="stylesheet" href="/static/css/style.css">
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="header">
        <div class="container">
            <h1>Traffic Shaping and Rate Limiting Demo</h1>
            <p>System Design Interview Roadmap - Issue #95</p>
        </div>
    </div>

    <div class="container">
        <div class="control-panel">
            <h2>Rate Limiter Testing</h2>
            <div class="limiter-controls">
                <div class="limiter-card" data-limiter="token_bucket">
                    <h3>Token Bucket</h3>
                    <div class="limiter-status" id="token_bucket_status">
                        <div class="status-item">
                            <span class="label">Tokens:</span>
                            <span class="value" id="token_bucket_tokens">-</span>
                        </div>
                        <div class="status-item">
                            <span class="label">Capacity:</span>
                            <span class="value">10</span>
                        </div>
                    </div>
                    <button class="test-btn" onclick="testLimiter('token_bucket')">Send Request</button>
                    <button class="reset-btn" onclick="resetLimiter('token_bucket')">Reset</button>
                </div>

                <div class="limiter-card" data-limiter="sliding_window">
                    <h3>Sliding Window</h3>
                    <div class="limiter-status" id="sliding_window_status">
                        <div class="status-item">
                            <span class="label">Current:</span>
                            <span class="value" id="sliding_window_current">-</span>
                        </div>
                        <div class="status-item">
                            <span class="label">Max:</span>
                            <span class="value">100/min</span>
                        </div>
                    </div>
                    <button class="test-btn" onclick="testLimiter('sliding_window')">Send Request</button>
                    <button class="reset-btn" onclick="resetLimiter('sliding_window')">Reset</button>
                </div>

                <div class="limiter-card" data-limiter="fixed_window">
                    <h3>Fixed Window</h3>
                    <div class="limiter-status" id="fixed_window_status">
                        <div class="status-item">
                            <span class="label">Current:</span>
                            <span class="value" id="fixed_window_current">-</span>
                        </div>
                        <div class="status-item">
                            <span class="label">Max:</span>
                            <span class="value">50/min</span>
                        </div>
                    </div>
                    <button class="test-btn" onclick="testLimiter('fixed_window')">Send Request</button>
                    <button class="reset-btn" onclick="resetLimiter('fixed_window')">Reset</button>
                </div>
            </div>

            <div class="bulk-testing">
                <h3>Bulk Testing</h3>
                <div class="bulk-controls">
                    <select id="bulk_limiter">
                        <option value="token_bucket">Token Bucket</option>
                        <option value="sliding_window">Sliding Window</option>
                        <option value="fixed_window">Fixed Window</option>
                    </select>
                    <input type="number" id="bulk_count" value="20" min="1" max="200" placeholder="Request count">
                    <input type="number" id="bulk_interval" value="100" min="10" max="5000" placeholder="Interval (ms)">
                    <button onclick="startBulkTest()">Start Bulk Test</button>
                    <button onclick="stopBulkTest()">Stop</button>
                </div>
                <div class="bulk-progress">
                    <div class="progress-bar">
                        <div class="progress-fill" id="bulk_progress"></div>
                    </div>
                    <span id="bulk_status">Ready</span>
                </div>
            </div>
        </div>

        <div class="metrics-panel">
            <h2>Real-time Metrics</h2>
            <div class="metrics-grid">
                <div class="metric-card">
                    <h4>Requests per Second</h4>
                    <div class="metric-value" id="rps_value">0</div>
                </div>
                <div class="metric-card">
                    <h4>Success Rate</h4>
                    <div class="metric-value" id="success_rate">100%</div>
                </div>
                <div class="metric-card">
                    <h4>Avg Response Time</h4>
                    <div class="metric-value" id="avg_response_time">0ms</div>
                </div>
                <div class="metric-card">
                    <h4>Total Requests</h4>
                    <div class="metric-value" id="total_requests">0</div>
                </div>
            </div>

            <div class="charts-container">
                <div class="chart-card">
                    <h4>Request Rate Over Time</h4>
                    <canvas id="requestRateChart"></canvas>
                </div>
                <div class="chart-card">
                    <h4>Response Time Distribution</h4>
                    <canvas id="responseTimeChart"></canvas>
                </div>
            </div>
        </div>

        <div class="logs-panel">
            <h2>Request Logs</h2>
            <div class="logs-container" id="logs_container">
                <!-- Logs will be populated here -->
            </div>
        </div>
    </div>

    <script src="/static/js/dashboard.js"></script>
</body>
</html>
EOF

    # CSS Styles
    cat > static/css/style.css << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Google Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    color: #333;
}

.header {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    padding: 20px 0;
    box-shadow: 0 2px 20px rgba(0, 0, 0, 0.1);
    margin-bottom: 30px;
}

.header h1 {
    color: #1a73e8;
    font-size: 2.5rem;
    font-weight: 400;
    margin-bottom: 5px;
}

.header p {
    color: #5f6368;
    font-size: 1.1rem;
}

.container {
    max-width: 1400px;
    margin: 0 auto;
    padding: 0 20px;
}

.control-panel {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    padding: 30px;
    border-radius: 12px;
    box-shadow: 0 4px 25px rgba(0, 0, 0, 0.1);
    margin-bottom: 30px;
}

.control-panel h2 {
    color: #1a73e8;
    margin-bottom: 25px;
    font-weight: 400;
    font-size: 1.8rem;
}

.limiter-controls {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 20px;
    margin-bottom: 30px;
}

.limiter-card {
    background: linear-gradient(145deg, #f8f9fa, #e8f0fe);
    border: 2px solid #e8eaed;
    border-radius: 12px;
    padding: 20px;
    transition: all 0.3s ease;
    position: relative;
    overflow: hidden;
}

.limiter-card::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 4px;
    background: linear-gradient(90deg, #1a73e8, #34a853);
}

.limiter-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 25px rgba(26, 115, 232, 0.2);
}

.limiter-card h3 {
    color: #1a73e8;
    margin-bottom: 15px;
    font-weight: 500;
    font-size: 1.3rem;
}

.limiter-status {
    margin-bottom: 20px;
}

.status-item {
    display: flex;
    justify-content: space-between;
    margin-bottom: 8px;
    padding: 8px 12px;
    background: rgba(255, 255, 255, 0.7);
    border-radius: 6px;
}

.status-item .label {
    color: #5f6368;
    font-weight: 500;
}

.status-item .value {
    color: #1a73e8;
    font-weight: 600;
}

.test-btn, .reset-btn {
    padding: 12px 24px;
    border: none;
    border-radius: 8px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.3s ease;
    margin-right: 10px;
    font-size: 14px;
}

.test-btn {
    background: linear-gradient(135deg, #1a73e8, #1557b0);
    color: white;
}

.test-btn:hover {
    background: linear-gradient(135deg, #1557b0, #1a73e8);
    transform: translateY(-1px);
    box-shadow: 0 4px 12px rgba(26, 115, 232, 0.3);
}

.reset-btn {
    background: linear-gradient(135deg, #ea4335, #d33b2c);
    color: white;
}

.reset-btn:hover {
    background: linear-gradient(135deg, #d33b2c, #ea4335);
    transform: translateY(-1px);
    box-shadow: 0 4px 12px rgba(234, 67, 53, 0.3);
}

.bulk-testing {
    border-top: 2px solid #e8eaed;
    padding-top: 25px;
}

.bulk-testing h3 {
    color: #1a73e8;
    margin-bottom: 15px;
    font-weight: 500;
}

.bulk-controls {
    display: flex;
    gap: 15px;
    align-items: center;
    flex-wrap: wrap;
    margin-bottom: 20px;
}

.bulk-controls select, .bulk-controls input {
    padding: 10px 15px;
    border: 2px solid #e8eaed;
    border-radius: 8px;
    font-size: 14px;
    background: white;
    transition: border-color 0.3s ease;
}

.bulk-controls select:focus, .bulk-controls input:focus {
    outline: none;
    border-color: #1a73e8;
}

.bulk-controls button {
    padding: 10px 20px;
    border: none;
    border-radius: 8px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.3s ease;
    background: linear-gradient(135deg, #34a853, #2d8f47);
    color: white;
}

.bulk-controls button:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 12px rgba(52, 168, 83, 0.3);
}

.bulk-progress {
    display: flex;
    align-items: center;
    gap: 15px;
}

.progress-bar {
    flex: 1;
    height: 8px;
    background: #e8eaed;
    border-radius: 4px;
    overflow: hidden;
}

.progress-fill {
    height: 100%;
    background: linear-gradient(90deg, #1a73e8, #34a853);
    width: 0%;
    transition: width 0.3s ease;
}

.metrics-panel {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    padding: 30px;
    border-radius: 12px;
    box-shadow: 0 4px 25px rgba(0, 0, 0, 0.1);
    margin-bottom: 30px;
}

.metrics-panel h2 {
    color: #1a73e8;
    margin-bottom: 25px;
    font-weight: 400;
    font-size: 1.8rem;
}

.metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 20px;
    margin-bottom: 30px;
}

.metric-card {
    background: linear-gradient(145deg, #f8f9fa, #e8f0fe);
    padding: 20px;
    border-radius: 12px;
    text-align: center;
    border: 2px solid #e8eaed;
    transition: transform 0.3s ease;
}

.metric-card:hover {
    transform: translateY(-2px);
}

.metric-card h4 {
    color: #5f6368;
    margin-bottom: 10px;
    font-weight: 500;
    font-size: 14px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

.metric-value {
    color: #1a73e8;
    font-size: 2rem;
    font-weight: 600;
}

.charts-container {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(400px, 1fr));
    gap: 30px;
}

.chart-card {
    background: rgba(255, 255, 255, 0.9);
    padding: 20px;
    border-radius: 12px;
    border: 2px solid #e8eaed;
}

.chart-card h4 {
    color: #1a73e8;
    margin-bottom: 15px;
    font-weight: 500;
}

.logs-panel {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    padding: 30px;
    border-radius: 12px;
    box-shadow: 0 4px 25px rgba(0, 0, 0, 0.1);
}

.logs-panel h2 {
    color: #1a73e8;
    margin-bottom: 25px;
    font-weight: 400;
    font-size: 1.8rem;
}

.logs-container {
    max-height: 400px;
    overflow-y: auto;
    background: #f8f9fa;
    border: 2px solid #e8eaed;
    border-radius: 8px;
    padding: 15px;
    font-family: 'SF Mono', 'Monaco', 'Consolas', monospace;
    font-size: 13px;
}

.log-entry {
    margin-bottom: 8px;
    padding: 8px 12px;
    border-radius: 6px;
    border-left: 4px solid #e8eaed;
}

.log-entry.success {
    background: #e8f5e8;
    border-left-color: #34a853;
    color: #137333;
}

.log-entry.error {
    background: #fce8e6;
    border-left-color: #ea4335;
    color: #d93025;
}

.log-entry.warning {
    background: #fef7e0;
    border-left-color: #fbbc04;
    color: #e37400;
}

/* Animations */
@keyframes pulse {
    0% { transform: scale(1); }
    50% { transform: scale(1.05); }
    100% { transform: scale(1); }
}

.limiter-card.active {
    animation: pulse 0.5s ease-in-out;
    border-color: #1a73e8;
}

/* Responsive design */
@media (max-width: 768px) {
    .header h1 {
        font-size: 2rem;
    }
    
    .limiter-controls {
        grid-template-columns: 1fr;
    }
    
    .bulk-controls {
        flex-direction: column;
        align-items: stretch;
    }
    
    .charts-container {
        grid-template-columns: 1fr;
    }
    
    .metrics-grid {
        grid-template-columns: repeat(2, 1fr);
    }
}

@media (max-width: 480px) {
    .metrics-grid {
        grid-template-columns: 1fr;
    }
}
EOF

    # JavaScript
    cat > static/js/dashboard.js << 'EOF'
// Global variables
let bulkTestInterval = null;
let bulkTestCount = 0;
let bulkTestTotal = 0;
let requestRateChart = null;
let responseTimeChart = null;
let metricsInterval = null;

// Initialize dashboard
document.addEventListener('DOMContentLoaded', function() {
    initializeCharts();
    startMetricsUpdate();
    updateLimiterStatus();
});

// Initialize charts
function initializeCharts() {
    // Request Rate Chart
    const requestRateCtx = document.getElementById('requestRateChart').getContext('2d');
    requestRateChart = new Chart(requestRateCtx, {
        type: 'line',
        data: {
            labels: [],
            datasets: [{
                label: 'Token Bucket',
                data: [],
                borderColor: '#1a73e8',
                backgroundColor: 'rgba(26, 115, 232, 0.1)',
                tension: 0.4
            }, {
                label: 'Sliding Window',
                data: [],
                borderColor: '#34a853',
                backgroundColor: 'rgba(52, 168, 83, 0.1)',
                tension: 0.4
            }, {
                label: 'Fixed Window',
                data: [],
                borderColor: '#ea4335',
                backgroundColor: 'rgba(234, 67, 53, 0.1)',
                tension: 0.4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'top'
                }
            },
            scales: {
                x: {
                    display: true,
                    title: {
                        display: true,
                        text: 'Time'
                    }
                },
                y: {
                    display: true,
                    title: {
                        display: true,
                        text: 'Requests/sec'
                    },
                    beginAtZero: true
                }
            }
        }
    });

    // Response Time Chart
    const responseTimeCtx = document.getElementById('responseTimeChart').getContext('2d');
    responseTimeChart = new Chart(responseTimeCtx, {
        type: 'bar',
        data: {
            labels: ['Token Bucket', 'Sliding Window', 'Fixed Window'],
            datasets: [{
                label: 'Avg Response Time (ms)',
                data: [0, 0, 0],
                backgroundColor: ['rgba(26, 115, 232, 0.7)', 'rgba(52, 168, 83, 0.7)', 'rgba(234, 67, 53, 0.7)'],
                borderColor: ['#1a73e8', '#34a853', '#ea4335'],
                borderWidth: 2
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    title: {
                        display: true,
                        text: 'Response Time (ms)'
                    }
                }
            }
        }
    });
}

// Test individual limiter
async function testLimiter(limiterType) {
    const card = document.querySelector(`[data-limiter="${limiterType}"]`);
    card.classList.add('active');
    
    try {
        const response = await fetch(`/api/request/${limiterType}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            }
        });
        
        const result = await response.json();
        
        // Log the request
        logRequest(limiterType, result.allowed, result.processing_time_ms, result.metadata);
        
        // Update status
        updateLimiterStatus();
        
        // Visual feedback
        setTimeout(() => {
            card.classList.remove('active');
        }, 500);
        
    } catch (error) {
        console.error('Request failed:', error);
        logRequest(limiterType, false, 0, { error: error.message });
    }
}

// Reset limiter
async function resetLimiter(limiterType) {
    try {
        await fetch(`/api/reset/${limiterType}`, {
            method: 'POST'
        });
        
        updateLimiterStatus();
        addLog(`Reset ${limiterType} limiter`, 'success');
        
    } catch (error) {
        console.error('Reset failed:', error);
        addLog(`Failed to reset ${limiterType}: ${error.message}`, 'error');
    }
}

// Start bulk test
function startBulkTest() {
    if (bulkTestInterval) {
        stopBulkTest();
        return;
    }
    
    const limiterType = document.getElementById('bulk_limiter').value;
    const count = parseInt(document.getElementById('bulk_count').value);
    const interval = parseInt(document.getElementById('bulk_interval').value);
    
    bulkTestCount = 0;
    bulkTestTotal = count;
    
    document.getElementById('bulk_status').textContent = `Testing ${limiterType}...`;
    
    bulkTestInterval = setInterval(async () => {
        if (bulkTestCount >= bulkTestTotal) {
            stopBulkTest();
            return;
        }
        
        try {
            const response = await fetch(`/api/request/${limiterType}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                }
            });
            
            const result = await response.json();
            logRequest(limiterType, result.allowed, result.processing_time_ms, result.metadata);
            
        } catch (error) {
            logRequest(limiterType, false, 0, { error: error.message });
        }
        
        bulkTestCount++;
        const progress = (bulkTestCount / bulkTestTotal) * 100;
        document.getElementById('bulk_progress').style.width = `${progress}%`;
        document.getElementById('bulk_status').textContent = `${bulkTestCount}/${bulkTestTotal} requests sent`;
        
    }, interval);
}

// Stop bulk test
function stopBulkTest() {
    if (bulkTestInterval) {
        clearInterval(bulkTestInterval);
        bulkTestInterval = null;
    }
    
    document.getElementById('bulk_progress').style.width = '0%';
    document.getElementById('bulk_status').textContent = 'Ready';
}

// Update limiter status
async function updateLimiterStatus() {
    const limiters = ['token_bucket', 'sliding_window', 'fixed_window'];
    
    for (const limiter of limiters) {
        try {
            const response = await fetch(`/api/limiter/${limiter}/status?user_id=default_user`);
            const status = await response.json();
            
            if (limiter === 'token_bucket') {
                document.getElementById('token_bucket_tokens').textContent = 
                    Math.floor(status.status.current_tokens || 0);
            } else if (limiter === 'sliding_window') {
                document.getElementById('sliding_window_current').textContent = 
                    `${status.status.current_requests || 0}`;
            } else if (limiter === 'fixed_window') {
                document.getElementById('fixed_window_current').textContent = 
                    `${status.status.current_requests || 0}`;
            }
            
        } catch (error) {
            console.error(`Failed to get ${limiter} status:`, error);
        }
    }
}

// Start metrics updates
function startMetricsUpdate() {
    metricsInterval = setInterval(async () => {
        try {
            const response = await fetch('/api/metrics');
            const metrics = await response.json();
            
            updateMetricsDisplay(metrics);
            updateCharts(metrics);
            
        } catch (error) {
            console.error('Failed to fetch metrics:', error);
        }
    }, 2000); // Update every 2 seconds
}

// Update metrics display
function updateMetricsDisplay(metrics) {
    const realtime = metrics.realtime_stats || {};
    
    // Calculate total RPS
    let totalRps = 0;
    let totalRequests = 0;
    let totalAllowed = 0;
    let avgResponseTime = 0;
    let responseTimeCount = 0;
    
    Object.values(realtime).forEach(stats => {
        if (stats.requests_per_second) {
            totalRps += stats.requests_per_second;
        }
        totalRequests += stats.total || 0;
        totalAllowed += stats.allowed || 0;
        if (stats.avg_processing_time) {
            avgResponseTime += stats.avg_processing_time;
            responseTimeCount++;
        }
    });
    
    const successRate = totalRequests > 0 ? (totalAllowed / totalRequests * 100) : 100;
    const avgTime = responseTimeCount > 0 ? (avgResponseTime / responseTimeCount) : 0;
    
    document.getElementById('rps_value').textContent = totalRps.toFixed(1);
    document.getElementById('success_rate').textContent = `${successRate.toFixed(1)}%`;
    document.getElementById('avg_response_time').textContent = `${avgTime.toFixed(1)}ms`;
    document.getElementById('total_requests').textContent = totalRequests;
}

// Update charts
function updateCharts(metrics) {
    const realtime = metrics.realtime_stats || {};
    const now = new Date().toLocaleTimeString();
    
    // Update request rate chart
    if (requestRateChart.data.labels.length > 20) {
        requestRateChart.data.labels.shift();
        requestRateChart.data.datasets.forEach(dataset => dataset.data.shift());
    }
    
    requestRateChart.data.labels.push(now);
    
    const limiters = ['token_bucket', 'sliding_window', 'fixed_window'];
    limiters.forEach((limiter, index) => {
        const rps = realtime[limiter]?.requests_per_second || 0;
        requestRateChart.data.datasets[index].data.push(rps);
    });
    
    requestRateChart.update('none');
    
    // Update response time chart
    limiters.forEach((limiter, index) => {
        const avgTime = realtime[limiter]?.avg_processing_time || 0;
        responseTimeChart.data.datasets[0].data[index] = avgTime;
    });
    
    responseTimeChart.update('none');
}

// Log request
function logRequest(limiterType, allowed, processingTime, metadata) {
    const timestamp = new Date().toLocaleTimeString();
    const status = allowed ? 'ALLOWED' : 'BLOCKED';
    const className = allowed ? 'success' : 'error';
    
    let message = `[${timestamp}] ${limiterType.toUpperCase()}: ${status}`;
    if (processingTime) {
        message += ` (${processingTime.toFixed(2)}ms)`;
    }
    
    if (metadata && metadata.retry_after) {
        message += ` - Retry after ${metadata.retry_after}s`;
    }
    
    addLog(message, className);
}

// Add log entry
function addLog(message, className = '') {
    const logsContainer = document.getElementById('logs_container');
    const logEntry = document.createElement('div');
    logEntry.className = `log-entry ${className}`;
    logEntry.textContent = message;
    
    logsContainer.insertBefore(logEntry, logsContainer.firstChild);
    
    // Keep only last 100 logs
    while (logsContainer.children.length > 100) {
        logsContainer.removeChild(logsContainer.lastChild);
    }
}

// Cleanup on page unload
window.addEventListener('beforeunload', function() {
    stopBulkTest();
    if (metricsInterval) {
        clearInterval(metricsInterval);
    }
});
EOF

    print_info "Web interface created"
}

create_load_tests() {
    print_step "Creating load testing suite..."
    
    cat > tests/__init__.py << 'EOF'
# Empty init file
EOF

    cat > tests/load_test.py << 'EOF'
import asyncio
import aiohttp
import time
import json
from typing import Dict, List
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class LoadTester:
    def __init__(self, base_url: str = "http://localhost:8000"):
        self.base_url = base_url
        self.results: Dict[str, List] = {
            "token_bucket": [],
            "sliding_window": [],
            "fixed_window": []
        }
    
    async def test_limiter(self, session: aiohttp.ClientSession, limiter_type: str, user_id: str = "load_test_user"):
        """Test a specific rate limiter"""
        start_time = time.time()
        
        try:
            async with session.post(f"{self.base_url}/api/request/{limiter_type}") as response:
                result = await response.json()
                processing_time = (time.time() - start_time) * 1000
                
                self.results[limiter_type].append({
                    "timestamp": start_time,
                    "allowed": result.get("allowed", False),
                    "status_code": response.status,
                    "processing_time": processing_time,
                    "metadata": result.get("metadata", {})
                })
                
                return result.get("allowed", False), processing_time
                
        except Exception as e:
            logger.error(f"Request failed: {e}")
            self.results[limiter_type].append({
                "timestamp": start_time,
                "allowed": False,
                "status_code": 0,
                "processing_time": (time.time() - start_time) * 1000,
                "error": str(e)
            })
            return False, 0
    
    async def burst_test(self, limiter_type: str, burst_size: int = 20, delay: float = 0.1):
        """Test burst handling capability"""
        logger.info(f"Starting burst test for {limiter_type}: {burst_size} requests with {delay}s delay")
        
        async with aiohttp.ClientSession() as session:
            tasks = []
            for i in range(burst_size):
                task = self.test_limiter(session, limiter_type)
                tasks.append(task)
                if delay > 0:
                    await asyncio.sleep(delay)
            
            results = await asyncio.gather(*tasks, return_exceptions=True)
            
            # Analyze results
            allowed_count = sum(1 for r in results if isinstance(r, tuple) and r[0])
            blocked_count = burst_size - allowed_count
            
            logger.info(f"Burst test results - Allowed: {allowed_count}, Blocked: {blocked_count}")
            return allowed_count, blocked_count
    
    async def sustained_load_test(self, limiter_type: str, duration: int = 60, rps: float = 5.0):
        """Test sustained load over time"""
        logger.info(f"Starting sustained load test for {limiter_type}: {rps} RPS for {duration}s")
        
        interval = 1.0 / rps
        end_time = time.time() + duration
        request_count = 0
        
        async with aiohttp.ClientSession() as session:
            while time.time() < end_time:
                start = time.time()
                
                await self.test_limiter(session, limiter_type)
                request_count += 1
                
                # Maintain rate
                elapsed = time.time() - start
                sleep_time = max(0, interval - elapsed)
                if sleep_time > 0:
                    await asyncio.sleep(sleep_time)
        
        logger.info(f"Sustained load test completed: {request_count} requests sent")
        return request_count
    
    async def comparative_test(self, requests_per_limiter: int = 50):
        """Compare all limiters under identical load"""
        logger.info(f"Starting comparative test: {requests_per_limiter} requests per limiter")
        
        async with aiohttp.ClientSession() as session:
            for limiter_type in ["token_bucket", "sliding_window", "fixed_window"]:
                logger.info(f"Testing {limiter_type}...")
                
                # Reset limiter first
                try:
                    await session.post(f"{self.base_url}/api/reset/{limiter_type}")
                except:
                    pass
                
                # Send requests with small delay to avoid overwhelming
                for i in range(requests_per_limiter):
                    await self.test_limiter(session, limiter_type)
                    await asyncio.sleep(0.05)  # 50ms delay
                
                await asyncio.sleep(1)  # Pause between limiters
    
    def analyze_results(self):
        """Analyze test results and generate report"""
        report = {
            "summary": {},
            "detailed_analysis": {}
        }
        
        for limiter_type, results in self.results.items():
            if not results:
                continue
            
            total_requests = len(results)
            allowed_requests = sum(1 for r in results if r.get("allowed", False))
            blocked_requests = total_requests - allowed_requests
            
            processing_times = [r["processing_time"] for r in results if "processing_time" in r]
            avg_processing_time = sum(processing_times) / len(processing_times) if processing_times else 0
            
            # Calculate success rate
            success_rate = (allowed_requests / total_requests * 100) if total_requests > 0 else 0
            
            report["summary"][limiter_type] = {
                "total_requests": total_requests,
                "allowed_requests": allowed_requests,
                "blocked_requests": blocked_requests,
                "success_rate": round(success_rate, 2),
                "avg_processing_time": round(avg_processing_time, 2)
            }
            
            # Time-based analysis
            if len(results) > 1:
                start_time = min(r["timestamp"] for r in results)
                end_time = max(r["timestamp"] for r in results)
                duration = end_time - start_time
                rps = total_requests / duration if duration > 0 else 0
                
                report["detailed_analysis"][limiter_type] = {
                    "duration": round(duration, 2),
                    "requests_per_second": round(rps, 2),
                    "min_processing_time": min(processing_times) if processing_times else 0,
                    "max_processing_time": max(processing_times) if processing_times else 0
                }
        
        return report
    
    def print_report(self):
        """Print formatted test report"""
        report = self.analyze_results()
        
        print("\n" + "="*80)
        print("LOAD TEST REPORT")
        print("="*80)
        
        print("\nSUMMARY:")
        print("-"*40)
        for limiter, stats in report["summary"].items():
            print(f"\n{limiter.upper()}:")
            print(f"  Total Requests: {stats['total_requests']}")
            print(f"  Allowed: {stats['allowed_requests']} ({stats['success_rate']}%)")
            print(f"  Blocked: {stats['blocked_requests']}")
            print(f"  Avg Processing Time: {stats['avg_processing_time']}ms")
        
        print("\nDETAILED ANALYSIS:")
        print("-"*40)
        for limiter, stats in report["detailed_analysis"].items():
            print(f"\n{limiter.upper()}:")
            print(f"  Test Duration: {stats['duration']}s")
            print(f"  Actual RPS: {stats['requests_per_second']}")
            print(f"  Processing Time Range: {stats['min_processing_time']:.2f}ms - {stats['max_processing_time']:.2f}ms")

async def main():
    """Run comprehensive load tests"""
    target_url = os.getenv("TARGET_URL", "http://localhost:8000")
    tester = LoadTester(target_url)
    
    # Wait for service to be ready
    logger.info("Waiting for service to be ready...")
    await asyncio.sleep(10)
    
    try:
        # Test 1: Burst testing
        logger.info("Running burst tests...")
        for limiter in ["token_bucket", "sliding_window", "fixed_window"]:
            await tester.burst_test(limiter, burst_size=15, delay=0.1)
            await asyncio.sleep(2)
        
        # Test 2: Sustained load
        logger.info("Running sustained load tests...")
        for limiter in ["token_bucket", "sliding_window", "fixed_window"]:
            await tester.sustained_load_test(limiter, duration=30, rps=3.0)
            await asyncio.sleep(5)
        
        # Test 3: Comparative test
        logger.info("Running comparative test...")
        await tester.comparative_test(requests_per_limiter=30)
        
        # Generate and print report
        tester.print_report()
        
    except Exception as e:
        logger.error(f"Load test failed: {e}")
        raise

if __name__ == "__main__":
    asyncio.run(main())
EOF

    print_info "Load testing suite created"
}

create_demo_script() {
    print_step "Creating demo script..."
    
    cat > demo.sh << 'EOF'
#!/bin/bash

# Demo script for Traffic Shaping and Rate Limiting

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}  🚀 Traffic Shaping and Rate Limiting Demo${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

print_step() {
    echo -e "${GREEN}[DEMO]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_header

print_step "Building and starting the demo environment..."
docker-compose up --build -d

print_step "Waiting for services to be ready..."
sleep 15

# Check if services are running
print_step "Checking service health..."
if curl -f http://localhost:8000/api/health > /dev/null 2>&1; then
    print_info "✓ Rate limiting service is running"
else
    echo -e "${RED}[ERROR]${NC} Service health check failed"
    exit 1
fi

print_step "Running basic functionality tests..."

# Test each rate limiter
for limiter in token_bucket sliding_window fixed_window; do
    print_info "Testing $limiter rate limiter..."
    
    # Send a few requests
    for i in {1..5}; do
        response=$(curl -s -X POST "http://localhost:8000/api/request/$limiter" \
            -H "Content-Type: application/json")
        
        allowed=$(echo "$response" | grep -o '"allowed":[^,]*' | cut -d':' -f2)
        if [ "$allowed" = "true" ]; then
            echo -e "  Request $i: ${GREEN}ALLOWED${NC}"
        else
            echo -e "  Request $i: ${RED}BLOCKED${NC}"
        fi
        
        sleep 0.5
    done
    echo
done

print_step "Running load tests..."
docker-compose run --rm load-tester

print_step "Demo is ready! Access points:"
echo -e "${BLUE}Web Dashboard:${NC} http://localhost:8000"
echo -e "${BLUE}API Docs:${NC} http://localhost:8000/docs"
echo -e "${BLUE}Health Check:${NC} http://localhost:8000/api/health"
echo

print_info "Try these manual tests:"
echo "1. Open the web dashboard and click 'Send Request' buttons"
echo "2. Run bulk tests with different parameters"
echo "3. Monitor real-time metrics and charts"
echo "4. Test API endpoints directly:"
echo "   curl -X POST http://localhost:8000/api/request/token_bucket"
echo

print_info "To stop the demo, run: ./cleanup.sh"
EOF

    chmod +x demo.sh
    
    print_info "Demo script created"
}

create_cleanup_script() {
    print_step "Creating cleanup script..."
    
    cat > cleanup.sh << 'EOF'
#!/bin/bash

# Cleanup script for Traffic Shaping and Rate Limiting Demo

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() {
    echo -e "${GREEN}[CLEANUP]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_step "Stopping all containers..."
docker-compose down

print_step "Removing volumes..."
docker-compose down -v

print_step "Removing unused Docker resources..."
docker system prune -f

print_step "Removing log files..."
rm -rf logs/*

print_info "Cleanup completed!"
print_info "All containers, volumes, and temporary files have been removed."
EOF

    chmod +x cleanup.sh
    
    print_info "Cleanup script created"
}

create_readme() {
    print_step "Creating documentation..."
    
    cat > README.md << 'EOF'
# Traffic Shaping and Rate Limiting Demo

A comprehensive demonstration of production-grade rate limiting algorithms and traffic shaping techniques.

## Features

- **Multiple Rate Limiting Algorithms**
  - Token Bucket: Allows bursts, memory efficient
  - Sliding Window: Precise limiting, higher memory usage
  - Fixed Window: Simple implementation, boundary effects

- **Distributed Coordination**
  - Redis-based shared state
  - Atomic operations using Lua scripts
  - Connection pooling and optimization

- **Real-time Monitoring**
  - Live metrics and statistics
  - Interactive charts and visualizations
  - Request logs and debugging

- **Load Testing Suite**
  - Burst testing capabilities
  - Sustained load testing
  - Comparative analysis

## Quick Start

1. **Setup and run the demo:**
   ```bash
   ./demo.sh
   ```

2. **Access the web dashboard:**
   - Open http://localhost:8000 in your browser
   - Test different rate limiting algorithms
   - Monitor real-time metrics

3. **API Testing:**
   ```bash
   # Test token bucket
   curl -X POST http://localhost:8000/api/request/token_bucket

   # Test sliding window
   curl -X POST http://localhost:8000/api/request/sliding_window

   # Test fixed window
   curl -X POST http://localhost:8000/api/request/fixed_window
   ```

4. **Cleanup:**
   ```bash
   ./cleanup.sh
   ```

## Architecture

### Rate Limiting Algorithms

1. **Token Bucket**
   - Capacity: 10 tokens
   - Refill rate: 2 tokens/second
   - Allows burst traffic up to capacity

2. **Sliding Window**
   - Window size: 60 seconds
   - Max requests: 100 per window
   - Precise request counting

3. **Fixed Window**
   - Window size: 60 seconds
   - Max requests: 50 per window
   - Simple implementation

### Components

- **FastAPI Application**: Main web service with async support
- **Redis**: Distributed state storage and coordination
- **Web Dashboard**: Real-time monitoring and testing interface
- **Load Tester**: Comprehensive testing suite

## Testing Scenarios

### Manual Testing
1. Use the web dashboard to send individual requests
2. Compare algorithm behaviors under different load patterns
3. Monitor real-time metrics and response times

### Automated Testing
```bash
# Run load tests
docker-compose run --rm load-tester

# Custom testing
python tests/load_test.py
```

### Bulk Testing
1. Select algorithm type
2. Configure request count and interval
3. Monitor progress and results in real-time

## Key Insights

### Token Bucket
- **Best for**: Bursty traffic patterns
- **Advantages**: Allows legitimate bursts, memory efficient
- **Trade-offs**: May allow sustained bursts that overwhelm downstream

### Sliding Window
- **Best for**: Precise rate limiting
- **Advantages**: Smooth traffic distribution, accurate limiting
- **Trade-offs**: Higher memory usage, more complex implementation

### Fixed Window
- **Best for**: Simple rate limiting needs
- **Advantages**: Easy to implement and understand
- **Trade-offs**: Boundary effects can allow 2x rate at window transitions

## Production Considerations

1. **Redis Configuration**
   - Use Redis Cluster for high availability
   - Configure appropriate memory limits
   - Monitor Redis performance metrics

2. **Algorithm Selection**
   - Choose based on traffic patterns
   - Consider memory and CPU constraints
   - Test under realistic load conditions

3. **Monitoring**
   - Track false positive/negative rates
   - Monitor processing latencies
   - Set up alerting for rate limit violations

4. **Graceful Degradation**
   - Implement fallback mechanisms
   - Fail open vs fail closed strategies
   - Circuit breaker integration

## Troubleshooting

### Common Issues

1. **Port conflicts**
   - Check if ports 8000, 6379 are available
   - Modify docker-compose.yml if needed

2. **Redis connection issues**
   - Verify Redis container is running
   - Check network connectivity

3. **Performance issues**
   - Monitor Docker resource usage
   - Adjust rate limiting parameters

### Debug Commands

```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs rate-limiter-app
docker-compose logs redis

# Test Redis connectivity
docker-compose exec redis redis-cli ping
```

## License

This demo is part of the System Design Interview Roadmap series and is provided for educational purposes.
EOF

    print_info "Documentation created"
}

main() {
    print_header
    
    check_dependencies
    create_project_structure
    create_requirements
    create_docker_files
    create_main_app
    create_rate_limiters
    create_metrics
    create_web_interface
    create_load_tests
    create_demo_script
    create_cleanup_script
    create_readme
    
    print_step "Setup completed successfully!"
    echo
    print_info "Next steps:"
    echo "1. cd $PROJECT_NAME"
    echo "2. ./demo.sh"
    echo "3. Open http://localhost:8000 in your browser"
    echo
    print_info "To clean up later: ./cleanup.sh"
}

# Check if running directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

chmod +x traffic-shaping-demo.sh

print_info "Complete demo script created successfully!"
echo
echo "To start the demo:"
echo "1. Run: ./traffic-shaping-demo.sh"
echo "2. Follow the setup instructions"
echo "3. Access the web dashboard at http://localhost:8000"