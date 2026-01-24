#!/bin/bash

set -e

echo "=========================================="
echo "Connection Exhaustion Demo Setup"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check for required tools
echo -e "${BLUE}Checking dependencies...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Docker is required but not installed.${NC}" >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo -e "${RED}Docker Compose is required but not installed.${NC}" >&2; exit 1; }

# Create directory structure
echo -e "${BLUE}Creating directory structure...${NC}"
mkdir -p backend frontend nginx haproxy monitoring client-simulator

# Create backend application (Go)
echo -e "${BLUE}Creating backend application...${NC}"
cat > backend/main.go << 'EOF'
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

type Stats struct {
	ActiveConnections int64     `json:"active_connections"`
	TotalRequests     int64     `json:"total_requests"`
	SuccessRequests   int64     `json:"success_requests"`
	FailedRequests    int64     `json:"failed_requests"`
	AvgResponseTime   float64   `json:"avg_response_time_ms"`
	Uptime            float64   `json:"uptime_seconds"`
	MaxConnections    int       `json:"max_connections"`
	StartTime         time.Time `json:"-"`
}

var (
	stats = &Stats{
		MaxConnections: 100,
		StartTime:      time.Now(),
	}
	connectionSemaphore chan struct{}
	responseTimes       []float64
	responseTimeMutex   sync.Mutex
)

func init() {
	connectionSemaphore = make(chan struct{}, stats.MaxConnections)
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	startTime := time.Now()
	
	select {
	case connectionSemaphore <- struct{}{}:
		defer func() { <-connectionSemaphore }()
		atomic.AddInt64(&stats.ActiveConnections, 1)
		defer atomic.AddInt64(&stats.ActiveConnections, -1)
		
		atomic.AddInt64(&stats.TotalRequests, 1)
		
		// Read body slowly to simulate processing
		buf := make([]byte, 1024)
		totalRead := 0
		for {
			n, err := r.Body.Read(buf)
			totalRead += n
			if err != nil {
				break
			}
			time.Sleep(10 * time.Millisecond)
		}
		r.Body.Close()
		
		duration := time.Since(startTime).Milliseconds()
		
		responseTimeMutex.Lock()
		responseTimes = append(responseTimes, float64(duration))
		if len(responseTimes) > 1000 {
			responseTimes = responseTimes[1:]
		}
		responseTimeMutex.Unlock()
		
		atomic.AddInt64(&stats.SuccessRequests, 1)
		
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":       "success",
			"bytes_read":   totalRead,
			"duration_ms":  duration,
			"worker_id":    fmt.Sprintf("worker-%d", atomic.LoadInt64(&stats.ActiveConnections)),
		})
		
	default:
		atomic.AddInt64(&stats.TotalRequests, 1)
		atomic.AddInt64(&stats.FailedRequests, 1)
		
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "error",
			"error":  "Connection pool exhausted",
		})
	}
}

