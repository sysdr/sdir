"""
Chaos Engineering Platform - Core Engine
Implements various failure injection patterns for distributed systems testing
"""

import asyncio
import random
import time
import psutil
import subprocess
import json
import logging
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
from datetime import datetime, timedelta
import aiohttp
from fastapi import FastAPI, WebSocket, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse, JSONResponse
from starlette.requests import Request
import uvicorn

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class ChaosExperiment:
    """Represents a chaos engineering experiment"""
    id: str
    name: str
    target_service: str
    failure_type: str
    intensity: float
    duration: int
    status: str = "ready"
    start_time: Optional[datetime] = None
    results: Dict = None

@dataclass
class ServiceHealth:
    """Tracks service health metrics"""
    service_name: str
    status: str
    response_time: float
    cpu_usage: float
    memory_usage: float
    error_rate: float
    timestamp: datetime

class ChaosEngine:
    """Core chaos engineering engine for failure injection"""
    
    def __init__(self):
        self.experiments: Dict[str, ChaosExperiment] = {}
        self.services: Dict[str, ServiceHealth] = {}
        self.active_failures: Dict[str, Dict] = {}
        self.metrics_history: List[Dict] = []
        
    async def inject_latency(self, service_name: str, delay_ms: int, duration: int):
        """Inject network latency into service communications"""
        logger.info(f"🐢 Injecting {delay_ms}ms latency to {service_name} for {duration}s")
        
        # Simulate latency injection (in real implementation, this would use iptables or toxiproxy)
        self.active_failures[service_name] = {
            "type": "latency",
            "delay_ms": delay_ms,
            "start_time": time.time(),
            "duration": duration
        }
        
        await asyncio.sleep(duration)
        
        if service_name in self.active_failures:
            del self.active_failures[service_name]
        logger.info(f"✅ Latency injection completed for {service_name}")
    
    async def inject_cpu_load(self, service_name: str, cpu_percent: int, duration: int):
        """Inject CPU load to simulate resource exhaustion"""
        logger.info(f"🔥 Injecting {cpu_percent}% CPU load to {service_name} for {duration}s")
        
        self.active_failures[service_name] = {
            "type": "cpu_load",
            "cpu_percent": cpu_percent,
            "start_time": time.time(),
            "duration": duration
        }
        
        # Simulate CPU load (in real implementation, use stress testing tools)
        start_time = time.time()
        while time.time() - start_time < duration:
            # Busy work to consume CPU
            for _ in range(100000):
                _ = sum(range(100))
            await asyncio.sleep(0.01)
        
        if service_name in self.active_failures:
            del self.active_failures[service_name]
        logger.info(f"✅ CPU load injection completed for {service_name}")
    
    async def inject_memory_pressure(self, service_name: str, memory_mb: int, duration: int):
        """Inject memory pressure to simulate memory leaks"""
        logger.info(f"🧠 Injecting {memory_mb}MB memory pressure to {service_name} for {duration}s")
        
        self.active_failures[service_name] = {
            "type": "memory_pressure",
            "memory_mb": memory_mb,
            "start_time": time.time(),
            "duration": duration
        }
        
        # Allocate memory to simulate pressure
        memory_hog = []
        try:
            for _ in range(memory_mb):
                memory_hog.append(b'x' * 1024 * 1024)  # 1MB chunks
            
            await asyncio.sleep(duration)
        finally:
            memory_hog.clear()
            if service_name in self.active_failures:
                del self.active_failures[service_name]
        
        logger.info(f"✅ Memory pressure injection completed for {service_name}")
    
    async def inject_network_partition(self, service_name: str, duration: int):
        """Simulate network partition by blocking communications"""
        logger.info(f"🚫 Creating network partition for {service_name} for {duration}s")
        
        self.active_failures[service_name] = {
            "type": "network_partition",
            "start_time": time.time(),
            "duration": duration
        }
        
        await asyncio.sleep(duration)
        
        if service_name in self.active_failures:
            del self.active_failures[service_name]
        logger.info(f"✅ Network partition resolved for {service_name}")
    
    async def run_experiment(self, experiment: ChaosExperiment):
        """Execute a chaos experiment"""
        experiment.status = "running"
        experiment.start_time = datetime.now()
        
        logger.info(f"🧪 Starting experiment: {experiment.name}")
        
        try:
            if experiment.failure_type == "latency":
                await self.inject_latency(
                    experiment.target_service,
                    int(experiment.intensity * 1000),  # Convert to ms
                    experiment.duration
                )
            elif experiment.failure_type == "cpu_load":
                await self.inject_cpu_load(
                    experiment.target_service,
                    int(experiment.intensity * 100),  # Convert to percentage
                    experiment.duration
                )
            elif experiment.failure_type == "memory_pressure":
                await self.inject_memory_pressure(
                    experiment.target_service,
                    int(experiment.intensity * 100),  # Convert to MB
                    experiment.duration
                )
            elif experiment.failure_type == "network_partition":
                await self.inject_network_partition(
                    experiment.target_service,
                    experiment.duration
                )
            
            experiment.status = "completed"
            experiment.results = {"success": True, "observations": "Experiment completed successfully"}
            
        except Exception as e:
            experiment.status = "failed"
            experiment.results = {"success": False, "error": str(e)}
            logger.error(f"❌ Experiment failed: {e}")
    
    def get_system_metrics(self) -> Dict:
        """Get current system metrics"""
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        
        return {
            "cpu_usage": cpu_percent,
            "memory_usage": memory.percent,
            "memory_available": memory.available / (1024**3),  # GB
            "disk_usage": disk.percent,
            "active_failures": len(self.active_failures),
            "timestamp": datetime.now().isoformat()
        }

# Initialize chaos engine
chaos_engine = ChaosEngine()

# FastAPI application
app = FastAPI(title="Chaos Engineering Platform", version="1.0.0")
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    """Main dashboard"""
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.get("/api/experiments")
async def get_experiments():
    """Get all experiments"""
    return [asdict(exp) for exp in chaos_engine.experiments.values()]

@app.post("/api/experiments")
async def create_experiment(experiment_data: dict):
    """Create new chaos experiment"""
    experiment = ChaosExperiment(
        id=f"exp_{int(time.time())}",
        name=experiment_data["name"],
        target_service=experiment_data["target_service"],
        failure_type=experiment_data["failure_type"],
        intensity=experiment_data["intensity"],
        duration=experiment_data["duration"]
    )
    
    chaos_engine.experiments[experiment.id] = experiment
    return {"id": experiment.id, "status": "created"}

@app.post("/api/experiments/{experiment_id}/run")
async def run_experiment(experiment_id: str):
    """Run a chaos experiment"""
    if experiment_id not in chaos_engine.experiments:
        raise HTTPException(status_code=404, detail="Experiment not found")
    
    experiment = chaos_engine.experiments[experiment_id]
    
    # Run experiment in background
    asyncio.create_task(chaos_engine.run_experiment(experiment))
    
    return {"status": "started", "experiment_id": experiment_id}

@app.get("/api/metrics")
async def get_metrics():
    """Get current system metrics"""
    return chaos_engine.get_system_metrics()

@app.get("/api/failures")
async def get_active_failures():
    """Get currently active failures"""
    return chaos_engine.active_failures

@app.websocket("/ws/metrics")
async def metrics_websocket(websocket: WebSocket):
    """WebSocket endpoint for real-time metrics"""
    await websocket.accept()
    try:
        while True:
            metrics = chaos_engine.get_system_metrics()
            await websocket.send_json(metrics)
            await asyncio.sleep(2)
    except Exception as e:
        logger.error(f"WebSocket error: {e}")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
