#!/bin/bash

# Seasonal Traffic Scaling Demo Setup Script
# Creates a complete demonstration environment for traffic scaling patterns

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Function to check dependencies
check_dependencies() {
    print_status "Checking dependencies..."
    
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is required but not installed. Please install Docker and try again."
        exit 1
    fi
    
    # Check for Python 3.11+
    if command -v python3 &> /dev/null; then
        python_version=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1-2)
        if [[ $(echo "$python_version >= 3.11" | bc -l 2>/dev/null || echo "0") -eq 1 ]] || python3 -c "import sys; exit(0 if sys.version_info >= (3,11) else 1)" 2>/dev/null; then
            print_success "Python 3.11+ found"
        else
            print_warning "Python 3.11+ recommended. Current version: $(python3 --version)"
        fi
    else
        print_warning "Python 3 not found. Using Docker-based setup."
    fi
    
    # Check for curl
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed."
        exit 1
    fi
}

# Create project structure
create_project_structure() {
    print_status "Creating project structure..."
    
    # Create main directories
    mkdir -p seasonal-traffic-demo/{src,static,templates,tests,docker,logs,data}
    cd seasonal-traffic-demo
    
    print_success "Project structure created"
}

# Create Python application files
create_application_files() {
    print_status "Creating application files..."
    
    # Create requirements.txt
    cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
python-multipart==0.0.6
jinja2==3.1.2
websockets==12.0
numpy==1.24.4
pandas==2.1.3
redis==5.0.1
prometheus-client==0.19.0
asyncio==3.4.3
aiofiles==23.2.0
httpx==0.25.2
pydantic==2.5.0
structlog==23.2.0
tenacity==8.2.3
psutil==5.9.6
scikit-learn==1.3.2
scipy==1.11.4
EOF

    # Create main application
    cat > src/app.py << 'EOF'
"""
Seasonal Traffic Scaling Demo Application
Demonstrates predictive auto-scaling, queue management, and circuit breaker patterns
"""

import asyncio
import json
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional
import uvicorn
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
import numpy as np
from dataclasses import dataclass, asdict
import os
import threading
import queue
import random

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class SystemMetrics:
    timestamp: float
    current_rps: int
    active_instances: int
    queue_size: int
    success_rate: float
    prediction: int
    circuit_breaker_state: str

@dataclass
class TrafficPattern:
    name: str
    duration_seconds: int
    peak_rps: int
    pattern_type: str  # 'gradual', 'spike', 'seasonal'

class PredictiveAutoScaler:
    """Implements predictive auto-scaling based on historical patterns"""
    
    def __init__(self):
        self.historical_data = []
        self.min_instances = 3
        self.max_instances = 20
        self.target_rps_per_instance = 200
        self.scale_up_threshold = 0.8
        self.scale_down_threshold = 0.3
        
    def add_data_point(self, rps: int, timestamp: float):
        """Add historical data point for learning"""
        self.historical_data.append((timestamp, rps))
        # Keep only last 1000 points
        if len(self.historical_data) > 1000:
            self.historical_data.pop(0)
    
    def predict_next_rps(self, current_rps: int) -> int:
        """Predict next RPS based on patterns"""
        if len(self.historical_data) < 10:
            return current_rps
        
        # Simple trend analysis
        recent_data = [rps for _, rps in self.historical_data[-10:]]
        trend = np.mean(np.diff(recent_data)) if len(recent_data) > 1 else 0
        
        # Apply seasonal multiplier based on time of day
        hour = datetime.now().hour
        seasonal_multiplier = 1.0
        if 9 <= hour <= 17:  # Business hours
            seasonal_multiplier = 1.2
        elif 19 <= hour <= 22:  # Evening peak
            seasonal_multiplier = 1.5
        
        prediction = int(current_rps + trend * 5) * seasonal_multiplier
        return max(0, prediction)
    
    def calculate_target_instances(self, predicted_rps: int) -> int:
        """Calculate optimal number of instances"""
        if predicted_rps == 0:
            return self.min_instances
        
        target = max(
            self.min_instances,
            min(self.max_instances, int(predicted_rps / self.target_rps_per_instance) + 1)
        )
        return target

class QueueManager:
    """Manages request queuing and prioritization"""
    
    def __init__(self):
        self.queue = queue.PriorityQueue()
        self.max_queue_size = 1000
        self.processing_rate = 100  # requests per second
        
    def add_request(self, priority: int, request_id: str) -> bool:
        """Add request to queue with priority (lower number = higher priority)"""
        if self.queue.qsize() >= self.max_queue_size:
            return False
        
        self.queue.put((priority, time.time(), request_id))
        return True
    
    def process_requests(self, capacity: int) -> int:
        """Process requests based on available capacity"""
        processed = 0
        target_process = min(capacity, self.queue.qsize())
        
        for _ in range(target_process):
            if not self.queue.empty():
                self.queue.get()
                processed += 1
        
        return processed

class CircuitBreaker:
    """Implements circuit breaker pattern for system protection"""
    
    def __init__(self):
        self.state = "closed"  # closed, open, half-open
        self.failure_count = 0
        self.success_count = 0
        self.failure_threshold = 5
        self.success_threshold = 3
        self.timeout = 30  # seconds
        self.last_failure_time = 0
        
    def call_success(self):
        """Record successful operation"""
        if self.state == "half-open":
            self.success_count += 1
            if self.success_count >= self.success_threshold:
                self.state = "closed"
                self.failure_count = 0
                self.success_count = 0
        else:
            self.failure_count = max(0, self.failure_count - 1)
    
    def call_failure(self):
        """Record failed operation"""
        self.failure_count += 1
        self.last_failure_time = time.time()
        
        if self.failure_count >= self.failure_threshold:
            self.state = "open"
    
    def can_execute(self) -> bool:
        """Check if operation can be executed"""
        if self.state == "closed":
            return True
        elif self.state == "open":
            if time.time() - self.last_failure_time > self.timeout:
                self.state = "half-open"
                self.success_count = 0
                return True
            return False
        else:  # half-open
            return True

class TrafficScalingSystem:
    """Main system coordinating all components"""
    
    def __init__(self):
        self.autoscaler = PredictiveAutoScaler()
        self.queue_manager = QueueManager()
        self.circuit_breaker = CircuitBreaker()
        
        # System state
        self.current_rps = 0
        self.active_instances = 3
        self.success_rate = 100.0
        self.connected_clients = set()
        
        # Simulation state
        self.simulation_running = False
        self.simulation_thread = None
        
    async def handle_request(self) -> bool:
        """Handle incoming request with all protection mechanisms"""
        if not self.circuit_breaker.can_execute():
            return False
        
        # Try to add to queue
        priority = random.randint(1, 3)  # 1=high, 2=medium, 3=low
        request_id = f"req_{int(time.time() * 1000)}"
        
        if not self.queue_manager.add_request(priority, request_id):
            self.circuit_breaker.call_failure()
            return False
        
        # Process based on capacity
        capacity = self.active_instances * 200
        processed = self.queue_manager.process_requests(capacity)
        
        if processed > 0:
            self.circuit_breaker.call_success()
            return True
        else:
            self.circuit_breaker.call_failure()
            return False
    
    def update_metrics(self):
        """Update system metrics and auto-scaling decisions"""
        # Add current data to autoscaler
        self.autoscaler.add_data_point(self.current_rps, time.time())
        
        # Predict future load
        predicted_rps = self.autoscaler.predict_next_rps(self.current_rps)
        target_instances = self.autoscaler.calculate_target_instances(predicted_rps)
        
        # Update instances (simulate scaling delay)
        if target_instances != self.active_instances:
            self.active_instances = target_instances
        
        # Update success rate based on system load
        capacity = self.active_instances * 200
        queue_size = self.queue_manager.queue.qsize()
        
        if self.current_rps > capacity:
            load_factor = self.current_rps / capacity
            self.success_rate = max(20, 100 - (load_factor - 1) * 50)
        else:
            self.success_rate = min(100, self.success_rate + 2)
        
        return SystemMetrics(
            timestamp=time.time(),
            current_rps=self.current_rps,
            active_instances=self.active_instances,
            queue_size=queue_size,
            success_rate=self.success_rate,
            prediction=predicted_rps,
            circuit_breaker_state=self.circuit_breaker.state
        )

# Global system instance
scaling_system = TrafficScalingSystem()

# FastAPI application
app = FastAPI(title="Seasonal Traffic Scaling Demo")

# Mount static files
app.mount("/static", StaticFiles(directory="static"), name="static")

@app.get("/")
async def read_root():
    """Serve the main demo page"""
    with open("index.html", "r") as f:
        html_content = f.read()
    return HTMLResponse(content=html_content)

@app.get("/api/metrics")
async def get_metrics():
    """Get current system metrics"""
    metrics = scaling_system.update_metrics()
    return asdict(metrics)

@app.post("/api/simulate/{scenario}")
async def start_simulation(scenario: str):
    """Start traffic simulation scenario"""
    scenarios = {
        "black_friday": TrafficPattern("Black Friday", 180, 1000, "gradual"),
        "super_bowl": TrafficPattern("Super Bowl", 60, 1500, "spike"),
        "christmas": TrafficPattern("Christmas Rush", 200, 800, "seasonal"),
        "failure": TrafficPattern("System Failure", 30, 0, "failure")
    }
    
    if scenario not in scenarios:
        return {"error": "Unknown scenario"}
    
    pattern = scenarios[scenario]
    
    # Start simulation in background
    if not scaling_system.simulation_running:
        scaling_system.simulation_running = True
        scaling_system.simulation_thread = threading.Thread(
            target=run_simulation, 
            args=(pattern,)
        )
        scaling_system.simulation_thread.start()
    
    return {"status": "started", "scenario": scenario}

@app.post("/api/reset")
async def reset_system():
    """Reset system to baseline"""
    scaling_system.simulation_running = False
    scaling_system.current_rps = 0
    scaling_system.active_instances = 3
    scaling_system.success_rate = 100.0
    scaling_system.circuit_breaker = CircuitBreaker()
    scaling_system.queue_manager = QueueManager()
    
    return {"status": "reset"}

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates"""
    await websocket.accept()
    scaling_system.connected_clients.add(websocket)
    
    try:
        while True:
            metrics = scaling_system.update_metrics()
            await websocket.send_text(json.dumps(asdict(metrics)))
            await asyncio.sleep(1)
    except WebSocketDisconnect:
        scaling_system.connected_clients.remove(websocket)

def run_simulation(pattern: TrafficPattern):
    """Run traffic simulation based on pattern"""
    steps = pattern.duration_seconds
    step_duration = 1.0  # 1 second per step
    
    for step in range(steps):
        if not scaling_system.simulation_running:
            break
        
        if pattern.pattern_type == "gradual":
            # Gradual increase to peak, then gradual decrease
            if step < steps // 3:
                rps = int((pattern.peak_rps * step) / (steps // 3))
            elif step < (2 * steps) // 3:
                rps = pattern.peak_rps + random.randint(-50, 50)
            else:
                remaining_steps = steps - step
                rps = int((pattern.peak_rps * remaining_steps) / (steps // 3))
                
        elif pattern.pattern_type == "spike":
            # Quick spike then quick decline
            if step < 10:
                rps = int((pattern.peak_rps * step) / 10)
            elif step < 20:
                rps = pattern.peak_rps + random.randint(-100, 100)
            else:
                rps = max(0, pattern.peak_rps - (step - 20) * 50)
                
        elif pattern.pattern_type == "seasonal":
            # Wave pattern with spikes
            base = pattern.peak_rps * 0.3
            wave = (pattern.peak_rps * 0.5) * (1 + np.sin(step / 10))
            spike = 200 if 40 < step < 60 else 0
            rps = int(base + wave + spike + random.randint(-30, 30))
            
        elif pattern.pattern_type == "failure":
            # Simulate system failure
            scaling_system.active_instances = max(1, scaling_system.active_instances // 2)
            scaling_system.success_rate = 30
            time.sleep(step_duration)
            continue
        
        scaling_system.current_rps = max(0, rps)
        time.sleep(step_duration)
    
    scaling_system.simulation_running = False

if __name__ == "__main__":
    print("Starting Seasonal Traffic Scaling Demo...")
    print("Demo will be available at: http://localhost:8000")
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    # Create test file
    cat > tests/test_scaling.py << 'EOF'
"""
Tests for seasonal traffic scaling components
"""

import pytest
import asyncio
import time
from src.app import (
    PredictiveAutoScaler, 
    QueueManager, 
    CircuitBreaker, 
    TrafficScalingSystem,
    TrafficPattern
)

def test_predictive_autoscaler():
    """Test predictive auto-scaling logic"""
    scaler = PredictiveAutoScaler()
    
    # Test with no historical data
    prediction = scaler.predict_next_rps(100)
    assert prediction >= 0
    
    # Add some historical data
    base_time = time.time()
    for i in range(20):
        scaler.add_data_point(100 + i * 5, base_time + i)
    
    # Test prediction with trend
    prediction = scaler.predict_next_rps(200)
    assert prediction > 200  # Should predict upward trend
    
    # Test instance calculation
    instances = scaler.calculate_target_instances(600)
    assert instances >= scaler.min_instances
    assert instances <= scaler.max_instances

def test_queue_manager():
    """Test queue management functionality"""
    queue_mgr = QueueManager()
    
    # Test adding requests
    assert queue_mgr.add_request(1, "req1") == True
    assert queue_mgr.add_request(2, "req2") == True
    
    # Test queue processing
    processed = queue_mgr.process_requests(100)
    assert processed >= 0

def test_circuit_breaker():
    """Test circuit breaker state transitions"""
    cb = CircuitBreaker()
    
    # Test initial state
    assert cb.state == "closed"
    assert cb.can_execute() == True
    
    # Test failure threshold
    for i in range(cb.failure_threshold + 1):
        cb.call_failure()
    
    assert cb.state == "open"
    assert cb.can_execute() == False
    
    # Test recovery after timeout
    cb.last_failure_time = time.time() - cb.timeout - 1
    assert cb.can_execute() == True
    assert cb.state == "half-open"

def test_traffic_scaling_system():
    """Test integrated scaling system"""
    system = TrafficScalingSystem()
    
    # Test initial state
    assert system.active_instances == 3
    assert system.success_rate == 100.0
    
    # Test metrics update
    metrics = system.update_metrics()
    assert metrics.active_instances >= 3
    assert 0 <= metrics.success_rate <= 100

@pytest.mark.asyncio
async def test_request_handling():
    """Test request handling with protection mechanisms"""
    system = TrafficScalingSystem()
    
    # Test successful request
    result = await system.handle_request()
    assert isinstance(result, bool)

def test_traffic_patterns():
    """Test traffic pattern definitions"""
    pattern = TrafficPattern("Test", 60, 500, "spike")
    
    assert pattern.name == "Test"
    assert pattern.duration_seconds == 60
    assert pattern.peak_rps == 500
    assert pattern.pattern_type == "spike"

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
EOF

    print_success "Application files created"
}

# Create Docker configuration
create_docker_config() {
    print_status "Creating Docker configuration..."
    
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

# Copy application files
COPY . .

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/api/metrics || exit 1

# Run application
CMD ["python", "src/app.py"]
EOF

    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  scaling-demo:
    build: .
    ports:
      - "8000:8000"
    environment:
      - PYTHONPATH=/app
    volumes:
      - ./logs:/app/logs
      - ./data:/app/data
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/api/metrics"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    depends_on:
      - scaling-demo

volumes:
  prometheus_data:
EOF

    cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'scaling-demo'
    static_configs:
      - targets: ['scaling-demo:8000']
    metrics_path: '/metrics'
    scrape_interval: 5s
EOF

    print_success "Docker configuration created"
}

# Create the HTML file (copy from the artifact)
create_html_file() {
    print_status "Creating HTML interface..."
    
    # The HTML content will be copied from the artifact
    # For now, create a simple version
    cat > index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Seasonal Traffic Scaling Demo</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }
        .metrics { display: grid; grid-template-columns: repeat(4, 1fr); gap: 20px; margin: 20px 0; }
        .metric { padding: 20px; background: #f5f5f5; border-radius: 8px; text-align: center; }
        .controls { margin: 20px 0; }
        .btn { padding: 10px 20px; margin: 5px; border: none; border-radius: 4px; cursor: pointer; }
        .btn-primary { background: #007bff; color: white; }
        .btn-danger { background: #dc3545; color: white; }
        .log { background: #000; color: #0f0; padding: 20px; height: 300px; overflow-y: scroll; font-family: monospace; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Seasonal Traffic Scaling Demo</h1>
        
        <div class="metrics">
            <div class="metric">
                <h3 id="rps">0</h3>
                <p>Requests/Second</p>
            </div>
            <div class="metric">
                <h3 id="instances">3</h3>
                <p>Active Instances</p>
            </div>
            <div class="metric">
                <h3 id="queue">0</h3>
                <p>Queue Size</p>
            </div>
            <div class="metric">
                <h3 id="success">100%</h3>
                <p>Success Rate</p>
            </div>
        </div>
        
        <div class="controls">
            <button class="btn btn-primary" onclick="simulate('black_friday')">Black Friday</button>
            <button class="btn btn-primary" onclick="simulate('super_bowl')">Super Bowl</button>
            <button class="btn btn-primary" onclick="simulate('christmas')">Christmas Rush</button>
            <button class="btn btn-danger" onclick="simulate('failure')">System Failure</button>
            <button class="btn" onclick="reset()">Reset</button>
        </div>
        
        <div class="log" id="log"></div>
    </div>
    
    <script>
        const log = document.getElementById('log');
        
        function addLog(message) {
            const time = new Date().toLocaleTimeString();
            log.innerHTML += `[${time}] ${message}\n`;
            log.scrollTop = log.scrollHeight;
        }
        
        function updateMetrics(data) {
            document.getElementById('rps').textContent = data.current_rps;
            document.getElementById('instances').textContent = data.active_instances;
            document.getElementById('queue').textContent = data.queue_size;
            document.getElementById('success').textContent = data.success_rate.toFixed(1) + '%';
        }
        
        function simulate(scenario) {
            fetch(`/api/simulate/${scenario}`, { method: 'POST' })
                .then(r => r.json())
                .then(data => addLog(`Started ${scenario} simulation`));
        }
        
        function reset() {
            fetch('/api/reset', { method: 'POST' })
                .then(r => r.json())
                .then(data => addLog('System reset'));
        }
        
        // Connect to WebSocket for real-time updates
        const ws = new WebSocket(`ws://${window.location.host}/ws`);
        ws.onmessage = function(event) {
            const data = JSON.parse(event.data);
            updateMetrics(data);
        };
        
        // Poll for metrics if WebSocket fails
        setInterval(() => {
            fetch('/api/metrics')
                .then(r => r.json())
                .then(data => updateMetrics(data))
                .catch(console.error);
        }, 2000);
        
        addLog('Demo initialized');
    </script>
</body>
</html>
EOF

    print_success "HTML interface created"
}

# Build and run the demo
build_and_run() {
    print_status "Building and running the demo..."
    
    # Build Docker image
    docker build -t seasonal-traffic-demo .
    
    # Run the application
    print_status "Starting the application..."
    docker-compose up -d
    
    # Wait for service to be ready
    print_status "Waiting for service to start..."
    sleep 10
    
    # Check if service is running
    if curl -f http://localhost:8000/api/metrics &>/dev/null; then
        print_success "Demo is running successfully!"
        print_success "Access the demo at: http://localhost:8000"
        print_success "Prometheus metrics at: http://localhost:9090"
    else
        print_error "Failed to start the demo. Check logs with: docker-compose logs"
        exit 1
    fi
}

# Run tests
run_tests() {
    print_status "Running tests..."
    
    # Run tests in Docker container
    docker run --rm -v $(pwd):/app -w /app seasonal-traffic-demo python -m pytest tests/ -v
    
    if [ $? -eq 0 ]; then
        print_success "All tests passed!"
    else
        print_warning "Some tests failed, but demo should still work"
    fi
}

# Show usage information
show_usage() {
    echo "Seasonal Traffic Scaling Demo"
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  setup     - Set up the complete demo environment"
    echo "  build     - Build the Docker images"
    echo "  run       - Start the demo"
    echo "  test      - Run tests"
    echo "  stop      - Stop the demo"
    echo "  logs      - Show application logs"
    echo "  clean     - Clean up everything"
    echo ""
    echo "Access points after running:"
    echo "  Demo: http://localhost:8000"
    echo "  Metrics: http://localhost:9090"
}

# Main execution
case "${1:-setup}" in
    "setup")
        check_dependencies
        create_project_structure
        create_application_files
        create_docker_config
        create_html_file
        build_and_run
        run_tests
        ;;
    "build")
        docker build -t seasonal-traffic-demo .
        ;;
    "run")
        docker-compose up -d
        ;;
    "test")
        run_tests
        ;;
    "stop")
        docker-compose down
        ;;
    "logs")
        docker-compose logs -f
        ;;
    "clean")
        docker-compose down -v
        docker rmi seasonal-traffic-demo 2>/dev/null || true
        cd ..
        rm -rf seasonal-traffic-demo
        print_success "Cleanup completed"
        ;;
    *)
        show_usage
        ;;
esac