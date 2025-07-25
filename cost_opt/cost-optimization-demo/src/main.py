import asyncio
import json
import time
import random
from datetime import datetime, timedelta
from typing import Dict, List, Optional
from fastapi import FastAPI, WebSocket, Request
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
import psutil
import numpy as np
from pydantic import BaseModel

app = FastAPI(title="Cost Optimization Dashboard", version="1.0.0")

# Mount static files and templates
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Data models
class ResourceMetrics(BaseModel):
    timestamp: float
    cpu_usage: float
    memory_usage: float
    network_io: float
    disk_io: float
    estimated_cost: float

class OptimizationRecommendation(BaseModel):
    type: str
    description: str
    potential_savings: float
    implementation_effort: str

class CostTracker:
    def __init__(self):
        self.metrics_history = []
        self.cost_per_hour = {
            'cpu': 0.05,  # $0.05 per CPU hour
            'memory': 0.01,  # $0.01 per GB hour
            'network': 0.09,  # $0.09 per GB
            'storage': 0.023  # $0.023 per GB hour
        }
        self.optimization_rules = [
            {"threshold": 0.3, "message": "CPU usage below 30% - consider downsizing", "savings": 15.0},
            {"threshold": 0.5, "message": "Memory usage below 50% - optimize memory allocation", "savings": 10.0},
            {"threshold": 0.8, "message": "High resource usage - consider auto-scaling", "savings": -5.0}
        ]
    
    def get_current_metrics(self) -> ResourceMetrics:
        """Get current system metrics with cost estimation"""
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        network = psutil.net_io_counters()
        disk = psutil.disk_io_counters()
        
        # Add some simulation for demo purposes
        cpu_usage = min(cpu_percent + random.uniform(-5, 15), 100)
        memory_usage = memory.percent + random.uniform(-5, 10)
        network_io = random.uniform(100, 1000)  # MB/s simulated
        disk_io = random.uniform(50, 500)  # MB/s simulated
        
        # Calculate estimated cost (simplified)
        estimated_cost = (
            cpu_usage * self.cost_per_hour['cpu'] / 100 +
            memory_usage * self.cost_per_hour['memory'] / 100 +
            network_io * self.cost_per_hour['network'] / 1000 +
            disk_io * self.cost_per_hour['storage'] / 1000
        )
        
        metrics = ResourceMetrics(
            timestamp=time.time(),
            cpu_usage=cpu_usage,
            memory_usage=memory_usage,
            network_io=network_io,
            disk_io=disk_io,
            estimated_cost=estimated_cost
        )
        
        self.metrics_history.append(metrics)
        
        # Keep only last 100 entries
        if len(self.metrics_history) > 100:
            self.metrics_history = self.metrics_history[-100:]
        
        return metrics
    
    def get_optimization_recommendations(self) -> List[OptimizationRecommendation]:
        """Generate optimization recommendations based on current metrics"""
        if not self.metrics_history:
            return []
        
        recent_metrics = self.metrics_history[-10:]  # Last 10 metrics
        avg_cpu = np.mean([m.cpu_usage for m in recent_metrics])
        avg_memory = np.mean([m.memory_usage for m in recent_metrics])
        
        recommendations = []
        
        if avg_cpu < 30:
            recommendations.append(OptimizationRecommendation(
                type="downsizing",
                description="CPU utilization consistently below 30%. Consider downsizing instance type.",
                potential_savings=25.0,
                implementation_effort="Low"
            ))
        
        if avg_memory < 40:
            recommendations.append(OptimizationRecommendation(
                type="memory_optimization",
                description="Memory usage is low. Optimize memory allocation or use smaller instances.",
                potential_savings=15.0,
                implementation_effort="Medium"
            ))
        
        if avg_cpu > 80:
            recommendations.append(OptimizationRecommendation(
                type="scaling",
                description="High CPU usage detected. Consider horizontal scaling or load balancing.",
                potential_savings=-10.0,  # Negative because it increases cost but improves performance
                implementation_effort="High"
            ))
        
        # Storage tier recommendations
        recommendations.append(OptimizationRecommendation(
            type="storage_optimization",
            description="Implement automated storage tier management for infrequently accessed data.",
            potential_savings=40.0,
            implementation_effort="Medium"
        ))
        
        # Batch processing recommendation
        recommendations.append(OptimizationRecommendation(
            type="batch_processing",
            description="Implement request batching to reduce per-operation costs.",
            potential_savings=30.0,
            implementation_effort="High"
        ))
        
        return recommendations
    
    def calculate_projected_savings(self) -> Dict[str, float]:
        """Calculate projected monthly savings from recommendations"""
        recommendations = self.get_optimization_recommendations()
        current_monthly_cost = sum(m.estimated_cost for m in self.metrics_history[-30:] if self.metrics_history) * 24
        
        total_savings = sum(r.potential_savings for r in recommendations if r.potential_savings > 0)
        projected_monthly_savings = current_monthly_cost * (total_savings / 100)
        
        return {
            "current_monthly_cost": current_monthly_cost,
            "projected_savings": projected_monthly_savings,
            "savings_percentage": total_savings
        }

# Global cost tracker instance
cost_tracker = CostTracker()

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.get("/api/metrics")
async def get_metrics():
    """Get current system metrics"""
    metrics = cost_tracker.get_current_metrics()
    return metrics

@app.get("/api/recommendations")
async def get_recommendations():
    """Get optimization recommendations"""
    recommendations = cost_tracker.get_optimization_recommendations()
    return recommendations

@app.get("/api/savings")
async def get_savings():
    """Get projected savings calculation"""
    savings = cost_tracker.calculate_projected_savings()
    return savings

@app.get("/api/history")
async def get_history():
    """Get metrics history for charts"""
    return cost_tracker.metrics_history[-50:]  # Last 50 entries

@app.websocket("/ws/metrics")
async def websocket_metrics(websocket: WebSocket):
    """WebSocket endpoint for real-time metrics"""
    await websocket.accept()
    try:
        while True:
            metrics = cost_tracker.get_current_metrics()
            await websocket.send_json(metrics.dict())
            await asyncio.sleep(2)  # Send updates every 2 seconds
    except Exception as e:
        print(f"WebSocket error: {e}")
    finally:
        await websocket.close()

# Background task to simulate varying workloads
async def simulate_workload():
    """Simulate varying workloads for demonstration"""
    while True:
        # Simulate different load patterns
        load_pattern = random.choice(['low', 'medium', 'high', 'spike'])
        
        if load_pattern == 'spike':
            # Simulate a traffic spike
            for _ in range(5):
                cost_tracker.get_current_metrics()
                await asyncio.sleep(1)
        else:
            cost_tracker.get_current_metrics()
        
        await asyncio.sleep(random.uniform(2, 5))

@app.on_event("startup")
async def startup_event():
    """Start background tasks"""
    asyncio.create_task(simulate_workload())
    print("Cost Optimization Dashboard started!")
    print("Access the dashboard at: http://localhost:8000")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
