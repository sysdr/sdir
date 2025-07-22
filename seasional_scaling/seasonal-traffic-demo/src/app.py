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