func handleStats(w http.ResponseWriter, r *http.Request) {
	responseTimeMutex.Lock()
	var avgTime float64
	if len(responseTimes) > 0 {
		sum := 0.0
		for _, t := range responseTimes {
			sum += t
		}
		avgTime = sum / float64(len(responseTimes))
	}
	responseTimeMutex.Unlock()
	
	stats.AvgResponseTime = avgTime
	stats.Uptime = time.Since(stats.StartTime).Seconds()
	
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(stats)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	
	http.HandleFunc("/api/upload", handleRequest)
	http.HandleFunc("/api/stats", handleStats)
	http.HandleFunc("/health", handleHealth)
	
	log.Printf("Backend server starting on port %s (max connections: %d)", port, stats.MaxConnections)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
EOF

cat > backend/Dockerfile << 'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go mod init backend && go build -o server main.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/server .
EXPOSE 8080
CMD ["./server"]
EOF

# Create client simulator (Python)
echo -e "${BLUE}Creating slow client simulator...${NC}"
cat > client-simulator/simulator.py << 'EOF'
import asyncio
import aiohttp
import time
import random
import json
from datetime import datetime

class SlowClientSimulator:
    def __init__(self, target_url, num_clients=50, slow_ratio=0.7):
        self.target_url = target_url
        self.num_clients = num_clients
        self.slow_ratio = slow_ratio
        self.stats = {
            'total_sent': 0,
            'success': 0,
            'failed': 0,
            'timeouts': 0
        }
    
    async def send_slow_request(self, session, client_id):
        """Simulate a slow 3G client uploading data"""
        data_size = random.randint(50000, 200000)
        chunk_size = random.randint(500, 2000)
        
        async def data_generator():
            sent = 0
            while sent < data_size:
                chunk = b'x' * min(chunk_size, data_size - sent)
                yield chunk
                sent += len(chunk)
                await asyncio.sleep(random.uniform(0.1, 0.5))
        
        start_time = time.time()
        try:
            async with session.post(
                f"{self.target_url}/api/upload",
                data=data_generator(),
                timeout=aiohttp.ClientTimeout(total=60)
            ) as resp:
                await resp.text()
                duration = time.time() - start_time
                
                if resp.status == 200:
                    self.stats['success'] += 1
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: SUCCESS ({duration:.1f}s)")
                else:
                    self.stats['failed'] += 1
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: FAILED {resp.status}")
                
                self.stats['total_sent'] += 1
                
        except asyncio.TimeoutError:
            self.stats['timeouts'] += 1
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: TIMEOUT")
        except Exception as e:
            self.stats['failed'] += 1
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: ERROR {str(e)}")
    
    async def send_fast_request(self, session, client_id):
        """Simulate a fast client"""
        data = b'x' * random.randint(1000, 5000)
        
        start_time = time.time()
        try:
            async with session.post(
                f"{self.target_url}/api/upload",
                data=data,
                timeout=aiohttp.ClientTimeout(total=10)
            ) as resp:
                await resp.text()
                duration = time.time() - start_time
                
                if resp.status == 200:
                    self.stats['success'] += 1
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: FAST SUCCESS ({duration:.2f}s)")
                else:
                    self.stats['failed'] += 1
                
                self.stats['total_sent'] += 1
                
        except Exception as e:
            self.stats['failed'] += 1
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: FAST ERROR {str(e)}")
    
    async def run_client(self, client_id):
        """Run a single client that sends requests continuously"""
        async with aiohttp.ClientSession() as session:
            while True:
                if random.random() < self.slow_ratio:
                    await self.send_slow_request(session, client_id)
                else:
                    await self.send_fast_request(session, client_id)
                
                await asyncio.sleep(random.uniform(1, 3))
    
    async def print_stats(self):
        """Periodically print statistics"""
        while True:
            await asyncio.sleep(10)
            print(f"\n{'='*60}")
            print(f"STATISTICS:")
            print(f"  Total Requests: {self.stats['total_sent']}")
            print(f"  Success: {self.stats['success']}")
            print(f"  Failed: {self.stats['failed']}")
            print(f"  Timeouts: {self.stats['timeouts']}")
            print(f"  Success Rate: {(self.stats['success']/max(1, self.stats['total_sent'])*100):.1f}%")
            print(f"{'='*60}\n")
    
    async def run(self):
        """Start all clients"""
        print(f"Starting {self.num_clients} clients ({int(self.slow_ratio*100)}% slow)...")
        print(f"Target: {self.target_url}")
        
        tasks = [
            self.run_client(i) for i in range(self.num_clients)
        ]
        tasks.append(self.print_stats())
        
        await asyncio.gather(*tasks)

if __name__ == "__main__":
    import sys
    
    target = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"
    num_clients = int(sys.argv[2]) if len(sys.argv) > 2 else 50
    
    simulator = SlowClientSimulator(target, num_clients=num_clients)
    asyncio.run(simulator.run())
EOF

cat > client-simulator/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install aiohttp
COPY simulator.py .
CMD ["python", "simulator.py", "http://haproxy:8080", "50"]
EOF

# Create Nginx L7 configuration
echo -e "${BLUE}Creating Nginx L7 load balancer config...${NC}"
cat > nginx/nginx.conf << 'EOF'
events {
    worker_connections 10000;
}

http {
    upstream backend {
        server backend:8080 max_conns=100;
        keepalive 32;
    }
    
    server {
        listen 9090;
        
        client_body_timeout 30s;
        client_header_timeout 10s;
        client_max_body_size 10M;
        
        location / {
            proxy_pass http://backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_buffering on;
            proxy_request_buffering on;
            proxy_connect_timeout 5s;
            proxy_send_timeout 10s;
            proxy_read_timeout 10s;
        }
        
        location /api/stats {
            proxy_pass http://backend/api/stats;
            add_header Access-Control-Allow-Origin *;
        }
    }
}
EOF

cat > nginx/Dockerfile << 'EOF'
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 9090
EOF

# Create HAProxy L4 configuration
echo -e "${BLUE}Creating HAProxy L4 load balancer config...${NC}"
cat > haproxy/haproxy.cfg << 'EOF'
global
    maxconn 10000
    log stdout format raw local0

defaults
    mode tcp
    timeout connect 5s
    timeout client 60s
    timeout server 60s
    log global

frontend l4_frontend
    bind *:8080
    default_backend backend_servers

backend backend_servers
    server backend1 backend:8080 maxconn 100
EOF

cat > haproxy/Dockerfile << 'EOF'
FROM haproxy:2.8-alpine
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
EXPOSE 8080
EOF

# Create monitoring dashboard
echo -e "${BLUE}Creating web dashboard...${NC}"
cat > frontend/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Connection Exhaustion Demo - SystemDRD</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .header {
            text-align: center;
            color: white;
            margin-bottom: 30px;
            padding: 20px;
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 15px;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.2);
        }
        
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }
        
        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 40px rgba(0, 0, 0, 0.3);
        }
        
        .card h3 {
            color: #667eea;
            margin-bottom: 15px;
            font-size: 1.3em;
            border-bottom: 2px solid #667eea;
            padding-bottom: 10px;
        }
        
        .metric {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 0;
            border-bottom: 1px solid #f0f0f0;
        }
        
        .metric:last-child {
            border-bottom: none;
        }
        
        .metric-label {
            color: #666;
            font-size: 0.95em;
        }
        
        .metric-value {
            font-size: 1.5em;
            font-weight: bold;
            color: #333;
        }
        
        .status-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: bold;
        }
        
        .status-healthy {
            background: #d4edda;
            color: #155724;
        }
        
        .status-warning {
            background: #fff3cd;
            color: #856404;
        }
        
        .status-critical {
            background: #f8d7da;
            color: #721c24;
        }
        
        .chart-container {
            grid-column: 1 / -1;
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0, 0, 0, 0.2);
            height: 400px;
        }
        
        .progress-bar {
            width: 100%;
            height: 30px;
            background: #f0f0f0;
            border-radius: 15px;
            overflow: hidden;
            margin-top: 10px;
        }
        
        .progress-fill {
            height: 100%;
            background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
            transition: width 0.5s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
        }
        
        .alert {
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 20px;
            font-weight: 500;
        }
        
        .alert-danger {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
        
        .alert-warning {
            background: #fff3cd;
            color: #856404;
            border: 1px solid #ffeaa7;
        }
        
        .timestamp {
            text-align: center;
            color: white;
            margin-top: 20px;
            opacity: 0.8;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔌 Connection Exhaustion Demo</h1>
            <p>Real-time monitoring of L4 vs L7 load balancing behavior</p>
        </div>
        
        <div id="alerts"></div>
        
        <div class="grid">
            <div class="card">
                <h3>L4 HAProxy (Direct)</h3>
                <div class="metric">
                    <span class="metric-label">Active Connections</span>
                    <span class="metric-value" id="l4-connections">-</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Total Requests</span>
                    <span class="metric-value" id="l4-total">-</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Success Rate</span>
                    <span class="metric-value" id="l4-success-rate">-</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Avg Response Time</span>
                    <span class="metric-value" id="l4-response-time">-</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill" id="l4-progress" style="width: 0%">0%</div>
                </div>
            </div>
            
            <div class="card">
                <h3>Backend Server</h3>
                <div class="metric">
                    <span class="metric-label">Status</span>
                    <span class="status-badge status-healthy" id="backend-status">Healthy</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Max Connections</span>
                    <span class="metric-value" id="max-connections">100</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Failed Requests</span>
                    <span class="metric-value" id="failed-requests">-</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Uptime</span>
                    <span class="metric-value" id="uptime">-</span>
                </div>
            </div>
            
            <div class="card">
                <h3>L7 Nginx (Buffered)</h3>
                <div class="metric">
                    <span class="metric-label">Status</span>
                    <span class="status-badge status-healthy">Available</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Connection Mode</span>
                    <span class="metric-value" style="font-size: 1em;">Buffered</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Backend Reuse</span>
                    <span class="metric-value" style="font-size: 1em;">Enabled</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Port</span>
                    <span class="metric-value">9090</span>
                </div>
                <div style="margin-top: 15px; padding: 10px; background: #d4edda; border-radius: 5px; color: #155724; font-size: 0.9em;">
                    ✓ Switch clients to :9090 to see improvement
                </div>
            </div>
        </div>
        
        <div class="chart-container">
            <canvas id="connectionChart"></canvas>
        </div>
        
        <div class="timestamp" id="timestamp">Last updated: -</div>
    </div>
    
    <script>
        const maxConnections = 100;
        const chartData = {
            labels: [],
            datasets: [{
                label: 'Active Connections',
                data: [],
                borderColor: '#667eea',
                backgroundColor: 'rgba(102, 126, 234, 0.1)',
                borderWidth: 3,
                fill: true,
                tension: 0.4
            }]
        };
        
        const ctx = document.getElementById('connectionChart').getContext('2d');
        const chart = new Chart(ctx, {
            type: 'line',
            data: chartData,
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        display: true,
                        position: 'top',
                    },
                    title: {
                        display: true,
                        text: 'Connection Count Over Time',
                        font: {
                            size: 18
                        }
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        max: maxConnections + 10,
                        ticks: {
                            font: {
                                size: 12
                            }
                        }
                    },
                    x: {
                        ticks: {
                            font: {
                                size: 12
                            }
                        }
                    }
                },
                annotation: {
                    annotations: [{
                        type: 'line',
                        mode: 'horizontal',
                        scaleID: 'y',
                        value: maxConnections,
                        borderColor: '#dc2626',
                        borderWidth: 2,
                        label: {
                            enabled: true,
                            content: 'Connection Limit'
                        }
                    }]
                }
            }
        });
        
        async function fetchStats() {
            try {
                const response = await fetch('http://localhost:8080/api/stats');
                const data = await response.json();
                
                document.getElementById('l4-connections').textContent = data.active_connections;
                document.getElementById('l4-total').textContent = data.total_requests;
                
                const successRate = ((data.success_requests / Math.max(1, data.total_requests)) * 100).toFixed(1);
                document.getElementById('l4-success-rate').textContent = successRate + '%';
                document.getElementById('l4-response-time').textContent = data.avg_response_time_ms.toFixed(0) + 'ms';
                document.getElementById('failed-requests').textContent = data.failed_requests;
                document.getElementById('uptime').textContent = Math.floor(data.uptime) + 's';
                
                const utilizationPct = (data.active_connections / maxConnections) * 100;
                document.getElementById('l4-progress').style.width = utilizationPct + '%';
                document.getElementById('l4-progress').textContent = utilizationPct.toFixed(0) + '%';
                
                if (utilizationPct > 90) {
                    document.getElementById('l4-progress').style.background = 'linear-gradient(90deg, #dc2626 0%, #991b1b 100%)';
                    document.getElementById('backend-status').className = 'status-badge status-critical';
                    document.getElementById('backend-status').textContent = 'Critical';
                    showAlert('danger', 'CRITICAL: Connection pool nearly exhausted! (' + data.active_connections + '/' + maxConnections + ')');
                } else if (utilizationPct > 70) {
                    document.getElementById('l4-progress').style.background = 'linear-gradient(90deg, #f59e0b 0%, #d97706 100%)';
                    document.getElementById('backend-status').className = 'status-badge status-warning';
                    document.getElementById('backend-status').textContent = 'Warning';
                    showAlert('warning', 'WARNING: High connection usage (' + data.active_connections + '/' + maxConnections + ')');
                } else {
                    document.getElementById('l4-progress').style.background = 'linear-gradient(90deg, #667eea 0%, #764ba2 100%)';
                    document.getElementById('backend-status').className = 'status-badge status-healthy';
                    document.getElementById('backend-status').textContent = 'Healthy';
                    clearAlerts();
                }
                
                const now = new Date().toLocaleTimeString();
                chartData.labels.push(now);
                chartData.datasets[0].data.push(data.active_connections);
                
                if (chartData.labels.length > 20) {
                    chartData.labels.shift();
                    chartData.datasets[0].data.shift();
                }
                
                chart.update();
                
                document.getElementById('timestamp').textContent = 'Last updated: ' + new Date().toLocaleString();
                
            } catch (error) {
                console.error('Error fetching stats:', error);
            }
        }
        
        function showAlert(type, message) {
            const alertDiv = document.getElementById('alerts');
            const alertClass = type === 'danger' ? 'alert-danger' : 'alert-warning';
            
            if (!alertDiv.querySelector('.alert')) {
                alertDiv.innerHTML = `<div class="alert ${alertClass}">${message}</div>`;
            }
        }
        
        function clearAlerts() {
            document.getElementById('alerts').innerHTML = '';
        }
        
        fetchStats();
        setInterval(fetchStats, 2000);
    </script>
