from fastapi import FastAPI, BackgroundTasks
from fastapi.responses import HTMLResponse
import asyncio
import time
import random
import psutil
import json
from prometheus_client import Counter, Histogram, Gauge, generate_latest
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Scalability Test Target Service")

# Prometheus metrics
request_count = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint'])
request_duration = Histogram('http_request_duration_seconds', 'HTTP request duration')
active_connections = Gauge('active_connections', 'Active connections')
cpu_usage = Gauge('cpu_usage_percent', 'CPU usage percentage') 
memory_usage = Gauge('memory_usage_percent', 'Memory usage percentage')
database_operations = Counter('database_operations_total', 'Database operations', ['operation'])

# Simulated database and cache
in_memory_db = {}
cache = {}
connection_pool = set()

class SystemResources:
    def __init__(self):
        self.connections = 0
        self.processing_queue = []
        
    def add_connection(self):
        self.connections += 1
        active_connections.set(self.connections)
        
    def remove_connection(self):
        self.connections = max(0, self.connections - 1)
        active_connections.set(self.connections)

system = SystemResources()

@app.middleware("http")
async def monitor_requests(request, call_next):
    start_time = time.time()
    system.add_connection()
    
    # Update system metrics
    cpu_usage.set(psutil.cpu_percent())
    memory_usage.set(psutil.virtual_memory().percent)
    
    try:
        response = await call_next(request)
        duration = time.time() - start_time
        
        request_count.labels(method=request.method, endpoint=request.url.path).inc()
        request_duration.observe(duration)
        
        # Log slow requests
        if duration > 0.5:
            logger.warning(f"Slow request: {request.url.path} took {duration:.2f}s")
            
        return response
    finally:
        system.remove_connection()

@app.get("/")
async def root():
    return {"message": "Scalability Test Service", "timestamp": datetime.now().isoformat()}

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "connections": system.connections,
        "cpu_percent": psutil.cpu_percent(),
        "memory_percent": psutil.virtual_memory().percent
    }

@app.get("/light")
async def light_endpoint():
    """Fast endpoint for baseline testing"""
    return {"result": "light", "timestamp": time.time()}

@app.get("/medium")
async def medium_endpoint():
    """Medium complexity endpoint with some processing"""
    await asyncio.sleep(0.1)  # Simulate processing
    data = {"numbers": [random.randint(1, 100) for _ in range(10)]}
    database_operations.labels(operation='read').inc()
    return {"result": data, "timestamp": time.time()}

@app.get("/heavy")
async def heavy_endpoint():
    """Heavy endpoint that consumes resources"""
    # Simulate CPU-intensive operation
    start = time.time()
    while time.time() - start < 0.3:
        _ = sum(random.randint(1, 1000) for _ in range(1000))
    
    # Simulate database operations
    database_operations.labels(operation='heavy_read').inc()
    
    return {
        "result": "heavy_computation_complete",
        "duration": time.time() - start,
        "timestamp": time.time()
    }

@app.get("/memory-stress")
async def memory_stress():
    """Endpoint that allocates memory to test memory limits"""
    # Allocate and hold memory briefly
    large_data = [random.random() for _ in range(100000)]
    await asyncio.sleep(0.2)
    return {"allocated_items": len(large_data)}

@app.get("/database-simulation")
async def database_simulation():
    """Simulates database connection pool behavior"""
    conn_id = f"conn_{random.randint(1000, 9999)}"
    
    # Simulate connection pool exhaustion
    if len(connection_pool) > 10:
        return {"error": "Connection pool exhausted", "pool_size": len(connection_pool)}, 503
    
    connection_pool.add(conn_id)
    database_operations.labels(operation='connection').inc()
    
    try:
        # Simulate query processing
        await asyncio.sleep(random.uniform(0.05, 0.2))
        
        # Random chance of slow query
        if random.random() < 0.1:
            await asyncio.sleep(1.0)  # Slow query simulation
            
        return {
            "query_result": f"Data for connection {conn_id}",
            "pool_size": len(connection_pool)
        }
    finally:
        connection_pool.discard(conn_id)

