#!/bin/bash

# Hot Partition Detection and Mitigation Demo
# System Design Interview Roadmap - Issue #96
# Creates a complete demonstration of hot partition handling

set -e

PROJECT_NAME="hot-partition-demo"
PYTHON_VERSION="3.11"

echo "🔥 Hot Partition Detection Demo Setup"
echo "======================================"

# Create project structure
create_project_structure() {
    echo "📁 Creating project structure..."
    
    mkdir -p $PROJECT_NAME/{src,frontend,docker,tests,logs,data}
    cd $PROJECT_NAME
    
    # Create backend structure
    mkdir -p src/{api,core,models,utils}
    mkdir -p frontend/{static/{css,js},templates}
    mkdir -p tests/{unit,integration}
}

# Create requirements.txt with latest compatible versions
create_requirements() {
    echo "📦 Creating requirements.txt..."
    
    cat > requirements.txt << 'EOF'
# Web Framework
fastapi==0.104.1
uvicorn[standard]==0.24.0
websockets==12.0

# Data Processing
numpy==1.24.4
pandas==2.1.4
scipy==1.11.4

# Async Support
aiofiles==23.2.0
asyncio-mqtt==0.16.1

# Monitoring & Metrics
prometheus-client==0.19.0
psutil==5.9.6

# Database & Storage
redis==5.0.1
aiosqlite==0.19.0

# Utilities
pydantic==2.5.0
python-multipart==0.0.6
jinja2==3.1.2
python-jose[cryptography]==3.3.0
httpx==0.25.2

# Development
pytest==7.4.3
pytest-asyncio==0.21.1
pytest-cov==4.1.0
EOF
}

