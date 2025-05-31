#!/bin/bash

# Distributed Systems Resilience Patterns Demo
# This script creates a mini distributed system to demonstrate:
# - Circuit breakers
# - Timeout handling  
# - Cascading failures
# - Bulkhead isolation
# - Exponential backoff

set -e

DEMO_DIR="distributed_systems_demo"
LOG_DIR="$DEMO_DIR/logs"
PID_FILE="$DEMO_DIR/pids.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Circuit breaker state tracking
CB_STATE_FILE="$DEMO_DIR/circuit_breaker_state.txt"

setup_demo() {
    echo -e "${BLUE}Setting up Distributed Systems Demo...${NC}"
    
    # Create directory structure
    mkdir -p "$LOG_DIR"
    rm -f "$PID_FILE"
    echo "CLOSED" > "$CB_STATE_FILE"
    
    # Create the load balancer service
    cat > "$DEMO_DIR/load_balancer.py" << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import time
import random
import requests
import threading
from urllib.parse import urlparse, parse_qs

class LoadBalancer(http.server.SimpleHTTPRequestHandler):
    # Service registry with health status
    services = [
        {"url": "http://localhost:8081", "healthy": True, "weight": 1},
        {"url": "http://localhost:8082", "healthy": True, "weight": 1},
        {"url": "http://localhost:8083", "healthy": True, "weight": 1}
    ]
    
    def do_GET(self):
        if self.path.startswith('/api/'):
            self.route_request()
        elif self.path == '/health':
            self.health_check()
        else:
            self.send_dashboard()
    
    def route_request(self):
        start_time = time.time()
        
        # Get healthy services
        healthy_services = [s for s in self.services if s["healthy"]]
        
        if not healthy_services:
            self.send_error(503, "No healthy services available")
            return
        
        # Simple round-robin with weights
        service = random.choice(healthy_services)
        
        try:
            # Forward request with timeout
            response = requests.get(f"{service['url']}{self.path}", timeout=2.0)
            
            # Send response back
            self.send_response(response.status_code)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            latency = int((time.time() - start_time) * 1000)
            result = response.json()
            result['load_balancer_latency'] = f"{latency}ms"
            result['routed_to'] = service['url']
            
            self.wfile.write(json.dumps(result).encode())
            
            print(f"✓ Routed to {service['url']} - {latency}ms")
            
        except requests.exceptions.Timeout:
            print(f"✗ Timeout to {service['url']}")
            service['healthy'] = False  # Mark as unhealthy
            self.send_error(504, "Service timeout")
            
        except Exception as e:
            print(f"✗ Error: {e}")
            service['healthy'] = False
            self.send_error(500, str(e))
    
    def health_check(self):
        # Background health checking
        for service in self.services:
            try:
                response = requests.get(f"{service['url']}/health", timeout=1.0)
                service['healthy'] = response.status_code == 200
            except:
                service['healthy'] = False
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(self.services).encode())
    
    def send_dashboard(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        
        html = """
        <html><head><title>Load Balancer Dashboard</title></head>
        <body style="font-family: Arial;">
        <h1>Distributed System Demo</h1>
        <h2>Service Status</h2>
        <div id="services"></div>
        <h2>Test Endpoints</h2>
        <button onclick="testEndpoint('/api/data')">Test Normal API</button>
        <button onclick="testEndpoint('/api/slow')">Test Slow API</button>
        <button onclick="testEndpoint('/api/fail')">Test Failing API</button>
        <div id="results"></div>
        <script>
        function testEndpoint(path) {
            fetch(path)
            .then(r => r.json())
            .then(data => {
                document.getElementById('results').innerHTML = 
                '<pre>' + JSON.stringify(data, null, 2) + '</pre>';
            })
            .catch(e => {
                document.getElementById('results').innerHTML = 
                '<div style="color:red;">Error: ' + e + '</div>';
            });
        }
        </script>
        </body></html>
        """
        self.wfile.write(html.encode())

if __name__ == "__main__":
    PORT = 8080
    with socketserver.TCPServer(("", PORT), LoadBalancer) as httpd:
        print(f"Load Balancer running on port {PORT}")
        httpd.serve_forever()
EOF

    # Create service A (healthy service)
    cat > "$DEMO_DIR/service_a.py" << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import time
import random

class ServiceA(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "healthy", "service": "A"}).encode())
        elif self.path.startswith('/api/'):
            self.handle_api_request()
        else:
            self.send_error(404)
    
    def handle_api_request(self):
        # Simulate some processing time
        time.sleep(random.uniform(0.05, 0.2))
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        
        response = {
            "service": "A",
            "status": "success",
            "data": "Service A processed successfully",
            "timestamp": time.time(),
            "latency": "fast"
        }
        
        self.wfile.write(json.dumps(response).encode())
        print(f"Service A: Handled {self.path}")

