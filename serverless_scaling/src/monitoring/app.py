from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse
import redis
import json
import os
import time
import asyncio
from typing import Dict, Any, List
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Serverless Scaling Monitoring", version="1.0.0")

# Redis connection
redis_client = redis.Redis.from_url(
    os.getenv("REDIS_URL", "redis://localhost:6379"),
    decode_responses=True
)

@app.get("/")
async def root():
    """Monitoring dashboard"""
    return HTMLResponse(content=get_dashboard_html(), status_code=200)

@app.get("/api/metrics")
async def get_metrics():
    """Get real-time system metrics"""
    try:
        # Get basic metrics
        request_count = int(redis_client.get("request_count") or 0)
        # Handle active_workers as a set, with fallback if it doesn't exist
        try:
            active_workers = len(redis_client.smembers("active_workers"))
        except:
            active_workers = 0
        queue_length = int(redis_client.get("queue_length") or 0)
        
        # Get worker details
        worker_details = []
        try:
            for worker_id in redis_client.smembers("active_workers"):
                last_seen = redis_client.get(f"worker:{worker_id}:last_seen")
                worker_details.append({
                    "id": worker_id,
                    "last_seen": float(last_seen) if last_seen else 0,
                    "status": "active"
                })
        except:
            # If active_workers is not a set, skip worker details
            pass
        
        # Get recent tasks
        recent_tasks = []
        for i in range(min(10, queue_length)):
            task_id = redis_client.lindex("task_queue", i)
            if task_id:
                task_data = redis_client.get(f"task:{task_id}")
                if task_data:
                    task_info = json.loads(task_data)
                    recent_tasks.append({
                        "id": task_id,
                        "status": task_info.get("status", "unknown"),
                        "created_at": task_info.get("created_at", 0),
                        "worker_id": task_info.get("worker_id")
                    })
        
        # Calculate performance metrics
        current_time = time.time()
        tasks_per_minute = 0
        avg_processing_time = 0
        
        # Get completed tasks from the last hour
        completed_tasks = []
        for key in redis_client.keys("task:*"):
            if key.startswith("task:task_"):
                task_data = redis_client.get(key)
                if task_data:
                    task_info = json.loads(task_data)
                    if task_info.get("status") == "completed":
                        completed_time = task_info.get("completed_at", 0)
                        if current_time - completed_time < 3600:  # Last hour
                            completed_tasks.append(task_info)
        
        if completed_tasks:
            tasks_per_minute = len(completed_tasks) / 60
            processing_times = [t.get("processing_time", 0) for t in completed_tasks if t.get("processing_time")]
            avg_processing_time = sum(processing_times) / len(processing_times) if processing_times else 0
        
        return {
            "timestamp": current_time,
            "system_health": {
                "redis_connected": redis_client.ping(),
                "total_requests": request_count,
                "active_workers": active_workers,
                "queue_length": queue_length
            },
            "performance": {
                "tasks_per_minute": round(tasks_per_minute, 2),
                "avg_processing_time": round(avg_processing_time, 2),
                "completed_tasks_last_hour": len(completed_tasks)
            },
            "workers": worker_details,
            "recent_tasks": recent_tasks,
            "scaling_recommendation": get_scaling_recommendation(active_workers, queue_length)
        }
    except Exception as e:
        logger.error(f"Error getting metrics: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/api/health")
async def health():
    """Health check endpoint"""
    return {
        "service": "Monitoring",
        "status": "healthy",
        "redis_connected": redis_client.ping(),
        "timestamp": time.time()
    }

