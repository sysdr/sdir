from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
import httpx
import redis.asyncio as redis
import os
import json
import hashlib
from typing import Dict, Any
import uvicorn

# Instance identification for X-axis scaling
INSTANCE_ID = os.getenv("INSTANCE_ID", "gateway_1")
SERVICE_PORT = int(os.getenv("SERVICE_PORT", 8000))
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")

app = FastAPI(title=f"API Gateway - {INSTANCE_ID}")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Redis client for session management
redis_client = None

# Service discovery mapping
SERVICES = {
    "user": ["http://user_service_1:8001", "http://user_service_2:8001"],
    "product": ["http://product_service:8002"],
    "order": ["http://order_service:8003"]
}

def get_shard_for_user(user_id: int, num_shards: int = 2) -> int:
    """Z-axis scaling: Route to correct user service shard"""
    hash_object = hashlib.md5(str(user_id).encode())
    hash_int = int(hash_object.hexdigest(), 16)
    return (hash_int % num_shards)

@app.on_event("startup")
async def startup():
    global redis_client
    redis_client = redis.from_url(REDIS_URL)

@app.on_event("shutdown")
async def shutdown():
    if redis_client:
        await redis_client.close()

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "instance": INSTANCE_ID,
        "scaling_demo": {
            "x_axis": "Multiple gateway instances behind load balancer",
            "y_axis": "Separate user, product, order services",
            "z_axis": "User data sharded across 2 databases"
        }
    }

@app.get("/api/scaling-info")
async def scaling_info():
    """Endpoint to demonstrate scaling architecture"""
    return {
        "scale_cube": {
            "x_axis": {
                "description": "Horizontal duplication",
                "implementation": "Multiple identical gateway instances",
                "current_instance": INSTANCE_ID
            },
            "y_axis": {
                "description": "Functional decomposition", 
                "implementation": "Separate microservices",
                "services": list(SERVICES.keys())
            },
            "z_axis": {
                "description": "Data partitioning",
                "implementation": "User sharding across databases",
                "shards": len(SERVICES["user"])
            }
        }
    }

# Y-axis scaling: Route to appropriate microservice
@app.api_route("/api/users/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def proxy_user_service(path: str, request: Request):
    """Route user requests with Z-axis sharding"""
    body = await request.body()
    
    # For user operations, determine shard based on user ID
    if "user_id" in path or request.method == "POST":
        if request.method == "POST":
            # New user creation - use round robin
            shard_index = 0  # Default to first shard for new users
        else:
            # Extract user ID for existing user operations
            user_id = int(path.split("/")[0]) if path.split("/")[0].isdigit() else 1
            shard_index = get_shard_for_user(user_id)
    else:
        shard_index = 0
    
    service_url = SERVICES["user"][shard_index]
    
    async with httpx.AsyncClient() as client:
        response = await client.request(
            method=request.method,
            url=f"{service_url}/api/users/{path}",
            content=body,
            headers=dict(request.headers)
        )
        return response.json()

@app.api_route("/api/products/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def proxy_product_service(path: str, request: Request):
    """Route product requests to product service"""
    body = await request.body()
    service_url = SERVICES["product"][0]
    
    async with httpx.AsyncClient() as client:
        response = await client.request(
            method=request.method,
            url=f"{service_url}/api/products/{path}",
            content=body,
            headers=dict(request.headers)
        )
        return response.json()

@app.api_route("/api/orders/{path:path}", methods=["GET", "POST", "PUT", "DELETE"])
async def proxy_order_service(path: str, request: Request):
    """Route order requests to order service"""
    body = await request.body()
    service_url = SERVICES["order"][0]
    
    async with httpx.AsyncClient() as client:
        response = await client.request(
            method=request.method,
            url=f"{service_url}/api/orders/{path}",
            content=body,
            headers=dict(request.headers)
        )
        return response.json()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=SERVICE_PORT)