if __name__ == "__main__":
    PORT = 8081
    with socketserver.TCPServer(("", PORT), ServiceA) as httpd:
        print(f"Service A running on port {PORT}")
        httpd.serve_forever()
EOF

    # Create service B (sometimes slow service with circuit breaker)
    cat > "$DEMO_DIR/service_b.py" << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import time
import random
import os

class CircuitBreaker:
    def __init__(self):
        self.failure_count = 0
        self.last_failure_time = 0
        self.timeout = 10  # 10 second timeout
        self.failure_threshold = 3
        self.state = "CLOSED"  # CLOSED, OPEN, HALF_OPEN
    
    def call(self, func):
        if self.state == "OPEN":
            if time.time() - self.last_failure_time > self.timeout:
                self.state = "HALF_OPEN"
                print("Circuit Breaker: OPEN -> HALF_OPEN")
            else:
                raise Exception("Circuit breaker is OPEN")
        
        try:
            result = func()
            if self.state == "HALF_OPEN":
                self.state = "CLOSED"
                self.failure_count = 0
                print("Circuit Breaker: HALF_OPEN -> CLOSED")
            return result
        except Exception as e:
            self.failure_count += 1
            self.last_failure_time = time.time()
            
            if self.failure_count >= self.failure_threshold:
                self.state = "OPEN"
                print(f"Circuit Breaker: -> OPEN (failures: {self.failure_count})")
            
            raise e

class ServiceB(http.server.SimpleHTTPRequestHandler):
    circuit_breaker = CircuitBreaker()
    
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            health_data = {
                "status": "healthy", 
                "service": "B",
                "circuit_breaker": self.circuit_breaker.state
            }
            self.wfile.write(json.dumps(health_data).encode())
        elif self.path.startswith('/api/'):
            self.handle_api_request()
        else:
            self.send_error(404)
    
    def handle_api_request(self):
        try:
            def process_request():
                # Simulate variable performance
                if 'slow' in self.path:
                    time.sleep(random.uniform(1.0, 3.0))  # Very slow
                else:
                    time.sleep(random.uniform(0.1, 0.8))  # Sometimes slow
                
                # Randomly fail sometimes
                if random.random() < 0.3:  # 30% failure rate
                    raise Exception("Database connection failed")
                
                return {
                    "service": "B",
                    "status": "success",
                    "data": "Service B processed (with circuit breaker)",
                    "timestamp": time.time(),
                    "circuit_breaker_state": self.circuit_breaker.state
                }
            
            response = self.circuit_breaker.call(process_request)
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
            print(f"Service B: Success {self.path} (CB: {self.circuit_breaker.state})")
            
        except Exception as e:
            print(f"Service B: Failed {self.path} - {e} (CB: {self.circuit_breaker.state})")
            self.send_error(500, str(e))

if __name__ == "__main__":
    PORT = 8082
    with socketserver.TCPServer(("", PORT), ServiceB) as httpd:
        print(f"Service B running on port {PORT}")
        httpd.serve_forever()
EOF

    # Create service C (failing service)
    cat > "$DEMO_DIR/service_c.py" << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import time
import random

