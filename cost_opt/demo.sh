#!/bin/bash

# Cost Optimization in Scaled Systems - Demo Script
# System Design Interview Roadmap - Issue #106

set -e

PROJECT_NAME="cost-optimization-demo"
DEMO_DIR="$(pwd)/$PROJECT_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is required but not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is required but not installed. Please install Docker Compose first."
        exit 1
    fi
    
    log "Prerequisites check passed!"
}

# Create project structure
create_project_structure() {
    log "Creating project structure..."
    
    mkdir -p "$DEMO_DIR"/{src,static/css,static/js,templates,tests,docker}
    cd "$DEMO_DIR"
    
    log "Project structure created at: $DEMO_DIR"
}

# Create requirements.txt
create_requirements() {
    log "Creating requirements.txt..."
    
    cat > requirements.txt << 'EOF'
fastapi==0.104.0
uvicorn[standard]==0.24.0
jinja2==3.1.2
python-multipart==0.0.6
aiofiles==23.2.0
websockets==12.0
psutil==5.9.6
numpy==1.24.4
asyncio==3.4.3
datetime
pydantic==2.5.0
prometheus-client==0.19.0
asyncio-mqtt==0.16.1
httpx==0.25.2
EOF

    log "Requirements file created!"
}

# Create main application
create_main_app() {
    log "Creating main application..."
    
    cat > src/main.py << 'EOF'
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
EOF

    log "Main application created!"
}

# Create HTML template
create_template() {
    log "Creating HTML template..."
    
    cat > templates/dashboard.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Cost Optimization Dashboard</title>
    <link rel="stylesheet" href="/static/css/style.css">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="container">
        <header class="header">
            <h1>🏗️ Cost Optimization Dashboard</h1>
            <p class="subtitle">Real-time monitoring and optimization recommendations</p>
        </header>

        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-header">
                    <h3>💰 Current Cost</h3>
                    <span class="metric-value" id="current-cost">$0.00/hr</span>
                </div>
                <div class="metric-chart">
                    <canvas id="cost-chart"></canvas>
                </div>
            </div>

            <div class="metric-card">
                <div class="metric-header">
                    <h3>🖥️ CPU Usage</h3>
                    <span class="metric-value" id="cpu-usage">0%</span>
                </div>
                <div class="metric-chart">
                    <canvas id="cpu-chart"></canvas>
                </div>
            </div>

            <div class="metric-card">
                <div class="metric-header">
                    <h3>🧠 Memory Usage</h3>
                    <span class="metric-value" id="memory-usage">0%</span>
                </div>
                <div class="metric-chart">
                    <canvas id="memory-chart"></canvas>
                </div>
            </div>

            <div class="metric-card">
                <div class="metric-header">
                    <h3>🌐 Network I/O</h3>
                    <span class="metric-value" id="network-io">0 MB/s</span>
                </div>
                <div class="metric-chart">
                    <canvas id="network-chart"></canvas>
                </div>
            </div>
        </div>

        <div class="optimization-section">
            <div class="recommendations-card">
                <h3>🎯 Optimization Recommendations</h3>
                <div id="recommendations-list">
                    <div class="loading">Loading recommendations...</div>
                </div>
            </div>

            <div class="savings-card">
                <h3>💡 Projected Savings</h3>
                <div class="savings-summary">
                    <div class="savings-item">
                        <span class="label">Current Monthly Cost:</span>
                        <span class="value" id="monthly-cost">$0.00</span>
                    </div>
                    <div class="savings-item">
                        <span class="label">Projected Savings:</span>
                        <span class="value" id="projected-savings">$0.00</span>
                    </div>
                    <div class="savings-item">
                        <span class="label">Savings Percentage:</span>
                        <span class="value" id="savings-percentage">0%</span>
                    </div>
                </div>
            </div>
        </div>

        <div class="status-section">
            <div class="status-indicator">
                <span id="connection-status" class="status-connected">● Connected</span>
                <span id="last-update">Last update: Never</span>
            </div>
        </div>
    </div>

    <script src="/static/js/dashboard.js"></script>
</body>
</html>
EOF

    log "HTML template created!"
}

# Create CSS styles
create_styles() {
    log "Creating CSS styles..."
    
    cat > static/css/style.css << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    color: #333;
}

.container {
    max-width: 1400px;
    margin: 0 auto;
    padding: 20px;
}

