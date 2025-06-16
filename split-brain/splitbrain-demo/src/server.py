"""
Web Server for Split-Brain Demo
Provides REST API and WebSocket interface for monitoring nodes
"""
import asyncio
import json
import logging
from typing import Dict, List
from fastapi import FastAPI, WebSocket, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.requests import Request
from fastapi.responses import HTMLResponse
import uvicorn

from .node import DistributedNode

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class DemoOrchestrator:
    def __init__(self):
        self.nodes: Dict[str, DistributedNode] = {}
        self.websockets: List[WebSocket] = []
        
    async def create_cluster(self, node_count: int = 5):
        """Create a cluster of nodes"""
        node_ids = [f"node{i+1}" for i in range(node_count)]
        
        for i, node_id in enumerate(node_ids):
            port = 8000 + i + 1
            node = DistributedNode(node_id, port, node_ids)
            self.nodes[node_id] = node
            await node.start()
        
        logger.info(f"✅ Created cluster with {node_count} nodes")
        await self.broadcast_status()
    
    async def simulate_partition(self, partition_config: dict):
        """Simulate network partition"""
        group_a = partition_config.get("group_a", [])
        group_b = partition_config.get("group_b", [])
        
        # Partition group A
        for node_id in group_a:
            if node_id in self.nodes:
                self.nodes[node_id].simulate_partition(group_b, "A")
        
        # Partition group B
        for node_id in group_b:
            if node_id in self.nodes:
                self.nodes[node_id].simulate_partition(group_a, "B")
        
        logger.info(f"🔌 Simulated partition: A={group_a}, B={group_b}")
        await self.broadcast_status()
    
    async def heal_partition(self):
        """Heal all partitions"""
        for node in self.nodes.values():
            node.heal_partition()
        
        logger.info("🔗 Healed all partitions")
        await self.broadcast_status()
    
    async def get_cluster_status(self) -> dict:
        """Get status of all nodes"""
        status = {}
        for node_id, node in self.nodes.items():
            status[node_id] = node.get_status()
        return status
    
    async def broadcast_status(self):
        """Broadcast status to all connected websockets"""
        if not self.websockets:
            return
            
        try:
            status = await self.get_cluster_status()
            message = json.dumps({
                "type": "status_update",
                "data": status
            })
            
            # Send to all connected websockets
            disconnected = []
            for ws in self.websockets:
                try:
                    await ws.send_text(message)
                except:
                    disconnected.append(ws)
            
            # Remove disconnected websockets
            for ws in disconnected:
                self.websockets.remove(ws)
                
        except Exception as e:
            logger.error(f"Failed to broadcast status: {e}")
    
    async def add_websocket(self, websocket: WebSocket):
        """Add websocket connection"""
        self.websockets.append(websocket)
        await self.broadcast_status()
    
    async def remove_websocket(self, websocket: WebSocket):
        """Remove websocket connection"""
        if websocket in self.websockets:
            self.websockets.remove(websocket)

# Global orchestrator
orchestrator = DemoOrchestrator()

# FastAPI app
app = FastAPI(title="Split-Brain Prevention Demo")

# Mount static files and templates
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard"""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.post("/api/cluster/create")
async def create_cluster(config: dict):
    """Create a new cluster"""
    node_count = config.get("node_count", 5)
    await orchestrator.create_cluster(node_count)
    return {"status": "success", "message": f"Created cluster with {node_count} nodes"}

@app.post("/api/cluster/partition")
async def create_partition(config: dict):
    """Create network partition"""
    await orchestrator.simulate_partition(config)
    return {"status": "success", "message": "Network partition created"}

@app.post("/api/cluster/heal")
async def heal_partition():
    """Heal network partition"""
    await orchestrator.heal_partition()
    return {"status": "success", "message": "Network partition healed"}

@app.get("/api/cluster/status")
async def get_status():
    """Get cluster status"""
    return await orchestrator.get_cluster_status()

@app.post("/api/nodes/{node_id}/add_entry")
async def add_log_entry(node_id: str, entry: dict):
    """Add log entry to specific node"""
    if node_id not in orchestrator.nodes:
        raise HTTPException(status_code=404, detail="Node not found")
    
    command = entry.get("command", "")
    success = await orchestrator.nodes[node_id].add_entry(command)
    
    if success:
        await orchestrator.broadcast_status()
        return {"status": "success", "message": "Log entry added"}
    else:
        return {"status": "error", "message": "Node is not leader"}

@app.post("/nodes/{node_id}/rpc")
async def handle_rpc(node_id: str, message: dict):
    """Handle RPC messages between nodes"""
    if node_id not in orchestrator.nodes:
        raise HTTPException(status_code=404, detail="Node not found")
    
    response = await orchestrator.nodes[node_id].handle_rpc(message)
    return response

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates"""
    await websocket.accept()
    await orchestrator.add_websocket(websocket)
    
    try:
        while True:
            # Keep connection alive and handle client messages
            await websocket.receive_text()
    except:
        pass
    finally:
        await orchestrator.remove_websocket(websocket)

# Background task to periodically broadcast status
async def status_broadcaster():
    """Periodically broadcast status updates"""
    while True:
        await asyncio.sleep(2)  # Broadcast every 2 seconds
        await orchestrator.broadcast_status()

@app.on_event("startup")
async def startup_event():
    """Start background tasks"""
    asyncio.create_task(status_broadcaster())

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")
