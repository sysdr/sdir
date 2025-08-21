from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import redis
import time
import random
import logging
from prometheus_client import Counter, Histogram, Gauge, generate_latest
from fastapi.responses import Response
import os

app = FastAPI(title="Backend Service")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Redis connection
redis_client = redis.from_url(os.getenv("REDIS_URL", "redis://localhost:6379"))

# Prometheus metrics
REQUEST_COUNT = Counter('backend_requests_total', 'Total backend requests', ['status'])
REQUEST_DURATION = Histogram('backend_request_duration_seconds', 'Backend request duration')
ACTIVE_CONNECTIONS = Gauge('backend_active_connections', 'Active backend connections')
FAILURE_RATE = Gauge('backend_failure_rate', 'Backend failure rate')

# Configuration
failure_rate = 0.0
latency_ms = 100

class ConfigRequest(BaseModel):
    failure_rate: float = 0.0
    latency_ms: int = 100

@app.get("/health")
async def health():
    return {"status": "healthy", "timestamp": time.time()}

@app.post("/config")
async def update_config(config: ConfigRequest):
    global failure_rate, latency_ms
    failure_rate = max(0.0, min(1.0, config.failure_rate))
    latency_ms = max(0, config.latency_ms)
    
    # Store in Redis for persistence
    redis_client.set("backend:failure_rate", failure_rate)
    redis_client.set("backend:latency_ms", latency_ms)
    
    FAILURE_RATE.set(failure_rate)
    return {"failure_rate": failure_rate, "latency_ms": latency_ms}

@app.get("/config")
async def get_config():
    return {"failure_rate": failure_rate, "latency_ms": latency_ms}

@app.post("/process")
async def process_request(data: dict):
    start_time = time.time()
    ACTIVE_CONNECTIONS.inc()
    
    try:
        # Simulate processing latency
        await simulate_latency()
        
        # Simulate failures
        if random.random() < failure_rate:
            REQUEST_COUNT.labels(status='error').inc()
            raise HTTPException(status_code=500, detail="Simulated failure")
        
        REQUEST_COUNT.labels(status='success').inc()
        return {
            "status": "processed",
            "data": data,
            "timestamp": time.time(),
            "processing_time_ms": (time.time() - start_time) * 1000
        }
    
    finally:
        REQUEST_DURATION.observe(time.time() - start_time)
        ACTIVE_CONNECTIONS.dec()

async def simulate_latency():
    if latency_ms > 0:
        # Add some jitter to make it realistic
        actual_latency = latency_ms + random.randint(-10, 10)
        time.sleep(max(0, actual_latency) / 1000)

@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type="text/plain")

@app.on_event("startup")
async def startup():
    global failure_rate, latency_ms
    # Restore config from Redis
    try:
        stored_failure_rate = redis_client.get("backend:failure_rate")
        stored_latency = redis_client.get("backend:latency_ms")
        
        if stored_failure_rate:
            failure_rate = float(stored_failure_rate)
        if stored_latency:
            latency_ms = int(stored_latency)
            
        FAILURE_RATE.set(failure_rate)
    except Exception:
        pass

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