def get_scaling_recommendation(active_workers: int, queue_length: int) -> Dict[str, Any]:
    """Generate scaling recommendations based on current metrics"""
    if queue_length > active_workers * 3:
        return {
            "action": "scale_up",
            "urgency": "high",
            "reason": f"Queue length ({queue_length}) is much higher than workers ({active_workers})",
            "suggested_workers": min(active_workers + 2, 10)
        }
    elif queue_length > active_workers:
        return {
            "action": "scale_up",
            "urgency": "medium",
            "reason": f"Queue length ({queue_length}) is higher than workers ({active_workers})",
            "suggested_workers": active_workers + 1
        }
    elif queue_length < active_workers // 2 and active_workers > 1:
        return {
            "action": "scale_down",
            "urgency": "low",
            "reason": f"Queue length ({queue_length}) is low compared to workers ({active_workers})",
            "suggested_workers": max(active_workers - 1, 1)
        }
    else:
        return {
            "action": "maintain",
            "urgency": "none",
            "reason": "Current scaling is appropriate",
            "suggested_workers": active_workers
        }

def get_dashboard_html() -> str:
    """Generate HTML dashboard"""
    return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Serverless Scaling Monitor</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
            color: #2c3e50;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 8px 25px rgba(0,0,0,0.15);
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
            color: white;
            padding: 20px;
            text-align: center;
        }
        .header h1 {
            margin: 0;
            font-size: 2.5em;
        }
        .header p {
            margin: 10px 0 0 0;
            opacity: 0.9;
        }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            padding: 20px;
        }
        .metric-card {
            background: #f8f9fa;
            border-radius: 8px;
            padding: 20px;
            border-left: 4px solid #667eea;
            box-shadow: 0 2px 10px rgba(0,0,0,0.05);
        }
        .metric-card h3 {
            margin: 0 0 10px 0;
            color: #667eea;
            font-size: 1.1em;
        }
        .metric-value {
            font-size: 2em;
            font-weight: bold;
            color: #333;
        }
        .metric-label {
            color: #666;
            font-size: 0.9em;
            margin-top: 5px;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .status-healthy { background: #28a745; }
        .status-warning { background: #ffc107; }
        .status-error { background: #dc3545; }
        .workers-section, .tasks-section {
            padding: 20px;
            border-top: 1px solid #eee;
        }
        .workers-section h2, .tasks-section h2 {
            color: #667eea;
            margin-bottom: 15px;
        }
        .worker-list, .task-list {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 10px;
        }
        .worker-item, .task-item {
            background: #f8f9fa;
            padding: 10px;
            border-radius: 5px;
            border-left: 3px solid #667eea;
        }
        .refresh-btn {
            background: #667eea;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 1em;
            margin: 20px;
        }
        .refresh-btn:hover {
            background: #5a6fd8;
        }
        .auto-refresh {
            text-align: center;
            padding: 10px;
            background: #f8f9fa;
            border-top: 1px solid #eee;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Serverless Scaling Monitor</h1>
            <p>Real-time system metrics and scaling insights</p>
        </div>
        
        <div class="metrics-grid" id="metrics-grid">
            <div class="metric-card">
                <h3>Total Requests</h3>
                <div class="metric-value" id="total-requests">-</div>
                <div class="metric-label">Lifetime requests</div>
            </div>
            <div class="metric-card">
                <h3>Active Workers</h3>
                <div class="metric-value" id="active-workers">-</div>
                <div class="metric-label">Currently processing</div>
            </div>
            <div class="metric-card">
                <h3>Queue Length</h3>
                <div class="metric-value" id="queue-length">-</div>
                <div class="metric-label">Pending tasks</div>
            </div>
            <div class="metric-card">
                <h3>Tasks/Minute</h3>
                <div class="metric-value" id="tasks-per-minute">-</div>
                <div class="metric-label">Processing rate</div>
            </div>
            <div class="metric-card">
                <h3>Avg Processing Time</h3>
                <div class="metric-value" id="avg-processing-time">-</div>
                <div class="metric-label">Seconds per task</div>
            </div>
            <div class="metric-card">
                <h3>System Status</h3>
                <div class="metric-value" id="system-status">-</div>
                <div class="metric-label">Overall health</div>
            </div>
        </div>
        
        <div class="workers-section">
            <h2>🛠️ Active Workers</h2>
            <div class="worker-list" id="worker-list">
                <div class="worker-item">Loading workers...</div>
            </div>
        </div>
        
        <div class="tasks-section">
            <h2>📋 Recent Tasks</h2>
            <div class="task-list" id="task-list">
                <div class="task-item">Loading tasks...</div>
            </div>
        </div>
        
        <div class="auto-refresh">
            <button class="refresh-btn" onclick="refreshMetrics()">🔄 Refresh Now</button>
            <span>Auto-refreshing every 5 seconds</span>
        </div>
    </div>

    <script>
        async function refreshMetrics() {
            try {
                // Use the correct API endpoint based on the current path
                const apiEndpoint = window.location.pathname.includes('/monitoring/') ? '/monitoring-api/metrics' : '/api/metrics';
                const response = await fetch(apiEndpoint);
                if (!response.ok) {
                    throw new Error(`HTTP error! status: ${response.status}`);
                }
                const data = await response.json();
                
                // Check if data exists and has required properties
                if (!data) {
                    throw new Error('No data received from server');
                }
                
                // Ensure required objects exist with fallbacks
                const systemHealth = data.system_health || {};
                const performance = data.performance || {};
                
                // Update metrics
                document.getElementById('total-requests').textContent = systemHealth.total_requests || 0;
                document.getElementById('active-workers').textContent = systemHealth.active_workers || 0;
                document.getElementById('queue-length').textContent = systemHealth.queue_length || 0;
                document.getElementById('tasks-per-minute').textContent = performance.tasks_per_minute || 0;
                document.getElementById('avg-processing-time').textContent = (performance.avg_processing_time || 0) + 's';
                
                // Update system status
                const statusEl = document.getElementById('system-status');
                if (systemHealth.redis_connected) {
                    statusEl.innerHTML = '<span class="status-indicator status-healthy"></span>Healthy';
                } else {
                    statusEl.innerHTML = '<span class="status-indicator status-error"></span>Error';
                }
                
                // Update workers
                const workerList = document.getElementById('worker-list');
                if (data.workers && data.workers.length > 0) {
                    workerList.innerHTML = data.workers.map(worker => `
                        <div class="worker-item">
                            <strong>Worker ${worker.id}</strong><br>
                            <small>Last seen: ${new Date(worker.last_seen * 1000).toLocaleTimeString()}</small>
                        </div>
                    `).join('');
                } else {
                    workerList.innerHTML = '<div class="worker-item">No active workers</div>';
                }
                
                // Update tasks
                const taskList = document.getElementById('task-list');
                if (data.recent_tasks && data.recent_tasks.length > 0) {
                    taskList.innerHTML = data.recent_tasks.map(task => `
                        <div class="task-item">
                            <strong>${task.id}</strong><br>
                            <small>Status: ${task.status}</small><br>
                            <small>Worker: ${task.worker_id || 'None'}</small>
                        </div>
                    `).join('');
                } else {
                    taskList.innerHTML = '<div class="task-item">No recent tasks</div>';
                }
                
            } catch (error) {
                console.error('Error fetching metrics:', error);
                
                // Show error message to user
                const errorMessage = 'Failed to load metrics. Please refresh the page.';
                document.getElementById('total-requests').textContent = 'Error';
                document.getElementById('active-workers').textContent = 'Error';
                document.getElementById('queue-length').textContent = 'Error';
                document.getElementById('tasks-per-minute').textContent = 'Error';
                document.getElementById('avg-processing-time').textContent = 'Error';
                document.getElementById('system-status').innerHTML = '<span class="status-indicator status-error"></span>Error';
                document.getElementById('worker-list').innerHTML = '<div class="worker-item">Error loading workers</div>';
                document.getElementById('task-list').innerHTML = '<div class="task-item">Error loading tasks</div>';
            }
        }
        
        // Initial load
        refreshMetrics();
        
        // Auto-refresh every 5 seconds
        setInterval(refreshMetrics, 5000);
    </script>
</body>
</html>
    """

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8080) 