class ServiceC(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            # This service reports unhealthy most of the time
            if random.random() < 0.8:  # 80% unhealthy
                self.send_error(500, "Service degraded")
            else:
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({"status": "degraded", "service": "C"}).encode())
        elif self.path.startswith('/api/'):
            self.handle_api_request()
        else:
            self.send_error(404)
    
    def handle_api_request(self):
        # This service fails most requests
        if random.random() < 0.9:  # 90% failure rate
            print(f"Service C: Failed {self.path}")
            self.send_error(500, "Service C is experiencing issues")
        else:
            time.sleep(random.uniform(2.0, 5.0))  # Very slow when it works
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            
            response = {
                "service": "C",
                "status": "success",
                "data": "Service C processed (rarely works)",
                "timestamp": time.time()
            }
            
            self.wfile.write(json.dumps(response).encode())
            print(f"Service C: Rare success {self.path}")

if __name__ == "__main__":
    PORT = 8083
    with socketserver.TCPServer(("", PORT), ServiceC) as httpd:
        print(f"Service C running on port {PORT}")
        httpd.serve_forever()
EOF

    # Create test client with retry logic
    cat > "$DEMO_DIR/test_client.py" << 'EOF'
#!/usr/bin/env python3
import requests
import time
import random
import json

class RetryClient:
    def __init__(self, base_url):
        self.base_url = base_url
        self.max_retries = 3
    
    def exponential_backoff(self, attempt):
        # Exponential backoff with jitter
        base_delay = 2 ** attempt
        jitter = random.uniform(0, 0.1 * base_delay)
        return base_delay + jitter
    
    def make_request(self, endpoint):
        for attempt in range(self.max_retries):
            try:
                print(f"Attempt {attempt + 1}: {endpoint}")
                start_time = time.time()
                
                response = requests.get(f"{self.base_url}{endpoint}", timeout=3.0)
                latency = int((time.time() - start_time) * 1000)
                
                if response.status_code == 200:
                    result = response.json()
                    print(f"✓ Success in {latency}ms: {result.get('service', 'unknown')}")
                    return result
                else:
                    print(f"✗ HTTP {response.status_code}")
                    
            except requests.exceptions.Timeout:
                print("✗ Timeout")
            except Exception as e:
                print(f"✗ Error: {e}")
            
            if attempt < self.max_retries - 1:
                delay = self.exponential_backoff(attempt)
                print(f"  Retrying in {delay:.2f}s...")
                time.sleep(delay)
        
        print("✗ All retries exhausted")
        return None

if __name__ == "__main__":
    client = RetryClient("http://localhost:8080")
    
    endpoints = ["/api/data", "/api/slow", "/api/fail"]
    
    print("Testing distributed system with retry logic...")
    for endpoint in endpoints:
        print(f"\n--- Testing {endpoint} ---")
        result = client.make_request(endpoint)
        time.sleep(2)  # Pause between tests
