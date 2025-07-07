import asyncio
import json
import time
import os
from typing import Dict, List
import redis.asyncio as redis
from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import uvicorn
from contextlib import asynccontextmanager

app = FastAPI(title="Task Scheduler Dashboard")

# Mount static files and templates
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

class DashboardManager:
    def __init__(self):
        self.redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
        self.redis_client = None
        self.connected_clients: List[WebSocket] = []
        
    async def init_redis(self):
        self.redis_client = redis.from_url(self.redis_url)
        
    async def start(self):
        await self.init_redis()
        # Start background task for broadcasting updates
        asyncio.create_task(self.broadcast_updates())
        
    async def get_system_status(self):
        """Get comprehensive system status"""
        try:
            # Get scheduler status
            scheduler_data = await self.redis_client.get("scheduler:workers")
            workers = json.loads(scheduler_data) if scheduler_data else {}
            
            # Get queue lengths
            high_queue = await self.redis_client.llen("tasks:high_priority")
            normal_queue = await self.redis_client.llen("tasks:normal_priority")
            low_queue = await self.redis_client.llen("tasks:low_priority")
            
            # Get current leader
            leader = await self.redis_client.get("scheduler:leader")
            leader_id = leader.decode() if leader else "none"
            
            # Get recent tasks
            task_keys = await self.redis_client.keys("task:*")
            task_keys = [k for k in task_keys if not k.decode().endswith(':original')]
            
            recent_tasks = []
            for task_key in task_keys[-20:]:  # Last 20 tasks
                task_data = await self.redis_client.hgetall(task_key)
                if task_data:
                    task_info = {k.decode(): v.decode() for k, v in task_data.items()}
                    task_info['id'] = task_key.decode().split(':')[1]
                    recent_tasks.append(task_info)
                    
            return {
                'timestamp': time.time(),
                'leader': leader_id,
                'workers': workers,
                'queues': {
                    'high_priority': high_queue,
                    'normal_priority': normal_queue,
                    'low_priority': low_queue,
                    'total': high_queue + normal_queue + low_queue
                },
                'recent_tasks': sorted(recent_tasks, key=lambda x: float(x.get('created_at', 0)), reverse=True)[:10]
            }
            
        except Exception as e:
            return {
                'error': str(e),
                'timestamp': time.time()
            }
            
    async def broadcast_updates(self):
        """Broadcast system updates to connected websockets"""
        while True:
            try:
                if self.connected_clients:
                    status = await self.get_system_status()
                    message = json.dumps(status)
                    
                    # Send to all connected clients
                    disconnected_clients = []
                    for client in self.connected_clients:
                        try:
                            await client.send_text(message)
                        except:
                            disconnected_clients.append(client)
                            
                    # Remove disconnected clients
                    for client in disconnected_clients:
                        self.connected_clients.remove(client)
                        
            except Exception as e:
                print(f"Broadcast error: {e}")
                
            await asyncio.sleep(2)  # Update every 2 seconds

dashboard = DashboardManager()

@asynccontextmanager
async def lifespan(app):
    await dashboard.start()
    yield

app = FastAPI(title="Task Scheduler Dashboard", lifespan=lifespan)

@app.get("/", response_class=HTMLResponse)
async def get_dashboard(request: Request):
    """Main dashboard page"""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates"""
    await websocket.accept()
    dashboard.connected_clients.append(websocket)
    
    try:
        # Send initial status
        status = await dashboard.get_system_status()
        await websocket.send_text(json.dumps(status))
        
        # Keep connection alive by sending periodic heartbeats
        while True:
            try:
                # Send heartbeat every 30 seconds to keep connection alive
                await asyncio.sleep(30)
                await websocket.send_text(json.dumps({"type": "heartbeat", "timestamp": time.time()}))
            except WebSocketDisconnect:
                break
            except Exception as e:
                print(f"WebSocket error: {e}")
                break
                
    except WebSocketDisconnect:
        pass
    finally:
        if websocket in dashboard.connected_clients:
            dashboard.connected_clients.remove(websocket)

@app.get("/api/status")
async def api_status():
    """API endpoint for system status"""
    return await dashboard.get_system_status()

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=3000)
