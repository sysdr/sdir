"""
Web Dashboard - Real-time visualization of backpressure mechanisms
"""
import asyncio
import json
import os
import time
from typing import Dict, List
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
import uvicorn
import sys
sys.path.append('/app/services')
from shared_utils import setup_logging, create_redis_client
import httpx

REDIS_HOST = os.getenv("REDIS_HOST", "redis")

app = FastAPI(title="Backpressure Dashboard")
logger = setup_logging("dashboard")
redis_client = None

# Store active WebSocket connections
websocket_connections: List[WebSocket] = []

@app.on_event("startup")
async def startup():
    global redis_client
    logger.info("Starting dashboard")
    
    redis_client = await create_redis_client(host=REDIS_HOST)
    if not redis_client:
        logger.error("Failed to connect to Redis")
        return
    
    # Start background task to broadcast metrics
    asyncio.create_task(broadcast_metrics())

async def broadcast_metrics():
    """Broadcast real-time metrics to connected WebSocket clients"""
    while True:
        try:
            # Collect metrics from all services
            metrics_data = {
                "timestamp": time.time(),
                "services": {}
            }
            
            # Get metrics for each service
            services = ["backend-service", "gateway-service"]
            for service in services:
                metrics_list = await redis_client.lrange(f"metrics:{service}", 0, 9)
                if metrics_list:
                    latest_metrics = json.loads(metrics_list[0])
                    metrics_data["services"][service] = latest_metrics
            
            # Get load generator statistics
            load_stats = await redis_client.get("load_generator_stats")
            if load_stats:
                metrics_data["load_generator"] = json.loads(load_stats)
            
            # Broadcast to all connected clients
            if websocket_connections:
                message = json.dumps(metrics_data)
                disconnected = []
                
                for ws in websocket_connections:
                    try:
                        await ws.send_text(message)
                    except:
                        disconnected.append(ws)
                
                # Remove disconnected clients
                for ws in disconnected:
                    websocket_connections.remove(ws)
            
            await asyncio.sleep(1.0)  # Update every second
            
        except Exception as e:
            logger.error("Error broadcasting metrics", error=str(e))
            await asyncio.sleep(5.0)