.header {
    text-align: center;
    margin-bottom: 30px;
    color: white;
}

.header h1 {
    font-size: 2.5rem;
    margin-bottom: 10px;
    text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
}

.subtitle {
    font-size: 1.1rem;
    opacity: 0.9;
}

.metrics-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: 20px;
    margin-bottom: 30px;
}

.metric-card {
    background: white;
    border-radius: 15px;
    padding: 20px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.1);
    transition: transform 0.3s ease, box-shadow 0.3s ease;
}

.metric-card:hover {
    transform: translateY(-5px);
    box-shadow: 0 15px 40px rgba(0,0,0,0.15);
}

.metric-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 15px;
}

.metric-header h3 {
    font-size: 1.1rem;
    color: #555;
}

.metric-value {
    font-size: 1.5rem;
    font-weight: bold;
    color: #2196F3;
}

.metric-chart {
    height: 200px;
    position: relative;
}

.optimization-section {
    display: grid;
    grid-template-columns: 2fr 1fr;
    gap: 20px;
    margin-bottom: 30px;
}

.recommendations-card, .savings-card {
    background: white;
    border-radius: 15px;
    padding: 25px;
    box-shadow: 0 10px 30px rgba(0,0,0,0.1);
}

.recommendations-card h3, .savings-card h3 {
    margin-bottom: 20px;
    color: #333;
    font-size: 1.3rem;
}

.recommendation-item {
    background: #f8f9ff;
    border-left: 4px solid #2196F3;
    padding: 15px;
    margin-bottom: 15px;
    border-radius: 8px;
    transition: background-color 0.3s ease;
}

.recommendation-item:hover {
    background: #e3f2fd;
}

.recommendation-type {
    font-weight: bold;
    color: #1976D2;
    text-transform: uppercase;
    font-size: 0.8rem;
    margin-bottom: 5px;
}

.recommendation-description {
    margin-bottom: 10px;
    line-height: 1.5;
}

.recommendation-meta {
    display: flex;
    justify-content: space-between;
    font-size: 0.9rem;
    color: #666;
}

.savings-summary {
    space-y: 15px;
}

.savings-item {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 0;
    border-bottom: 1px solid #eee;
}

.savings-item:last-child {
    border-bottom: none;
}

.savings-item .label {
    color: #666;
    font-weight: 500;
}

.savings-item .value {
    font-weight: bold;
    color: #4CAF50;
    font-size: 1.1rem;
}

.status-section {
    text-align: center;
    padding: 20px;
    background: rgba(255, 255, 255, 0.1);
    border-radius: 15px;
    backdrop-filter: blur(10px);
}

.status-indicator {
    color: white;
    font-size: 0.9rem;
}

.status-connected {
    color: #4CAF50;
    font-weight: bold;
}

.status-disconnected {
    color: #f44336;
    font-weight: bold;
}

.loading {
    text-align: center;
    color: #666;
    font-style: italic;
}

@media (max-width: 768px) {
    .metrics-grid {
        grid-template-columns: 1fr;
    }
    
    .optimization-section {
        grid-template-columns: 1fr;
    }
    
    .header h1 {
        font-size: 2rem;
    }
}

.chart-container {
    position: relative;
    height: 200px;
    width: 100%;
}

.chart-container canvas {
    position: absolute;
    top: 0;
    left: 0;
}
EOF

    log "CSS styles created!"
}

