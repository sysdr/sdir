"""
Long-tail Latency Observatory - Backend Service
Demonstrates various latency causes and mitigation strategies
"""

import asyncio
import time
import random
import json
import logging
from typing import Dict, List, Optional
from datetime import datetime, timedelta
from collections import deque
import numpy as np
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from fastapi.responses import HTMLResponse
from fastapi import Request
from pydantic import BaseModel
import uvicorn
# import psutil  # Removed due to compilation issues in Docker
import gc

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Long-tail Latency Observatory", version="1.0.0")

# Mount static files and templates
app.mount("/static", StaticFiles(directory="frontend/static"), name="static")
templates = Jinja2Templates(directory="frontend/templates")

# Global state for latency simulation
class LatencyConfig(BaseModel):
    gc_pause_enabled: bool = False
    gc_pause_probability: float = 0.01
    gc_pause_duration: float = 100.0  # ms
    
    db_lock_enabled: bool = False
    db_lock_probability: float = 0.005
    db_lock_duration: float = 500.0  # ms
    
    cache_miss_enabled: bool = False
    cache_miss_probability: float = 0.1
    cache_miss_penalty: float = 50.0  # ms
    
    network_jitter_enabled: bool = False
    network_jitter_max: float = 20.0  # ms
    
    thread_pool_exhaustion: bool = False
    cpu_throttling: bool = False
    
    # Mitigation strategies
    load_shedding_enabled: bool = False
    load_shedding_threshold: float = 0.8
    
    request_hedging_enabled: bool = False
    hedging_threshold: float = 100.0  # ms
    
    circuit_breaker_enabled: bool = False
    circuit_breaker_failure_threshold: int = 5
    
    adaptive_timeouts_enabled: bool = False

class LatencyMetrics:
    def __init__(self, max_samples: int = 1000):
        self.response_times = deque(maxlen=max_samples)
        self.timestamps = deque(maxlen=max_samples)
        self.request_count = 0
        self.error_count = 0
        self.shed_count = 0
        self.hedged_count = 0
        
    def add_sample(self, response_time: float):
        self.response_times.append(response_time)
        self.timestamps.append(time.time())
        self.request_count += 1
        
    def get_percentiles(self) -> Dict[str, float]:
        if not self.response_times:
            return {"p50": 0, "p95": 0, "p99": 0, "p99_9": 0}
            
        times = list(self.response_times)
        return {
            "p50": np.percentile(times, 50),
            "p95": np.percentile(times, 95),
            "p99": np.percentile(times, 99),
            "p99_9": np.percentile(times, 99.9)
        }
    
    def get_recent_stats(self, window_seconds: int = 60) -> Dict:
        cutoff_time = time.time() - window_seconds
        recent_times = []
        
        for i, timestamp in enumerate(self.timestamps):
            if timestamp >= cutoff_time:
                recent_times.append(self.response_times[i])
        
        if not recent_times:
            return {"count": 0, "avg": 0, "percentiles": self.get_percentiles()}
            
        return {
            "count": len(recent_times),
            "avg": np.mean(recent_times),
            "percentiles": {
                "p50": np.percentile(recent_times, 50),
                "p95": np.percentile(recent_times, 95),
                "p99": np.percentile(recent_times, 99),
                "p99_9": np.percentile(recent_times, 99.9) if len(recent_times) > 10 else np.percentile(recent_times, 99)
            }
        }

# Global instances
latency_config = LatencyConfig()
metrics = LatencyMetrics()
connected_clients = []
circuit_breaker_failures = 0
circuit_breaker_state = "closed"  # closed, open, half-open

class LatencySimulator:
    @staticmethod
    async def simulate_gc_pause():
        """Simulate JVM garbage collection pause"""
        if latency_config.gc_pause_enabled and random.random() < latency_config.gc_pause_probability:
            logger.info(f"Simulating GC pause: {latency_config.gc_pause_duration}ms")
            await asyncio.sleep(latency_config.gc_pause_duration / 1000.0)
            # Force actual garbage collection for realism
            gc.collect()
            return latency_config.gc_pause_duration
        return 0
    
    @staticmethod
    async def simulate_db_lock():
        """Simulate database lock contention"""
        if latency_config.db_lock_enabled and random.random() < latency_config.db_lock_probability:
            logger.info(f"Simulating DB lock: {latency_config.db_lock_duration}ms")
            await asyncio.sleep(latency_config.db_lock_duration / 1000.0)
            return latency_config.db_lock_duration
        return 0
    
    @staticmethod
    async def simulate_cache_miss():
        """Simulate cache miss penalty"""
        if latency_config.cache_miss_enabled and random.random() < latency_config.cache_miss_probability:
            await asyncio.sleep(latency_config.cache_miss_penalty / 1000.0)
            return latency_config.cache_miss_penalty
        return 0
    
    @staticmethod
    async def simulate_network_jitter():
        """Simulate network latency variation"""
        if latency_config.network_jitter_enabled:
            jitter = random.uniform(0, latency_config.network_jitter_max)
            await asyncio.sleep(jitter / 1000.0)
            return jitter
        return 0

