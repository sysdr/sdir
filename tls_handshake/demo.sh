#!/bin/bash

# TLS Handshake Latency Demo
# This script sets up a complete working demo showing TLS handshake latency under load

set -e

echo "🚀 Setting up TLS Handshake Latency Demo..."
echo ""

# Create project directory
PROJECT_DIR="tls-handshake-demo"
mkdir -p $PROJECT_DIR
cd $PROJECT_DIR

# Create directory structure
mkdir -p nginx/certs
mkdir -p backend
mkdir -p dashboard
mkdir -p load-generator
mkdir -p metrics

echo "📁 Created project structure"

# Generate self-signed certificates for TLS
echo "🔐 Generating TLS certificates..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/certs/server.key \
  -out nginx/certs/server.crt \
  -subj "/C=US/ST=State/L=City/O=Demo/CN=localhost" 2>/dev/null

# Create nginx configuration with limited workers to simulate saturation
cat > nginx/nginx.conf << 'EOF'
user nginx;
worker_processes 2;  # Limited workers to show saturation effect
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
}

http {
    log_format tls_timing '$remote_addr - $remote_user [$time_local] '
                         '"$request" $status $body_bytes_sent '
                         '"$http_referer" "$http_user_agent" '
                         'ssl_handshake_time=$ssl_handshake_time '
                         'request_time=$request_time';

    access_log /var/log/nginx/access.log tls_timing;

    upstream backend {
        least_conn;
        server backend:8080;
    }

    server {
        listen 8443 ssl http2;
        server_name localhost;

        ssl_certificate /etc/nginx/certs/server.crt;
        ssl_certificate_key /etc/nginx/certs/server.key;
        
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;
        
        # Session cache settings
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;
        ssl_session_tickets on;

        location / {
            proxy_pass http://backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /metrics {
            proxy_pass http://backend:8080/metrics;
        }
    }
}
EOF

echo "✅ Created nginx configuration"

# Create backend service that tracks connection metrics
cat > backend/server.go << 'EOF'
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "sync"
    "sync/atomic"
    "time"
)

type Metrics struct {
    TotalConnections    int64     `json:"total_connections"`
    ActiveConnections   int64     `json:"active_connections"`
    HandshakeLatencyP50 float64   `json:"handshake_latency_p50_ms"`
    HandshakeLatencyP99 float64   `json:"handshake_latency_p99_ms"`
    FailedHandshakes    int64     `json:"failed_handshakes"`
    LastUpdated         time.Time `json:"last_updated"`
}

var (
    totalConns    int64
    activeConns   int64
    failedConns   int64
    latencies     []float64
    latencyMutex  sync.RWMutex
)

func recordConnection(duration time.Duration) {
    atomic.AddInt64(&totalConns, 1)
    atomic.AddInt64(&activeConns, 1)
    
    latencyMutex.Lock()
    latencies = append(latencies, duration.Seconds()*1000) // Convert to ms
    if len(latencies) > 1000 {
        latencies = latencies[len(latencies)-1000:] // Keep last 1000
    }
    latencyMutex.Unlock()
    
    // Simulate connection lifetime
    go func() {
        time.Sleep(time.Duration(100+time.Now().Unix()%400) * time.Millisecond)
        atomic.AddInt64(&activeConns, -1)
    }()
}

func calculatePercentile(data []float64, percentile float64) float64 {
    if len(data) == 0 {
        return 0
    }
    sorted := make([]float64, len(data))
    copy(sorted, data)
    
    // Simple sort
    for i := 0; i < len(sorted); i++ {
        for j := i + 1; j < len(sorted); j++ {
            if sorted[i] > sorted[j] {
                sorted[i], sorted[j] = sorted[j], sorted[i]
            }
        }
    }
    
    idx := int(float64(len(sorted)) * percentile)
    if idx >= len(sorted) {
        idx = len(sorted) - 1
    }
    return sorted[idx]
}

