#!/bin/bash

# Chaos Engineering Demo - One-Click Setup Script
# Creates a complete chaos engineering platform with microservices

set -e

echo "🚀 Setting up Chaos Engineering Demo Platform..."

# Create project directory structure
mkdir -p chaos-engineering-demo/{src,templates,static,docker,logs,config}
cd chaos-engineering-demo

echo "📁 Creating project structure..."

# Create requirements.txt with latest compatible versions
cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
aiohttp==3.9.1
asyncio==3.4.3
psutil==5.9.6
docker==6.1.3
redis==5.0.1
requests==2.31.0
jinja2==3.1.2
python-multipart==0.0.6
websockets==12.0
prometheus-client==0.19.0
asyncio-mqtt==0.16.1
pydantic==2.5.0
numpy==1.24.4
matplotlib==3.8.2
plotly==5.17.0
dash==2.14.2
dash-bootstrap-components==1.5.0
EOF

# Create main chaos engineering application
cat > src/chaos_engine.py << 'EOF'
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
EOF

# Create mock microservices for testing
cat > src/mock_services.py << 'EOF'
"""
Mock Microservices for Chaos Engineering Testing
Simulates a distributed system with multiple services
"""

import asyncio
import random
import time
from fastapi import FastAPI
from typing import Dict
import uvicorn
import logging

logger = logging.getLogger(__name__)

class MockService:
    """Simulates a microservice with realistic behavior"""
    
    def __init__(self, name: str, port: int):
        self.name = name
        self.port = port
        self.app = FastAPI(title=f"Mock {name} Service")
        self.health_status = "healthy"
        self.response_delay = 0
        self.error_rate = 0.0
        
        self.setup_routes()
    
    def setup_routes(self):
        """Setup service endpoints"""
        
        @self.app.get("/health")
        async def health():
            await asyncio.sleep(self.response_delay)
            
            if random.random() < self.error_rate:
                return {"status": "error", "service": self.name}
            
            return {"status": self.health_status, "service": self.name}
        
        @self.app.get("/api/data")
        async def get_data():
            await asyncio.sleep(self.response_delay)
            
            if random.random() < self.error_rate:
                return {"error": "Service unavailable"}
            
            return {
                "service": self.name,
                "data": [{"id": i, "value": random.randint(1, 100)} for i in range(10)],
                "timestamp": time.time()
            }
        
        @self.app.post("/api/process")
        async def process_data(data: dict):
            # Simulate processing time
            processing_time = random.uniform(0.1, 0.5) + self.response_delay
            await asyncio.sleep(processing_time)
            
            if random.random() < self.error_rate:
                return {"error": "Processing failed"}
            
            return {
                "service": self.name,
                "processed": True,
                "input_size": len(str(data)),
                "processing_time": processing_time
            }
    
    def start(self):
        """Start the service"""
        uvicorn.run(self.app, host="0.0.0.0", port=self.port)

# Create mock services
services = [
    MockService("user-service", 8001),
    MockService("order-service", 8002),
    MockService("payment-service", 8003),
    MockService("inventory-service", 8004)
]
EOF

