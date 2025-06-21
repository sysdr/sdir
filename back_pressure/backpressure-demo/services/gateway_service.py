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
