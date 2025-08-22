import asyncio
import aiohttp
import json
import time
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, Response
from fastapi.staticfiles import StaticFiles
import uvicorn

app = FastAPI(title="Cascade Monitor Dashboard")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

@app.get("/favicon.ico")
async def favicon():
    """Serve a simple favicon to prevent 404 errors"""
    return Response(content="", media_type="image/x-icon")

@app.get("/robots.txt")
async def robots():
    """Serve robots.txt to prevent 404 errors"""
    return Response(content="User-agent: *\nDisallow: /", media_type="text/plain")

@app.get("/", response_class=HTMLResponse)
async def dashboard():
    return """
<!DOCTYPE html>
<html>
<head>
    <title>Cascading Failures Monitor</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui; margin: 0; padding: 20px; background: #f5f7fa; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { text-align: center; margin-bottom: 30px; }
        .services { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .service { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .service.healthy { border-left: 4px solid #10b981; }
        .service.degraded { border-left: 4px solid #f59e0b; }
        .service.failed { border-left: 4px solid #ef4444; }
        .controls { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .btn { padding: 10px 20px; margin: 5px; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; }
        .btn-danger { background: #ef4444; color: white; }
        .btn-success { background: #10b981; color: white; }
        .btn-primary { background: #3b82f6; color: white; }
        .circuit-state { display: inline-block; padding: 4px 8px; border-radius: 4px; font-size: 12px; font-weight: bold; }
        .circuit-closed { background: #10b981; color: white; }
        .circuit-open { background: #ef4444; color: white; }
        .circuit-half-open { background: #f59e0b; color: white; }
        .metrics { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 10px; margin-top: 15px; }
        .metric { background: #f8fafc; padding: 10px; border-radius: 4px; }
        .logs { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); max-height: 300px; overflow-y: auto; }
        .log-entry { padding: 5px 0; border-bottom: 1px solid #e5e7eb; font-family: monospace; font-size: 12px; }
        .log-error { color: #ef4444; }
        .log-warning { color: #f59e0b; }
        .log-success { color: #10b981; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔗 Cascading Failures Detection & Prevention</h1>
            <p>Real-time monitoring of service dependencies and circuit breaker states</p>
        </div>
        
        <div class="controls">
            <h3>Failure Simulation Controls</h3>
            <button class="btn btn-danger" onclick="triggerFailure()">🚨 Trigger Auth Failure</button>
            <button class="btn btn-success" onclick="recoverServices()">🔄 Recover All Services</button>
            <button class="btn btn-primary" onclick="loadTest()">📈 Generate Load</button>
        </div>
        
        <div class="services" id="services">
            <!-- Services will be populated by JavaScript -->
        </div>
        
        <div class="logs">
            <h3>🔍 Cascade Detection Logs</h3>
            <div id="logs"></div>
        </div>
    </div>

    <script>
        let logCount = 0;
        const maxLogs = 50;

        async function updateServices() {
            try {
                const services = ['auth-service:8001', 'user-service:8002', 'order-service:8003'];
                const servicesContainer = document.getElementById('services');
                servicesContainer.innerHTML = '';
                
                for (const service of services) {
                    const [name, port] = service.split(':');
                    const serviceName = name.replace('-service', '');
                    
                    try {
                        const response = await fetch(`http://localhost:${port}/metrics`);
                        const data = await response.json();
                        
                        const healthResponse = await fetch(`http://localhost:${port}/health`);
                        const healthData = await healthResponse.json();
                        
                        servicesContainer.innerHTML += createServiceCard(serviceName, data, healthData);
                    } catch (error) {
                        servicesContainer.innerHTML += createServiceCard(serviceName, {error: error.message}, {status: 'unhealthy'});
                    }
                }
            } catch (error) {
                addLog(`Error updating services: ${error.message}`, 'error');
            }
        }

        function createServiceCard(name, metrics, health) {
            const status = health.status === 'healthy' ? 'healthy' : 'failed';
            const circuitState = metrics.circuit_state || 'unknown';
            
            return `
                <div class="service ${status}">
                    <h3>${name.charAt(0).toUpperCase() + name.slice(1)} Service</h3>
                    <div class="circuit-state circuit-${circuitState.replace('_', '-')}">${circuitState.toUpperCase()}</div>
                    <div class="metrics">
                        <div class="metric">
                            <strong>Status</strong><br>
                            ${health.status || 'unknown'}
                        </div>
                        <div class="metric">
                            <strong>Failures</strong><br>
                            ${metrics.circuit_failures || 0}
                        </div>
                        ${metrics.dependencies ? `
                        <div class="metric">
                            <strong>Dependencies</strong><br>
                            ${Object.entries(metrics.dependencies).map(([k,v]) => `${k}: ${v}`).join('<br>')}
                        </div>
                        ` : ''}
                    </div>
                </div>
            `;
        }

        async function triggerFailure() {
            try {
                await fetch('http://localhost:8001/control/trigger_failure', {method: 'POST'});
                addLog('🚨 Auth service failure triggered - cascade detection active', 'error');
            } catch (error) {
                addLog(`Failed to trigger failure: ${error.message}`, 'error');
            }
        }

        async function recoverServices() {
            try {
                await fetch('http://localhost:8001/control/recover', {method: 'POST'});
                addLog('🔄 All services recovering - monitoring cascade healing', 'success');
            } catch (error) {
                addLog(`Failed to recover services: ${error.message}`, 'error');
            }
        }

        async function loadTest() {
            addLog('📈 Starting load test - simulating user traffic', 'warning');
            
            for (let i = 0; i < 20; i++) {
                setTimeout(async () => {
                    try {
                        await fetch('http://localhost:8003/order/create', {
                            method: 'POST',
                            headers: {'Content-Type': 'application/json'},
                            body: JSON.stringify({
                                user_id: `user_${i}`,
                                items: ['item1', 'item2'],
                                total: 99.99
                            })
                        });
                    } catch (error) {
                        // Expected during cascade
                    }
                }, i * 500);
            }
        }

        function addLog(message, type = 'info') {
            const logs = document.getElementById('logs');
            const entry = document.createElement('div');
            entry.className = `log-entry log-${type}`;
            entry.innerHTML = `[${new Date().toLocaleTimeString()}] ${message}`;
            logs.insertBefore(entry, logs.firstChild);
            
            // Keep only recent logs
            logCount++;
            if (logCount > maxLogs) {
                logs.removeChild(logs.lastChild);
            }
        }

        // Update every 2 seconds
        setInterval(updateServices, 2000);
        updateServices();
        
        // Initial log
        addLog('🔍 Cascade monitoring system initialized', 'success');
    </script>
</body>
</html>
    """

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")
