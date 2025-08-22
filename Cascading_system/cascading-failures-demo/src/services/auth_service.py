import asyncio
import time
import random
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import logging

app = FastAPI(title="Auth Service")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# Service state
failure_mode = False
response_delay = 0.1
request_count = 0

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "auth", "timestamp": time.time()}

@app.post("/auth/login")
async def login(user_data: dict):
    global request_count, failure_mode
    request_count += 1
    
    # Simulate cascade trigger - auth service becomes slow/fails under load
    if failure_mode:
        if random.random() < 0.8:  # 80% failure rate when overloaded
            await asyncio.sleep(5)  # Slow response
            raise HTTPException(status_code=503, detail="Auth service overloaded")
    
    await asyncio.sleep(response_delay)
    return {
        "token": f"auth_token_{int(time.time())}",
        "user_id": user_data.get("user_id", "user123"),
        "expires": int(time.time()) + 3600
    }

@app.post("/control/trigger_failure")
async def trigger_failure():
    global failure_mode
    failure_mode = True
    return {"message": "Auth service failure triggered"}

@app.post("/control/recover")
async def recover():
    global failure_mode, request_count
    failure_mode = False
    request_count = 0
    return {"message": "Auth service recovered"}

@app.get("/metrics")
async def metrics():
    return {
        "service": "auth",
        "failure_mode": failure_mode,
        "request_count": request_count,
        "status": "failing" if failure_mode else "healthy"
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8001, log_level="info")