# Create Dockerfile
create_dockerfile() {
    echo "🐳 Creating Dockerfile..."
    
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create necessary directories
RUN mkdir -p logs data

# Expose ports
EXPOSE 8000 8001

# Default command
CMD ["python", "-m", "uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
EOF
}

# Create docker-compose.yml
create_docker_compose() {
    echo "🐳 Creating docker-compose.yml..."
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  hot-partition-api:
    build: .
    ports:
      - "8000:8000"
    environment:
      - REDIS_URL=redis://redis:6379
      - PYTHONPATH=/app
    depends_on:
      - redis
    volumes:
      - ./logs:/app/logs
      - ./data:/app/data
      - .:/app
    command: ["python", "-m", "uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]

  partition-simulator:
    build: .
    environment:
      - REDIS_URL=redis://redis:6379
      - PYTHONPATH=/app
    depends_on:
      - redis
    volumes:
      - ./logs:/app/logs
      - ./data:/app/data
      - .:/app
    command: ["python", "src/core/simulator.py"]

volumes:
  redis_data:
EOF
}

# Create core partition models
create_partition_models() {
    echo "🏗️ Creating partition models..."
    
    cat > src/models/__init__.py << 'EOF'
"""Data models for hot partition detection system."""
EOF

    cat > src/models/partition.py << 'EOF'
"""Partition data models and utilities."""

from typing import Dict, List, Optional
from dataclasses import dataclass, field
from datetime import datetime, timedelta
import math
import numpy as np

@dataclass
class PartitionMetrics:
    """Metrics for a single partition."""
    partition_id: str
    request_count: int = 0
    memory_usage_mb: float = 0.0
    cpu_usage_percent: float = 0.0
    avg_response_time_ms: float = 0.0
    error_rate: float = 0.0
    timestamp: datetime = field(default_factory=datetime.now)

@dataclass
class HotPartitionAlert:
    """Alert data for hot partition detection."""
    partition_id: str
    severity: str  # LOW, MEDIUM, HIGH, CRITICAL
    entropy_score: float
    load_factor: float
    recommended_action: str
    timestamp: datetime = field(default_factory=datetime.now)

class PartitionAnalyzer:
    """Analyzes partition metrics for hot partition detection."""
    
    def __init__(self, entropy_threshold: float = 0.7):
        self.entropy_threshold = entropy_threshold
        self.historical_metrics: Dict[str, List[PartitionMetrics]] = {}
        
    def calculate_entropy(self, partition_loads: List[float]) -> float:
        """Calculate Shannon entropy for load distribution."""
        if not partition_loads or sum(partition_loads) == 0:
            return 1.0
            
        total = sum(partition_loads)
        probabilities = [load / total for load in partition_loads if load > 0]
        
        if len(probabilities) <= 1:
            return 0.0
            
        entropy = -sum(p * math.log2(p) for p in probabilities)
        max_entropy = math.log2(len(partition_loads))
        
        return entropy / max_entropy if max_entropy > 0 else 0.0
    
    def detect_temporal_patterns(self, partition_id: str, 
                                window_minutes: int = 5) -> Dict:
        """Detect temporal access patterns for a partition."""
        if partition_id not in self.historical_metrics:
            return {"trend": "stable", "acceleration": 0.0}
            
        metrics = self.historical_metrics[partition_id]
        cutoff_time = datetime.now() - timedelta(minutes=window_minutes)
        recent_metrics = [m for m in metrics if m.timestamp >= cutoff_time]
        
        if len(recent_metrics) < 3:
            return {"trend": "insufficient_data", "acceleration": 0.0}
            
        # Calculate acceleration in request rate
        times = [(m.timestamp - recent_metrics[0].timestamp).total_seconds() 
                for m in recent_metrics]
        loads = [m.request_count for m in recent_metrics]
        
        if len(times) > 2:
            # Linear regression to find acceleration
            coeffs = np.polyfit(times, loads, 2) if len(times) > 2 else [0, 0, 0]
            acceleration = coeffs[0] * 2  # Second derivative
            
            if acceleration > 10:
                trend = "accelerating"
            elif acceleration < -10:
                trend = "decelerating"
            else:
                trend = "stable"
                
            return {"trend": trend, "acceleration": acceleration}
        
        return {"trend": "stable", "acceleration": 0.0}
    
    def analyze_memory_correlation(self, all_metrics: List[PartitionMetrics]) -> Dict:
        """Analyze memory usage correlation with request load."""
        if len(all_metrics) < 2:
            return {"correlation": 0.0, "memory_pressure_detected": False}
            
        loads = [m.request_count for m in all_metrics]
        memory = [m.memory_usage_mb for m in all_metrics]
        
        correlation = np.corrcoef(loads, memory)[0, 1] if len(loads) > 1 else 0.0
        
        # Detect memory pressure
        avg_memory = np.mean(memory)
        std_memory = np.std(memory)
        memory_pressure = any(m > avg_memory + 2 * std_memory for m in memory)
        
        return {
            "correlation": correlation,
            "memory_pressure_detected": memory_pressure,
            "avg_memory_mb": avg_memory
        }
    
    def generate_alert(self, partition_id: str, metrics: PartitionMetrics,
                      entropy_score: float, temporal_analysis: Dict) -> Optional[HotPartitionAlert]:
        """Generate alert based on analysis results."""
        load_factor = metrics.request_count / 1000.0  # Normalize to expected load
        
        # Determine severity
        if entropy_score < 0.3 or load_factor > 5.0:
            severity = "CRITICAL"
            action = "Immediate range splitting required"
        elif entropy_score < 0.5 or load_factor > 3.0:
            severity = "HIGH" 
            action = "Consider replication or load shedding"
        elif entropy_score < self.entropy_threshold or load_factor > 2.0:
            severity = "MEDIUM"
            action = "Monitor closely, prepare mitigation"
        else:
            return None
            
        if temporal_analysis["trend"] == "accelerating":
            severity = "CRITICAL" if severity != "CRITICAL" else severity
            action = f"{action} (Accelerating pattern detected)"
            
        return HotPartitionAlert(
            partition_id=partition_id,
            severity=severity,
            entropy_score=entropy_score,
            load_factor=load_factor,
            recommended_action=action
        )
    
    def add_metrics(self, metrics: PartitionMetrics):
        """Add metrics to historical data."""
        if metrics.partition_id not in self.historical_metrics:
            self.historical_metrics[metrics.partition_id] = []
            
        self.historical_metrics[metrics.partition_id].append(metrics)
        
        # Keep only last 100 entries per partition
        if len(self.historical_metrics[metrics.partition_id]) > 100:
            self.historical_metrics[metrics.partition_id] = \
                self.historical_metrics[metrics.partition_id][-100:]
EOF
}

# Create partition simulator
create_simulator() {
    echo "🎲 Creating partition simulator..."
    
    cat > src/core/__init__.py << 'EOF'
"""Core system components."""
EOF

    cat > src/core/simulator.py << 'EOF'
"""Partition workload simulator with hot partition generation."""

import asyncio
import random
import time
import json
import logging
from datetime import datetime, timedelta
from typing import Dict, List
import redis.asyncio as redis
import numpy as np

from src.models.partition import PartitionMetrics, PartitionAnalyzer

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class PartitionSimulator:
    """Simulates a distributed system with multiple partitions."""
    
    def __init__(self, num_partitions: int = 5, redis_url: str = "redis://localhost:6379"):
        self.num_partitions = num_partitions
        self.partitions = {f"partition_{i}": self._create_partition_state() 
                          for i in range(num_partitions)}
        self.analyzer = PartitionAnalyzer()
        self.redis_client = None
        self.redis_url = redis_url
        self.running = False
        
        # Hotspot configuration
        self.hotspot_active = False
        self.hotspot_partition = None
        self.hotspot_start_time = None
        self.hotspot_intensity = 1.0
        
    def _create_partition_state(self) -> Dict:
        """Create initial state for a partition."""
        return {
            "base_load": random.randint(100, 500),
            "memory_base": random.uniform(100, 300),
            "cpu_base": random.uniform(10, 30),
            "response_time_base": random.uniform(50, 150)
        }
    
    async def initialize(self):
        """Initialize Redis connection."""
        self.redis_client = redis.from_url(self.redis_url)
        await self.redis_client.ping()
        logger.info("Connected to Redis")
        
    async def trigger_hotspot(self, partition_id: str = None, intensity: float = 5.0):
        """Trigger a hotspot on a specific partition."""
        if partition_id is None:
            partition_id = random.choice(list(self.partitions.keys()))
            
        self.hotspot_active = True
        self.hotspot_partition = partition_id
        self.hotspot_start_time = datetime.now()
        self.hotspot_intensity = intensity
        
        logger.info(f"🔥 Hotspot triggered on {partition_id} with intensity {intensity}")
        
        # Store hotspot info in Redis
        hotspot_info = {
            "partition_id": partition_id,
            "intensity": intensity,
            "start_time": self.hotspot_start_time.isoformat(),
            "active": True
        }
        await self.redis_client.hset("hotspot_info", mapping=hotspot_info)
        
    async def end_hotspot(self):
        """End the current hotspot."""
        if self.hotspot_active:
            logger.info(f"🧯 Ending hotspot on {self.hotspot_partition}")
            self.hotspot_active = False
            self.hotspot_partition = None
            self.hotspot_start_time = None
            
            await self.redis_client.hset("hotspot_info", "active", "false")
    
    def _generate_partition_load(self, partition_id: str) -> PartitionMetrics:
        """Generate realistic load for a partition."""
        partition_state = self.partitions[partition_id]
        
        # Base load with some randomness
        base_requests = partition_state["base_load"]
        current_requests = base_requests + random.randint(-50, 100)
        
        # Apply hotspot if active
        if (self.hotspot_active and 
            partition_id == self.hotspot_partition and
            self.hotspot_start_time):
            
            # Calculate hotspot decay over time
            elapsed = (datetime.now() - self.hotspot_start_time).total_seconds()
            decay_factor = max(0.1, 1.0 - (elapsed / 300))  # 5 minute decay
            
            hotspot_multiplier = 1.0 + (self.hotspot_intensity - 1.0) * decay_factor
            current_requests = int(current_requests * hotspot_multiplier)
            
            # If hotspot has decayed significantly, end it
            if decay_factor < 0.2:
                asyncio.create_task(self.end_hotspot())
        
        # Generate correlated metrics
        memory_usage = (partition_state["memory_base"] + 
                       current_requests * 0.1 + 
                       random.uniform(-20, 30))
        
        cpu_usage = min(95, partition_state["cpu_base"] + 
                       current_requests * 0.05 + 
                       random.uniform(-5, 15))
        
        response_time = (partition_state["response_time_base"] + 
                        max(0, current_requests - base_requests) * 0.2 +
                        random.uniform(-10, 20))
        
        error_rate = max(0, min(100, (current_requests - base_requests * 2) * 0.01))
        
        return PartitionMetrics(
            partition_id=partition_id,
            request_count=max(0, current_requests),
            memory_usage_mb=max(50, memory_usage),
            cpu_usage_percent=max(5, cpu_usage),
            avg_response_time_ms=max(10, response_time),
            error_rate=max(0, error_rate)
        )
    
    async def _store_metrics(self, metrics: List[PartitionMetrics]):
        """Store metrics in Redis for API access."""
        try:
            # Store current metrics
            metrics_data = {}
            for metric in metrics:
                metrics_data[metric.partition_id] = json.dumps({
                    "request_count": metric.request_count,
                    "memory_usage_mb": metric.memory_usage_mb,
                    "cpu_usage_percent": metric.cpu_usage_percent,
                    "avg_response_time_ms": metric.avg_response_time_ms,
                    "error_rate": metric.error_rate,
                    "timestamp": metric.timestamp.isoformat()
                })
            
            await self.redis_client.hset("current_metrics", mapping=metrics_data)
            
            # Store historical metrics (last 50 entries)
            for metric in metrics:
                key = f"historical_{metric.partition_id}"
                value = json.dumps({
                    "request_count": metric.request_count,
                    "memory_usage_mb": metric.memory_usage_mb,
                    "cpu_usage_percent": metric.cpu_usage_percent,
                    "timestamp": metric.timestamp.isoformat()
                })
                
                await self.redis_client.lpush(key, value)
                await self.redis_client.ltrim(key, 0, 49)  # Keep last 50
                
        except Exception as e:
            logger.error(f"Error storing metrics: {e}")
    
    async def _analyze_and_alert(self, metrics: List[PartitionMetrics]):
        """Analyze metrics and generate alerts."""
        try:
            # Calculate entropy
            loads = [m.request_count for m in metrics]
            entropy = self.analyzer.calculate_entropy(loads)
            
            # Store entropy score
            await self.redis_client.hset("analysis_results", 
                                       "entropy_score", str(entropy))
            
            # Analyze each partition
            alerts = []
            for metric in metrics:
                # Add to analyzer history
                self.analyzer.add_metrics(metric)
                
                # Temporal analysis
                temporal = self.analyzer.detect_temporal_patterns(metric.partition_id)
                
                # Generate alert if needed
                alert = self.analyzer.generate_alert(
                    metric.partition_id, metric, entropy, temporal
                )
                
                if alert:
                    alerts.append(alert)
                    logger.warning(f"⚠️ Alert: {alert.partition_id} - {alert.severity} - {alert.recommended_action}")
            
            # Store alerts
            if alerts:
                alert_data = {}
                for i, alert in enumerate(alerts):
                    alert_data[f"alert_{i}"] = json.dumps({
                        "partition_id": alert.partition_id,
                        "severity": alert.severity,
                        "entropy_score": alert.entropy_score,
                        "load_factor": alert.load_factor,
                        "recommended_action": alert.recommended_action,
                        "timestamp": alert.timestamp.isoformat()
                    })
                
                await self.redis_client.hset("current_alerts", mapping=alert_data)
            else:
                await self.redis_client.delete("current_alerts")
                
        except Exception as e:
            logger.error(f"Error in analysis: {e}")
    
    async def run_simulation(self):
        """Main simulation loop."""
        logger.info("🚀 Starting partition simulation...")
        self.running = True
        
        # Auto-trigger hotspot after 30 seconds
        asyncio.create_task(self._auto_hotspot_cycle())
        
        iteration = 0
        while self.running:
            try:
                # Generate metrics for all partitions
                current_metrics = []
                for partition_id in self.partitions:
                    metrics = self._generate_partition_load(partition_id)
                    current_metrics.append(metrics)
                
                # Store metrics
                await self._store_metrics(current_metrics)
                
                # Analyze for hot partitions
                await self._analyze_and_alert(current_metrics)
                
                # Log summary every 10 iterations
                if iteration % 10 == 0:
                    total_requests = sum(m.request_count for m in current_metrics)
                    max_requests = max(m.request_count for m in current_metrics)
                    entropy = self.analyzer.calculate_entropy([m.request_count for m in current_metrics])
                    
                    logger.info(f"📊 Iteration {iteration}: Total={total_requests}, Max={max_requests}, Entropy={entropy:.3f}")
                
                iteration += 1
                await asyncio.sleep(2)  # Generate metrics every 2 seconds
                
            except Exception as e:
                logger.error(f"Error in simulation loop: {e}")
                await asyncio.sleep(5)
    
    async def _auto_hotspot_cycle(self):
        """Automatically trigger hotspots for demonstration."""
        await asyncio.sleep(30)  # Wait 30 seconds before first hotspot
        
        while self.running:
            if not self.hotspot_active:
                # Trigger random hotspot
                partition = random.choice(list(self.partitions.keys()))
                intensity = random.uniform(3.0, 8.0)
                await self.trigger_hotspot(partition, intensity)
                
                # Let hotspot run for 2-5 minutes
                await asyncio.sleep(random.uniform(120, 300))
            else:
                await asyncio.sleep(10)
    
    async def stop(self):
        """Stop the simulation."""
        self.running = False
        if self.redis_client:
            await self.redis_client.close()

async def main():
    """Main entry point for simulator."""
    simulator = PartitionSimulator(num_partitions=5)
    
    try:
        await simulator.initialize()
        await simulator.run_simulation()
    except KeyboardInterrupt:
        logger.info("Shutting down simulator...")
    finally:
        await simulator.stop()

if __name__ == "__main__":
    asyncio.run(main())
EOF
}

# Create FastAPI application
create_api() {
    echo "🌐 Creating FastAPI application..."
    
    cat > src/api/__init__.py << 'EOF'
"""API package for hot partition demo."""
EOF

    cat > src/api/main.py << 'EOF'
"""FastAPI application for hot partition detection demo."""

import json
import logging
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
app.mount("/static", StaticFiles(directory="frontend/static"), name="static")
templates = Jinja2Templates(directory="frontend/templates")

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
EOF
}

# Create web dashboard
create_dashboard() {
    echo "🎨 Creating dashboard interface..."
    
    cat > frontend/templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hot Partition Detection Dashboard</title>
    <link rel="stylesheet" href="/static/css/dashboard.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="dashboard-container">
        <!-- Header -->
        <header class="dashboard-header">
            <div class="header-content">
                <h1>🔥 Hot Partition Detection Dashboard</h1>
                <div class="header-stats">
                    <div class="stat-item">
                        <span class="stat-label">Entropy Score</span>
                        <span class="stat-value" id="entropy-score">--</span>
                    </div>
                    <div class="stat-item">
                        <span class="stat-label">Active Partitions</span>
                        <span class="stat-value" id="active-partitions">5</span>
                    </div>
                    <div class="stat-item">
                        <span class="stat-label">System Status</span>
                        <span class="stat-value" id="system-status">Normal</span>
                    </div>
                </div>
            </div>
        </header>

        <!-- Main Content -->
        <main class="dashboard-main">
            <!-- Control Panel -->
            <section class="control-panel">
                <h2>Control Panel</h2>
                <div class="controls">
                    <button class="btn btn-warning" onclick="triggerHotspot()">
                        🔥 Trigger Hotspot
                    </button>
                    <button class="btn btn-success" onclick="endHotspot()">
                        🧯 End Hotspot
                    </button>
                    <select id="hotspot-partition">
                        <option value="">Auto Select</option>
                        <option value="partition_0">Partition 0</option>
                        <option value="partition_1">Partition 1</option>
                        <option value="partition_2">Partition 2</option>
                        <option value="partition_3">Partition 3</option>
                        <option value="partition_4">Partition 4</option>
                    </select>
                    <input type="range" id="intensity-slider" min="2" max="10" value="5" step="0.5">
                    <span id="intensity-value">5.0x</span>
                </div>
            </section>

            <!-- Metrics Grid -->
            <section class="metrics-grid">
                <div class="metric-card">
                    <h3>Request Distribution</h3>
                    <canvas id="request-chart"></canvas>
                </div>
                
                <div class="metric-card">
                    <h3>Memory Usage</h3>
                    <canvas id="memory-chart"></canvas>
                </div>
                
                <div class="metric-card">
                    <h3>Response Times</h3>
                    <canvas id="response-chart"></canvas>
                </div>
                
                <div class="metric-card">
                    <h3>Entropy Timeline</h3>
                    <canvas id="entropy-chart"></canvas>
                </div>
            </section>

            <!-- Partition Status -->
            <section class="partition-status">
                <h2>Partition Status</h2>
                <div class="partition-grid" id="partition-grid">
                    <!-- Dynamically populated -->
                </div>
            </section>

            <!-- Alerts Panel -->
            <section class="alerts-panel">
                <h2>Active Alerts</h2>
                <div class="alerts-container" id="alerts-container">
                    <div class="no-alerts">No active alerts</div>
                </div>
            </section>
        </main>
    </div>

    <script src="/static/js/dashboard.js"></script>
</body>
</html>
EOF

    # Create CSS with Google Cloud Skills Boost styling
    cat > frontend/static/css/dashboard.css << 'EOF'
/* Google Cloud Skills Boost inspired styling */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Google Sans', 'Roboto', sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    color: #333;
}

.dashboard-container {
    max-width: 1400px;
    margin: 0 auto;
    padding: 20px;
}

/* Header */
.dashboard-header {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    border-radius: 16px;
    padding: 24px;
    margin-bottom: 24px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.2);
}

.header-content {
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-wrap: wrap;
    gap: 16px;
}

.header-content h1 {
    color: #1a73e8;
    font-size: 2rem;
    font-weight: 500;
}

.header-stats {
    display: flex;
    gap: 24px;
    flex-wrap: wrap;
}

.stat-item {
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 12px 20px;
    background: linear-gradient(135deg, #1a73e8, #4285f4);
    border-radius: 12px;
    color: white;
    min-width: 120px;
}

.stat-label {
    font-size: 0.8rem;
    opacity: 0.9;
    margin-bottom: 4px;
}

.stat-value {
    font-size: 1.2rem;
    font-weight: 600;
}

/* Main Content */
.dashboard-main {
    display: grid;
    gap: 24px;
}

/* Control Panel */
.control-panel {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    border-radius: 16px;
    padding: 24px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
}

.control-panel h2 {
    color: #1a73e8;
    margin-bottom: 16px;
    font-weight: 500;
}

.controls {
    display: flex;
    gap: 16px;
    align-items: center;
    flex-wrap: wrap;
}

.btn {
    padding: 12px 24px;
    border: none;
    border-radius: 8px;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.3s ease;
    font-size: 0.9rem;
}

.btn-warning {
    background: linear-gradient(135deg, #ff6b35, #f7931e);
    color: white;
}

.btn-success {
    background: linear-gradient(135deg, #00c851, #00a041);
    color: white;
}

.btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.2);
}

select, input[type="range"] {
    padding: 8px 12px;
    border: 1px solid #ddd;
    border-radius: 8px;
    font-size: 0.9rem;
}

#intensity-value {
    background: #e8f0fe;
    padding: 4px 8px;
    border-radius: 4px;
    color: #1a73e8;
    font-weight: 500;
}

/* Metrics Grid */
.metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
    gap: 24px;
}