</body>
</html>
EOF

cat > frontend/Dockerfile << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
EOF

# Create docker-compose file
echo -e "${BLUE}Creating docker-compose configuration...${NC}"
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  backend:
    build: ./backend
    container_name: connection_demo_backend
    environment:
      - PORT=8080
    ports:
      - "8081:8080"
    networks:
      - demo-network
    restart: unless-stopped
  
  haproxy:
    build: ./haproxy
    container_name: connection_demo_haproxy_l4
    ports:
      - "8080:8080"
    depends_on:
      - backend
    networks:
      - demo-network
    restart: unless-stopped
  
  nginx:
    build: ./nginx
    container_name: connection_demo_nginx_l7
    ports:
      - "9090:9090"
    depends_on:
      - backend
    networks:
      - demo-network
    restart: unless-stopped
  
  frontend:
    build: ./frontend
    container_name: connection_demo_dashboard
    ports:
      - "3000:80"
    networks:
      - demo-network
    restart: unless-stopped
  
  client-simulator:
    build: ./client-simulator
    container_name: connection_demo_clients
    depends_on:
      - haproxy
      - backend
    networks:
      - demo-network
    restart: unless-stopped

networks:
  demo-network:
    driver: bridge
EOF

# Build and start services
echo -e "${GREEN}Building Docker images...${NC}"
docker-compose build

