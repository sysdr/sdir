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
    
    # Start background task to send metrics to Redis
    asyncio.create_task(send_metrics_to_redis())

async def send_metrics_to_redis():
    """Send metrics to Redis every second"""
    while True:
        try:
            if backpressure_manager and redis_client:
                metrics = await backpressure_manager.get_metrics()
                logger.debug("Sent metrics to Redis", queue_depth=metrics.queue_depth, cpu_usage=metrics.cpu_usage)
            await asyncio.sleep(1.0)
        except Exception as e:
            logger.error("Error sending metrics to Redis", error=str(e))
            await asyncio.sleep(5.0)

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
        
        return JSONResponse(
            status_code=500,
            content={"error": "Internal server error"}
        )
            

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