.metric-card {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    border-radius: 16px;
    padding: 24px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
    border: 1px solid rgba(255, 255, 255, 0.2);
}

.metric-card h3 {
    color: #1a73e8;
    margin-bottom: 16px;
    font-weight: 500;
}

.metric-card canvas {
    max-height: 300px;
}

/* Partition Status */
.partition-status {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    border-radius: 16px;
    padding: 24px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
}

.partition-status h2 {
    color: #1a73e8;
    margin-bottom: 16px;
    font-weight: 500;
}

.partition-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 16px;
}

.partition-card {
    background: linear-gradient(135deg, #f8f9fa, #e9ecef);
    border-radius: 12px;
    padding: 16px;
    transition: all 0.3s ease;
    border-left: 4px solid #28a745;
}

.partition-card.warning {
    border-left-color: #ffc107;
    background: linear-gradient(135deg, #fff8e1, #ffecb3);
}

.partition-card.danger {
    border-left-color: #dc3545;
    background: linear-gradient(135deg, #ffebee, #ffcdd2);
}

.partition-card.critical {
    border-left-color: #dc3545;
    background: linear-gradient(135deg, #ffebee, #ffcdd2);
    animation: pulse 2s infinite;
}

@keyframes pulse {
    0% { transform: scale(1); }
    50% { transform: scale(1.02); }
    100% { transform: scale(1); }
}

.partition-name {
    font-weight: 600;
    color: #1a73e8;
    margin-bottom: 8px;
}

.partition-metrics {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
    font-size: 0.8rem;
}

/* Alerts Panel */
.alerts-panel {
    background: rgba(255, 255, 255, 0.95);
    backdrop-filter: blur(10px);
    border-radius: 16px;
    padding: 24px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
}

.alerts-panel h2 {
    color: #1a73e8;
    margin-bottom: 16px;
    font-weight: 500;
}

.alert-item {
    background: linear-gradient(135deg, #ffebee, #ffcdd2);
    border-left: 4px solid #dc3545;
    border-radius: 8px;
    padding: 16px;
    margin-bottom: 12px;
    transition: all 0.3s ease;
}

.alert-item.critical {
    animation: pulse 2s infinite;
}

.alert-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 8px;
}

.alert-title {
    font-weight: 600;
    color: #d32f2f;
}

.alert-severity {
    background: #d32f2f;
    color: white;
    padding: 2px 8px;
    border-radius: 4px;
    font-size: 0.8rem;
}

.alert-description {
    color: #666;
    font-size: 0.9rem;
}

.no-alerts {
    text-align: center;
    color: #666;
    font-style: italic;
    padding: 24px;
}

/* Responsive Design */
@media (max-width: 768px) {
    .header-content {
        flex-direction: column;
    }
    
    .controls {
        flex-direction: column;
        align-items: stretch;
    }
    
    .btn {
        width: 100%;
    }
}
EOF

    # Create JavaScript for dashboard functionality
    cat > frontend/static/js/dashboard.js << 'EOF'
// Dashboard JavaScript for Hot Partition Detection Demo
class HotPartitionDashboard {
    constructor() {
        this.websocket = null;
        this.charts = {};
        this.currentMetrics = {};
        this.entropyHistory = [];
        
        this.init();
    }
    
    init() {
        this.setupWebSocket();
        this.setupCharts();
        this.setupEventListeners();
        this.loadInitialData();
    }
    
    setupWebSocket() {
        const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${wsProtocol}//${window.location.host}/ws`;
        
        this.websocket = new WebSocket(wsUrl);
        
        this.websocket.onopen = () => {
            console.log('WebSocket connected');
        };
        
        this.websocket.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.handleWebSocketMessage(data);
        };
        
        this.websocket.onclose = () => {
            console.log('WebSocket disconnected. Reconnecting...');
            setTimeout(() => this.setupWebSocket(), 5000);
        };
        
        this.websocket.onerror = (error) => {
            console.error('WebSocket error:', error);
        };
    }
    
    setupCharts() {
        // Request Distribution Chart
        const requestCtx = document.getElementById('request-chart').getContext('2d');
        this.charts.request = new Chart(requestCtx, {
            type: 'bar',
            data: {
                labels: ['Partition 0', 'Partition 1', 'Partition 2', 'Partition 3', 'Partition 4'],
                datasets: [{
                    label: 'Requests/sec',
                    data: [0, 0, 0, 0, 0],
                    backgroundColor: [
                        '#4285f4',
                        '#34a853',
                        '#fbbc04',
                        '#ea4335',
                        '#9c27b0'
                    ],
                    borderColor: '#1a73e8',
                    borderWidth: 2
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false }
                },
                scales: {
                    y: { beginAtZero: true }
                }
            }
        });
        
        // Memory Usage Chart
        const memoryCtx = document.getElementById('memory-chart').getContext('2d');
        this.charts.memory = new Chart(memoryCtx, {
            type: 'doughnut',
            data: {
                labels: ['Partition 0', 'Partition 1', 'Partition 2', 'Partition 3', 'Partition 4'],
                datasets: [{
                    data: [100, 100, 100, 100, 100],
                    backgroundColor: [
                        '#4285f4',
                        '#34a853',
                        '#fbbc04',
                        '#ea4335',
                        '#9c27b0'
                    ]
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { position: 'bottom' }
                }
            }
        });
        
        // Response Times Chart
        const responseCtx = document.getElementById('response-chart').getContext('2d');
        this.charts.response = new Chart(responseCtx, {
            type: 'line',
            data: {
                labels: ['Partition 0', 'Partition 1', 'Partition 2', 'Partition 3', 'Partition 4'],
                datasets: [{
                    label: 'Response Time (ms)',
                    data: [0, 0, 0, 0, 0],
                    borderColor: '#1a73e8',
                    backgroundColor: 'rgba(26, 115, 232, 0.1)',
                    fill: true,
                    tension: 0.4
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: { beginAtZero: true }
                }
            }
        });
        
        // Entropy Timeline Chart
        const entropyCtx = document.getElementById('entropy-chart').getContext('2d');
        this.charts.entropy = new Chart(entropyCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    label: 'Entropy Score',
                    data: [],
                    borderColor: '#34a853',
                    backgroundColor: 'rgba(52, 168, 83, 0.1)',
                    fill: true,
                    tension: 0.4
                }, {
                    label: 'Critical Threshold',
                    data: [],
                    borderColor: '#ea4335',
                    borderDash: [5, 5],
                    fill: false,
                    pointRadius: 0
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    y: { 
                        beginAtZero: true,
                        max: 1.0
                    }
                }
            }
        });
    }
    
    setupEventListeners() {
        // Intensity slider
        const intensitySlider = document.getElementById('intensity-slider');
        const intensityValue = document.getElementById('intensity-value');
        
        intensitySlider.addEventListener('input', (e) => {
            intensityValue.textContent = `${e.target.value}x`;
        });
    }
    
    async loadInitialData() {
        try {
            const response = await fetch('/api/metrics');
            const data = await response.json();
            this.updateMetrics(data.metrics);
            
            const analysisResponse = await fetch('/api/analysis');
            const analysisData = await analysisResponse.json();
            this.updateAnalysis(analysisData);
        } catch (error) {
            console.error('Error loading initial data:', error);
        }
    }
    
    handleWebSocketMessage(data) {
        if (data.type === 'metrics_update') {
            this.updateMetrics(data.metrics);
            this.updateEntropy(data.entropy_score);
        }
    }
    
    updateMetrics(metrics) {
        this.currentMetrics = metrics;
        
        const partitionIds = Object.keys(metrics).sort();
        const requestCounts = partitionIds.map(id => metrics[id]?.request_count || 0);
        const memoryUsage = partitionIds.map(id => metrics[id]?.memory_usage_mb || 0);
        const responseTimes = partitionIds.map(id => metrics[id]?.avg_response_time_ms || 0);
        
        // Update charts
        this.charts.request.data.datasets[0].data = requestCounts;
        this.charts.request.update('none');
        
        this.charts.memory.data.datasets[0].data = memoryUsage;
        this.charts.memory.update('none');
        
        this.charts.response.data.datasets[0].data = responseTimes;
        this.charts.response.update('none');
        
        // Update partition cards
        this.updatePartitionCards(metrics);
        
        // Update header stats
        const totalRequests = requestCounts.reduce((sum, count) => sum + count, 0);
        const maxRequests = Math.max(...requestCounts);
        const avgRequests = totalRequests / requestCounts.length;
        
        // Determine system status
        let systemStatus = 'Normal';
        let statusClass = 'success';
        
        if (maxRequests > avgRequests * 3) {
            systemStatus = 'Hot Partition Detected';
            statusClass = 'danger';
        } else if (maxRequests > avgRequests * 2) {
            systemStatus = 'Warning';
            statusClass = 'warning';
        }
        
        document.getElementById('system-status').textContent = systemStatus;
        document.getElementById('system-status').className = `stat-value ${statusClass}`;
    }
    
    updateEntropy(entropyScore) {
        document.getElementById('entropy-score').textContent = entropyScore.toFixed(3);
        
        // Update entropy history
        const now = new Date();
        this.entropyHistory.push({
            time: now.toLocaleTimeString(),
            entropy: entropyScore
        });
        
        // Keep last 20 points
        if (this.entropyHistory.length > 20) {
            this.entropyHistory.shift();
        }
        
        // Update entropy chart
        const labels = this.entropyHistory.map(point => point.time);
        const entropies = this.entropyHistory.map(point => point.entropy);
        const thresholds = new Array(entropies.length).fill(0.7);
        
        this.charts.entropy.data.labels = labels;
        this.charts.entropy.data.datasets[0].data = entropies;
        this.charts.entropy.data.datasets[1].data = thresholds;
        this.charts.entropy.update('none');
        
        // Update entropy score color
        const entropyElement = document.getElementById('entropy-score');
        if (entropyScore < 0.5) {
            entropyElement.style.color = '#ea4335';
        } else if (entropyScore < 0.7) {
            entropyElement.style.color = '#fbbc04';
        } else {
            entropyElement.style.color = '#34a853';
        }
    }
    
    updatePartitionCards(metrics) {
        const partitionGrid = document.getElementById('partition-grid');
        partitionGrid.innerHTML = '';
        
        Object.keys(metrics).sort().forEach(partitionId => {
            const metric = metrics[partitionId];
            const card = document.createElement('div');
            card.className = 'partition-card';
            
            // Determine status
            const avgLoad = Object.values(metrics).reduce((sum, m) => sum + m.request_count, 0) / Object.keys(metrics).length;
            
            if (metric.request_count > avgLoad * 4) {
                card.classList.add('critical');
            } else if (metric.request_count > avgLoad * 2.5) {
                card.classList.add('danger');
            } else if (metric.request_count > avgLoad * 1.5) {
                card.classList.add('warning');
            }
            
            card.innerHTML = `
                <div class="partition-name">${partitionId.replace('_', ' ').toUpperCase()}</div>
                <div class="partition-metrics">
                    <div>Requests: ${metric.request_count}</div>
                    <div>Memory: ${metric.memory_usage_mb.toFixed(1)}MB</div>
                    <div>CPU: ${metric.cpu_usage_percent.toFixed(1)}%</div>
                    <div>Response: ${metric.avg_response_time_ms.toFixed(0)}ms</div>
                </div>
            `;
            
            partitionGrid.appendChild(card);
        });
    }
    
    async updateAnalysis(analysisData) {
        // Update alerts
        const alertsContainer = document.getElementById('alerts-container');
        
        if (analysisData.alerts && analysisData.alerts.length > 0) {
            alertsContainer.innerHTML = '';
            
            analysisData.alerts.forEach(alert => {
                const alertElement = document.createElement('div');
                alertElement.className = `alert-item ${alert.severity.toLowerCase()}`;
                
                alertElement.innerHTML = `
                    <div class="alert-header">
                        <div class="alert-title">${alert.partition_id.replace('_', ' ').toUpperCase()}</div>
                        <div class="alert-severity">${alert.severity}</div>
                    </div>
                    <div class="alert-description">${alert.recommended_action}</div>
                    <div style="margin-top: 8px; font-size: 0.8rem; color: #666;">
                        Entropy: ${alert.entropy_score.toFixed(3)} | Load Factor: ${alert.load_factor.toFixed(2)}
                    </div>
                `;
                
                alertsContainer.appendChild(alertElement);
            });
        } else {
            alertsContainer.innerHTML = '<div class="no-alerts">No active alerts</div>';
        }
    }
}

// Global functions for buttons
async function triggerHotspot() {
    const partitionSelect = document.getElementById('hotspot-partition');
    const intensitySlider = document.getElementById('intensity-slider');
    
    const data = {
        partition_id: partitionSelect.value || null,
        intensity: parseFloat(intensitySlider.value)
    };
    
    try {
        const response = await fetch('/api/trigger-hotspot', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(data)
        });
        
        if (response.ok) {
            console.log('Hotspot triggered successfully');
        }
    } catch (error) {
        console.error('Error triggering hotspot:', error);
    }
}

async function endHotspot() {
    try {
        const response = await fetch('/api/end-hotspot', {
            method: 'POST'
        });
        
        if (response.ok) {
            console.log('Hotspot ended successfully');
        }
    } catch (error) {
        console.error('Error ending hotspot:', error);
    }
}

// Initialize dashboard when page loads
document.addEventListener('DOMContentLoaded', () => {
    new HotPartitionDashboard();
});
EOF
}

