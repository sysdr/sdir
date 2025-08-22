import asyncio
import aiohttp
import time
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from shared.utils import CircuitBreaker, monitor

app = FastAPI(title="User Service")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

auth_circuit = CircuitBreaker(failure_threshold=3, recovery_timeout=30)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "user", "timestamp": time.time()}

@app.get("/user/profile/{user_id}")
async def get_profile(user_id: str):
    # This service depends on auth service for token validation
    start_time = time.time()
    
    try:
        async with aiohttp.ClientSession() as session:
            # Call auth service through circuit breaker
            auth_result = await auth_circuit.call(
                call_auth_service, session, user_id
            )
            
            response_time = time.time() - start_time
            monitor.update_service_health("user_service", True, response_time)
            
            return {
                "user_id": user_id,
                "name": f"User {user_id}",
                "email": f"{user_id}@example.com",
                "auth_validated": True,
                "circuit_state": auth_circuit.state.value
            }
    except Exception as e:
        response_time = time.time() - start_time
        monitor.update_service_health("user_service", False, response_time)
        
        # Graceful degradation - return limited profile without auth
        return {
            "user_id": user_id,
            "name": f"User {user_id}",
            "email": "email_unavailable",
            "auth_validated": False,
            "circuit_state": auth_circuit.state.value,
            "error": "Auth service unavailable - degraded mode"
        }

async def call_auth_service(session, user_id):
    async with session.post(
        "http://auth-service:8001/auth/login",
        json={"user_id": user_id},
        timeout=aiohttp.ClientTimeout(total=2)
    ) as response:
        if response.status != 200:
            raise Exception(f"Auth failed: {response.status}")
        return await response.json()

@app.get("/metrics")
async def metrics():
    return {
        "service": "user",
        "circuit_state": auth_circuit.state.value,
        "circuit_failures": auth_circuit.failure_count,
        "dependencies": {"auth_service": auth_circuit.state.value}
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8002, log_level="info")