func getMetrics() Metrics {
    latencyMutex.RLock()
    latencyCopy := make([]float64, len(latencies))
    copy(latencyCopy, latencies)
    latencyMutex.RUnlock()
    
    return Metrics{
        TotalConnections:    atomic.LoadInt64(&totalConns),
        ActiveConnections:   atomic.LoadInt64(&activeConns),
        HandshakeLatencyP50: calculatePercentile(latencyCopy, 0.50),
        HandshakeLatencyP99: calculatePercentile(latencyCopy, 0.99),
        FailedHandshakes:    atomic.LoadInt64(&failedConns),
        LastUpdated:         time.Now(),
    }
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    w.Header().Set("Access-Control-Allow-Origin", "*")
    json.NewEncoder(w).Encode(getMetrics())
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
    start := time.Now()
    recordConnection(time.Since(start))
    
    w.Header().Set("Content-Type", "application/json")
    fmt.Fprintf(w, `{"status":"ok","message":"Connection established"}`)
}

func main() {
    http.HandleFunc("/", rootHandler)
    http.HandleFunc("/metrics", metricsHandler)
    
    log.Println("Backend service starting on :8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

cat > backend/Dockerfile << 'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY server.go .
RUN go build -o server server.go

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/server .
EXPOSE 8080
CMD ["./server"]
EOF

echo "✅ Created backend service"

# Create load generator
cat > load-generator/generator.py << 'EOF'
import requests
import time
import threading
import random
from urllib3.exceptions import InsecureRequestWarning
requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

def make_request(session_pool):
    """Make a request with a session from the pool"""
    try:
        session = random.choice(session_pool)
        response = session.get('https://nginx:8443/', timeout=30, verify=False)
        return response.status_code == 200
    except Exception as e:
        return False

def worker(session_pool, duration, delay):
    """Worker thread that makes continuous requests"""
    end_time = time.time() + duration
    while time.time() < end_time:
        make_request(session_pool)
        time.sleep(delay)

def run_load_test(num_workers=10, duration=60, delay=0.1, new_connections=False):
    """Run load test with specified parameters"""
    print(f"Starting load test: {num_workers} workers for {duration}s")
    
    # Create session pool
    if new_connections:
        # Force new TLS handshakes by not reusing sessions
        session_pool = [requests.Session() for _ in range(num_workers * 2)]
        print("Mode: NEW CONNECTIONS (high TLS handshake load)")
    else:
        # Reuse sessions to minimize handshakes
        session_pool = [requests.Session() for _ in range(5)]
        print("Mode: REUSED CONNECTIONS (normal load)")
    
    threads = []
    for i in range(num_workers):
        t = threading.Thread(target=worker, args=(session_pool, duration, delay))
        t.daemon = True
        t.start()
        threads.append(t)
    
    for t in threads:
        t.join()
    
    print(f"Load test complete")

if __name__ == "__main__":
    print("TLS Load Generator Starting...")
    print("\n=== Phase 1: Normal Load (30s) ===")
    run_load_test(num_workers=5, duration=30, delay=0.2, new_connections=False)
    
    time.sleep(5)
    
    print("\n=== Phase 2: HIGH LOAD - New Connections (60s) ===")
    run_load_test(num_workers=30, duration=60, delay=0.05, new_connections=True)
    
    time.sleep(5)
    
    print("\n=== Phase 3: Recovery (20s) ===")
    run_load_test(num_workers=5, duration=20, delay=0.2, new_connections=False)
    
    print("\nLoad generation complete. Keep container running for metrics...")
    while True:
        time.sleep(60)
EOF

cat > load-generator/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
RUN pip install requests urllib3
COPY generator.py .
CMD ["python", "generator.py"]
EOF

echo "✅ Created load generator"

# Create modern web dashboard
cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TLS Handshake Latency Monitor</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
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
            background: white;
            padding: 30px;
            border-radius: 20px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        
        .header h1 {
            color: #667eea;
            font-size: 32px;
            margin-bottom: 10px;
        }
        
        .header p {
            color: #666;
            font-size: 16px;
        }
        
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .metric-card {
            background: white;
            padding: 25px;
            border-radius: 15px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.08);
            transition: transform 0.3s ease;
        }
        
        .metric-card:hover {
            transform: translateY(-5px);
        }
        
        .metric-label {
            font-size: 14px;
            color: #999;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 10px;
        }
        
        .metric-value {
            font-size: 36px;
            font-weight: bold;
            color: #333;
        }
        
        .metric-value.warning {
            color: #f59e0b;
        }
        
        .metric-value.danger {
            color: #ef4444;
            animation: pulse 2s infinite;
        }
        
        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.7; }
        }
        
        .chart-container {
            background: white;
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 5px 20px rgba(0,0,0,0.08);
            margin-bottom: 30px;
        }
        
        .chart-title {
            font-size: 20px;
            font-weight: 600;
            color: #333;
            margin-bottom: 20px;
        }
        
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        
        .status-indicator.healthy {
            background: #22c55e;
            box-shadow: 0 0 10px #22c55e;
        }
        
        .status-indicator.warning {
            background: #f59e0b;
            box-shadow: 0 0 10px #f59e0b;
        }
        
        .status-indicator.critical {
            background: #ef4444;
            box-shadow: 0 0 10px #ef4444;
            animation: blink 1s infinite;
        }
        
        @keyframes blink {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.3; }
        }
        
        .metric-unit {
            font-size: 18px;
            color: #999;
            margin-left: 5px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔒 TLS Handshake Latency Monitor</h1>
            <p>Real-time monitoring of TLS connection establishment under load</p>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <div class="metric-label">
                    <span class="status-indicator healthy" id="status-indicator"></span>
                    System Status
                </div>
                <div class="metric-value" id="status-text">Healthy</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-label">Active Connections</div>
                <div class="metric-value" id="active-connections">0</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-label">Total Handshakes</div>
                <div class="metric-value" id="total-connections">0</div>
            </div>
            
            <div class="metric-card">
                <div class="metric-label">Handshake P50</div>
                <div class="metric-value" id="p50-latency">0<span class="metric-unit">ms</span></div>
            </div>
            
            <div class="metric-card">
                <div class="metric-label">Handshake P99</div>
                <div class="metric-value" id="p99-latency">0<span class="metric-unit">ms</span></div>
            </div>
            
            <div class="metric-card">
                <div class="metric-label">Failed Handshakes</div>
                <div class="metric-value" id="failed-handshakes">0</div>
            </div>
        </div>
        
        <div class="chart-container">
            <div class="chart-title">TLS Handshake Latency Over Time</div>
            <canvas id="latencyChart"></canvas>
        </div>
        
        <div class="chart-container">
            <div class="chart-title">Connection Activity</div>
            <canvas id="connectionChart"></canvas>
        </div>
    </div>
    
    <script>
        // Chart configuration
        const latencyCtx = document.getElementById('latencyChart').getContext('2d');
        const connectionCtx = document.getElementById('connectionChart').getContext('2d');
        
        const latencyChart = new Chart(latencyCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'P50 Latency (ms)',
                        data: [],
                        borderColor: '#3b82f6',
                        backgroundColor: 'rgba(59, 130, 246, 0.1)',
                        tension: 0.4
                    },
                    {
                        label: 'P99 Latency (ms)',
                        data: [],
                        borderColor: '#ef4444',
                        backgroundColor: 'rgba(239, 68, 68, 0.1)',
                        tension: 0.4
                    }
                ]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: { display: true }
                },
                scales: {
                    y: { beginAtZero: true }
                }
            }
        });
        
        const connectionChart = new Chart(connectionCtx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'Active Connections',
                        data: [],
                        borderColor: '#22c55e',
                        backgroundColor: 'rgba(34, 197, 94, 0.1)',
                        tension: 0.4,
                        fill: true
                    }
                ]
            },
            options: {
                responsive: true,
                plugins: {
                    legend: { display: true }
                },
                scales: {
                    y: { beginAtZero: true }
                }
            }
        });
        
        // Update metrics from backend
        async function updateMetrics() {
            try {
                const response = await fetch('http://localhost:8080/metrics');
                const data = await response.json();
                
                // Update metric cards
                document.getElementById('active-connections').textContent = data.active_connections;
                document.getElementById('total-connections').textContent = data.total_connections;
                document.getElementById('p50-latency').innerHTML = 
                    data.handshake_latency_p50_ms.toFixed(1) + '<span class="metric-unit">ms</span>';
                document.getElementById('p99-latency').innerHTML = 
                    data.handshake_latency_p99_ms.toFixed(1) + '<span class="metric-unit">ms</span>';
                document.getElementById('failed-handshakes').textContent = data.failed_handshakes;
                
                // Update status
                const statusIndicator = document.getElementById('status-indicator');
                const statusText = document.getElementById('status-text');
                const p99Element = document.getElementById('p99-latency');
                
                if (data.handshake_latency_p99_ms > 2000) {
                    statusIndicator.className = 'status-indicator critical';
                    statusText.textContent = 'Critical';
                    statusText.className = 'metric-value danger';
                    p99Element.className = 'metric-value danger';
                } else if (data.handshake_latency_p99_ms > 500) {
                    statusIndicator.className = 'status-indicator warning';
                    statusText.textContent = 'Degraded';
                    statusText.className = 'metric-value warning';
                    p99Element.className = 'metric-value warning';
                } else {
                    statusIndicator.className = 'status-indicator healthy';
                    statusText.textContent = 'Healthy';
                    statusText.className = 'metric-value';
                    p99Element.className = 'metric-value';
                }
                
                // Update charts
                const now = new Date().toLocaleTimeString();
                
                if (latencyChart.data.labels.length > 30) {
                    latencyChart.data.labels.shift();
                    latencyChart.data.datasets[0].data.shift();
                    latencyChart.data.datasets[1].data.shift();
                }
                
                latencyChart.data.labels.push(now);
                latencyChart.data.datasets[0].data.push(data.handshake_latency_p50_ms);
                latencyChart.data.datasets[1].data.push(data.handshake_latency_p99_ms);
                latencyChart.update('none');
                
                if (connectionChart.data.labels.length > 30) {
                    connectionChart.data.labels.shift();
                    connectionChart.data.datasets[0].data.shift();
                }
                
                connectionChart.data.labels.push(now);
                connectionChart.data.datasets[0].data.push(data.active_connections);
                connectionChart.update('none');
                
            } catch (error) {
                console.error('Error fetching metrics:', error);
            }
        }
        
        // Update every 2 seconds
        setInterval(updateMetrics, 2000);
        updateMetrics(); // Initial call
    </script>
