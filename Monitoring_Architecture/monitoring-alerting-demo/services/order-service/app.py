import time
import random
import asyncio
from fastapi import FastAPI, HTTPException
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response
import uvicorn
import os

app = FastAPI(title="Order Service")

REQUEST_COUNT = Counter(
    'http_requests_total', 
    'Total HTTP requests', 
    ['method', 'endpoint', 'status', 'service']
)

REQUEST_DURATION = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration',
    ['method', 'endpoint', 'service']
)

SERVICE_NAME = os.getenv('SERVICE_NAME', 'order-service')
FAILURE_RATE = float(os.getenv('FAILURE_RATE', '0.01'))

@app.middleware("http")
async def metrics_middleware(request, call_next):
    start_time = time.time()
    response = await call_next(request)
    
    duration = time.time() - start_time
    REQUEST_DURATION.labels(
        method=request.method,
        endpoint=request.url.path,
        service=SERVICE_NAME
    ).observe(duration)
    
    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path, 
        status=response.status_code,
        service=SERVICE_NAME
    ).inc()
    
    return response

@app.post("/orders")
async def create_order(order_data: dict):
    await asyncio.sleep(random.uniform(0.3, 0.7))
    
    if random.random() < FAILURE_RATE:
        raise HTTPException(status_code=500, detail="Order creation failed")
    
    return {"status": "success", "order_id": f"order_{random.randint(1000, 9999)}"}

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": SERVICE_NAME}

@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
