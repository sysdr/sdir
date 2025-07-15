"""FastAPI application for hot partition detection demo."""

import json
import logging
import os
from datetime import datetime
from typing import Dict, List, Optional

import redis.asyncio as redis
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.requests import Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Hot Partition Detection Demo", version="1.0.0")

# Mount static files and templates
static_dir = "frontend/static"
templates_dir = "frontend/templates"

# Debug: Check if directories exist
logger.info(f"Static directory exists: {os.path.exists(static_dir)}")
logger.info(f"Templates directory exists: {os.path.exists(templates_dir)}")
if os.path.exists(static_dir):
    logger.info(f"Static directory contents: {os.listdir(static_dir)}")

app.mount("/static", StaticFiles(directory=static_dir), name="static")
templates = Jinja2Templates(directory=templates_dir)

# Add error handling for static files
@app.exception_handler(404)
async def not_found_handler(request: Request, exc: HTTPException):
    """Handle 404 errors for static files."""
    if request.url.path.startswith("/static/"):
        logger.error(f"Static file not found: {request.url.path}")
        return {"error": "Static file not found", "path": request.url.path}
    return {"error": "Not found"}

# Redis client
redis_client = None

# WebSocket connections
active_connections: List[WebSocket] = []

class PartitionMetrics(BaseModel):
    partition_id: str
    request_count: int
    memory_usage_mb: float
    cpu_usage_percent: float
    avg_response_time_ms: float
    error_rate: float
    timestamp: str

class HotspotTrigger(BaseModel):
    partition_id: Optional[str] = None
    intensity: float = 5.0

@app.on_event("startup")
async def startup():
    """Initialize Redis connection."""
    global redis_client
    redis_client = redis.from_url("redis://redis:6379")
    try:
        await redis_client.ping()
        logger.info("Connected to Redis")
    except Exception as e:
        logger.error(f"Failed to connect to Redis: {e}")

@app.on_event("shutdown")
async def shutdown():
    """Close Redis connection."""
    if redis_client:
        await redis_client.close()

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Render the main dashboard."""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.get("/api/metrics")
async def get_current_metrics():
    """Get current partition metrics."""
    try:
        metrics_data = await redis_client.hgetall("current_metrics")
        
        metrics = {}
        for partition_id, data in metrics_data.items():
            if isinstance(partition_id, bytes):
                partition_id = partition_id.decode()
            if isinstance(data, bytes):
                data = data.decode()
            metrics[partition_id] = json.loads(data)
        
        return {"metrics": metrics, "timestamp": datetime.now().isoformat()}
    
    except Exception as e:
        logger.error(f"Error fetching metrics: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch metrics")

@app.get("/api/analysis")
async def get_analysis_results():
    """Get current analysis results."""
    try:
        # Get entropy score
        entropy_score = await redis_client.hget("analysis_results", "entropy_score")
        entropy_score = float(entropy_score) if entropy_score else 1.0
        
        # Get current alerts
        alerts_data = await redis_client.hgetall("current_alerts")
        alerts = []
        
        for alert_key, alert_data in alerts_data.items():
            if isinstance(alert_data, bytes):
                alert_data = alert_data.decode()
            alerts.append(json.loads(alert_data))
        
        # Get hotspot info
        hotspot_info = await redis_client.hgetall("hotspot_info")
        hotspot = {}
        for key, value in hotspot_info.items():
            if isinstance(key, bytes):
                key = key.decode()
            if isinstance(value, bytes):
                value = value.decode()
            hotspot[key] = value
        
        return {
            "entropy_score": entropy_score,
            "alerts": alerts,
            "hotspot_info": hotspot,
            "timestamp": datetime.now().isoformat()
        }
    
    except Exception as e:
        logger.error(f"Error fetching analysis: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch analysis")

@app.get("/api/historical/{partition_id}")
async def get_historical_metrics(partition_id: str, limit: int = 20):
    """Get historical metrics for a partition."""
    try:
        key = f"historical_{partition_id}"
        data = await redis_client.lrange(key, 0, limit - 1)
        
        historical = []
        for item in data:
            if isinstance(item, bytes):
                item = item.decode()
            historical.append(json.loads(item))
        
        return {"partition_id": partition_id, "historical": historical}
    
    except Exception as e:
        logger.error(f"Error fetching historical data: {e}")
        raise HTTPException(status_code=500, detail="Failed to fetch historical data")

@app.post("/api/trigger-hotspot")
async def trigger_hotspot(trigger: HotspotTrigger):
    """Trigger a hotspot for demonstration."""
    try:
        # Store trigger request
        trigger_data = {
            "partition_id": trigger.partition_id or "auto",
            "intensity": str(trigger.intensity),
            "triggered_at": datetime.now().isoformat(),
            "triggered": "true"
        }
        
        await redis_client.hset("hotspot_trigger", mapping=trigger_data)
        
        return {
            "message": "Hotspot trigger submitted",
            "partition_id": trigger.partition_id,
            "intensity": trigger.intensity
        }
    
    except Exception as e:
        logger.error(f"Error triggering hotspot: {e}")
        raise HTTPException(status_code=500, detail="Failed to trigger hotspot")

@app.post("/api/end-hotspot")
async def end_hotspot():
    """End current hotspot."""
    try:
        await redis_client.hset("hotspot_trigger", "end_requested", "true")
        return {"message": "Hotspot end requested"}
    
    except Exception as e:
        logger.error(f"Error ending hotspot: {e}")
        raise HTTPException(status_code=500, detail="Failed to end hotspot")

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates."""
    await websocket.accept()
    active_connections.append(websocket)
    
    try:
        while True:
            # Send current metrics and analysis
            try:
                metrics_data = await redis_client.hgetall("current_metrics")
                analysis_data = await redis_client.hgetall("analysis_results")
                
                metrics = {}
                for partition_id, data in metrics_data.items():
                    if isinstance(partition_id, bytes):
                        partition_id = partition_id.decode()
                    if isinstance(data, bytes):
                        data = data.decode()
                    metrics[partition_id] = json.loads(data)
                
                entropy_score = await redis_client.hget("analysis_results", "entropy_score")
                entropy_score = float(entropy_score) if entropy_score else 1.0
                
                await websocket.send_json({
                    "type": "metrics_update",
                    "metrics": metrics,
                    "entropy_score": entropy_score,
                    "timestamp": datetime.now().isoformat()
                })
                
            except Exception as e:
                logger.error(f"Error sending WebSocket data: {e}")
            
            await asyncio.sleep(2)
            
    except WebSocketDisconnect:
        active_connections.remove(websocket)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