@app.get("/", response_class=HTMLResponse)
async def dashboard_home():
    """Serve the main dashboard page"""
    return """
<!DOCTYPE html>
<html>
<head>
    <title>Backpressure Mechanisms Dashboard</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 20px;
        }
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        .metric-card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .metric-title {
            font-size: 18px;
            font-weight: bold;
            margin-bottom: 10px;
            color: #333;
        }
        .metric-value {
            font-size: 24px;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .metric-label {
            font-size: 14px;
            color: #666;
        }
        .status-healthy { color: #4CAF50; }
        .status-warning { color: #FF9800; }
        .status-critical { color: #F44336; }
        .controls {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
        .control-group {
            display: inline-block;
            margin-right: 20px;
            margin-bottom: 10px;
        }
        button {
            padding: 10px 20px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
        }
        .btn-primary { background: #007bff; color: white; }
        .btn-warning { background: #ffc107; color: black; }
        .btn-danger { background: #dc3545; color: white; }
        .log-container {
            background: #1e1e1e;
            color: #00ff00;
            padding: 20px;
            border-radius: 10px;
            height: 300px;
            overflow-y: auto;
            font-family: 'Courier New', monospace;
            font-size: 12px;
        }
        .chart-container {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔄 Backpressure Mechanisms Dashboard</h1>
            <p>Real-time monitoring of distributed system backpressure patterns</p>
        </div>

        <div class="controls">
            <h3>Load Control</h3>
            <div class="control-group">
                <button class="btn-primary" onclick="startLoad()">Start Load Test</button>
                <button class="btn-warning" onclick="stopLoad()">Stop Load Test</button>
            </div>
            <div class="control-group">
                <button class="btn-danger" onclick="increaseLatency()">Increase Backend Latency</button>
                <button class="btn-primary" onclick="resetLatency()">Reset Latency</button>
            </div>
            <div class="control-group">
                <button class="btn-warning" onclick="enableErrors()">Enable Backend Errors</button>
                <button class="btn-primary" onclick="disableErrors()">Disable Errors</button>
            </div>
        </div>

        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-title">Gateway Service</div>
                <div id="gateway-status" class="metric-value status-healthy">Healthy</div>
                <div class="metric-label">Queue Depth: <span id="gateway-queue">0</span></div>
                <div class="metric-label">Circuit Breaker: <span id="gateway-circuit">Closed</span></div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Backend Service</div>
                <div id="backend-status" class="metric-value status-healthy">Healthy</div>
                <div class="metric-label">Queue Depth: <span id="backend-queue">0</span></div>
                <div class="metric-label">Circuit Breaker: <span id="backend-circuit">Closed</span></div>
            </div>

            <div class="metric-card">
                <div class="metric-title">Load Generator</div>
                <div id="load-status" class="metric-value">Stopped</div>
                <div class="metric-label">Success Rate: <span id="success-rate">0%</span></div>
                <div class="metric-label">Avg Latency: <span id="avg-latency">0ms</span></div>
            </div>

            <div class="metric-card">
                <div class="metric-title">System Health</div>
                <div id="system-health" class="metric-value status-healthy">Good</div>
                <div class="metric-label">Backpressure Active: <span id="backpressure-active">No</span></div>
                <div class="metric-label">Load Shedding: <span id="load-shedding">No</span></div>
            </div>
        </div>

        <div class="chart-container">
            <h3>Real-time Metrics</h3>
            <canvas id="metricsChart" width="800" height="300"></canvas>
        </div>

        <div class="metric-card">
            <div class="metric-title">Live Logs</div>
            <div id="logs" class="log-container"></div>
        </div>
    </div>

    <!-- Chart.js for real-time charts -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    
    <script>
        let socket;
        let metricsHistory = [];
        const maxHistoryLength = 50;
        let metricsChart;

        function connectWebSocket() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = protocol + '//' + window.location.host + '/ws';
            
            console.log('Connecting to WebSocket:', wsUrl);
            addLog('Connecting to WebSocket...');
            
            socket = new WebSocket(wsUrl);
            
            socket.onopen = function(event) {
                console.log('WebSocket connected successfully');
                addLog('Connected to dashboard');
            };
            
            socket.onmessage = function(event) {
                console.log('Received WebSocket message:', event.data);
                try {
                    const data = JSON.parse(event.data);
                    updateMetrics(data);
                } catch (error) {
                    console.error('Error parsing WebSocket message:', error);
                    addLog('Error parsing message: ' + error.message);
                }
            };
            
            socket.onclose = function(event) {
                console.log('WebSocket connection closed:', event.code, event.reason);
                addLog('Connection closed, reconnecting...');
                setTimeout(connectWebSocket, 3000);
            };
            
            socket.onerror = function(error) {
                console.error('WebSocket error:', error);
                addLog('WebSocket error: ' + error);
            };
        }

        function updateMetrics(data) {
            console.log('Received metrics data:', data);
            addLog('Received metrics update');
            
            // Update service metrics
            if (data.services) {
                console.log('Updating service metrics:', data.services);
                updateServiceMetrics('gateway', data.services['gateway-service']);
                updateServiceMetrics('backend', data.services['backend-service']);
            }
            
            // Update load generator metrics
            if (data.load_generator) {
                console.log('Updating load generator metrics:', data.load_generator);
                updateLoadGeneratorMetrics(data.load_generator);
            }
            
            // Update system health
            updateSystemHealth(data);
            
            // Store metrics for charting
            metricsHistory.push(data);
            if (metricsHistory.length > maxHistoryLength) {
                metricsHistory.shift();
            }
            
            updateChart();
        }

        function updateServiceMetrics(servicePrefix, metrics) {
            if (!metrics) {
                console.log('No metrics for service:', servicePrefix);
                return;
            }
            
            console.log('Updating metrics for', servicePrefix, ':', metrics);
            
            const queueDepth = metrics.queue_depth || 0;
            const cpuUsage = metrics.cpu_usage || 0;
            const errorRate = metrics.error_rate || 0;
            const processingRate = metrics.processing_rate || 0;
            
            document.getElementById(servicePrefix + '-queue').textContent = queueDepth;
            
            // Update status based on queue depth, CPU usage, and error rate
            const statusElement = document.getElementById(servicePrefix + '-status');
            let status = 'Healthy';
            let statusClass = 'status-healthy';
            
            // Enhanced status logic considering error rates as backpressure indicators
            if (queueDepth > 500 || cpuUsage > 80 || errorRate > 100) {
                status = 'Critical';
                statusClass = 'status-critical';
            } else if (queueDepth > 200 || cpuUsage > 60 || errorRate > 50) {
                status = 'Stressed';
                statusClass = 'status-warning';
            } else if (queueDepth > 50 || cpuUsage > 40 || errorRate > 20) {
                status = 'Warning';
                statusClass = 'status-warning';
            } else if (errorRate > 5) {
                status = 'Degraded';
                statusClass = 'status-warning';
            }
            
            statusElement.textContent = status;
            statusElement.className = 'metric-value ' + statusClass;
            
            // Update circuit breaker status based on error rate and processing rate
            const circuitElement = document.getElementById(servicePrefix + '-circuit');
            let circuitStatus = 'Closed';
            let circuitClass = 'status-healthy';
            
            // Circuit breaker logic: high error rates indicate circuit breaker activity
            if (errorRate > 50 || (errorRate > 20 && processingRate < 0.1)) {
                circuitStatus = 'Open';
                circuitClass = 'status-critical';
            } else if (errorRate > 10 || processingRate < 0.5) {
                circuitStatus = 'Half-Open';
                circuitClass = 'status-warning';
            }
            
            circuitElement.textContent = circuitStatus;
            circuitElement.className = circuitClass;
            
            console.log('Updated', servicePrefix, 'status to:', status, 'circuit:', circuitStatus);
        }

        function updateSystemHealth(data) {
            // Determine overall system health based on all metrics
            let backpressureActive = false;
            let loadShedding = false;
            let systemHealth = 'Good';
            let healthClass = 'status-healthy';
            
            // Check gateway service health
            const gatewayMetrics = data.services?.['gateway-service'];
            if (gatewayMetrics) {
                const gatewayQueue = gatewayMetrics.queue_depth || 0;
                const gatewayCpu = gatewayMetrics.cpu_usage || 0;
                const gatewayErrors = gatewayMetrics.error_rate || 0;
                
                // Consider high error rates as backpressure indicators (circuit breaker rejecting requests)
                if (gatewayQueue > 200 || gatewayCpu > 60 || gatewayErrors > 20) {
                    backpressureActive = true;
                }
            }
            
            // Check backend service health
            const backendMetrics = data.services?.['backend-service'];
            if (backendMetrics) {
                const backendQueue = backendMetrics.queue_depth || 0;
                const backendCpu = backendMetrics.cpu_usage || 0;
                const backendErrors = backendMetrics.error_rate || 0;
                
                if (backendQueue > 200 || backendCpu > 60 || backendErrors > 20) {
                    backpressureActive = true;
                }
            }
            
            // Check load shedding (high rejection rate) - this is the main indicator
            const loadStats = data.load_generator;
            if (loadStats) {
                const total = loadStats.total_requests || 0;
                const rejections = loadStats.backpressure_rejections || 0;
                if (total > 0 && (rejections / total) > 0.1) { // Lowered threshold to 10%
                    loadShedding = true;
                }
            }
            
            // Enhanced backpressure detection: consider high error rates as backpressure
            if (gatewayMetrics && gatewayMetrics.error_rate > 50) {
                backpressureActive = true;
            }
            
            // Determine overall system health
            if (backpressureActive && loadShedding) {
                systemHealth = 'Critical';
                healthClass = 'status-critical';
            } else if (backpressureActive || loadShedding) {
                systemHealth = 'Warning';
                healthClass = 'status-warning';
            } else if (gatewayMetrics && backendMetrics) {
                const gatewayHealthy = (gatewayMetrics.queue_depth || 0) < 50 && (gatewayMetrics.cpu_usage || 0) < 40 && (gatewayMetrics.error_rate || 0) < 5;
                const backendHealthy = (backendMetrics.queue_depth || 0) < 50 && (backendMetrics.cpu_usage || 0) < 40 && (backendMetrics.error_rate || 0) < 5;
                
                if (gatewayHealthy && backendHealthy) {
                    systemHealth = 'Excellent';
                    healthClass = 'status-healthy';
                } else {
                    systemHealth = 'Good';
                    healthClass = 'status-healthy';
                }
            }
            
            // Update UI
            const systemHealthElement = document.getElementById('system-health');
            systemHealthElement.textContent = systemHealth;
            systemHealthElement.className = 'metric-value ' + healthClass;
            
            document.getElementById('backpressure-active').textContent = backpressureActive ? 'Yes' : 'No';
            document.getElementById('load-shedding').textContent = loadShedding ? 'Yes' : 'No';
            
            console.log('Updated system health to:', systemHealth, 'backpressure:', backpressureActive, 'load shedding:', loadShedding);
        }

        function updateLoadGeneratorMetrics(stats) {
            if (!stats) {
                console.log('No load generator stats');
                return;
            }
            
            const total = stats.total_requests || 0;
            const successful = stats.successful_requests || 0;
            const rejections = stats.backpressure_rejections || 0;
            const successRate = total > 0 ? (successful / total * 100).toFixed(1) : 0;
            const avgLatency = (stats.average_latency * 1000).toFixed(0);
            
            document.getElementById('success-rate').textContent = successRate + '%';
            document.getElementById('avg-latency').textContent = avgLatency + 'ms';
            
            // Determine load generator status
            const loadStatusElement = document.getElementById('load-status');
            let loadStatus = 'Stopped';
            let statusClass = '';
            
            if (total > 0) {
                if (rejections > 0 && (rejections / total) > 0.8) {
                    loadStatus = 'Load Shedding';
                    statusClass = 'status-critical';
                } else if (successRate < 50) {
                    loadStatus = 'High Failure Rate';
                    statusClass = 'status-warning';
                } else if (successRate < 80) {
                    loadStatus = 'Degraded';
                    statusClass = 'status-warning';
                } else {
                    loadStatus = 'Running';
                    statusClass = 'status-healthy';
                }
            }
            
            loadStatusElement.textContent = loadStatus;
            loadStatusElement.className = 'metric-value ' + statusClass;
            
            console.log('Updated load generator status to:', loadStatus);
        }

        function updateChart() {
            if (!metricsHistory.length) return;
            
            try {
                const canvas = document.getElementById('metricsChart');
                if (!canvas) {
                    console.log('Canvas element not found');
                    return;
                }
                
                if (!metricsChart) {
                    const ctx = canvas.getContext('2d');
                    metricsChart = new Chart(ctx, {
                        type: 'line',
                        data: {
                            labels: [],
                            datasets: [
                                {
                                    label: 'Gateway Queue Depth',
                                    data: [],
                                    borderColor: 'rgb(75, 192, 192)',
                                    backgroundColor: 'rgba(75, 192, 192, 0.2)',
                                    tension: 0.1,
                                    yAxisID: 'y'
                                },
                                {
                                    label: 'Backend Queue Depth',
                                    data: [],
                                    borderColor: 'rgb(255, 99, 132)',
                                    backgroundColor: 'rgba(255, 99, 132, 0.2)',
                                    tension: 0.1,
                                    yAxisID: 'y'
                                },
                                {
                                    label: 'Gateway CPU %',
                                    data: [],
                                    borderColor: 'rgb(54, 162, 235)',
                                    backgroundColor: 'rgba(54, 162, 235, 0.2)',
                                    tension: 0.1,
                                    yAxisID: 'y1'
                                },
                                {
                                    label: 'Backend CPU %',
                                    data: [],
                                    borderColor: 'rgb(255, 205, 86)',
                                    backgroundColor: 'rgba(255, 205, 86, 0.2)',
                                    tension: 0.1,
                                    yAxisID: 'y1'
                                },
                                {
                                    label: 'Success Rate %',
                                    data: [],
                                    borderColor: 'rgb(153, 102, 255)',
                                    backgroundColor: 'rgba(153, 102, 255, 0.2)',
                                    tension: 0.1,
                                    yAxisID: 'y2'
                                }
                            ]
                        },
                        options: {
                            responsive: true,
                            interaction: {
                                mode: 'index',
                                intersect: false,
                            },
                            scales: {
                                x: {
                                    display: true,
                                    title: {
                                        display: true,
                                        text: 'Time'
                                    }
                                },
                                y: {
                                    type: 'linear',
                                    display: true,
                                    position: 'left',
                                    title: {
                                        display: true,
                                        text: 'Queue Depth'
                                    }
                                },
                                y1: {
                                    type: 'linear',
                                    display: true,
                                    position: 'right',
                                    title: {
                                        display: true,
                                        text: 'CPU Usage %'
                                    },
                                    grid: {
                                        drawOnChartArea: false,
                                    },
                                    max: 100
                                },
                                y2: {
                                    type: 'linear',
                                    display: true,
                                    position: 'right',
                                    title: {
                                        display: true,
                                        text: 'Success Rate %'
                                    },
                                    grid: {
                                        drawOnChartArea: false,
                                    },
                                    max: 100
                                }
                            },
                            plugins: {
                                title: {
                                    display: true,
                                    text: 'Real-time System Metrics'
                                },
                                legend: {
                                    display: true
                                }
                            },
                            animation: {
                                duration: 0
                            }
                        }
                    });
                }
                
                // Update chart data
                const labels = [];
                const gatewayQueueData = [];
                const backendQueueData = [];
                const gatewayCpuData = [];
                const backendCpuData = [];
                const successRateData = [];
                
                metricsHistory.forEach((metric, index) => {
                    const time = new Date(metric.timestamp * 1000).toLocaleTimeString();
                    labels.push(time);
                    
                    if (metric.services && metric.services['gateway-service']) {
                        gatewayQueueData.push(metric.services['gateway-service'].queue_depth || 0);
                        gatewayCpuData.push(metric.services['gateway-service'].cpu_usage || 0);
                    }
                    
                    if (metric.services && metric.services['backend-service']) {
                        backendQueueData.push(metric.services['backend-service'].queue_depth || 0);
                        backendCpuData.push(metric.services['backend-service'].cpu_usage || 0);
                    }
                    
                    if (metric.load_generator) {
                        const total = metric.load_generator.total_requests || 0;
                        const successful = metric.load_generator.successful_requests || 0;
                        const successRate = total > 0 ? (successful / total) * 100 : 0;
                        successRateData.push(successRate);
                    }
                });
                
                metricsChart.data.labels = labels;
                metricsChart.data.datasets[0].data = gatewayQueueData;
                metricsChart.data.datasets[1].data = backendQueueData;
                metricsChart.data.datasets[2].data = gatewayCpuData;
                metricsChart.data.datasets[3].data = backendCpuData;
                metricsChart.data.datasets[4].data = successRateData;
                
                metricsChart.update('none');
            } catch (error) {
                console.error('Error updating chart:', error);
            }
        }

        function addLog(message) {
            const logsElement = document.getElementById('logs');
            const timestamp = new Date().toLocaleTimeString();
            logsElement.innerHTML += timestamp + ' - ' + message + '\\n';
            logsElement.scrollTop = logsElement.scrollHeight;
        }

        // Control functions
        async function startLoad() {
            try {
                const response = await fetch('/api/load/start', { method: 'POST' });
                const result = await response.json();
                addLog('Load test started');
            } catch (error) {
                addLog('Error starting load test: ' + error);
            }
        }

        async function stopLoad() {
            try {
                const response = await fetch('/api/load/stop', { method: 'POST' });
                const result = await response.json();
                addLog('Load test stopped');
            } catch (error) {
                addLog('Error stopping load test: ' + error);
            }
        }

        async function increaseLatency() {
            try {
                const response = await fetch('/api/backend/latency/1.0', { method: 'POST' });
                const result = await response.json();
                addLog('Backend latency increased to 1000ms');
            } catch (error) {
                addLog('Error increasing latency: ' + error);
            }
        }

        async function resetLatency() {
            try {
                const response = await fetch('/api/backend/latency/0.1', { method: 'POST' });
                const result = await response.json();
                addLog('Backend latency reset to 100ms');
            } catch (error) {
                addLog('Error resetting latency: ' + error);
            }
        }

        async function enableErrors() {
            try {
                const response = await fetch('/api/backend/errors/0.2', { method: 'POST' });
                const result = await response.json();
                addLog('Backend error rate set to 20%');
            } catch (error) {
                addLog('Error enabling errors: ' + error);
            }
        }

        async function disableErrors() {
            try {
                const response = await fetch('/api/backend/errors/0.0', { method: 'POST' });
                const result = await response.json();
                addLog('Backend errors disabled');
            } catch (error) {
                addLog('Error disabling errors: ' + error);
            }
        }

        // Initialize
        connectWebSocket();
        addLog('Dashboard initialized');
    </script>
</body>
</html>
"""



