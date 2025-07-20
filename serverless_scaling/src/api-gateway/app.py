from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
import httpx
import redis
import json
import os
import time
from typing import Dict, Any
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Serverless Scaling API Gateway", version="1.0.0")

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Redis connection
redis_client = redis.Redis.from_url(
    os.getenv("REDIS_URL", "redis://localhost:6379"),
    decode_responses=True
)

# Worker service URL
WORKER_SERVICE_URL = os.getenv("WORKER_SERVICE_URL", "http://localhost:8001")

@app.on_event("startup")
async def startup_event():
    logger.info("API Gateway starting up...")
    # Initialize Redis with demo data
    redis_client.set("request_count", 0)
    # Don't initialize active_workers here - let worker service manage it as a set

@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "service": "API Gateway",
        "status": "healthy",
        "timestamp": time.time(),
        "request_count": redis_client.get("request_count") or 0
    }

@app.get("/api/status")
async def get_status():
    """Get system status and metrics"""
    try:
        # Get metrics from Redis
        request_count = int(redis_client.get("request_count") or 0)
        active_workers = int(redis_client.get("active_workers") or 0)
        
        # Check worker service health
        async with httpx.AsyncClient() as client:
            try:
                worker_response = await client.get(f"{WORKER_SERVICE_URL}/health", timeout=5.0)
                worker_healthy = worker_response.status_code == 200
            except:
                worker_healthy = False
        
        return {
            "api_gateway": "healthy",
            "worker_service": "healthy" if worker_healthy else "unhealthy",
            "redis": "connected" if redis_client.ping() else "disconnected",
            "metrics": {
                "total_requests": request_count,
                "active_workers": active_workers,
                "timestamp": time.time()
            }
        }
    except Exception as e:
        logger.error(f"Error getting status: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.post("/api/task")
async def create_task(background_tasks: BackgroundTasks, task_data: Dict[str, Any]):
    """Create a new task and queue it for processing"""
    try:
        # Increment request counter
        redis_client.incr("request_count")
        
        # Generate task ID
        task_id = f"task_{int(time.time() * 1000)}"
        
        # Store task in Redis
        task_info = {
            "id": task_id,
            "data": task_data,
            "status": "queued",
            "created_at": time.time(),
            "worker_id": None
        }
        
        redis_client.setex(f"task:{task_id}", 3600, json.dumps(task_info))  # 1 hour TTL
        
        # Add task to processing queue
        redis_client.lpush("task_queue", task_id)
        
        # Update active workers count
        queue_length = redis_client.llen("task_queue")
        redis_client.set("queue_length", queue_length)
        
        logger.info(f"Task {task_id} queued successfully")
        
        return {
            "task_id": task_id,
            "status": "queued",
            "message": "Task has been queued for processing",
            "queue_position": queue_length
        }
    except Exception as e:
        logger.error(f"Error creating task: {e}")
        raise HTTPException(status_code=500, detail="Failed to create task")

@app.get("/api/task/{task_id}")
async def get_task_status(task_id: str):
    """Get the status of a specific task"""
    try:
        task_data = redis_client.get(f"task:{task_id}")
        if not task_data:
            raise HTTPException(status_code=404, detail="Task not found")
        
        task_info = json.loads(task_data)
        return task_info
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting task status: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/api/metrics")
async def get_metrics():
    """Get detailed system metrics"""
    try:
        request_count = int(redis_client.get("request_count") or 0)
        active_workers = int(redis_client.get("active_workers") or 0)
        queue_length = int(redis_client.get("queue_length") or 0)
        
        # Get recent tasks (last 10)
        recent_tasks = []
        for i in range(min(10, queue_length)):
            task_id = redis_client.lindex("task_queue", i)
            if task_id:
                task_data = redis_client.get(f"task:{task_id}")
                if task_data:
                    recent_tasks.append(json.loads(task_data))
        
        return {
            "system_metrics": {
                "total_requests": request_count,
                "active_workers": active_workers,
                "queue_length": queue_length,
                "redis_connected": redis_client.ping()
            },
            "recent_tasks": recent_tasks,
            "timestamp": time.time()
        }
    except Exception as e:
        logger.error(f"Error getting metrics: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000) 