echo -e "${GREEN}Starting services...${NC}"
docker-compose up -d

echo ""
echo -e "${GREEN}=========================================="
echo "Demo is ready!"
echo "=========================================="
echo -e "${NC}"
echo -e "${BLUE}Access the dashboard:${NC}"
echo -e "  ${GREEN}http://localhost:3000${NC}"
echo ""
echo -e "${BLUE}Endpoints:${NC}"
echo -e "  L4 HAProxy (Direct):    ${YELLOW}http://localhost:8080${NC}"
echo -e "  L7 Nginx (Buffered):    ${YELLOW}http://localhost:9090${NC}"
echo -e "  Backend (Direct):       ${YELLOW}http://localhost:8081${NC}"
echo ""
echo -e "${BLUE}To test manually:${NC}"
echo -e "  # L4 (will see connection exhaustion)"
echo -e "  ${YELLOW}curl -X POST http://localhost:8080/api/upload -d @largefile.txt${NC}"
echo ""
echo -e "  # L7 (handles slow clients better)"
echo -e "  ${YELLOW}curl -X POST http://localhost:9090/api/upload -d @largefile.txt${NC}"
echo ""
echo -e "${BLUE}View logs:${NC}"
echo -e "  ${YELLOW}docker-compose logs -f client-simulator${NC}"
echo -e "  ${YELLOW}docker-compose logs -f backend${NC}"
echo ""
echo -e "${BLUE}To see the difference:${NC}"
echo -e "  1. Watch the dashboard at http://localhost:3000"
echo -e "  2. See connections pile up with L4 (port 8080)"
echo -e "  3. Edit client-simulator to use port 9090 (L7)"
echo -e "  4. Rebuild: ${YELLOW}docker-compose up -d --build client-simulator${NC}"
echo -e "  5. Observe how L7 prevents exhaustion"
echo ""
echo -e "${GREEN}Demo is running! Press Ctrl+C in logs to detach.${NC}"
echo -e "${RED}Run ./cleanup.sh to stop and remove all containers.${NC}"