@app.get("/cascade-failure")
async def cascade_failure():
    """Demonstrates cascade failure patterns"""
    # Check system load
    if system.connections > 20:
        # Simulate downstream service failure under load
        if random.random() < 0.3:
            return {"error": "Downstream service unavailable"}, 503
    
    return {"status": "success", "load": system.connections}

@app.get("/metrics")
async def get_metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

@app.get("/dashboard")
async def dashboard():
    """Simple dashboard to view system status"""
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Scalability Test Dashboard</title>
        <style>
            body { font-family: 'Segoe UI', sans-serif; margin: 40px; background: #f5f7fa; }
            .container { max-width: 1200px; margin: 0 auto; }
            .header { background: white; padding: 30px; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); margin-bottom: 30px; }
            .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
            .metric-card { background: white; padding: 25px; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
            .metric-value { font-size: 2.5em; font-weight: bold; color: #2c3e50; margin: 10px 0; }
            .metric-label { color: #7f8c8d; font-size: 0.9em; text-transform: uppercase; letter-spacing: 1px; }
            .status-good { color: #27ae60; }
            .status-warning { color: #f39c12; }
            .status-critical { color: #e74c3c; }
            .refresh-btn { background: #3498db; color: white; border: none; padding: 12px 24px; border-radius: 6px; cursor: pointer; margin: 10px 0; }
            .test-controls { background: white; padding: 20px; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); margin-top: 20px; }
        </style>
        <script>
            async function updateMetrics() {
                try {
                    const response = await fetch('/health');
                    const data = await response.json();
                    
                    document.getElementById('connections').textContent = data.connections;
                    document.getElementById('cpu').textContent = data.cpu_percent.toFixed(1) + '%';
                    document.getElementById('memory').textContent = data.memory_percent.toFixed(1) + '%';
                    
                    // Update status classes
                    const cpuElement = document.getElementById('cpu-card');
                    const memoryElement = document.getElementById('memory-card');
                    
                    cpuElement.className = 'metric-card ' + (data.cpu_percent > 80 ? 'status-critical' : data.cpu_percent > 60 ? 'status-warning' : 'status-good');
                    memoryElement.className = 'metric-card ' + (data.memory_percent > 80 ? 'status-critical' : data.memory_percent > 60 ? 'status-warning' : 'status-good');
                    
                } catch (error) {
                    console.error('Failed to update metrics:', error);
                }
            }
            
            setInterval(updateMetrics, 1000);
            window.onload = updateMetrics;
        </script>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1>🚀 Scalability Testing Dashboard</h1>
                <p>Real-time system metrics and performance monitoring</p>
            </div>
            
            <div class="metrics-grid">
                <div class="metric-card">
                    <div class="metric-label">Active Connections</div>
                    <div class="metric-value" id="connections">0</div>
                </div>
                
                <div class="metric-card" id="cpu-card">
                    <div class="metric-label">CPU Usage</div>
                    <div class="metric-value" id="cpu">0%</div>
                </div>
                
                <div class="metric-card" id="memory-card">
                    <div class="metric-label">Memory Usage</div>
                    <div class="metric-value" id="memory">0%</div>
                </div>
                
                <div class="metric-card">
                    <div class="metric-label">System Status</div>
                    <div class="metric-value status-good">✓ Healthy</div>
                </div>
            </div>
            
            <div class="test-controls">
                <h3>📊 Test Endpoints</h3>
                <p><strong>Light Load:</strong> <a href="/light">/light</a> - Fast baseline endpoint</p>
                <p><strong>Medium Load:</strong> <a href="/medium">/medium</a> - Moderate processing</p>
                <p><strong>Heavy Load:</strong> <a href="/heavy">/heavy</a> - CPU intensive operations</p>
                <p><strong>Memory Test:</strong> <a href="/memory-stress">/memory-stress</a> - Memory allocation test</p>
                <p><strong>Database Sim:</strong> <a href="/database-simulation">/database-simulation</a> - Connection pool testing</p>
                <p><strong>Cascade Test:</strong> <a href="/cascade-failure">/cascade-failure</a> - Failure pattern testing</p>
            </div>
        </div>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)