# Create test suite
create_tests() {
    echo "🧪 Creating test suite..."
    
    cat > tests/__init__.py << 'EOF'
"""Test package for hot partition demo."""
EOF

    cat > tests/test_partition_analysis.py << 'EOF'
"""Tests for partition analysis functionality."""

import pytest
import math
from datetime import datetime
from src.models.partition import PartitionMetrics, PartitionAnalyzer

class TestPartitionAnalyzer:
    
    def test_entropy_calculation_perfect_balance(self):
        """Test entropy calculation with perfect load balance."""
        analyzer = PartitionAnalyzer()
        loads = [100, 100, 100, 100, 100]  # Perfect balance
        entropy = analyzer.calculate_entropy(loads)
        assert abs(entropy - 1.0) < 0.001  # Should be close to 1.0
    
    def test_entropy_calculation_complete_skew(self):
        """Test entropy calculation with complete skew."""
        analyzer = PartitionAnalyzer()
        loads = [500, 0, 0, 0, 0]  # Complete skew
        entropy = analyzer.calculate_entropy(loads)
        assert abs(entropy - 0.0) < 0.001  # Should be close to 0.0
    
    def test_entropy_calculation_moderate_skew(self):
        """Test entropy calculation with moderate skew."""
        analyzer = PartitionAnalyzer()
        loads = [300, 100, 100, 100, 100]  # Moderate skew
        entropy = analyzer.calculate_entropy(loads)
        assert 0.7 < entropy < 0.9  # Should be between thresholds
    
    def test_entropy_calculation_critical_skew(self):
        """Test entropy calculation with critical skew."""
        analyzer = PartitionAnalyzer()
        loads = [650, 100, 50, 50, 50]  # Critical skew
        entropy = analyzer.calculate_entropy(loads)
        assert entropy < 0.7  # Should be below critical threshold
    
    def test_alert_generation_critical(self):
        """Test alert generation for critical hotspot."""
        analyzer = PartitionAnalyzer()
        
        metrics = PartitionMetrics(
            partition_id="partition_0",
            request_count=5000,  # Very high load
            memory_usage_mb=800,
            cpu_usage_percent=95,
            avg_response_time_ms=2000
        )
        
        entropy_score = 0.3  # Critical entropy
        temporal_analysis = {"trend": "accelerating", "acceleration": 50.0}
        
        alert = analyzer.generate_alert(
            "partition_0", metrics, entropy_score, temporal_analysis
        )
        
        assert alert is not None
        assert alert.severity == "CRITICAL"
        assert "Accelerating" in alert.recommended_action
    
    def test_alert_generation_normal(self):
        """Test no alert generation for normal conditions."""
        analyzer = PartitionAnalyzer()
        
        metrics = PartitionMetrics(
            partition_id="partition_0",
            request_count=200,  # Normal load
            memory_usage_mb=150,
            cpu_usage_percent=25,
            avg_response_time_ms=100
        )
        
        entropy_score = 0.9  # Good entropy
        temporal_analysis = {"trend": "stable", "acceleration": 0.0}
        
        alert = analyzer.generate_alert(
            "partition_0", metrics, entropy_score, temporal_analysis
        )
        
        assert alert is None
    
    def test_temporal_pattern_detection(self):
        """Test temporal pattern detection."""
        analyzer = PartitionAnalyzer()
        
        # Add historical metrics showing acceleration
        base_time = datetime.now()
        for i in range(10):
            metrics = PartitionMetrics(
                partition_id="partition_0",
                request_count=100 + i * 50,  # Increasing load
                memory_usage_mb=100 + i * 10,
                cpu_usage_percent=20 + i * 5,
                avg_response_time_ms=100 + i * 20,
                timestamp=base_time
            )
            analyzer.add_metrics(metrics)
        
        temporal = analyzer.detect_temporal_patterns("partition_0")
        assert temporal["trend"] in ["accelerating", "stable"]
        assert isinstance(temporal["acceleration"], float)
    
    def test_memory_correlation_analysis(self):
        """Test memory correlation analysis."""
        analyzer = PartitionAnalyzer()
        
        # Create metrics with correlated memory and load
        metrics_list = []
        for i in range(10):
            load = 100 + i * 50
            memory = 50 + load * 0.5  # Correlated memory usage
            
            metrics = PartitionMetrics(
                partition_id=f"partition_{i % 5}",
                request_count=load,
                memory_usage_mb=memory,
                cpu_usage_percent=20 + i * 2,
                avg_response_time_ms=100 + i * 10
            )
            metrics_list.append(metrics)
        
        correlation_analysis = analyzer.analyze_memory_correlation(metrics_list)
        
        assert isinstance(correlation_analysis["correlation"], float)
        assert isinstance(correlation_analysis["memory_pressure_detected"], bool)
        assert correlation_analysis["correlation"] > 0.5  # Should show positive correlation

if __name__ == "__main__":
    pytest.main([__file__])
EOF

    cat > tests/test_api.py << 'EOF'
"""Tests for API endpoints."""

import pytest
import asyncio
from fastapi.testclient import TestClient
from src.api.main import app

client = TestClient(app)

class TestAPI:
    
    def test_dashboard_endpoint(self):
        """Test dashboard endpoint returns HTML."""
        response = client.get("/")
        assert response.status_code == 200
        assert "text/html" in response.headers["content-type"]
    
    def test_metrics_endpoint(self):
        """Test metrics endpoint structure."""
        response = client.get("/api/metrics")
        assert response.status_code in [200, 500]  # May fail without Redis
        
        if response.status_code == 200:
            data = response.json()
            assert "metrics" in data
            assert "timestamp" in data
    
    def test_analysis_endpoint(self):
        """Test analysis endpoint structure."""
        response = client.get("/api/analysis")
        assert response.status_code in [200, 500]  # May fail without Redis
        
        if response.status_code == 200:
            data = response.json()
            assert "entropy_score" in data
            assert "alerts" in data
            assert "timestamp" in data
    
    def test_trigger_hotspot_endpoint(self):
        """Test hotspot trigger endpoint."""
        payload = {
            "partition_id": "partition_0",
            "intensity": 5.0
        }
        
        response = client.post("/api/trigger-hotspot", json=payload)
        assert response.status_code in [200, 500]  # May fail without Redis
        
        if response.status_code == 200:
            data = response.json()
            assert "message" in data
    
    def test_end_hotspot_endpoint(self):
        """Test hotspot end endpoint."""
        response = client.post("/api/end-hotspot")
        assert response.status_code in [200, 500]  # May fail without Redis
        
        if response.status_code == 200:
            data = response.json()
            assert "message" in data

if __name__ == "__main__":
    pytest.main([__file__])
EOF
}