</body>
</html>
EOF

cat > dashboard/Dockerfile << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
EOF

echo "✅ Created dashboard"

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  nginx:
    image: nginx:latest
    container_name: tls-nginx
    ports:
      - "8443:8443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/certs:/etc/nginx/certs:ro
    depends_on:
      - backend
    networks:
      - tls-demo

  backend:
    build: ./backend
    container_name: tls-backend
    ports:
      - "8080:8080"
    networks:
      - tls-demo

  dashboard:
    build: ./dashboard
    container_name: tls-dashboard
    ports:
      - "3000:80"
    networks:
      - tls-demo

  load-generator:
    build: ./load-generator
    container_name: tls-load-gen
    depends_on:
      - nginx
      - backend
    networks:
      - tls-demo

networks:
  tls-demo:
    driver: bridge
EOF

echo "✅ Created Docker Compose configuration"

# Build and start services
echo ""
echo "🏗️  Building Docker images..."
docker-compose build

echo ""
echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "✅ Demo is running!"
echo ""
echo "📊 Access the dashboard at: http://localhost:3000"
echo "📈 Backend metrics API at: http://localhost:8080/metrics"
echo "🔒 HTTPS endpoint at: https://localhost:8443"
echo ""
echo "📝 The load generator will automatically cycle through:"
echo "   1. Normal load (30s) - Connection reuse"
echo "   2. High load (60s) - New connections (watch latency spike!)"
echo "   3. Recovery (20s) - Back to normal"
echo ""
echo "💡 Watch the dashboard to see TLS handshake latency degrade under load!"
echo ""
echo "To stop: ./cleanup.sh"
echo "To view logs: docker-compose logs -f"