# Create web dashboard template
cat > templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Chaos Engineering Platform</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #ff6b6b, #ee5a24);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .content {
            padding: 30px;
        }
        
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .metric-card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            text-align: center;
            border-left: 4px solid #007bff;
            transition: transform 0.2s;
        }
        
        .metric-card:hover {
            transform: translateY(-2px);
        }
        
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #007bff;
            margin-bottom: 5px;
        }
        
        .metric-label {
            color: #6c757d;
            font-size: 0.9em;
        }
        
        .experiment-section {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
        }
        
        .section-title {
            font-size: 1.5em;
            margin-bottom: 20px;
            color: #333;
        }
        
        .experiment-form {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .form-group {
            display: flex;
            flex-direction: column;
        }
        
        .form-group label {
            margin-bottom: 5px;
            font-weight: 500;
            color: #333;
        }
        
        .form-group input, .form-group select {
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 14px;
        }
        
        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 5px;
            font-size: 16px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.3s;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #007bff, #0056b3);
            color: white;
        }
        
        .btn-primary:hover {
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(0,123,255,0.3);
        }
        
        .btn-danger {
            background: linear-gradient(135deg, #dc3545, #c82333);
            color: white;
        }
        
        .experiment-list {
            display: grid;
            gap: 15px;
        }
        
        .experiment-item {
            background: white;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 15px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        
        .experiment-info {
            flex: 1;
        }
        
        .experiment-title {
            font-weight: 500;
            margin-bottom: 5px;
        }
        
        .experiment-details {
            font-size: 0.9em;
            color: #6c757d;
        }
        
        .status-badge {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.8em;
            font-weight: 500;
            text-transform: uppercase;
        }
        
        .status-ready {
            background: #e3f2fd;
            color: #1976d2;
        }
        
        .status-running {
            background: #fff3e0;
            color: #f57c00;
        }
        
        .status-completed {
            background: #e8f5e8;
            color: #388e3c;
        }
        
        .status-failed {
            background: #ffebee;
            color: #d32f2f;
        }
        
        .live-metrics {
            background: #e8f5e8;
            border-radius: 10px;
            padding: 20px;
            margin-top: 20px;
        }
        
        .loading {
            text-align: center;
            color: #6c757d;
            font-style: italic;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔥 Chaos Engineering Platform</h1>
            <p>Break things systematically to build antifragile systems</p>
        </div>
        
        <div class="content">
            <!-- System Metrics -->
            <div class="metrics-grid">
                <div class="metric-card">
                    <div class="metric-value" id="cpu-usage">--</div>
                    <div class="metric-label">CPU Usage (%)</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value" id="memory-usage">--</div>
                    <div class="metric-label">Memory Usage (%)</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value" id="active-failures">0</div>
                    <div class="metric-label">Active Failures</div>
                </div>
                <div class="metric-card">
                    <div class="metric-value" id="experiment-count">0</div>
                    <div class="metric-label">Total Experiments</div>
                </div>
            </div>
            
            <!-- Create Experiment -->
            <div class="experiment-section">
                <h2 class="section-title">🧪 Create Chaos Experiment</h2>
                <form id="experiment-form" class="experiment-form">
                    <div class="form-group">
                        <label for="experiment-name">Experiment Name</label>
                        <input type="text" id="experiment-name" required>
                    </div>
                    <div class="form-group">
                        <label for="target-service">Target Service</label>
                        <select id="target-service" required>
                            <option value="user-service">User Service</option>
                            <option value="order-service">Order Service</option>
                            <option value="payment-service">Payment Service</option>
                            <option value="inventory-service">Inventory Service</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="failure-type">Failure Type</label>
                        <select id="failure-type" required>
                            <option value="latency">Network Latency</option>
                            <option value="cpu_load">CPU Load</option>
                            <option value="memory_pressure">Memory Pressure</option>
                            <option value="network_partition">Network Partition</option>
                        </select>
                    </div>
                    <div class="form-group">
                        <label for="intensity">Intensity (0.1 - 1.0)</label>
                        <input type="number" id="intensity" step="0.1" min="0.1" max="1.0" value="0.5" required>
                    </div>
                    <div class="form-group">
                        <label for="duration">Duration (seconds)</label>
                        <input type="number" id="duration" min="10" max="300" value="30" required>
                    </div>
                    <div class="form-group">
                        <button type="submit" class="btn btn-primary">Create Experiment</button>
                    </div>
                </form>
            </div>
            
            <!-- Experiment List -->
            <div class="experiment-section">
                <h2 class="section-title">📊 Experiment History</h2>
                <div id="experiment-list" class="experiment-list">
                    <div class="loading">No experiments yet. Create your first chaos experiment above!</div>
                </div>
            </div>
            
            <!-- Live Metrics -->
            <div class="live-metrics">
                <h2 class="section-title">⚡ Live System Monitoring</h2>
                <div id="live-status">Connecting to metrics stream...</div>
            </div>
        </div>
    </div>

    <script>
        // WebSocket connection for real-time metrics
        let ws = null;
        let experiments = [];
        
        function connectWebSocket() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            ws = new WebSocket(`${protocol}//${window.location.host}/ws/metrics`);
            
            ws.onmessage = function(event) {
                const metrics = JSON.parse(event.data);
                updateMetrics(metrics);
            };
            
            ws.onclose = function() {
                setTimeout(connectWebSocket, 3000);
            };
        }
        
        function updateMetrics(metrics) {
            document.getElementById('cpu-usage').textContent = metrics.cpu_usage.toFixed(1);
            document.getElementById('memory-usage').textContent = metrics.memory_usage.toFixed(1);
            document.getElementById('active-failures').textContent = metrics.active_failures;
            
            const status = `CPU: ${metrics.cpu_usage.toFixed(1)}% | Memory: ${metrics.memory_usage.toFixed(1)}% | Active Failures: ${metrics.active_failures}`;
            document.getElementById('live-status').textContent = status;
        }
        
        async function loadExperiments() {
            try {
                const response = await fetch('/api/experiments');
                experiments = await response.json();
                renderExperiments();
            } catch (error) {
                console.error('Failed to load experiments:', error);
            }
        }
        
        function renderExperiments() {
            const container = document.getElementById('experiment-list');
            document.getElementById('experiment-count').textContent = experiments.length;
            
            if (experiments.length === 0) {
                container.innerHTML = '<div class="loading">No experiments yet. Create your first chaos experiment above!</div>';
                return;
            }
            
            container.innerHTML = experiments.map(exp => `
                <div class="experiment-item">
                    <div class="experiment-info">
                        <div class="experiment-title">${exp.name}</div>
                        <div class="experiment-details">
                            Target: ${exp.target_service} | Type: ${exp.failure_type} | 
                            Intensity: ${exp.intensity} | Duration: ${exp.duration}s
                        </div>
                    </div>
                    <div>
                        <span class="status-badge status-${exp.status}">${exp.status}</span>
                        ${exp.status === 'ready' ? `<button class="btn btn-danger" onclick="runExperiment('${exp.id}')" style="margin-left: 10px;">Run</button>` : ''}
                    </div>
                </div>
            `).join('');
        }
        
        async function runExperiment(experimentId) {
            try {
                await fetch(`/api/experiments/${experimentId}/run`, { method: 'POST' });
                setTimeout(loadExperiments, 1000);
            } catch (error) {
                console.error('Failed to run experiment:', error);
                alert('Failed to run experiment');
            }
        }
        
        document.getElementById('experiment-form').addEventListener('submit', async function(e) {
            e.preventDefault();
            
            const formData = {
                name: document.getElementById('experiment-name').value,
                target_service: document.getElementById('target-service').value,
                failure_type: document.getElementById('failure-type').value,
                intensity: parseFloat(document.getElementById('intensity').value),
                duration: parseInt(document.getElementById('duration').value)
            };
            
            try {
                await fetch('/api/experiments', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(formData)
                });
                
                this.reset();
                loadExperiments();
            } catch (error) {
                console.error('Failed to create experiment:', error);
                alert('Failed to create experiment');
            }
        });
        
        // Initialize
        connectWebSocket();
        loadExperiments();
        setInterval(loadExperiments, 5000);
    </script>
</body>
</html>
EOF

# Create Docker configuration
cat > docker/Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies including build tools for psutil
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY templates/ ./templates/
COPY static/ ./static/

# Create directories
RUN mkdir -p logs config

# Set Python path
ENV PYTHONPATH="/app/src:${PYTHONPATH}"

# Expose port
EXPOSE 8000

# Run application
CMD ["python", "src/chaos_engine.py"]
EOF

cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  chaos-platform:
    build:
      context: .
      dockerfile: docker/Dockerfile
    ports:
      - "8000:8000"
    volumes:
      - ./logs:/app/logs
      - ./config:/app/config
    environment:
      - PYTHONPATH=/app/src
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/metrics"]
      interval: 30s
      timeout: 10s
      retries: 3

  user-service:
    build:
      context: .
      dockerfile: docker/Dockerfile
    ports:
      - "8001:8001"
    command: ["python", "-c", "from src.mock_services import MockService; MockService('user-service', 8001).start()"]
    environment:
      - PYTHONPATH=/app/src

  order-service:
    build:
      context: .
      dockerfile: docker/Dockerfile
    ports:
      - "8002:8002"
    command: ["python", "-c", "from src.mock_services import MockService; MockService('order-service', 8002).start()"]
    environment:
      - PYTHONPATH=/app/src

  payment-service:
    build:
      context: .
      dockerfile: docker/Dockerfile
    ports:
      - "8003:8003"
    command: ["python", "-c", "from src.mock_services import MockService; MockService('payment-service', 8003).start()"]
    environment:
      - PYTHONPATH=/app/src

  inventory-service:
    build:
      context: .
      dockerfile: docker/Dockerfile
    ports:
      - "8004:8004"
    command: ["python", "-c", "from src.mock_services import MockService; MockService('inventory-service', 8004).start()"]
    environment:
      - PYTHONPATH=/app/src
EOF

# Create static directory and basic CSS
mkdir -p static
touch static/.gitkeep

# Create test script
cat > test_chaos.py << 'EOF'
#!/usr/bin/env python3
"""
Chaos Engineering Platform Test Suite
Validates all functionality and demonstrates capabilities
"""

import asyncio
import aiohttp
import time
import json
import sys

async def test_chaos_platform():
    """Comprehensive test of chaos engineering platform"""
    
    print("🧪 Testing Chaos Engineering Platform...")
    
    base_url = "http://localhost:8000"
    
    async with aiohttp.ClientSession() as session:
        # Test 1: Check platform health
        print("\n1. Testing platform health...")
        try:
            async with session.get(f"{base_url}/api/metrics") as response:
                if response.status == 200:
                    metrics = await response.json()
                    print(f"✅ Platform healthy - CPU: {metrics['cpu_usage']:.1f}%, Memory: {metrics['memory_usage']:.1f}%")
                else:
                    print(f"❌ Platform health check failed: {response.status}")
                    return False
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            return False
        
        # Test 2: Create experiment
        print("\n2. Creating chaos experiment...")
        experiment_data = {
            "name": "Test CPU Load Injection",
            "target_service": "user-service",
            "failure_type": "cpu_load",
            "intensity": 0.7,
            "duration": 15
        }
        
        try:
            async with session.post(f"{base_url}/api/experiments", 
                                  json=experiment_data) as response:
                if response.status == 200:
                    result = await response.json()
                    experiment_id = result["id"]
                    print(f"✅ Experiment created: {experiment_id}")
                else:
                    print(f"❌ Failed to create experiment: {response.status}")
                    return False
        except Exception as e:
            print(f"❌ Experiment creation failed: {e}")
            return False
        
        # Test 3: Run experiment
        print("\n3. Running chaos experiment...")
        try:
            async with session.post(f"{base_url}/api/experiments/{experiment_id}/run") as response:
                if response.status == 200:
                    print("✅ Experiment started successfully")
                    
                    # Monitor for 20 seconds
                    print("📊 Monitoring system during experiment...")
                    for i in range(10):
                        await asyncio.sleep(2)
                        async with session.get(f"{base_url}/api/metrics") as metrics_response:
                            if metrics_response.status == 200:
                                metrics = await metrics_response.json()
                                print(f"   CPU: {metrics['cpu_usage']:.1f}%, Memory: {metrics['memory_usage']:.1f}%, Active Failures: {metrics['active_failures']}")
                else:
                    print(f"❌ Failed to run experiment: {response.status}")
                    return False
        except Exception as e:
            print(f"❌ Experiment execution failed: {e}")
            return False
        
        # Test 4: Check active failures
        print("\n4. Checking active failures...")
        try:
            async with session.get(f"{base_url}/api/failures") as response:
                if response.status == 200:
                    failures = await response.json()
                    print(f"✅ Active failures retrieved: {len(failures)} active")
                    for service, failure in failures.items():
                        print(f"   - {service}: {failure['type']} (duration: {failure['duration']}s)")
                else:
                    print(f"❌ Failed to get failures: {response.status}")
        except Exception as e:
            print(f"❌ Failures check failed: {e}")
        
        # Test 5: Verify mock services
        print("\n5. Testing mock services...")
        mock_services = [
            ("user-service", 8001),
            ("order-service", 8002),
            ("payment-service", 8003),
            ("inventory-service", 8004)
        ]
        
        for service_name, port in mock_services:
            try:
                async with session.get(f"http://localhost:{port}/health") as response:
                    if response.status == 200:
                        health = await response.json()
                        print(f"✅ {service_name} is healthy: {health['status']}")
                    else:
                        print(f"⚠️  {service_name} returned status: {response.status}")
            except Exception as e:
                print(f"❌ {service_name} unreachable: {e}")
    
    print("\n🎉 Chaos Engineering Platform test completed!")
    return True

def run_tests():
    """Run all tests"""
    return asyncio.run(test_chaos_platform())

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
EOF

chmod +x test_chaos.py

# Create comprehensive README
cat > README.md << 'EOF'
# Chaos Engineering Platform Demo

A complete chaos engineering platform for testing distributed system resilience.

## Quick Start

1. **Build and Start:**
   ```bash
   docker-compose up --build -d
   ```

2. **Access Dashboard:**
   Open http://localhost:8000 in your browser

3. **Run Tests:**
   ```bash
   python test_chaos.py
   ```

## Features

- **Multiple Failure Types:** Latency injection, CPU load, memory pressure, network partitions
- **Real-time Monitoring:** Live system metrics and failure tracking
- **Mock Services:** Simulated microservices for testing
- **Web Interface:** Interactive dashboard for experiment management

## Experiment Types

1. **Latency Injection:** Add network delays to service communications
2. **CPU Load:** Simulate high CPU usage scenarios
3. **Memory Pressure:** Test memory exhaustion handling
4. **Network Partitions:** Simulate network connectivity failures

## Usage Examples

### Create CPU Load Experiment
- Target: user-service
- Type: cpu_load
- Intensity: 0.8 (80% CPU)
- Duration: 30 seconds

### Monitor Results
Watch real-time metrics during experiments to observe:
- System resource impact
- Service degradation patterns
- Recovery behavior

## Architecture

```
Chaos Platform (8000) → Orchestrates experiments
├── User Service (8001)
├── Order Service (8002)
├── Payment Service (8003)
└── Inventory Service (8004)
```

## Testing Commands

```bash
# Test experiment creation
curl -X POST http://localhost:8000/api/experiments \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","target_service":"user-service","failure_type":"latency","intensity":0.5,"duration":20}'

# Check system metrics
curl http://localhost:8000/api/metrics

# View active failures
curl http://localhost:8000/api/failures
```
EOF

echo "✅ Chaos Engineering Demo created successfully!"
echo ""
echo "🚀 To start the demo:"
echo "   docker-compose up --build -d"
echo ""
echo "🌐 Access the dashboard:"
echo "   http://localhost:8000"
echo ""
echo "🧪 Run tests:"
echo "   python test_chaos.py"
echo ""
echo "📊 The platform includes:"
echo "   - Interactive chaos engineering dashboard"
echo "   - Multiple failure injection types"
echo "   - Real-time system monitoring"
echo "   - Mock microservices for testing"
echo "   - Comprehensive test suite"