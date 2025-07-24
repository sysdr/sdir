#!/bin/bash

# Long-tail Latency Observatory Demo
# System Design Interview Roadmap - Issue #105

set -e

PROJECT_NAME="longtail-latency-demo"
PROJECT_DIR=$(pwd)/$PROJECT_NAME

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    print_step "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is required but not installed"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is required but not installed"
        exit 1
    fi
    
    print_success "All dependencies are available"
}

create_project_structure() {
    print_step "Creating project structure..."
    
    mkdir -p $PROJECT_DIR/{backend,frontend,config,scripts}
    mkdir -p $PROJECT_DIR/backend/{app,requirements}
    mkdir -p $PROJECT_DIR/frontend/{static,templates}
    
    print_success "Project structure created"
}

create_backend_files() {
    print_step "Creating backend application..."
    
    # Requirements file
    cat > $PROJECT_DIR/backend/requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
numpy==1.24.4
asyncio==3.4.3
aiofiles==23.2.0
python-multipart==0.0.6
websockets==12.0
redis==5.0.1
prometheus-client==0.19.0
jinja2==3.1.2
python-jose[cryptography]==3.3.0
python-dateutil==2.8.2
scipy==1.11.4
EOF

    # Main application
    cat > $PROJECT_DIR/backend/app/main.py << 'EOF'
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
EOF

    print_success "Backend application created"
}

create_frontend_files() {
    print_step "Creating frontend interface..."
    
    # HTML template
    cat > $PROJECT_DIR/frontend/templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Long-tail Latency Observatory</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns/dist/chartjs-adapter-date-fns.bundle.min.js"></script>
    <link rel="stylesheet" href="/static/styles.css">
</head>
<body>
    <div class="header">
        <div class="header-content">
            <h1>🔍 Long-tail Latency Observatory</h1>
            <p>System Design Interview Roadmap - Issue #105</p>
        </div>
    </div>

    <div class="container">
        <!-- Metrics Dashboard -->
        <div class="metrics-grid">
            <div class="metric-card">
                <h3>P50 Latency</h3>
                <div class="metric-value" id="p50-metric">0ms</div>
                <div class="metric-trend" id="p50-trend">—</div>
            </div>
            <div class="metric-card">
                <h3>P95 Latency</h3>
                <div class="metric-value" id="p95-metric">0ms</div>
                <div class="metric-trend" id="p95-trend">—</div>
            </div>
            <div class="metric-card">
                <h3>P99 Latency</h3>
                <div class="metric-value" id="p99-metric">0ms</div>
                <div class="metric-trend" id="p99-trend">—</div>
            </div>
            <div class="metric-card">
                <h3>Total Requests</h3>
                <div class="metric-value" id="total-requests">0</div>
                <div class="metric-trend" id="error-rate">0% errors</div>
            </div>
        </div>

        <!-- Charts -->
        <div class="chart-grid">
            <div class="chart-container">
                <h3>Real-time Latency Percentiles</h3>
                <canvas id="latencyChart"></canvas>
            </div>
            <div class="chart-container">
                <h3>Request Rate & Errors</h3>
                <canvas id="requestChart"></canvas>
            </div>
        </div>

        <!-- Configuration Panel -->
        <div class="config-panel">
            <h3>🎛️ Latency Simulation Controls</h3>
            
            <div class="config-section">
                <h4>Latency Sources</h4>
                <div class="config-grid">
                    <label class="config-item">
                        <input type="checkbox" id="gc-pause" onchange="updateConfig()">
                        <span>GC Pauses</span>
                        <input type="range" id="gc-duration" min="50" max="500" value="100" onchange="updateConfig()">
                        <span id="gc-duration-value">100ms</span>
                    </label>
                    
                    <label class="config-item">
                        <input type="checkbox" id="db-lock" onchange="updateConfig()">
                        <span>DB Lock Contention</span>
                        <input type="range" id="db-duration" min="100" max="2000" value="500" onchange="updateConfig()">
                        <span id="db-duration-value">500ms</span>
                    </label>
                    
                    <label class="config-item">
                        <input type="checkbox" id="cache-miss" onchange="updateConfig()">
                        <span>Cache Misses</span>
                        <input type="range" id="cache-penalty" min="10" max="200" value="50" onchange="updateConfig()">
                        <span id="cache-penalty-value">50ms</span>
                    </label>
                    
                    <label class="config-item">
                        <input type="checkbox" id="network-jitter" onchange="updateConfig()">
                        <span>Network Jitter</span>
                        <input type="range" id="jitter-max" min="5" max="100" value="20" onchange="updateConfig()">
                        <span id="jitter-max-value">20ms</span>
                    </label>
                </div>
            </div>

            <div class="config-section">
                <h4>Mitigation Strategies</h4>
                <div class="config-grid">
                    <label class="config-item mitigation">
                        <input type="checkbox" id="load-shedding" onchange="updateConfig()">
                        <span>Load Shedding</span>
                        <small>Drop requests when overloaded</small>
                    </label>
                    
                    <label class="config-item mitigation">
                        <input type="checkbox" id="request-hedging" onchange="updateConfig()">
                        <span>Request Hedging</span>
                        <small>Duplicate slow requests</small>
                    </label>
                    
                    <label class="config-item mitigation">
                        <input type="checkbox" id="circuit-breaker" onchange="updateConfig()">
                        <span>Circuit Breaker</span>
                        <small>Fail fast on repeated errors</small>
                    </label>
                    
                    <label class="config-item mitigation">
                        <input type="checkbox" id="adaptive-timeouts" onchange="updateConfig()">
                        <span>Adaptive Timeouts</span>
                        <small>Dynamic timeout adjustment</small>
                    </label>
                </div>
            </div>
        </div>

        <!-- Test Controls -->
        <div class="test-controls">
            <h3>🧪 Load Testing</h3>
            <div class="button-group">
                <button onclick="runLoadTest('light')" class="btn btn-primary">Light Load</button>
                <button onclick="runLoadTest('moderate')" class="btn btn-secondary">Moderate Load</button>
                <button onclick="runLoadTest('heavy')" class="btn btn-danger">Heavy Load</button>
                <button onclick="stopLoadTest()" class="btn btn-outline">Stop Test</button>
            </div>
            <div id="load-test-status" class="test-status"></div>
        </div>
    </div>

    <script src="/static/app.js"></script>
</body>
</html>
EOF

    # CSS styles
    cat > $PROJECT_DIR/frontend/static/styles.css << 'EOF'
* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

body {
    font-family: 'Google Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    max-height: 100vh;
    overflow-x: hidden;
    color: #333;
}

.header {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    padding: 1rem 0;
    box-shadow: 0 2px 20px rgba(0, 0, 0, 0.1);
    margin-bottom: 2rem;
}

.header-content {
    max-width: 1200px;
    margin: 0 auto;
    padding: 0 2rem;
}

.header h1 {
    color: #1a73e8;
    font-size: 2rem;
    font-weight: 500;
    margin-bottom: 0.5rem;
}

.header p {
    color: #5f6368;
    font-size: 1rem;
}

.container {
    max-width: 1200px;
    margin: 0 auto;
    padding: 0 2rem;
    overflow-y: auto;
    max-height: calc(100vh - 120px);
}

.metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    gap: 1.5rem;
    margin-bottom: 2rem;
}

