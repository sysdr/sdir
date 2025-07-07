import asyncio
import json
import time
import logging
import os
from typing import Dict, List, Optional
import redis.asyncio as redis
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn
import structlog
from contextlib import asynccontextmanager

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = structlog.get_logger()

@asynccontextmanager
async def lifespan(app):
    await scheduler.start()
    yield

app = FastAPI(title="Distributed Task Scheduler", lifespan=lifespan)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class Task(BaseModel):
    id: str
    type: str
    priority: int = 1
    payload: dict
    created_at: float
    assigned_to: Optional[str] = None
    status: str = "pending"  # pending, assigned, running, completed, failed

class SchedulerNode:
    def __init__(self):
        self.node_id = os.getenv("NODE_ID", "scheduler-1")
        self.redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        self.redis_client = None
        self.is_leader = False
        self.workers: Dict[str, dict] = {}
        self.task_queue = asyncio.Queue()
        
    async def init_redis(self):
        self.redis_client = redis.from_url(self.redis_url)
        
    async def start(self):
        await self.init_redis()
        
        # Start background tasks
        asyncio.create_task(self.leader_election())
        asyncio.create_task(self.worker_heartbeat_monitor())
        asyncio.create_task(self.task_scheduler())
        asyncio.create_task(self.cleanup_dead_tasks())
        
        logger.info("Scheduler started", node_id=self.node_id)
        
    async def leader_election(self):
        """Simple leader election using Redis"""
        while True:
            try:
                # Try to acquire leadership
                acquired = await self.redis_client.set(
                    "scheduler:leader", 
                    self.node_id, 
                    nx=True, 
                    ex=10  # 10 second TTL
                )
                
                if acquired:
                    if not self.is_leader:
                        logger.info("Became leader", node_id=self.node_id)
                        self.is_leader = True
                else:
                    # Extend leadership if we're already leader
                    current_leader = await self.redis_client.get("scheduler:leader")
                    if current_leader and current_leader.decode() == self.node_id:
                        await self.redis_client.expire("scheduler:leader", 10)
                    else:
                        self.is_leader = False
                        
            except Exception as e:
                logger.error("Leader election error", error=str(e))
                self.is_leader = False
                
            await asyncio.sleep(5)
            
    async def worker_heartbeat_monitor(self):
        """Monitor worker heartbeats and maintain worker registry"""
        while True:
            try:
                # Get all worker heartbeats
                worker_keys = await self.redis_client.keys("worker:*:heartbeat")
                active_workers = {}
                
                for key in worker_keys:
                    worker_id = key.decode().split(':')[1]
                    heartbeat_data = await self.redis_client.get(key)
                    
                    if heartbeat_data:
                        worker_info = json.loads(heartbeat_data)
                        if time.time() - worker_info['timestamp'] < 30:  # 30 second timeout
                            active_workers[worker_id] = worker_info
                            
                self.workers = active_workers
                
                # Store active workers list in Redis for web UI
                await self.redis_client.set(
                    "scheduler:workers", 
                    json.dumps(active_workers),
                    ex=60
                )
                
                logger.info("Active workers", count=len(active_workers), workers=list(active_workers.keys()))
                
            except Exception as e:
                logger.error("Worker monitoring error", error=str(e))
                
            await asyncio.sleep(10)
            
    async def task_scheduler(self):
        """Main task scheduling loop - only runs on leader"""
        while True:
            try:
                if not self.is_leader:
                    await asyncio.sleep(1)
                    continue
                    
                # Get pending tasks from priority queues
                high_priority_task = await self.redis_client.lpop("tasks:high_priority")
                normal_priority_task = await self.redis_client.lpop("tasks:normal_priority")
                low_priority_task = await self.redis_client.lpop("tasks:low_priority")
                
                # Process high priority first
                for task_data in [high_priority_task, normal_priority_task, low_priority_task]:
                    if task_data:
                        await self.assign_task(json.loads(task_data))
                        break
                        
            except Exception as e:
                logger.error("Task scheduling error", error=str(e))
                
            await asyncio.sleep(0.1)  # 100ms scheduling loop
            
    async def assign_task(self, task_data: dict):
        """Assign task to best available worker"""
        if not self.workers:
            # No workers available, put task back in queue
            queue_name = f"tasks:{task_data.get('priority_level', 'normal')}_priority"
            await self.redis_client.lpush(queue_name, json.dumps(task_data))
            return
            
        # Simple load balancing - find worker with least tasks
        best_worker = min(
            self.workers.items(), 
            key=lambda x: x[1].get('active_tasks', 0)
        )
        
        worker_id = best_worker[0]
        task_data['assigned_to'] = worker_id
        task_data['status'] = 'assigned'
        task_data['assigned_at'] = time.time()
        
        # Assign task to worker
        await self.redis_client.lpush(f"worker:{worker_id}:tasks", json.dumps(task_data))
        
        # Update task status
        await self.redis_client.hset(
            f"task:{task_data['id']}", 
            mapping={
                'status': 'assigned',
                'assigned_to': worker_id,
                'assigned_at': str(time.time())
            }
        )
        
        logger.info(
            "Task assigned", 
            task_id=task_data['id'], 
            worker_id=worker_id,
            task_type=task_data.get('type')
        )
        
    async def cleanup_dead_tasks(self):
        """Clean up tasks that have been assigned but workers died"""
        while True:
            try:
                if not self.is_leader:
                    await asyncio.sleep(30)
                    continue
                    
                # Find tasks that were assigned to dead workers
                task_keys = await self.redis_client.keys("task:*")
                
                for task_key in task_keys:
                    task_data = await self.redis_client.hgetall(task_key)
                    if not task_data:
                        continue
                        
                    assigned_to = task_data.get(b'assigned_to')
                    status = task_data.get(b'status')
                    assigned_at = task_data.get(b'assigned_at')
                    
                    if (assigned_to and status in [b'assigned', b'running'] and 
                        assigned_to.decode() not in self.workers and assigned_at):
                        
                        # Task assigned to dead worker, reassign it
                        task_id = task_key.decode().split(':')[1]
                        
                        # Get original task data
                        original_task = await self.redis_client.hgetall(f"task:{task_id}:original")
                        if original_task:
                            task_dict = {k.decode(): v.decode() for k, v in original_task.items()}
                            task_dict['id'] = task_id
                            
                            # Put back in appropriate queue
                            priority_level = task_dict.get('priority_level', 'normal')
                            await self.redis_client.lpush(
                                f"tasks:{priority_level}_priority", 
                                json.dumps(task_dict)
                            )
                            
                            logger.warning(
                                "Reassigning orphaned task", 
                                task_id=task_id, 
                                dead_worker=assigned_to.decode()
                            )
                            
            except Exception as e:
                logger.error("Task cleanup error", error=str(e))
                
            await asyncio.sleep(30)

