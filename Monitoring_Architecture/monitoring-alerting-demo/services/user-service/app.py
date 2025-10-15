import time
import random
import asyncio
from fastapi import FastAPI, HTTPException
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from fastapi.responses import Response
import uvicorn
import os

app = FastAPI(title="User Service")

# Prometheus metrics
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

SERVICE_NAME = os.getenv('SERVICE_NAME', 'user-service')
FAILURE_RATE = float(os.getenv('FAILURE_RATE', '0.02'))

users_db = {
    "1": {"id": "1", "name": "John Doe", "email": "john@example.com"},
    "2": {"id": "2", "name": "Jane Smith", "email": "jane@example.com"},
    "3": {"id": "3", "name": "Bob Johnson", "email": "bob@example.com"}
}

@app.middleware("http")
async def metrics_middleware(request, call_next):
    start_time = time.time()
    
    response = await call_next(request)
    
    # Record metrics
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

@app.get("/users/{user_id}")
async def get_user(user_id: str):
    # Simulate processing time
    await asyncio.sleep(random.uniform(0.1, 0.3))
    
    # Simulate failures based on failure rate
    if random.random() < FAILURE_RATE:
        raise HTTPException(status_code=500, detail="Internal server error")
    
    if user_id not in users_db:
        raise HTTPException(status_code=404, detail="User not found")
    
    return users_db[user_id]

@app.get("/users")
async def list_users():
    # Simulate higher latency for list operations
    await asyncio.sleep(random.uniform(0.2, 0.8))
    
    if random.random() < FAILURE_RATE * 0.5:  # Lower failure rate for list
        raise HTTPException(status_code=500, detail="Internal server error")
    
    return list(users_db.values())

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": SERVICE_NAME}

@app.get("/metrics")
async def metrics():
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