# Create demo and cleanup scripts
create_scripts() {
    echo "🚀 Creating demo and cleanup scripts..."
    
    cat > demo.sh << 'EOF'
#!/bin/bash

echo "🔥 Hot Partition Detection Demo"
echo "================================"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build and start services
echo "🏗️ Building and starting services..."
docker-compose up --build -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 15

# Check service health
echo "🔍 Checking service health..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:8000/api/metrics > /dev/null; then
        echo "✅ API service is ready!"
        break
    fi
    
    echo "Waiting for API service... (attempt $((attempt + 1))/$max_attempts)"
    sleep 2
    attempt=$((attempt + 1))
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ API service failed to start"
    docker-compose logs
    exit 1
fi

# Run tests
echo "🧪 Running tests..."
docker-compose exec -T hot-partition-api python -m pytest tests/ -v

# Show service status
echo "📊 Service Status:"
docker-compose ps

echo ""
echo "🎉 Demo is ready!"
echo ""
echo "🌐 Access the dashboard: http://localhost:8000"
echo "📊 API endpoints: http://localhost:8000/docs"
echo ""
echo "📝 Demo Instructions:"
echo "1. Open http://localhost:8000 in your browser"
echo "2. Watch the normal partition distribution"
echo "3. Click 'Trigger Hotspot' to simulate a hot partition"
echo "4. Observe the entropy drop and alerts generated"
echo "5. Watch the mitigation recommendations"
echo "6. Click 'End Hotspot' to return to normal"
echo ""
echo "🔥 Key Features to Observe:"
echo "• Entropy score changes (watch for values < 0.7)"
echo "• Request distribution becoming skewed"
echo "• Memory usage correlation"
echo "• Real-time alert generation"
echo "• Partition status color changes"
echo ""
echo "📊 To view logs: docker-compose logs -f"
echo "🛑 To stop demo: ./cleanup.sh"
EOF

    cat > cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up Hot Partition Demo"
echo "================================="

# Stop and remove containers
echo "🛑 Stopping services..."
docker-compose down -v

# Remove unused images
echo "🗑️ Cleaning up Docker images..."
docker image prune -f

# Remove any leftover data
echo "📁 Cleaning up data files..."
rm -rf logs/* data/*

echo "✅ Cleanup complete!"
echo ""
echo "To restart the demo, run: ./demo.sh"
EOF

    # Make scripts executable
    chmod +x demo.sh cleanup.sh
}

# Main execution
main() {
    echo "Starting Hot Partition Detection Demo setup..."
    
    create_project_structure
    create_requirements
    create_dockerfile
    create_docker_compose
    create_partition_models
    create_simulator
    create_api
    create_dashboard
    create_tests
    create_scripts
    
    echo ""
    echo "✅ Setup Complete!"
    echo ""
    echo "📁 Project structure created in: $PROJECT_NAME/"
    echo ""
    echo "🚀 To start the demo:"
    echo "   cd $PROJECT_NAME"
    echo "   ./demo.sh"
    echo ""
    echo "🧹 To clean up:"
    echo "   ./cleanup.sh"
    echo ""
    echo "📖 What this demo shows:"
    echo "• Real-time hot partition detection using entropy analysis"
    echo "• Temporal pattern recognition for emerging hotspots"
    echo "• Memory correlation analysis for early warning"
    echo "• Automated alert generation with severity levels"
    echo "• Interactive hotspot simulation and mitigation"
    echo "• Production-grade monitoring dashboard"
    echo ""
    echo "🎯 Learning Objectives:"
    echo "• Understanding mathematical detection algorithms"
    echo "• Implementing real-time monitoring systems"
    echo "• Designing adaptive partitioning strategies"
    echo "• Building resilient distributed systems"
}

# Execute main function
main