.metric-card {
    background: white;
    border-radius: 12px;
    padding: 1.5rem;
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
    border: 1px solid #e8eaed;
    transition: all 0.3s ease;
}

.metric-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 30px rgba(0, 0, 0, 0.15);
}

.metric-card h3 {
    color: #5f6368;
    font-size: 0.875rem;
    font-weight: 500;
    margin-bottom: 0.5rem;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

.metric-value {
    font-size: 2rem;
    font-weight: 600;
    color: #1a73e8;
    margin-bottom: 0.25rem;
}

.metric-trend {
    font-size: 0.875rem;
    color: #5f6368;
}

.chart-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1.5rem;
    margin-bottom: 2rem;
    min-height: 380px;
    max-height: 380px;
}

.chart-container {
    background: white;
    border-radius: 12px;
    padding: 1.5rem;
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
    border: 1px solid #e8eaed;
    height: 380px;
    position: relative;
    display: flex;
    flex-direction: column;
}

.chart-container h3 {
    color: #202124;
    font-size: 1.125rem;
    font-weight: 500;
    margin-bottom: 0.75rem;
    flex-shrink: 0;
}

.chart-container canvas {
    flex: 1;
    max-height: 280px !important;
    height: 280px !important;
    width: 100% !important;
    overflow: hidden !important;
}

.config-panel {
    background: white;
    border-radius: 12px;
    padding: 1.5rem;
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
    border: 1px solid #e8eaed;
    margin-bottom: 2rem;
}

.config-panel h3 {
    color: #202124;
    font-size: 1.25rem;
    font-weight: 500;
    margin-bottom: 1.5rem;
}

.config-section {
    margin-bottom: 2rem;
}

