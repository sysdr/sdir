from fastapi import FastAPI, HTTPException
import redis
import json
import os
import time
import threading
import uuid
import logging
from typing import Dict, Any
import psycopg2
from psycopg2.extras import RealDictCursor

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Serverless Scaling Worker Service", version="1.0.0")

# Redis connection
redis_client = redis.Redis.from_url(
    os.getenv("REDIS_URL", "redis://localhost:6379"),
    decode_responses=True
)

# Database connection
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://user:password@localhost:5432/serverless_demo")

# Worker instance ID
WORKER_ID = str(uuid.uuid4())[:8]
logger.info(f"Worker {WORKER_ID} starting up...")

# Global flag to control worker loop
worker_running = False
worker_thread = None

def get_db_connection():
    """Get database connection"""
    try:
        return psycopg2.connect(DATABASE_URL)
    except Exception as e:
        logger.error(f"Database connection failed: {e}")
        return None

def init_database():
    """Initialize database tables"""
    conn = get_db_connection()
    if conn:
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS tasks (
                        id VARCHAR(50) PRIMARY KEY,
                        data JSONB,
                        status VARCHAR(20),
                        created_at TIMESTAMP,
                        completed_at TIMESTAMP,
                        worker_id VARCHAR(20),
                        processing_time FLOAT
                    )
                """)
                conn.commit()
                logger.info("Database initialized successfully")
        except Exception as e:
            logger.error(f"Database initialization failed: {e}")
        finally:
            conn.close()

def process_task(task_id: str) -> Dict[str, Any]:
    """Process a single task"""
    try:
        # Get task data from Redis
        task_data = redis_client.get(f"task:{task_id}")
        if not task_data:
            return {"status": "error", "message": "Task not found"}
        
        task_info = json.loads(task_data)
        
        # Update task status
        task_info["status"] = "processing"
        task_info["worker_id"] = WORKER_ID
        task_info["started_at"] = time.time()
        
        redis_client.setex(f"task:{task_id}", 3600, json.dumps(task_info))
        
        # Simulate processing time (1-5 seconds)
        processing_time = 1 + (hash(task_id) % 4)
        time.sleep(processing_time)
        
        # Process the task (simulate work)
        result = {
            "processed": True,
            "worker_id": WORKER_ID,
            "processing_time": processing_time,
            "result": f"Task {task_id} processed successfully"
        }
        
        # Update task with result
        task_info["status"] = "completed"
        task_info["result"] = result
        task_info["completed_at"] = time.time()
        task_info["processing_time"] = processing_time
        
        redis_client.setex(f"task:{task_id}", 3600, json.dumps(task_info))
        
        # Store in database
        conn = get_db_connection()
        if conn:
            try:
                with conn.cursor() as cur:
                    cur.execute("""
                        INSERT INTO tasks (id, data, status, created_at, completed_at, worker_id, processing_time)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                        ON CONFLICT (id) DO UPDATE SET
                            status = EXCLUDED.status,
                            completed_at = EXCLUDED.completed_at,
                            processing_time = EXCLUDED.processing_time
                    """, (
                        task_id,
                        json.dumps(task_info["data"]),
                        "completed",
                        time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(task_info["created_at"])),
                        time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(task_info["completed_at"])),
                        WORKER_ID,
                        processing_time
                    ))
                    conn.commit()
            except Exception as e:
                logger.error(f"Database write failed: {e}")
            finally:
                conn.close()
        
        logger.info(f"Task {task_id} completed by worker {WORKER_ID}")
        return result
        
    except Exception as e:
        logger.error(f"Error processing task {task_id}: {e}")
        return {"status": "error", "message": str(e)}

def worker_loop():
    """Main worker loop that processes tasks from the queue"""
    global worker_running
    
    # Register this worker
    redis_client.sadd("active_workers", WORKER_ID)
    redis_client.set(f"worker:{WORKER_ID}:last_seen", time.time())
    
    while worker_running:
        try:
            # Get task from queue (blocking for 1 second)
            result = redis_client.brpop("task_queue", timeout=1)
            
            if result:
                task_id = result[1]
                logger.info(f"Worker {WORKER_ID} processing task {task_id}")
                
                # Process the task
                process_task(task_id)
                
                # Update queue length
                queue_length = redis_client.llen("task_queue")
                redis_client.set("queue_length", queue_length)
            
            # Update worker heartbeat
            redis_client.set(f"worker:{WORKER_ID}:last_seen", time.time())
            
        except Exception as e:
            logger.error(f"Worker loop error: {e}")
            time.sleep(1)
    
    # Unregister worker
    redis_client.srem("active_workers", WORKER_ID)
    redis_client.delete(f"worker:{WORKER_ID}:last_seen")
    logger.info(f"Worker {WORKER_ID} stopped")

def start_worker():
    """Start the worker thread"""
    global worker_running, worker_thread
    
    if not worker_running:
        worker_running = True
        worker_thread = threading.Thread(target=worker_loop, daemon=True)
        worker_thread.start()
        logger.info(f"Worker {WORKER_ID} started")

def stop_worker():
    """Stop the worker thread"""
    global worker_running
    
    if worker_running:
        worker_running = False
        if worker_thread:
            worker_thread.join(timeout=5)
        logger.info(f"Worker {WORKER_ID} stopped")

@app.on_event("startup")
async def startup_event():
    """Initialize the worker service"""
    logger.info(f"Worker service {WORKER_ID} starting up...")
    init_database()
    start_worker()

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    logger.info(f"Worker service {WORKER_ID} shutting down...")
    stop_worker()

@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "service": "Worker Service",
        "worker_id": WORKER_ID,
        "status": "healthy",
        "timestamp": time.time(),
        "active": worker_running
    }

@app.get("/health")
async def health():
    """Health check for load balancer"""
    return {"status": "healthy", "worker_id": WORKER_ID}

@app.get("/worker/status")
async def worker_status():
    """Get detailed worker status"""
    try:
        active_workers = redis_client.smembers("active_workers")
        queue_length = int(redis_client.get("queue_length") or 0)
        
        # Get worker metrics
        worker_metrics = {}
        for worker_id in active_workers:
            last_seen = redis_client.get(f"worker:{worker_id}:last_seen")
            worker_metrics[worker_id] = {
                "last_seen": float(last_seen) if last_seen else 0,
                "active": True
            }
        
        return {
            "worker_id": WORKER_ID,
            "status": "running" if worker_running else "stopped",
            "active_workers": list(active_workers),
            "queue_length": queue_length,
            "worker_metrics": worker_metrics,
            "timestamp": time.time()
        }
    except Exception as e:
        logger.error(f"Error getting worker status: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.post("/worker/scale")
async def scale_worker():
    """Simulate worker scaling (in real scenario, this would trigger container scaling)"""
    try:
        # Get current metrics
        active_workers = len(redis_client.smembers("active_workers"))
        queue_length = int(redis_client.get("queue_length") or 0)
        
        # Simple scaling logic: if queue is long, suggest scaling up
        if queue_length > active_workers * 2:
            return {
                "action": "scale_up",
                "reason": f"Queue length ({queue_length}) is high compared to workers ({active_workers})",
                "current_workers": active_workers,
                "queue_length": queue_length
            }
        elif queue_length < active_workers and active_workers > 1:
            return {
                "action": "scale_down",
                "reason": f"Queue length ({queue_length}) is low compared to workers ({active_workers})",
                "current_workers": active_workers,
                "queue_length": queue_length
            }
        else:
            return {
                "action": "maintain",
                "reason": "Current scaling is appropriate",
                "current_workers": active_workers,
                "queue_length": queue_length
            }
    except Exception as e:
        logger.error(f"Error in scaling logic: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001) 