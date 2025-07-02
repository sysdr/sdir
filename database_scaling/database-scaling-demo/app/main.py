from fastapi import FastAPI, Request, HTTPException, BackgroundTasks
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
import asyncio
import time
import random
import json
from datetime import datetime, timedelta
from typing import List, Dict, Any
import os
from .database import DatabaseManager
from .load_generator import LoadGenerator
from .monitoring import MetricsCollector

app = FastAPI(title="Database Scaling Patterns Demo")

# Mount static files and templates
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Initialize components
db_manager = DatabaseManager()
load_generator = LoadGenerator(db_manager)
metrics = MetricsCollector()

@app.on_event("startup")
async def startup_event():
    await db_manager.initialize()
    await load_generator.setup_test_data()
    print("✅ Database Scaling Demo Ready!")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.get("/api/stats")
async def get_stats():
    """Get real-time performance statistics"""
    stats = await metrics.get_current_stats()
    return JSONResponse(stats)

@app.post("/api/test/read-replicas")
async def test_read_replicas(background_tasks: BackgroundTasks):
    """Test read replica performance"""
    background_tasks.add_task(load_generator.test_read_replicas)
    return {"status": "started", "message": "Read replica load test initiated"}

@app.post("/api/test/sharding")
async def test_sharding(background_tasks: BackgroundTasks):
    """Test sharding performance"""
    background_tasks.add_task(load_generator.test_sharding)
    return {"status": "started", "message": "Sharding load test initiated"}

@app.post("/api/test/comparison")
async def test_comparison(background_tasks: BackgroundTasks):
    """Run comprehensive comparison test"""
    background_tasks.add_task(load_generator.run_comparison_test)
    return {"status": "started", "message": "Comprehensive performance test initiated"}

@app.get("/api/metrics/live")
async def live_metrics():
    """Get live performance metrics"""
    return await metrics.get_live_metrics()

@app.post("/api/chaos/partition")
async def chaos_partition():
    """Simulate network partition"""
    await load_generator.simulate_partition()
    return {"status": "partition_simulated"}

@app.post("/api/chaos/replica-failure")
async def chaos_replica_failure():
    """Simulate replica failure"""
    await load_generator.simulate_replica_failure()
    return {"status": "replica_failure_simulated"}

@app.get("/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}
