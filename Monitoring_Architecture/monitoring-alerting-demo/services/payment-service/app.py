import time
import random
import asyncio
from fastapi import FastAPI, HTTPException
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response
import uvicorn
import os

app = FastAPI(title="Payment Service")

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

SERVICE_NAME = os.getenv('SERVICE_NAME', 'payment-service')
FAILURE_RATE = float(os.getenv('FAILURE_RATE', '0.05'))

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

@app.post("/payments")
async def process_payment(payment_data: dict):
    # Simulate payment processing time
    await asyncio.sleep(random.uniform(0.5, 1.5))
    
    if random.random() < FAILURE_RATE:
        raise HTTPException(status_code=500, detail="Payment processing failed")
    
    return {"status": "success", "payment_id": f"pay_{random.randint(1000, 9999)}"}

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": SERVICE_NAME}

@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
