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

app = FastAPI(title="Order Service")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

user_circuit = CircuitBreaker(failure_threshold=3, recovery_timeout=30)

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "order", "timestamp": time.time()}

@app.post("/order/create")
async def create_order(order_data: dict):
    start_time = time.time()
    user_id = order_data.get("user_id", "default_user")
    
    try:
        async with aiohttp.ClientSession() as session:
            # Call user service through circuit breaker
            user_result = await user_circuit.call(
                call_user_service, session, user_id
            )
            
            response_time = time.time() - start_time
            monitor.update_service_health("order_service", True, response_time)
            
            return {
                "order_id": f"order_{int(time.time())}",
                "user_id": user_id,
                "items": order_data.get("items", []),
                "total": order_data.get("total", 0),
                "user_verified": user_result.get("auth_validated", False),
                "circuit_state": user_circuit.state.value
            }
    except Exception as e:
        response_time = time.time() - start_time
        monitor.update_service_health("order_service", False, response_time)
        
        # Graceful degradation - create order without user validation
        return {
            "order_id": f"order_{int(time.time())}",
            "user_id": user_id,
            "items": order_data.get("items", []),
            "total": order_data.get("total", 0),
            "user_verified": False,
            "circuit_state": user_circuit.state.value,
            "warning": "Order created without user validation - review required"
        }

async def call_user_service(session, user_id):
    async with session.get(
        f"http://user-service:8002/user/profile/{user_id}",
        timeout=aiohttp.ClientTimeout(total=3)
    ) as response:
        if response.status != 200:
            raise Exception(f"User service failed: {response.status}")
        return await response.json()

@app.get("/metrics")
async def metrics():
    return {
        "service": "order",
        "circuit_state": user_circuit.state.value,
        "circuit_failures": user_circuit.failure_count,
        "dependencies": {"user_service": user_circuit.state.value}
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8003, log_level="info")