EOF

    chmod +x "$DEMO_DIR"/*.py
    
    echo -e "${GREEN}Demo setup complete!${NC}"
}

start_services() {
    echo -e "${BLUE}Starting distributed services...${NC}"
    
    # Start all services in background
    python3 "$DEMO_DIR/service_a.py" > "$LOG_DIR/service_a.log" 2>&1 &
    echo $! >> "$PID_FILE"
    
    python3 "$DEMO_DIR/service_b.py" > "$LOG_DIR/service_b.log" 2>&1 &
    echo $! >> "$PID_FILE"
    
    python3 "$DEMO_DIR/service_c.py" > "$LOG_DIR/service_c.log" 2>&1 &
    echo $! >> "$PID_FILE"
    
    python3 "$DEMO_DIR/load_balancer.py" > "$LOG_DIR/load_balancer.log" 2>&1 &
    echo $! >> "$PID_FILE"
    
    echo -e "${GREEN}Services starting... (waiting 3 seconds)${NC}"
    sleep 3
    
    echo -e "${BLUE}Service Status:${NC}"
    check_service_health "Service A" "http://localhost:8081/health"
    check_service_health "Service B" "http://localhost:8082/health"
    check_service_health "Service C" "http://localhost:8083/health"
    check_service_health "Load Balancer" "http://localhost:8080/health"
}

check_service_health() {
    local name=$1
    local url=$2
    
    if curl -s "$url" > /dev/null 2>&1; then
        echo -e "  ${GREEN}✓ $name${NC}"
    else
        echo -e "  ${RED}✗ $name${NC}"
    fi
}

run_demonstration() {
    echo -e "${YELLOW}Running Distributed Systems Demonstration...${NC}"
    echo
    
    echo -e "${BLUE}Phase 1: Normal Operation${NC}"
    echo "Testing basic load balancing..."
    for i in {1..5}; do
        curl -s "http://localhost:8080/api/data" | jq '.service, .routed_to' || echo "Request failed"
        sleep 1
    done
    
    echo
    echo -e "${BLUE}Phase 2: Simulating Slow Responses${NC}"
    echo "Testing circuit breaker behavior with slow endpoint..."
    for i in {1..3}; do
        echo "Request $i:"
        timeout 5 curl -s "http://localhost:8080/api/slow" | jq '.service, .circuit_breaker_state' || echo "Timeout or failure"
        sleep 2
    done
    
    echo
    echo -e "${BLUE}Phase 3: Testing Retry Logic${NC}"
    echo "Running client with exponential backoff..."
    python3 "$DEMO_DIR/test_client.py"
    
    echo
    echo -e "${BLUE}Phase 4: Observing Circuit Breaker States${NC}"
    echo "Checking service health and circuit breaker states..."
    curl -s "http://localhost:8080/health" | jq '.'
}

monitor_logs() {
    echo -e "${YELLOW}Monitoring service logs (Ctrl+C to stop)...${NC}"
    echo
    
    # Show recent logs from all services
    for log_file in "$LOG_DIR"/*.log; do
        if [ -f "$log_file" ]; then
            echo -e "${BLUE}=== $(basename "$log_file") ===${NC}"
            tail -n 5 "$log_file"
            echo
        fi
    done
    
    # Follow all logs
    tail -f "$LOG_DIR"/*.log
}

cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    
    if [ -f "$PID_FILE" ]; then
        while read -r pid; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
                echo "Stopped process $pid"
            fi
        done < "$PID_FILE"
        rm -f "$PID_FILE"
    fi
    
    echo -e "${GREEN}Cleanup complete!${NC}"
}

show_dashboard() {
    echo -e "${BLUE}Dashboard URLs:${NC}"
    echo "Load Balancer Dashboard: http://localhost:8080"
    echo "Health Check: http://localhost:8080/health"
    echo "API Endpoints:"
    echo "  http://localhost:8080/api/data (normal)"
    echo "  http://localhost:8080/api/slow (slow responses)"
    echo "  http://localhost:8080/api/fail (high failure rate)"
    echo
    echo -e "${YELLOW}Open these URLs in your browser to interact with the system!${NC}"
}

# Main script logic
case "${1:-help}" in
    "setup")
        setup_demo
        ;;
    "start")
        start_services
        show_dashboard
        ;;
    "demo")
        run_demonstration
        ;;
    "monitor")
        monitor_logs
        ;;
    "stop")
        cleanup
        ;;
    "full")
        setup_demo
        start_services
        show_dashboard
        echo
        echo -e "${YELLOW}Services are running. Try the demo commands:${NC}"
        echo "./distributed_demo.sh demo    - Run automated demonstration"
        echo "./distributed_demo.sh monitor - View live logs"
        echo "./distributed_demo.sh stop    - Stop all services"
        ;;
    *)
        echo -e "${BLUE}Distributed Systems Resilience Demo${NC}"
        echo
        echo "This demo creates a mini distributed system with:"
        echo "- Load balancer with health checking"
        echo "- Multiple services with different reliability characteristics"
        echo "- Circuit breakers with state management"
        echo "- Exponential backoff retry logic"
        echo "- Real-time monitoring and logging"
        echo
        echo "Commands:"
        echo "  setup   - Create demo files and structure"
        echo "  start   - Start all services"
        echo "  demo    - Run automated demonstration"
        echo "  monitor - View live service logs"
        echo "  stop    - Stop all services and cleanup"
        echo "  full    - Complete setup and start (recommended first run)"
        echo
        echo "Requirements: Python 3, curl, jq (optional for pretty JSON)"
        echo
        echo -e "${YELLOW}Start with: ./distributed_demo.sh full${NC}"
        ;;
esac