class MitigationStrategies:
    @staticmethod
    def should_shed_load() -> bool:
        """Determine if request should be shed due to high load"""
        if not latency_config.load_shedding_enabled:
            return False
            
        # Simplified load shedding based on recent latency patterns
        recent_stats = metrics.get_recent_stats(30)
        
        if recent_stats["percentiles"]["p99"] > 1000:  # 1 second P99
            return random.random() < 0.1  # Shed 10% of requests
            
        # Simulate high CPU usage based on request rate
        if metrics.request_count > 1000:  # High request volume
            return random.random() < 0.05  # Shed 5% of requests
            
        return False
    
    @staticmethod
    def should_hedge_request(current_latency: float) -> bool:
        """Determine if request should be hedged"""
        return (latency_config.request_hedging_enabled and 
                current_latency > latency_config.hedging_threshold)
    
    @staticmethod
    def circuit_breaker_check() -> bool:
        """Check circuit breaker state"""
        global circuit_breaker_state, circuit_breaker_failures
        
        if not latency_config.circuit_breaker_enabled:
            return True
            
        if circuit_breaker_state == "open":
            return False
        elif circuit_breaker_state == "half-open":
            return random.random() < 0.5  # Let some requests through
            
        return True

@app.get("/", response_class=HTMLResponse)
async def root(request: Request):
    """Serve the main dashboard"""
    return templates.TemplateResponse("index.html", {"request": request})

@app.get("/api/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}

@app.post("/api/config")
async def update_config(config: LatencyConfig):
    """Update latency simulation configuration"""
    global latency_config
    latency_config = config
    logger.info(f"Configuration updated: {config}")
    return {"status": "updated", "config": config}

@app.get("/api/config")
async def get_config():
    """Get current configuration"""
    return latency_config

@app.get("/api/simulate")
async def simulate_request():
    """Simulate a request with potential latency issues"""
    start_time = time.time()
    total_latency = 0
    latency_sources = []
    
    try:
        # Check if request should be shed
        if MitigationStrategies.should_shed_load():
            metrics.shed_count += 1
            raise HTTPException(status_code=503, detail="Load shed")
        
        # Check circuit breaker
        if not MitigationStrategies.circuit_breaker_check():
            raise HTTPException(status_code=503, detail="Circuit breaker open")
        
        # Simulate base processing time
        base_time = random.uniform(10, 50)  # 10-50ms base latency
        await asyncio.sleep(base_time / 1000.0)
        total_latency += base_time
        
        # Apply various latency sources
        gc_latency = await LatencySimulator.simulate_gc_pause()
        if gc_latency > 0:
            latency_sources.append(f"GC: {gc_latency:.1f}ms")
            total_latency += gc_latency
        
        db_latency = await LatencySimulator.simulate_db_lock()
        if db_latency > 0:
            latency_sources.append(f"DB Lock: {db_latency:.1f}ms")
            total_latency += db_latency
        
        cache_latency = await LatencySimulator.simulate_cache_miss()
        if cache_latency > 0:
            latency_sources.append(f"Cache Miss: {cache_latency:.1f}ms")
            total_latency += cache_latency
        
        network_latency = await LatencySimulator.simulate_network_jitter()
        if network_latency > 0:
            latency_sources.append(f"Network: {network_latency:.1f}ms")
            total_latency += network_latency
        
        # Record metrics
        actual_time = (time.time() - start_time) * 1000
        metrics.add_sample(actual_time)
        
        # Check if request should be hedged (for logging)
        hedged = MitigationStrategies.should_hedge_request(actual_time)
        if hedged:
            metrics.hedged_count += 1
        
        return {
            "response_time_ms": round(actual_time, 2),
            "simulated_latency_ms": round(total_latency, 2),
            "latency_sources": latency_sources,
            "hedged": hedged,
            "timestamp": datetime.now().isoformat()
        }
        
    except HTTPException:
        metrics.error_count += 1
        raise
    except Exception as e:
        metrics.error_count += 1
        logger.error(f"Request simulation error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/api/metrics")
async def get_metrics():
    """Get current latency metrics"""
    recent_stats = metrics.get_recent_stats(60)
    overall_percentiles = metrics.get_percentiles()
    
    return {
        "recent_stats": recent_stats,
        "overall_percentiles": overall_percentiles,
        "total_requests": metrics.request_count,
        "error_count": metrics.error_count,
        "shed_count": metrics.shed_count,
        "hedged_count": metrics.hedged_count,
        "circuit_breaker_state": circuit_breaker_state,
        "system_metrics": {
            "cpu_percent": random.uniform(20, 80),  # Simulated CPU usage
            "memory_percent": random.uniform(30, 70),  # Simulated memory usage
            "disk_io": {"read_count": random.randint(100, 1000), "write_count": random.randint(50, 500)}  # Simulated disk I/O
        }
    }

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time metrics"""
    await websocket.accept()
    connected_clients.append(websocket)
    
    try:
        while True:
            # Send metrics every second
            metrics_data = await get_metrics()
            await websocket.send_text(json.dumps(metrics_data))
            await asyncio.sleep(1)
            
    except WebSocketDisconnect:
        connected_clients.remove(websocket)

# Background task to generate load
async def background_load_generator():
    """Generate background load to demonstrate patterns"""
    while True:
        try:
            # Generate requests at varying rates
            rate = random.uniform(0.1, 2.0)  # 0.1 to 2 requests per second
            await asyncio.sleep(1.0 / rate)
            
            # Make a simulated request
            async with asyncio.timeout(5.0):
                await simulate_request()
                
        except Exception as e:
            logger.error(f"Background load generation error: {e}")
            await asyncio.sleep(1)

@app.on_event("startup")
async def startup_event():
    """Start background tasks"""
    asyncio.create_task(background_load_generator())
    logger.info("Long-tail Latency Observatory started")
    logger.info("Dashboard available at: http://localhost:8000")

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