.config-section h4 {
    color: #5f6368;
    font-size: 1rem;
    font-weight: 500;
    margin-bottom: 1rem;
}

.config-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 1rem;
}

.config-item {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.75rem;
    border: 1px solid #e8eaed;
    border-radius: 8px;
    background: #f8f9fa;
    transition: all 0.2s ease;
    cursor: pointer;
}

.config-item:hover {
    background: #f1f3f4;
}

.config-item.mitigation {
    background: linear-gradient(135deg, #e8f5e8 0%, #f0f8f0 100%);
    border-color: #34a853;
}

.config-item input[type="checkbox"] {
    width: 16px;
    height: 16px;
    accent-color: #1a73e8;
}

.config-item input[type="range"] {
    flex: 1;
    accent-color: #1a73e8;
}

.config-item span:first-of-type {
    font-weight: 500;
    min-width: 120px;
}

.config-item small {
    color: #5f6368;
    font-size: 0.75rem;
    margin-left: auto;
}

.test-controls {
    background: white;
    border-radius: 12px;
    padding: 1.5rem;
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
    border: 1px solid #e8eaed;
    margin-bottom: 2rem;
}

.test-controls h3 {
    color: #202124;
    font-size: 1.25rem;
    font-weight: 500;
    margin-bottom: 1rem;
}

.button-group {
    display: flex;
    gap: 1rem;
    margin-bottom: 1rem;
}

.btn {
    padding: 0.75rem 1.5rem;
    border: none;
    border-radius: 8px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.2s ease;
    font-size: 0.875rem;
}

.btn-primary {
    background: #1a73e8;
    color: white;
}

.btn-primary:hover {
    background: #1557b0;
}

.btn-secondary {
    background: #fbbc04;
    color: #333;
}

.btn-secondary:hover {
    background: #f9ab00;
}

.btn-danger {
    background: #ea4335;
    color: white;
}

.btn-danger:hover {
    background: #d33b2c;
}

.btn-outline {
    background: transparent;
    color: #1a73e8;
    border: 1px solid #1a73e8;
}

.btn-outline:hover {
    background: #1a73e8;
    color: white;
}

.test-status {
    padding: 0.75rem;
    border-radius: 8px;
    background: #f8f9fa;
    border: 1px solid #e8eaed;
    font-family: 'Courier New', monospace;
    font-size: 0.875rem;
    min-height: 50px;
    color: #5f6368;
}

@media (max-width: 768px) {
    .chart-grid {
        grid-template-columns: 1fr;
        min-height: 320px;
        max-height: 320px;
    }
    
    .chart-container {
        height: 320px;
    }
    
    .chart-container canvas {
        flex: 1;
        max-height: 240px !important;
        height: 240px !important;
    }
    
    .button-group {
        flex-direction: column;
    }
    
    .config-grid {
        grid-template-columns: 1fr;
    }
}

/* Animation for metrics updates */
.metric-value {
    transition: color 0.3s ease;
}

.metric-value.updated {
    color: #34a853;
}

/* Loading states */
.loading {
    position: relative;
}

.loading::after {
    content: '';
    position: absolute;
    top: 50%;
    left: 50%;
    width: 20px;
    height: 20px;
    margin: -10px 0 0 -10px;
    border: 2px solid #f3f3f3;
    border-top: 2px solid #1a73e8;
    border-radius: 50%;
    animation: spin 1s linear infinite;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}
EOF

    # JavaScript application
    cat > $PROJECT_DIR/frontend/static/app.js << 'EOF'
// Long-tail Latency Observatory Frontend
class LatencyObservatory {
    constructor() {
        this.ws = null;
        this.latencyChart = null;
        this.requestChart = null;
        this.loadTestInterval = null;
        this.metrics = {
            timestamps: [],
            p50: [],
            p95: [],
            p99: [],
            requestRate: [],
            errorRate: []
        };
        
        this.init();
    }
    
    init() {
        this.setupWebSocket();
        this.setupCharts();
        this.setupSliderUpdates();
        this.loadConfig();
    }
    
    setupWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws`;
        
        this.ws = new WebSocket(wsUrl);
        
        this.ws.onopen = () => {
            console.log('WebSocket connected');
        };
        
        this.ws.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.updateMetrics(data);
        };
        
        this.ws.onclose = () => {
            console.log('WebSocket disconnected, reconnecting...');
            setTimeout(() => this.setupWebSocket(), 5000);
        };
        
        this.ws.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
    }
    
    setupCharts() {
        // Latency percentiles chart
        const latencyCtx = document.getElementById('latencyChart').getContext('2d');
        this.latencyChart = new Chart(latencyCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'P50',
                        data: [],
                        borderColor: '#34a853',
                        backgroundColor: 'rgba(52, 168, 83, 0.1)',
                        tension: 0.4,
                        fill: false
                    },
                    {
                        label: 'P95',
                        data: [],
                        borderColor: '#fbbc04',
                        backgroundColor: 'rgba(251, 188, 4, 0.1)',
                        tension: 0.4,
                        fill: false
                    },
                    {
                        label: 'P99',
                        data: [],
                        borderColor: '#ea4335',
                        backgroundColor: 'rgba(234, 67, 53, 0.1)',
                        tension: 0.4,
                        fill: false
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                height: 280,
                scales: {
                    x: {
                        type: 'time',
                        time: {
                            displayFormats: {
                                second: 'HH:mm:ss'
                            }
                        },
                        title: {
                            display: true,
                            text: 'Time'
                        }
                    },
                    y: {
                        title: {
                            display: true,
                            text: 'Latency (ms)'
                        },
                        beginAtZero: true
                    }
                },
                plugins: {
                    legend: {
                        position: 'top'
                    }
                }
            }
        });
        
        // Request rate chart
        const requestCtx = document.getElementById('requestChart').getContext('2d');
        this.requestChart = new Chart(requestCtx, {
            type: 'bar',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'Requests/min',
                        data: [],
                        backgroundColor: '#1a73e8'
                    },
                    {
                        label: 'Errors/min',
                        data: [],
                        backgroundColor: '#ea4335'
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                height: 280,
                scales: {
                    x: {
                        title: {
                            display: true,
                            text: 'Time'
                        }
                    },
                    y: {
                        title: {
                            display: true,
                            text: 'Count'
                        },
                        beginAtZero: true
                    }
                }
            }
        });
    }
    
    updateMetrics(data) {
        const now = new Date();
        const recentStats = data.recent_stats;
        const percentiles = recentStats.percentiles;
        
        // Update metric cards
        document.getElementById('p50-metric').textContent = `${Math.round(percentiles.p50)}ms`;
        document.getElementById('p95-metric').textContent = `${Math.round(percentiles.p95)}ms`;
        document.getElementById('p99-metric').textContent = `${Math.round(percentiles.p99)}ms`;
        document.getElementById('total-requests').textContent = data.total_requests;
        
        const errorRate = data.total_requests > 0 ? 
            ((data.error_count / data.total_requests) * 100).toFixed(1) : 0;
        document.getElementById('error-rate').textContent = `${errorRate}% errors`;
        
        // Update charts
        this.updateLatencyChart(now, percentiles);
        this.updateRequestChart(now, recentStats.count, data.error_count);
        
        // Add visual feedback for metric updates
        this.animateMetricUpdate('p50-metric');
        this.animateMetricUpdate('p95-metric');
        this.animateMetricUpdate('p99-metric');
    }
    
    updateLatencyChart(timestamp, percentiles) {
        const maxPoints = 30; // Reduced to prevent infinite growth
        
        // Add new data point
        this.latencyChart.data.labels.push(timestamp);
        this.latencyChart.data.datasets[0].data.push(percentiles.p50);
        this.latencyChart.data.datasets[1].data.push(percentiles.p95);
        this.latencyChart.data.datasets[2].data.push(percentiles.p99);
        
        // Remove old data points
        if (this.latencyChart.data.labels.length > maxPoints) {
            this.latencyChart.data.labels.shift();
            this.latencyChart.data.datasets.forEach(dataset => dataset.data.shift());
        }
        
        this.latencyChart.update('none');
    }
    
    updateRequestChart(timestamp, requestCount, errorCount) {
        const maxPoints = 15; // Reduced to prevent infinite growth
        const timeLabel = timestamp.toLocaleTimeString();
        
        this.requestChart.data.labels.push(timeLabel);
        this.requestChart.data.datasets[0].data.push(requestCount);
        this.requestChart.data.datasets[1].data.push(errorCount);
        
        if (this.requestChart.data.labels.length > maxPoints) {
            this.requestChart.data.labels.shift();
            this.requestChart.data.datasets.forEach(dataset => dataset.data.shift());
        }
        
        this.requestChart.update('none');
    }
    
    animateMetricUpdate(elementId) {
        const element = document.getElementById(elementId);
        element.classList.add('updated');
        setTimeout(() => element.classList.remove('updated'), 500);
    }
    
    setupSliderUpdates() {
        // Setup real-time slider value updates
        const sliders = [
            { id: 'gc-duration', valueId: 'gc-duration-value', suffix: 'ms' },
            { id: 'db-duration', valueId: 'db-duration-value', suffix: 'ms' },
            { id: 'cache-penalty', valueId: 'cache-penalty-value', suffix: 'ms' },
            { id: 'jitter-max', valueId: 'jitter-max-value', suffix: 'ms' }
        ];
        
        sliders.forEach(slider => {
            const element = document.getElementById(slider.id);
            const valueElement = document.getElementById(slider.valueId);
            
            element.addEventListener('input', () => {
                valueElement.textContent = element.value + slider.suffix;
            });
        });
    }
    
    async loadConfig() {
        try {
            const response = await fetch('/api/config');
            const config = await response.json();
            this.applyConfigToUI(config);
        } catch (error) {
            console.error('Failed to load config:', error);
        }
    }
    
    applyConfigToUI(config) {
        // Apply checkbox states
        document.getElementById('gc-pause').checked = config.gc_pause_enabled;
        document.getElementById('db-lock').checked = config.db_lock_enabled;
        document.getElementById('cache-miss').checked = config.cache_miss_enabled;
        document.getElementById('network-jitter').checked = config.network_jitter_enabled;
        
        document.getElementById('load-shedding').checked = config.load_shedding_enabled;
        document.getElementById('request-hedging').checked = config.request_hedging_enabled;
        document.getElementById('circuit-breaker').checked = config.circuit_breaker_enabled;
        document.getElementById('adaptive-timeouts').checked = config.adaptive_timeouts_enabled;
        
        // Apply slider values
        document.getElementById('gc-duration').value = config.gc_pause_duration;
        document.getElementById('db-duration').value = config.db_lock_duration;
        document.getElementById('cache-penalty').value = config.cache_miss_penalty;
        document.getElementById('jitter-max').value = config.network_jitter_max;
        
        // Update value displays
        document.getElementById('gc-duration-value').textContent = config.gc_pause_duration + 'ms';
        document.getElementById('db-duration-value').textContent = config.db_lock_duration + 'ms';
        document.getElementById('cache-penalty-value').textContent = config.cache_miss_penalty + 'ms';
        document.getElementById('jitter-max-value').textContent = config.network_jitter_max + 'ms';
    }
}

// Configuration management
async function updateConfig() {
    const config = {
        gc_pause_enabled: document.getElementById('gc-pause').checked,
        gc_pause_probability: 0.01,
        gc_pause_duration: parseFloat(document.getElementById('gc-duration').value),
        
        db_lock_enabled: document.getElementById('db-lock').checked,
        db_lock_probability: 0.005,
        db_lock_duration: parseFloat(document.getElementById('db-duration').value),
        
        cache_miss_enabled: document.getElementById('cache-miss').checked,
        cache_miss_probability: 0.1,
        cache_miss_penalty: parseFloat(document.getElementById('cache-penalty').value),
        
        network_jitter_enabled: document.getElementById('network-jitter').checked,
        network_jitter_max: parseFloat(document.getElementById('jitter-max').value),
        
        thread_pool_exhaustion: false,
        cpu_throttling: false,
        
        load_shedding_enabled: document.getElementById('load-shedding').checked,
        load_shedding_threshold: 0.8,
        
        request_hedging_enabled: document.getElementById('request-hedging').checked,
        hedging_threshold: 100.0,
        
        circuit_breaker_enabled: document.getElementById('circuit-breaker').checked,
        circuit_breaker_failure_threshold: 5,
        
        adaptive_timeouts_enabled: document.getElementById('adaptive-timeouts').checked
    };
    
    try {
        const response = await fetch('/api/config', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(config)
        });
        
        if (!response.ok) {
            throw new Error('Failed to update configuration');
        }
        
        console.log('Configuration updated successfully');
    } catch (error) {
        console.error('Failed to update config:', error);
    }
}

// Load testing functions
async function runLoadTest(intensity) {
    stopLoadTest(); // Stop any existing test
    
    const statusElement = document.getElementById('load-test-status');
    statusElement.textContent = `Running ${intensity} load test...`;
    statusElement.style.color = '#1a73e8';
    
    const intervals = {
        light: 1000,    // 1 request per second
        moderate: 500,  // 2 requests per second  
        heavy: 200      // 5 requests per second
    };
    
    const interval = intervals[intensity] || 1000;
    
    window.loadTestInterval = setInterval(async () => {
        try {
            const response = await fetch('/api/simulate');
            const result = await response.json();
            
            // Update status with latest result
            const latency = Math.round(result.response_time_ms);
            statusElement.innerHTML = `
                ${intensity} load test running<br>
                Last request: ${latency}ms
                ${result.latency_sources.length > 0 ? '<br>Sources: ' + result.latency_sources.join(', ') : ''}
            `;
            
        } catch (error) {
            console.error('Load test request failed:', error);
        }
    }, interval);
}

function stopLoadTest() {
    if (window.loadTestInterval) {
        clearInterval(window.loadTestInterval);
        window.loadTestInterval = null;
        
        const statusElement = document.getElementById('load-test-status');
        statusElement.textContent = 'Load test stopped';
        statusElement.style.color = '#5f6368';
    }
}

// Initialize the application
let observatory;
document.addEventListener('DOMContentLoaded', () => {
    observatory = new LatencyObservatory();
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
    stopLoadTest();
    if (observatory && observatory.ws) {
        observatory.ws.close();
    }
});
EOF

    print_success "Frontend interface created"
}

create_docker_files() {
    print_step "Creating Docker configuration..."
    
    # Dockerfile
    cat > $PROJECT_DIR/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY backend/app/ ./backend/app/
COPY frontend/ ./frontend/

# Set Python path
ENV PYTHONPATH="/app/backend"

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/api/health || exit 1

# Start application
CMD ["python", "-m", "uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
EOF

    # Docker Compose
    cat > $PROJECT_DIR/docker-compose.yml << 'EOF'
version: '3.8'

services:
  latency-observatory:
    build: .
    ports:
      - "8000:8000"
    environment:
      - PYTHONPATH=/app/backend
    volumes:
      - ./backend/app:/app/backend/app
      - ./frontend:/app/frontend
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF

    print_success "Docker configuration created"
}

create_scripts() {
    print_step "Creating utility scripts..."
    
    # Cleanup script
    cat > $PROJECT_DIR/cleanup.sh << 'EOF'
#!/bin/bash

# Long-tail Latency Observatory Cleanup Script

set -e

PROJECT_NAME="longtail-latency-demo"

echo "🧹 Cleaning up Long-tail Latency Observatory..."

# Stop and remove containers
if command -v docker-compose &> /dev/null; then
    echo "Stopping Docker services..."
    docker-compose down --volumes --remove-orphans 2>/dev/null || true
fi

# Remove Docker images
echo "Removing Docker images..."
docker rmi $(docker images "*latency*" -q) 2>/dev/null || true
docker system prune -f

echo "✅ Cleanup completed successfully!"
echo "Project files are preserved in: $(pwd)"
EOF

    chmod +x $PROJECT_DIR/cleanup.sh
    
    # Test script
    cat > $PROJECT_DIR/test.sh << 'EOF'
#!/bin/bash

# Test script for Long-tail Latency Observatory

set -e

echo "🧪 Testing Long-tail Latency Observatory..."

# Wait for service to be ready
echo "Waiting for service to be ready..."
timeout=60
counter=0

while [ $counter -lt $timeout ]; do
    if curl -s http://localhost:8000/api/health > /dev/null; then
        echo "✅ Service is ready!"
        break
    fi
    sleep 1
    counter=$((counter + 1))
done

if [ $counter -eq $timeout ]; then
    echo "❌ Service failed to start within $timeout seconds"
    exit 1
fi

# Run tests
echo "Running API tests..."

# Test health endpoint
echo "Testing health endpoint..."
curl -s http://localhost:8000/api/health | grep -q "healthy" || (echo "❌ Health check failed" && exit 1)

# Test configuration
echo "Testing configuration endpoint..."
curl -s http://localhost:8000/api/config > /dev/null || (echo "❌ Config endpoint failed" && exit 1)

# Test simulation
echo "Testing request simulation..."
curl -s http://localhost:8000/api/simulate | grep -q "response_time_ms" || (echo "❌ Simulation failed" && exit 1)

# Test metrics
echo "Testing metrics endpoint..."
curl -s http://localhost:8000/api/metrics | grep -q "recent_stats" || (echo "❌ Metrics failed" && exit 1)

echo "✅ All tests passed!"
echo "🌐 Dashboard available at: http://localhost:8000"
EOF

    chmod +x $PROJECT_DIR/test.sh
    
    print_success "Utility scripts created"
}

build_and_run() {
    print_step "Building and starting the application..."
    
    cd $PROJECT_DIR
    
    # Build Docker image
    print_step "Building Docker image..."
    docker-compose build
    
    # Start services
    print_step "Starting services..."
    docker-compose up -d
    
    # Wait for services to be ready
    print_step "Waiting for services to be ready..."
    sleep 10
    
    print_success "Application started successfully!"
}

run_tests() {
    print_step "Running tests..."
    
    cd $PROJECT_DIR
    ./test.sh
    
    print_success "All tests passed!"
}

display_info() {
    print_success "🎉 Long-tail Latency Observatory is ready!"
    echo ""
    echo "📊 Dashboard: http://localhost:8000"
    echo "🔧 API Docs: http://localhost:8000/docs"
    echo ""
    echo "🧪 Available commands:"
    echo "  ./test.sh     - Run functionality tests"
    echo "  ./verify.sh   - Interactive learning guide & demos"
    echo "  ./cleanup.sh  - Stop and cleanup everything"
    echo ""
    echo "📖 Quick Start Learning Path:"
    echo "  1. Run: ./verify.sh (guided tour with demos)"
    echo "  2. Open dashboard: http://localhost:8000"
    echo "  3. Follow the interactive experiments"
    echo "  4. Observe real-time latency patterns"
    echo ""
    echo "🎯 Key Learning Objectives:"
    echo "  • Understand P50 vs P95 vs P99 latency differences"
    echo "  • Experience how latency sources compound in real systems"
    echo "  • Test effectiveness of production mitigation strategies"
    echo "  • Learn observability patterns for tail latency diagnosis"
    echo ""
    echo "🔬 Interactive Experiments Available:"
    echo "  • GC Pause Impact: See 100-500ms spikes"
    echo "  • Database Lock Contention: Experience blocking behavior"
    echo "  • Network Jitter: Observe cumulative latency effects"
    echo "  • Load Shedding: Test circuit breaker patterns"
    echo "  • Request Hedging: Compare mitigation effectiveness"
    echo ""
    echo "💡 Production Insights You'll Gain:"
    echo "  • Why monitoring only P50 latency is dangerous"
    echo "  • How to identify and mitigate tail latency causes"
    echo "  • When to use different mitigation strategies"
    echo "  • Observable patterns that predict system issues"
    echo ""
    echo "🚀 Ready to start? Run: ./verify.sh"
}

create_verification_script() {
    print_step "Creating verification and learning guide..."
    
    # Create the verification script
    cat > $PROJECT_DIR/verify.sh << 'EOF'
#!/bin/bash

# Long-tail Latency Observatory - Verification and Learning Guide
# System Design Interview Roadmap - Issue #105

set -e

PROJECT_NAME="longtail-latency-demo"
PROJECT_DIR=$(pwd)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_insight() {
    echo -e "${MAGENTA}[INSIGHT]${NC} $1"
}

wait_for_service() {
    local max_wait=60
    local counter=0
    
    print_step "Waiting for service to be ready (max ${max_wait}s)..."
    
    while [ $counter -lt $max_wait ]; do
        if curl -s http://localhost:8000/api/health > /dev/null 2>&1; then
            print_success "Service is ready!"
            return 0
        fi
        sleep 1
        counter=$((counter + 1))
        if [ $((counter % 10)) -eq 0 ]; then
            echo -n "⏳ Still waiting... (${counter}s) "
        fi
    done
    
    echo ""
    echo "❌ Service failed to start within $max_wait seconds"
    echo "Check Docker logs with: docker-compose logs"
    return 1
}

verify_endpoints() {
    print_header "API ENDPOINT VERIFICATION"
    
    local endpoints=(
        "/api/health:Health Check"
        "/api/config:Configuration"
        "/api/metrics:Metrics Collection"
        "/api/simulate:Request Simulation"
    )
    
    for endpoint_info in "${endpoints[@]}"; do
        IFS=':' read -r endpoint description <<< "$endpoint_info"
        
        print_step "Testing $description ($endpoint)..."
        
        if response=$(curl -s "http://localhost:8000$endpoint"); then
            if echo "$response" | python3 -m json.tool > /dev/null 2>&1; then
                print_success "$description endpoint working"
            else
                echo "⚠️  $description returned non-JSON response"
            fi
        else
            echo "❌ $description endpoint failed"
            return 1
        fi
    done
    
    print_success "All API endpoints verified!"
}

demonstrate_latency_sources() {
    print_header "LATENCY SOURCES DEMONSTRATION"
    
    print_step "Testing baseline performance..."
    baseline=$(curl -s http://localhost:8000/api/simulate | python3 -c "import sys,json; print(json.load(sys.stdin)['response_time_ms'])")
    print_warning "Baseline latency: ${baseline}ms"
    
    # Enable GC pauses
    print_step "Enabling GC pause simulation..."
    curl -s -X POST http://localhost:8000/api/config \
        -H "Content-Type: application/json" \
        -d '{"gc_pause_enabled": true, "gc_pause_probability": 0.5, "gc_pause_duration": 200}' > /dev/null
    
    print_step "Testing with GC pauses (may take a moment)..."
    for i in {1..5}; do
        response=$(curl -s http://localhost:8000/api/simulate)
        latency=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['response_time_ms'])")
        sources=$(echo "$response" | python3 -c "import sys,json; data=json.load(sys.stdin); print(', '.join(data.get('latency_sources', [])))")
        
        if [ "$sources" != "" ]; then
            print_insight "Request $i: ${latency}ms (Sources: $sources)"
        else
            print_warning "Request $i: ${latency}ms (No latency sources)"
        fi
    done
    
    # Reset configuration
    curl -s -X POST http://localhost:8000/api/config \
        -H "Content-Type: application/json" \
        -d '{"gc_pause_enabled": false}' > /dev/null
    
    print_success "Latency sources demonstration completed!"
}

interactive_learning_guide() {
    print_header "INTERACTIVE LEARNING GUIDE"
    
    echo "🎓 Welcome to the Long-tail Latency Observatory!"
    echo ""
    echo "This demo teaches critical concepts about latency in distributed systems:"
    echo ""
    echo "1. 📊 DASHBOARD ACCESS:"
    echo "   • Open: http://localhost:8000"
    echo "   • Real-time latency percentile charts"
    echo "   • Live system metrics and configuration"
    echo ""
    echo "2. 🧪 EXPERIMENTS TO TRY:"
    echo "   • Enable 'GC Pauses' and watch P99 latency spike"
    echo "   • Turn on 'DB Lock Contention' to see blocking effects"
    echo "   • Test 'Load Shedding' under heavy load"
    echo "   • Compare 'Request Hedging' effectiveness"
    echo ""
    echo "3. 🎯 KEY INSIGHTS TO DISCOVER:"
    print_insight "P50 vs P99: Why averages lie about user experience"
    print_insight "Latency Sources: How multiple causes compound"
    print_insight "Mitigation Trade-offs: Performance vs complexity"
    print_insight "System Behavior: How tail latency affects scaling"
    echo ""
    echo "4. 🔬 ADVANCED EXPERIMENTS:"
    echo "   • Run concurrent load tests with different intensities"
    echo "   • Observe circuit breaker state transitions"
    echo "   • Monitor system resource correlation with latency"
    echo "   • Test combinations of multiple latency sources"
    echo ""
    echo "5. 📚 PRODUCTION RELEVANCE:"
    print_insight "Real systems exhibit these exact patterns"
    print_insight "P99 latency often drives user satisfaction more than P50"
    print_insight "Mitigation strategies must be chosen based on workload"
    print_insight "Observability is crucial for diagnosing tail latency"
    echo ""
}

main() {
    echo "🔍 Long-tail Latency Observatory - Verification Guide"
    echo "===================================================="
    echo ""
    
    # Check if service is running
    if ! curl -s http://localhost:8000/api/health > /dev/null 2>&1; then
        echo "⚠️  Service doesn't appear to be running."
        echo "Start it first with: docker-compose up -d"
        echo "Or run the main demo script: ./demo.sh"
        exit 1
    fi
    
    wait_for_service || exit 1
    verify_endpoints || exit 1
    demonstrate_latency_sources
    interactive_learning_guide
    
    print_success "🎉 System verification completed successfully!"
    echo ""
    echo "📊 Dashboard ready at: http://localhost:8000"
    echo "🧪 Run './test.sh' for additional tests"
    echo "🧹 Run './cleanup.sh' when finished"
}

# Run main function
main "$@"
EOF

    chmod +x $PROJECT_DIR/verify.sh
    
    print_success "Verification script created"
}

main() {
    echo "🚀 Setting up Long-tail Latency Observatory Demo"
    echo "=================================================="
    
    check_dependencies
    create_project_structure
    create_backend_files
    create_frontend_files
    create_docker_files
    create_scripts
    create_verification_script
    build_and_run
    run_tests
    display_info
}

# Handle cleanup on exit
cleanup_on_exit() {
    if [ $? -ne 0 ]; then
        print_error "Setup failed!"
        echo "Check the logs above for details."
        echo "You can try running the setup again or check Docker logs:"
        echo "  docker-compose logs"
    fi
}

trap cleanup_on_exit EXIT

# Run main function
main