# Create JavaScript
create_javascript() {
    log "Creating JavaScript..."
    
    cat > static/js/dashboard.js << 'EOF'
class CostOptimizationDashboard {
    constructor() {
        this.socket = null;
        this.charts = {};
        this.metricsHistory = [];
        this.maxHistoryLength = 50;
        
        this.initializeCharts();
        this.connectWebSocket();
        this.loadInitialData();
        
        // Update recommendations and savings every 10 seconds
        setInterval(() => {
            this.updateRecommendations();
            this.updateSavings();
        }, 10000);
    }
    
    initializeCharts() {
        const chartOptions = {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    display: false
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    grid: {
                        color: 'rgba(0,0,0,0.1)'
                    }
                },
                x: {
                    display: false
                }
            },
            elements: {
                point: {
                    radius: 0
                },
                line: {
                    tension: 0.4
                }
            }
        };
        
        // Cost chart
        this.charts.cost = new Chart(document.getElementById('cost-chart'), {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    data: [],
                    borderColor: '#FF6B6B',
                    backgroundColor: 'rgba(255, 107, 107, 0.1)',
                    fill: true
                }]
            },
            options: chartOptions
        });
        
        // CPU chart
        this.charts.cpu = new Chart(document.getElementById('cpu-chart'), {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    data: [],
                    borderColor: '#4ECDC4',
                    backgroundColor: 'rgba(78, 205, 196, 0.1)',
                    fill: true
                }]
            },
            options: {
                ...chartOptions,
                scales: {
                    ...chartOptions.scales,
                    y: {
                        ...chartOptions.scales.y,
                        max: 100
                    }
                }
            }
        });
        
        // Memory chart
        this.charts.memory = new Chart(document.getElementById('memory-chart'), {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    data: [],
                    borderColor: '#45B7D1',
                    backgroundColor: 'rgba(69, 183, 209, 0.1)',
                    fill: true
                }]
            },
            options: {
                ...chartOptions,
                scales: {
                    ...chartOptions.scales,
                    y: {
                        ...chartOptions.scales.y,
                        max: 100
                    }
                }
            }
        });
        
        // Network chart
        this.charts.network = new Chart(document.getElementById('network-chart'), {
            type: 'line',
            data: {
                labels: [],
                datasets: [{
                    data: [],
                    borderColor: '#96CEB4',
                    backgroundColor: 'rgba(150, 206, 180, 0.1)',
                    fill: true
                }]
            },
            options: chartOptions
        });
    }
    
    connectWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/ws/metrics`;
        
        this.socket = new WebSocket(wsUrl);
        
        this.socket.onopen = () => {
            console.log('WebSocket connected');
            this.updateConnectionStatus(true);
        };
        
        this.socket.onmessage = (event) => {
            const data = JSON.parse(event.data);
            this.updateMetrics(data);
        };
        
        this.socket.onclose = () => {
            console.log('WebSocket disconnected');
            this.updateConnectionStatus(false);
            // Attempt to reconnect after 5 seconds
            setTimeout(() => this.connectWebSocket(), 5000);
        };
        
        this.socket.onerror = (error) => {
            console.error('WebSocket error:', error);
            this.updateConnectionStatus(false);
        };
    }
    
    updateConnectionStatus(connected) {
        const statusElement = document.getElementById('connection-status');
        if (connected) {
            statusElement.textContent = '● Connected';
            statusElement.className = 'status-connected';
        } else {
            statusElement.textContent = '● Disconnected';
            statusElement.className = 'status-disconnected';
        }
    }
    
    updateMetrics(data) {
        // Update metric values
        document.getElementById('current-cost').textContent = `$${data.estimated_cost.toFixed(3)}/hr`;
        document.getElementById('cpu-usage').textContent = `${data.cpu_usage.toFixed(1)}%`;
        document.getElementById('memory-usage').textContent = `${data.memory_usage.toFixed(1)}%`;
        document.getElementById('network-io').textContent = `${data.network_io.toFixed(1)} MB/s`;
        
        // Update last update time
        document.getElementById('last-update').textContent = `Last update: ${new Date().toLocaleTimeString()}`;
        
        // Add to history
        this.metricsHistory.push(data);
        if (this.metricsHistory.length > this.maxHistoryLength) {
            this.metricsHistory.shift();
        }
        
        // Update charts
        this.updateCharts();
    }
    
    updateCharts() {
        const labels = this.metricsHistory.map((_, index) => index);
        
        // Update cost chart
        this.charts.cost.data.labels = labels;
        this.charts.cost.data.datasets[0].data = this.metricsHistory.map(m => m.estimated_cost);
        this.charts.cost.update('none');
        
        // Update CPU chart
        this.charts.cpu.data.labels = labels;
        this.charts.cpu.data.datasets[0].data = this.metricsHistory.map(m => m.cpu_usage);
        this.charts.cpu.update('none');
        
        // Update memory chart
        this.charts.memory.data.labels = labels;
        this.charts.memory.data.datasets[0].data = this.metricsHistory.map(m => m.memory_usage);
        this.charts.memory.update('none');
        
        // Update network chart
        this.charts.network.data.labels = labels;
        this.charts.network.data.datasets[0].data = this.metricsHistory.map(m => m.network_io);
        this.charts.network.update('none');
    }
    
    async updateRecommendations() {
        try {
            const response = await fetch('/api/recommendations');
            const recommendations = await response.json();
            
            const listElement = document.getElementById('recommendations-list');
            
            if (recommendations.length === 0) {
                listElement.innerHTML = '<div class="loading">No recommendations at this time</div>';
                return;
            }
            
            listElement.innerHTML = recommendations.map(rec => `
                <div class="recommendation-item">
                    <div class="recommendation-type">${rec.type.replace('_', ' ')}</div>
                    <div class="recommendation-description">${rec.description}</div>
                    <div class="recommendation-meta">
                        <span>Potential Savings: ${rec.potential_savings > 0 ? '+' : ''}${rec.potential_savings.toFixed(1)}%</span>
                        <span>Effort: ${rec.implementation_effort}</span>
                    </div>
                </div>
            `).join('');
            
        } catch (error) {
            console.error('Error updating recommendations:', error);
        }
    }
    
    async updateSavings() {
        try {
            const response = await fetch('/api/savings');
            const savings = await response.json();
            
            document.getElementById('monthly-cost').textContent = `$${savings.current_monthly_cost.toFixed(2)}`;
            document.getElementById('projected-savings').textContent = `$${savings.projected_savings.toFixed(2)}`;
            document.getElementById('savings-percentage').textContent = `${savings.savings_percentage.toFixed(1)}%`;
            
        } catch (error) {
            console.error('Error updating savings:', error);
        }
    }
    
    async loadInitialData() {
        try {
            // Load initial metrics history
            const historyResponse = await fetch('/api/history');
            const history = await historyResponse.json();
            this.metricsHistory = history;
            this.updateCharts();
            
            // Load initial recommendations and savings
            await this.updateRecommendations();
            await this.updateSavings();
            
        } catch (error) {
            console.error('Error loading initial data:', error);
        }
    }
}

// Initialize dashboard when page loads
document.addEventListener('DOMContentLoaded', () => {
    new CostOptimizationDashboard();
});
EOF

    log "JavaScript created!"
}

# Create Dockerfile
create_dockerfile() {
    log "Creating Dockerfile..."
    
    cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/
COPY static/ ./static/
COPY templates/ ./templates/

# Set Python path
ENV PYTHONPATH=/app/src

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/api/metrics || exit 1

# Run the application
CMD ["python", "src/main.py"]
EOF

    log "Dockerfile created!"
}

# Create docker-compose.yml
create_docker_compose() {
    log "Creating docker-compose.yml..."
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  cost-dashboard:
    build: .
    ports:
      - "8000:8000"
    environment:
      - PYTHONPATH=/app/src
    volumes:
      - ./src:/app/src
      - ./static:/app/static
      - ./templates:/app/templates
    healthcheck:
      test: ["CMD", "python", "-c", "import requests; requests.get('http://localhost:8000/api/metrics')"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    restart: unless-stopped

volumes:
  app_data:
EOF

    log "Docker Compose configuration created!"
}

# Create test file
create_tests() {
    log "Creating test file..."
    
    cat > tests/test_cost_optimization.py << 'EOF'
import pytest
import asyncio
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from main import CostTracker, ResourceMetrics

class TestCostTracker:
    def setup_method(self):
        """Set up test fixtures"""
        self.cost_tracker = CostTracker()
    
    def test_cost_tracker_initialization(self):
        """Test CostTracker initializes correctly"""
        assert self.cost_tracker.metrics_history == []
        assert len(self.cost_tracker.cost_per_hour) == 4
        assert len(self.cost_tracker.optimization_rules) == 3
    
    def test_get_current_metrics(self):
        """Test metrics collection"""
        metrics = self.cost_tracker.get_current_metrics()
        
        assert isinstance(metrics, ResourceMetrics)
        assert 0 <= metrics.cpu_usage <= 100
        assert 0 <= metrics.memory_usage <= 100
        assert metrics.network_io > 0
        assert metrics.disk_io > 0
        assert metrics.estimated_cost > 0
        assert len(self.cost_tracker.metrics_history) == 1
    
    def test_metrics_history_limit(self):
        """Test metrics history doesn't exceed limit"""
        # Generate more than 100 metrics
        for _ in range(105):
            self.cost_tracker.get_current_metrics()
        
        assert len(self.cost_tracker.metrics_history) == 100
    
    def test_optimization_recommendations(self):
        """Test optimization recommendations generation"""
        # Generate some metrics first
        for _ in range(10):
            self.cost_tracker.get_current_metrics()
        
        recommendations = self.cost_tracker.get_optimization_recommendations()
        
        assert isinstance(recommendations, list)
        assert len(recommendations) >= 2  # Should have at least storage and batch recommendations
        
        for rec in recommendations:
            assert hasattr(rec, 'type')
            assert hasattr(rec, 'description')
            assert hasattr(rec, 'potential_savings')
            assert hasattr(rec, 'implementation_effort')
    
    def test_projected_savings_calculation(self):
        """Test projected savings calculation"""
        # Generate some metrics
        for _ in range(30):
            self.cost_tracker.get_current_metrics()
        
        savings = self.cost_tracker.calculate_projected_savings()
        
        assert 'current_monthly_cost' in savings
        assert 'projected_savings' in savings
        assert 'savings_percentage' in savings
        assert savings['current_monthly_cost'] >= 0
        assert savings['projected_savings'] >= 0
        assert savings['savings_percentage'] >= 0

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
EOF

    log "Test file created!"
}

# Build and run the demo
build_and_run() {
    log "Building and running the demo..."
    
    # Build Docker images
    log "Building Docker image..."
    docker-compose build
    
    # Start services
    log "Starting services..."
    docker-compose up -d
    
    # Wait for services to be ready
    log "Waiting for services to be ready..."
    sleep 10
    
    # Check if service is running
    if curl -s http://localhost:8000/api/metrics > /dev/null; then
        log "✅ Demo is running successfully!"
        log "🌐 Access the dashboard at: http://localhost:8000"
        log "📊 The dashboard shows real-time cost optimization metrics and recommendations"
        log ""
        log "Demo Features:"
        log "- Real-time resource monitoring with cost calculation"
        log "- Dynamic optimization recommendations"
        log "- Projected savings analysis"
        log "- Interactive charts and live updates"
        log ""
        log "Next steps:"
        log "1. Open http://localhost:8000 in your browser"
        log "2. Watch the real-time metrics update"
        log "3. Review optimization recommendations"
        log "4. Observe how different resource usage patterns affect costs"
    else
        error "Demo failed to start properly. Check logs with: docker-compose logs"
    fi
}

# Run tests
run_tests() {
    log "Running tests..."
    
    docker-compose exec cost-dashboard python -m pytest tests/ -v
    
    if [ $? -eq 0 ]; then
        log "✅ All tests passed!"
    else
        warn "Some tests failed. Check the output above."
    fi
}

# Main execution
main() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "  Cost Optimization in Scaled Systems - Demo"
    echo "  System Design Interview Roadmap - Issue #106"
    echo "=================================================="
    echo -e "${NC}"
    
    check_prerequisites
    create_project_structure
    create_requirements
    create_main_app
    create_template
    create_styles
    create_javascript
    create_dockerfile
    create_docker_compose
    create_tests
    build_and_run
    
    log "Demo setup complete!"
    log ""
    log "🎯 Learning Objectives Demonstrated:"
    log "• Resource utilization monitoring and cost attribution"
    log "• Real-time optimization recommendation engine"
    log "• Cost-performance trade-off visualization"
    log "• Automated savings calculation and projection"
    log ""
    log "💡 Key Insights You'll Discover:"
    log "• How different resource usage patterns affect costs"
    log "• The importance of right-sizing infrastructure"
    log "• Optimization strategies for different workload types"
    log "• The economics of auto-scaling decisions"
    log ""
    log "🧪 Experiment with:"
    log "• Different load patterns and their cost implications"
    log "• Resource optimization recommendations"
    log "• Cost projection calculations"
    log "• Real-time monitoring and alerting"
    log ""
    log "To run tests: ./demo.sh test"
    log "To stop the demo: ./demo.sh cleanup"
}

# Handle command line arguments
case "${1:-}" in
    "test")
        run_tests
        ;;
    "cleanup")
        log "Cleaning up..."
        cd "$DEMO_DIR" 2>/dev/null || true
        docker-compose down -v 2>/dev/null || true
        cd .. && rm -rf "$DEMO_DIR" 2>/dev/null || true
        log "Cleanup complete!"
        ;;
    *)
        main
        ;;
esac