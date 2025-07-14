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
