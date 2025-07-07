import asyncio
import json
import time
import logging
import os
import random
from typing import Dict, Any
import redis.asyncio as redis
from fastapi import FastAPI
import uvicorn
import structlog
from contextlib import asynccontextmanager

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = structlog.get_logger()

@asynccontextmanager
async def lifespan(app):
    await worker.start()
    yield

app = FastAPI(title="Task Worker", lifespan=lifespan)

class WorkerNode:
    def __init__(self):
        self.node_id = os.getenv("NODE_ID", f"worker-{random.randint(1000, 9999)}")
        self.worker_port = int(os.getenv("WORKER_PORT", "8001"))
        self.redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        self.redis_client = None
        self.active_tasks = 0
        self.completed_tasks = 0
        self.failed_tasks = 0
        self.is_running = True
        
    async def init_redis(self):
        self.redis_client = redis.from_url(self.redis_url)
        
    async def start(self):
        await self.init_redis()
        
        # Start background tasks
        asyncio.create_task(self.heartbeat_sender())
        asyncio.create_task(self.task_processor())
        
        logger.info("Worker started", node_id=self.node_id, port=self.worker_port)
        
    async def heartbeat_sender(self):
        """Send periodic heartbeats to scheduler"""
        while self.is_running:
            try:
                heartbeat_data = {
                    'node_id': self.node_id,
                    'timestamp': time.time(),
                    'active_tasks': self.active_tasks,
                    'completed_tasks': self.completed_tasks,
                    'failed_tasks': self.failed_tasks,
                    'port': self.worker_port,
                    'status': 'healthy'
                }
                
                await self.redis_client.set(
                    f"worker:{self.node_id}:heartbeat",
                    json.dumps(heartbeat_data),
                    ex=60  # 60 second TTL
                )
                
            except Exception as e:
                logger.error("Heartbeat error", error=str(e))
                
            await asyncio.sleep(10)  # Send heartbeat every 10 seconds
            
    async def task_processor(self):
        """Main task processing loop"""
        while self.is_running:
            try:
                # Get task from our queue (blocking pop with timeout)
                task_data = await self.redis_client.blpop(
                    f"worker:{self.node_id}:tasks",
                    timeout=5
                )
                
                if task_data:
                    _, task_json = task_data
                    task = json.loads(task_json)
                    await self.process_task(task)
                    
            except Exception as e:
                logger.error("Task processing error", error=str(e))
                await asyncio.sleep(1)
                
    async def process_task(self, task: dict):
        """Process a single task"""
        task_id = task['id']
        task_type = task.get('type', 'unknown')
        
        try:
            self.active_tasks += 1
            
            # Update task status to running
            await self.redis_client.hset(
                f"task:{task_id}",
                mapping={
                    'status': 'running',
                    'started_at': str(time.time()),
                    'worker_id': self.node_id
                }
            )
            
            logger.info("Task started", task_id=task_id, type=task_type)
            
            # Simulate task processing based on type
            await self.simulate_task_processing(task)
            
            # Mark task as completed
            await self.redis_client.hset(
                f"task:{task_id}",
                mapping={
                    'status': 'completed',
                    'completed_at': str(time.time()),
                    'result': 'success'
                }
            )
            
            self.completed_tasks += 1
            logger.info("Task completed", task_id=task_id, type=task_type)
            
        except Exception as e:
            # Mark task as failed
            await self.redis_client.hset(
                f"task:{task_id}",
                mapping={
                    'status': 'failed',
                    'failed_at': str(time.time()),
                    'error': str(e)
                }
            )
            
            self.failed_tasks += 1
            logger.error("Task failed", task_id=task_id, type=task_type, error=str(e))
            
        finally:
            self.active_tasks -= 1
            
    async def simulate_task_processing(self, task: dict):
        """Simulate different types of task processing"""
        task_type = task.get('type', 'default')
        payload = task.get('payload', {})
        
        if task_type == 'cpu_intensive':
            # Simulate CPU-intensive task (2-5 seconds)
            duration = random.uniform(2, 5)
            await asyncio.sleep(duration)
            
        elif task_type == 'io_intensive':
            # Simulate I/O-intensive task (1-3 seconds)
            duration = random.uniform(1, 3)
            await asyncio.sleep(duration)
            
        elif task_type == 'quick':
            # Quick task (0.1-0.5 seconds)
            duration = random.uniform(0.1, 0.5)
            await asyncio.sleep(duration)
            
        elif task_type == 'long_running':
            # Long running task (5-10 seconds)
            duration = random.uniform(5, 10)
            await asyncio.sleep(duration)
            
        elif task_type == 'failing':
            # Task that randomly fails
            if random.random() < 0.3:  # 30% failure rate
                raise Exception("Simulated task failure")
            duration = random.uniform(1, 2)
            await asyncio.sleep(duration)
            
        else:
            # Default task processing (1-2 seconds)
            duration = random.uniform(1, 2)
            await asyncio.sleep(duration)

# Initialize worker
worker = WorkerNode()

@app.get("/status")
async def get_worker_status():
    """Get worker status"""
    return {
        "node_id": worker.node_id,
        "port": worker.worker_port,
        "active_tasks": worker.active_tasks,
        "completed_tasks": worker.completed_tasks,
        "failed_tasks": worker.failed_tasks,
        "is_running": worker.is_running
    }

@app.post("/shutdown")
async def shutdown_worker():
    """Gracefully shutdown worker"""
    worker.is_running = False
    return {"status": "shutting_down"}

if __name__ == "__main__":
    port = int(os.getenv("WORKER_PORT", "8001"))
    uvicorn.run(app, host="0.0.0.0", port=port)