# Initialize scheduler
scheduler = SchedulerNode()

@app.post("/tasks")
async def submit_task(task: Task):
    """Submit a new task"""
    task.created_at = time.time()
    task_dict = task.model_dump()
    
    # Store original task data for recovery
    await scheduler.redis_client.hset(
        f"task:{task.id}:original",
        mapping={k: str(v) for k, v in task_dict.items()}
    )
    
    # Store task status
    await scheduler.redis_client.hset(
        f"task:{task.id}",
        mapping={
            'status': 'pending',
            'created_at': str(task.created_at),
            'priority': str(task.priority)
        }
    )
    
    # Add to appropriate priority queue
    if task.priority >= 3:
        queue_name = "tasks:high_priority"
        priority_level = "high"
    elif task.priority >= 2:
        queue_name = "tasks:normal_priority"
        priority_level = "normal"
    else:
        queue_name = "tasks:low_priority"
        priority_level = "low"
        
    task_dict['priority_level'] = priority_level
    await scheduler.redis_client.lpush(queue_name, json.dumps(task_dict))
    
    logger.info("Task submitted", task_id=task.id, priority=task.priority, type=task.type)
    
    return {"status": "submitted", "task_id": task.id}

@app.get("/status")
async def get_status():
    """Get scheduler status"""
    # Get queue lengths
    high_queue = await scheduler.redis_client.llen("tasks:high_priority")
    normal_queue = await scheduler.redis_client.llen("tasks:normal_priority")
    low_queue = await scheduler.redis_client.llen("tasks:low_priority")
    
    return {
        "node_id": scheduler.node_id,
        "is_leader": scheduler.is_leader,
        "active_workers": len(scheduler.workers),
        "queue_lengths": {
            "high_priority": high_queue,
            "normal_priority": normal_queue,
            "low_priority": low_queue
        },
        "workers": scheduler.workers
    }

@app.get("/tasks/{task_id}")
async def get_task_status(task_id: str):
    """Get task status"""
    task_data = await scheduler.redis_client.hgetall(f"task:{task_id}")
    if not task_data:
        raise HTTPException(status_code=404, detail="Task not found")
        
    return {k.decode(): v.decode() for k, v in task_data.items()}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