@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time metrics"""
    await websocket.accept()
    websocket_connections.append(websocket)
    logger.info("New WebSocket connection")
    
    try:
        while True:
            # Keep connection alive
            await websocket.receive_text()
    except WebSocketDisconnect:
        websocket_connections.remove(websocket)
        logger.info("WebSocket disconnected")

@app.post("/api/load/start")
async def start_load_test():
    """Start load test"""
    load_config = {"enabled": True, "concurrent_users": 20, "requests_per_second": 10}
    await redis_client.set("load_config", json.dumps(load_config))
    return {"status": "started"}

@app.post("/api/load/stop")
async def stop_load_test():
    """Stop load test"""
    load_config = {"enabled": False}
    await redis_client.set("load_config", json.dumps(load_config))
    return {"status": "stopped"}

@app.post("/api/backend/latency/{latency}")
async def set_backend_latency(latency: float):
    """Configure backend latency via gateway"""
    try:
        import httpx
        async with httpx.AsyncClient() as client:
            response = await client.post(f"http://backend-service:8001/config/latency/{latency}")
            if response.status_code == 200:
                logger.info("Backend latency configured", latency=latency)
                return response.json()
            else:
                logger.error("Failed to configure backend latency", status_code=response.status_code)
                return {"error": "Failed to configure backend latency"}
    except Exception as e:
        logger.error("Error configuring backend latency", error=str(e))
        return {"error": f"Error configuring backend latency: {str(e)}"}

@app.post("/api/backend/errors/{rate}")
async def set_backend_error_rate(rate: float):
    """Configure backend error rate via gateway"""
    try:
        import httpx
        async with httpx.AsyncClient() as client:
            response = await client.post(f"http://backend-service:8001/config/error_rate/{rate}")
            if response.status_code == 200:
                logger.info("Backend error rate configured", rate=rate)
                return response.json()
            else:
                logger.error("Failed to configure backend error rate", status_code=response.status_code)
                return {"error": "Failed to configure backend error rate"}
    except Exception as e:
        logger.error("Error configuring backend error rate", error=str(e))
        return {"error": f"Error configuring backend error rate: {str(e)}"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=3000)
