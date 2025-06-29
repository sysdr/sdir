#!/usr/bin/env python3
"""
Multi-Region Architecture Demo
Simulates a global distributed system with multiple regions,
demonstrating latency, failover, and data replication patterns.
"""

import asyncio
import json
import time
import random
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
from enum import Enum
import threading
import webbrowser
from pathlib import Path

from fastapi import FastAPI, Request, WebSocket, WebSocketDisconnect
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse, JSONResponse
import uvicorn
import redis.asyncio as redis

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class RegionStatus(Enum):
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    FAILED = "failed"

class CircuitBreakerState(Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"

@dataclass
class Region:
    name: str
    location: str
    latitude: float
    longitude: float
    status: RegionStatus = RegionStatus.HEALTHY
    latency_base: float = 50.0  # Base latency in ms
    failure_rate: float = 0.0
    last_health_check: Optional[datetime] = None
    connection_count: int = 0
    data_version: int = 1

@dataclass
class CircuitBreaker:
    state: CircuitBreakerState = CircuitBreakerState.CLOSED
    failure_count: int = 0
    last_failure_time: Optional[datetime] = None
    timeout_duration: int = 60  # seconds
    failure_threshold: int = 5
    success_threshold: int = 3
    success_count: int = 0

class GlobalLoadBalancer:
    def __init__(self):
        self.regions = {
            "us-west": Region("us-west", "San Francisco", 37.7749, -122.4194, latency_base=25),
            "us-east": Region("us-east", "Virginia", 39.0458, -77.4580, latency_base=30),
            "eu-west": Region("eu-west", "Frankfurt", 50.1109, 8.6821, latency_base=45),
            "asia-southeast": Region("asia-southeast", "Singapore", 1.3521, 103.8198, latency_base=60),
            "asia-northeast": Region("asia-northeast", "Tokyo", 35.6762, 139.6503, latency_base=70),
        }
        self.circuit_breakers = {name: CircuitBreaker() for name in self.regions.keys()}
        self.active_connections = {}
        self.replication_log = []
        
    def calculate_latency(self, user_region: str, target_region: str) -> float:
        """Calculate simulated latency between regions"""
        base_latency = self.regions[target_region].latency_base
        
        # Add random jitter
        jitter = random.uniform(-10, 20)
        
        # Add load-based latency
        load_factor = min(self.regions[target_region].connection_count / 100, 2.0)
        load_latency = base_latency * load_factor * 0.3
        
        # Add failure simulation
        if self.regions[target_region].status == RegionStatus.DEGRADED:
            base_latency *= 2
        elif self.regions[target_region].status == RegionStatus.FAILED:
            return float('inf')
            
        return max(base_latency + jitter + load_latency, 1.0)
    
    def get_best_region(self, user_location: str = "us-west") -> str:
        """Select the best region for a user based on health and latency"""
        available_regions = []
        
        for region_name, region in self.regions.items():
            cb = self.circuit_breakers[region_name]
            
            # Skip if circuit breaker is open
            if cb.state == CircuitBreakerState.OPEN:
                if datetime.now() - cb.last_failure_time > timedelta(seconds=cb.timeout_duration):
                    cb.state = CircuitBreakerState.HALF_OPEN
                    cb.success_count = 0
                else:
                    continue
            
            if region.status != RegionStatus.FAILED:
                latency = self.calculate_latency(user_location, region_name)
                if latency != float('inf'):
                    available_regions.append((region_name, latency))
        
        if not available_regions:
            return list(self.regions.keys())[0]  # Fallback
            
        # Sort by latency and return best option
        available_regions.sort(key=lambda x: x[1])
        return available_regions[0][0]
    
    def handle_request(self, region_name: str) -> Dict:
        """Simulate handling a request in a specific region"""
        region = self.regions[region_name]
        cb = self.circuit_breakers[region_name]
        
        # Simulate request processing
        processing_time = random.uniform(10, 100)
        
        # Simulate failures based on region status
        success = True
        if region.status == RegionStatus.DEGRADED:
            success = random.random() > 0.3  # 30% failure rate
        elif region.status == RegionStatus.FAILED:
            success = False
        else:
            success = random.random() > region.failure_rate
        
        # Update circuit breaker
        if success:
            if cb.state == CircuitBreakerState.HALF_OPEN:
                cb.success_count += 1
                if cb.success_count >= cb.success_threshold:
                    cb.state = CircuitBreakerState.CLOSED
                    cb.failure_count = 0
            elif cb.state == CircuitBreakerState.CLOSED:
                cb.failure_count = max(0, cb.failure_count - 1)
        else:
            cb.failure_count += 1
            cb.last_failure_time = datetime.now()
            
            if cb.failure_count >= cb.failure_threshold:
                cb.state = CircuitBreakerState.OPEN
        
        region.connection_count += 1
        
        return {
            "success": success,
            "region": region_name,
            "latency": processing_time,
            "circuit_breaker_state": cb.state.value,
            "timestamp": datetime.now().isoformat()
        }
    
    def replicate_data(self, source_region: str, data: Dict):
        """Simulate data replication between regions"""
        replication_entry = {
            "source": source_region,
            "data": data,
            "timestamp": datetime.now().isoformat(),
            "replicated_to": []
        }
        
        for target_region in self.regions.keys():
            if target_region != source_region and self.regions[target_region].status != RegionStatus.FAILED:
                # Simulate replication latency
                replication_latency = self.calculate_latency(source_region, target_region) * 2
                replication_entry["replicated_to"].append({
                    "region": target_region,
                    "latency": replication_latency,
                    "status": "success" if replication_latency != float('inf') else "failed"
                })
                
                # Update data version
                self.regions[target_region].data_version += 1
        
        self.replication_log.append(replication_entry)
        return replication_entry

# Global state
glb = GlobalLoadBalancer()
app = FastAPI(title="Multi-Region Architecture Demo")

# Setup templates and static files
templates = Jinja2Templates(directory="templates")
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.get("/api/regions")
async def get_regions():
    """Get current state of all regions"""
    result = {}
    for name, region in glb.regions.items():
        cb = glb.circuit_breakers[name]
        result[name] = {
            **asdict(region),
            "circuit_breaker": {
                "state": cb.state.value,
                "failure_count": cb.failure_count,
                "success_count": cb.success_count
            }
        }
    return result

@app.post("/api/request")
async def simulate_request(request_data: dict):
    """Simulate a user request"""
    user_location = request_data.get("user_location", "us-west")
    best_region = glb.get_best_region(user_location)
    result = glb.handle_request(best_region)
    return result

@app.post("/api/region/{region_name}/status")
async def update_region_status(region_name: str, status_data: dict):
    """Update region status for testing failover"""
    if region_name in glb.regions:
        new_status = RegionStatus(status_data["status"])
        glb.regions[region_name].status = new_status
        glb.regions[region_name].failure_rate = status_data.get("failure_rate", 0.0)
        return {"message": f"Region {region_name} status updated to {new_status.value}"}
    return {"error": "Region not found"}, 404

@app.post("/api/replicate")
async def simulate_replication(data: dict):
    """Simulate data replication"""
    source_region = data.get("source_region", "us-west")
    payload = data.get("payload", {"user_id": 123, "action": "update_profile"})
    
    result = glb.replicate_data(source_region, payload)
    return result

@app.get("/api/metrics")
async def get_metrics():
    """Get system metrics for monitoring"""
    total_connections = sum(r.connection_count for r in glb.regions.values())
    healthy_regions = sum(1 for r in glb.regions.values() if r.status == RegionStatus.HEALTHY)
    
    return {
        "total_regions": len(glb.regions),
        "healthy_regions": healthy_regions,
        "total_connections": total_connections,
        "replication_events": len(glb.replication_log),
        "circuit_breakers": {
            name: cb.state.value for name, cb in glb.circuit_breakers.items()
        }
    }

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket for real-time updates"""
    await websocket.accept()
    try:
        while True:
            # Send periodic updates
            data = {
                "regions": await get_regions(),
                "metrics": await get_metrics(),
                "timestamp": datetime.now().isoformat()
            }
            await websocket.send_json(data)
            await asyncio.sleep(2)
    except WebSocketDisconnect:
        pass

if __name__ == "__main__":
    print("🌍 Starting Multi-Region Architecture Demo...")
    print("📊 Dashboard will be available at: http://localhost:5000")
    
    # Start background tasks
    def background_simulation():
        """Simulate ongoing traffic and events"""
        while True:
            try:
                # Simulate random requests
                for _ in range(random.randint(1, 5)):
                    user_location = random.choice(list(glb.regions.keys()))
                    glb.get_best_region(user_location)
                
                # Occasionally simulate failures
                if random.random() < 0.1:  # 10% chance
                    region_name = random.choice(list(glb.regions.keys()))
                    if glb.regions[region_name].status == RegionStatus.HEALTHY:
                        glb.regions[region_name].status = RegionStatus.DEGRADED
                        print(f"⚠️ Region {region_name} degraded")
                    elif glb.regions[region_name].status == RegionStatus.DEGRADED:
                        glb.regions[region_name].status = RegionStatus.HEALTHY
                        print(f"✅ Region {region_name} recovered")
                
                time.sleep(5)
            except Exception as e:
                logger.error(f"Background simulation error: {e}")
                time.sleep(1)
    
    # Start background thread
    threading.Thread(target=background_simulation, daemon=True).start()
    
    # Try to open browser
    try:
        threading.Timer(2.0, lambda: webbrowser.open('http://localhost:5000')).start()
    except:
        pass
    
    # Start the server
    uvicorn.run(app, host="0.0.0.0", port=5000, log_level="info")
