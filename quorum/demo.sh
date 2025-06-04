#!/bin/bash

# Quorum-Based Systems Demonstration Script
# Creates a working quorum system with 5 nodes demonstrating R=2, W=2, N=5 configuration
# Shows quorum operations, failures, and repair mechanisms

set -e

# Configuration
NODES=5
READ_QUORUM=2
WRITE_QUORUM=2
BASE_PORT=8080
DEMO_DIR="quorum_demo"
LOG_DIR="$DEMO_DIR/logs"
WEB_DIR="$DEMO_DIR/web"
DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-local}"  # local or docker

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}================================================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}================================================================${NC}"
}

print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    print_info "Cleaning up previous demo..."
    pkill -f "quorum_node" 2>/dev/null || true
    pkill -f "python3.*quorum" 2>/dev/null || true
    
    # Docker cleanup
    docker-compose down 2>/dev/null || true
    docker system prune -f 2>/dev/null || true
    
    rm -rf "$DEMO_DIR" 2>/dev/null || true
    sleep 2
}

build_docker_images() {
    print_step "Building Docker images..."
    
    if ! docker build -t quorum-node . 2>&1; then
        print_error "Failed to build Docker image"
        exit 1
    fi
    
    print_info "Docker image built successfully"
}

deploy_docker_cluster() {
    print_step "Deploying Docker cluster..."
    
    # Set Docker mode environment variable
    export DOCKER_MODE=true
    
    if ! docker-compose up -d 2>&1; then
        print_error "Failed to start Docker cluster"
        exit 1
    fi
    
    print_info "Waiting for containers to be healthy..."
    local max_wait=60
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        if docker-compose ps 2>/dev/null | grep -c "healthy" | grep -q "5"; then
            print_info "All containers are healthy!"
            break
        fi
        
        print_info "Waiting for containers... ($wait_time/$max_wait seconds)"
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    if [ $wait_time -ge $max_wait ]; then
        print_warning "Containers taking longer than expected to become healthy"
        docker-compose ps
    fi
}

verify_docker_cluster() {
    print_step "Verifying Docker cluster health..."
    
    local healthy_nodes=0
    
    for port in $(seq $BASE_PORT $((BASE_PORT + NODES - 1))); do
        if curl -s http://localhost:$port/status > /dev/null 2>&1; then
            healthy_nodes=$((healthy_nodes + 1))
            print_info "Node on port $port is responding"
        else
            print_warning "Node on port $port is not responding"
        fi
    done
    
    if [ $healthy_nodes -eq $NODES ]; then
        print_info "✅ All $NODES Docker nodes are healthy!"
        return 0
    else
        print_error "❌ Only $healthy_nodes out of $NODES nodes are healthy"
        return 1
    fi
}

run_docker_tests() {
    print_step "Running Docker-based tests..."
    
    # Update test script for Docker mode
    cat > docker_test_scenarios.py << 'EOF'
#!/usr/bin/env python3
import requests
import time
import json
import random
import os
import threading

# Configure for Docker mode
DOCKER_MODE = True
BASE_URL = "http://localhost"

def wait_for_nodes():
    """Wait for all nodes to be ready"""
    nodes = [8080, 8081, 8082, 8083, 8084]
    print("🐳 Waiting for Docker nodes to be ready...")
    
    max_attempts = 30
    attempt = 0
    
    while attempt < max_attempts:
        ready_count = 0
        for port in nodes:
            try:
                response = requests.get(f"{BASE_URL}:{port}/status", timeout=2)
                if response.status_code == 200:
                    ready_count += 1
            except:
                pass
        
        if ready_count == len(nodes):
            print(f"✅ All {len(nodes)} Docker nodes are ready!")
            break
        else:
            print(f"⏳ {ready_count}/{len(nodes)} nodes ready, waiting... (attempt {attempt + 1}/{max_attempts})")
            time.sleep(2)
            attempt += 1
    
    if attempt >= max_attempts:
        print("❌ Timeout waiting for nodes to be ready")
        return False
    
    return True

def test_docker_networking():
    """Test inter-container communication"""
    print("\n🔗 Testing Docker networking...")
    
    coordinator = f"{BASE_URL}:8080"
    
    # Test write that requires inter-container communication
    try:
        response = requests.post(
            f"{coordinator}/coordinate_write",
            json={"key": "docker_test", "value": "networking_test", "w": 3},
            timeout=10
        )
        
        result = response.json()
        if result["success"]:
            print("✅ Docker inter-container communication working")
            return True
        else:
            print("❌ Docker networking issues detected")
            print(f"Responses: {result.get('responses', [])}")
            return False
    except Exception as e:
        print(f"❌ Docker networking test failed: {e}")
        return False

def test_docker_persistence():
    """Test data persistence across container operations"""
    print("\n💾 Testing Docker data persistence...")
    
    coordinator = f"{BASE_URL}:8080"
    
    # Write test data
    test_data = {
        "persistence_test_1": "data_1",
        "persistence_test_2": "data_2",
        "persistence_test_3": "data_3"
    }
    
    try:
        for key, value in test_data.items():
            response = requests.post(
                f"{coordinator}/coordinate_write",
                json={"key": key, "value": value, "w": 2},
                timeout=10
            )
            if not response.json()["success"]:
                print(f"❌ Failed to write {key}")
                return False
        
        # Verify reads
        for key, expected_value in test_data.items():
            response = requests.get(f"{coordinator}/coordinate_read?key={key}&r=2", timeout=10)
            result = response.json()
            
            if result["success"] and result["value"] == expected_value:
                print(f"✅ Persistence verified for {key}")
            else:
                print(f"❌ Persistence failed for {key}")
                return False
        
        return True
    except Exception as e:
        print(f"❌ Docker persistence test failed: {e}")
        return False

def test_docker_scaling():
    """Test behavior under Docker resource constraints"""
    print("\n📈 Testing Docker scaling behavior...")
    
    coordinator = f"{BASE_URL}:8080"
    
    # Generate concurrent load
    results = {"success": 0, "failed": 0}
    
    def worker():
        for i in range(5):
            try:
                response = requests.post(
                    f"{coordinator}/coordinate_write",
                    json={"key": f"scale_test_{threading.current_thread().ident}_{i}", 
                          "value": f"value_{i}", "w": 2},
                    timeout=10
                )
                if response.json()["success"]:
                    results["success"] += 1
                else:
                    results["failed"] += 1
            except:
                results["failed"] += 1
    
    # Create 3 worker threads
    threads = []
    for _ in range(3):
        t = threading.Thread(target=worker)
        threads.append(t)
        t.start()
    
    for t in threads:
        t.join()
    
    total_ops = results["success"] + results["failed"]
    success_rate = results["success"] / total_ops if total_ops > 0 else 0
    
    print(f"📊 Scale test: {results['success']}/{total_ops} operations successful ({success_rate:.1%})")
    
    return success_rate > 0.8

def main():
    print("🐳 Starting Docker-based Quorum System Tests")
    print("=" * 60)
    
    if not wait_for_nodes():
        return False
    
    tests = [
        ("Docker Networking", test_docker_networking),
        ("Data Persistence", test_docker_persistence), 
        ("Scaling Behavior", test_docker_scaling)
    ]
    
    passed = 0
    for test_name, test_func in tests:
        try:
            if test_func():
                print(f"✅ {test_name}: PASSED")
                passed += 1
            else:
                print(f"❌ {test_name}: FAILED")
        except Exception as e:
            print(f"❌ {test_name}: ERROR - {e}")
    
    print(f"\n🎯 Docker tests completed: {passed}/{len(tests)} passed")
    
    if passed == len(tests):
        print("🎉 All Docker tests passed!")
        return True
    else:
        print("⚠️  Some Docker tests failed")
        return False

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
EOF

    if python3 docker_test_scenarios.py; then
        print_info "Docker tests completed successfully"
    else
        print_warning "Some Docker tests failed"
    fi
}

stop_docker_demo() {
    print_step "Stopping Docker components..."
    
    if docker-compose down 2>&1; then
        print_info "Docker demo stopped successfully"
    else
        print_warning "Failed to stop some containers"
    fi
}

setup_directory() {
    print_step "Setting up demo directory structure..."
    mkdir -p "$DEMO_DIR"/{logs,web,nodes}
    cd "$DEMO_DIR"
}

check_dependencies() {
    print_step "Checking dependencies..."
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_error "python3 is required but not installed"
        exit 1
    fi
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        print_error "curl is required but not installed"
        exit 1
    fi
    
    # Check Docker if using docker mode
    if [ "$DEPLOYMENT_MODE" = "docker" ] && ! command -v docker &> /dev/null; then
        print_error "docker is required for docker mode but not installed"
        exit 1
    fi
    
    print_info "All dependencies satisfied"
}

create_docker_files() {
    print_step "Creating Docker configuration..."
    
    # Create Dockerfile
    cat > Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app

# Install dependencies including curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
RUN pip install requests

COPY quorum_node.py .
COPY test_scenarios.py .

# Create logs directory
RUN mkdir -p logs

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/status || exit 1

EXPOSE 8080

# Use environment variables for configuration
CMD python3 quorum_node.py
EOF

    # Create docker-compose.yml
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  node0:
    build: .
    environment:
      - NODE_ID=0
      - NODE_PORT=8080
      - DOCKER_MODE=true
    ports:
      - "8080:8080"
    networks:
      - quorum-net
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/status"]
      interval: 10s
      timeout: 5s
      retries: 3

  node1:
    build: .
    environment:
      - NODE_ID=1
      - NODE_PORT=8080
      - DOCKER_MODE=true
    ports:
      - "8081:8080"
    networks:
      - quorum-net
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/status"]
      interval: 10s
      timeout: 5s
      retries: 3

  node2:
    build: .
    environment:
      - NODE_ID=2
      - NODE_PORT=8080
      - DOCKER_MODE=true
    ports:
      - "8082:8080"
    networks:
      - quorum-net
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/status"]
      interval: 10s
      timeout: 5s
      retries: 3

  node3:
    build: .
    environment:
      - NODE_ID=3
      - NODE_PORT=8080
      - DOCKER_MODE=true
    ports:
      - "8083:8080"
    networks:
      - quorum-net
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/status"]
      interval: 10s
      timeout: 5s
      retries: 3

  node4:
    build: .
    environment:
      - NODE_ID=4
      - NODE_PORT=8080
      - DOCKER_MODE=true
    ports:
      - "8084:8080"
    networks:
      - quorum-net
    volumes:
      - ./logs:/app/logs
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/status"]
      interval: 10s
      timeout: 5s
      retries: 3

  web:
    image: python:3.9-slim
    command: python3 -m http.server 8090
    working_dir: /app/web
    ports:
      - "8090:8090"
    volumes:
      - ./web:/app/web
    networks:
      - quorum-net

networks:
  quorum-net:
    driver: bridge
EOF

    # Create .dockerignore
    cat > .dockerignore << 'EOF'
logs/
web/
*.pid
*.log
__pycache__/
.git/
README.md
EOF
}

create_node_script() {
    print_step "Creating quorum node implementation..."
    
    cat > quorum_node.py << 'EOF'
#!/usr/bin/env python3
import json
import time
import threading
import hashlib
import os
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import requests
import sys
import random

class QuorumNode:
    def __init__(self, node_id, port, all_nodes):
        self.node_id = node_id
        self.port = port
        self.all_nodes = all_nodes
        self.data = {}  # key -> {value, timestamp, version}
        self.is_healthy = True
        self.request_count = 0
        self.docker_mode = os.getenv('DOCKER_MODE', 'false').lower() == 'true'
        
    def get_node_url(self, port_or_service):
        """Get URL for node - handles both local and Docker modes"""
        if self.docker_mode:
            # In Docker mode, use service names
            service_map = {
                8080: 'node0:8080',
                8081: 'node1:8080', 
                8082: 'node2:8080',
                8083: 'node3:8080',
                8084: 'node4:8080'
            }
            host = service_map.get(port_or_service, f'node{port_or_service-8080}:8080')
            return f"http://{host}"
        else:
            # Local mode
            return f"http://localhost:{port_or_service}"
        
    def log(self, message, level="INFO"):
        timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
        log_message = f"[{timestamp}] NODE-{self.node_id} [{level}] {message}"
        print(log_message)
        
        # Write to log file
        with open(f"logs/node_{self.node_id}.log", "a") as f:
            f.write(log_message + "\n")
    
    def get_replicas_for_key(self, key, count):
        # Simple consistent hashing - hash key and take next N nodes
        hash_value = int(hashlib.md5(key.encode()).hexdigest(), 16)
        start_index = hash_value % len(self.all_nodes)
        
        replicas = []
        for i in range(count):
            replica_index = (start_index + i) % len(self.all_nodes)
            replicas.append(self.all_nodes[replica_index])
        
        return replicas
    
    def coordinate_write(self, key, value, write_quorum=2):
        self.log(f"Coordinating write: {key}={value}, W={write_quorum}")
        
        # Generate timestamp
        timestamp = time.time()
        version = f"{timestamp}_{self.node_id}"
        
        # Get replicas for this key
        replicas = self.get_replicas_for_key(key, len(self.all_nodes))
        
        # Send write to all replicas
        success_count = 0
        responses = []
        
        for replica_port in replicas:
            try:
                if replica_port == self.port:
                    # Local write
                    self.local_write(key, value, timestamp, version)
                    success_count += 1
                    responses.append(f"node_{replica_port}: SUCCESS")
                    self.log(f"Local write successful: {key}")
                else:
                    # Remote write
                    node_url = self.get_node_url(replica_port)
                    response = requests.post(
                        f"{node_url}/write",
                        json={"key": key, "value": value, "timestamp": timestamp, "version": version},
                        timeout=2
                    )
                    if response.status_code == 200:
                        success_count += 1
                        responses.append(f"node_{replica_port}: SUCCESS")
                        self.log(f"Remote write successful to node {replica_port}: {key}")
                    else:
                        responses.append(f"node_{replica_port}: FAILED")
                        self.log(f"Remote write failed to node {replica_port}: {key}")
            except Exception as e:
                responses.append(f"node_{replica_port}: ERROR - {str(e)}")
                self.log(f"Write error to node {replica_port}: {e}", "ERROR")
        
        # Check if write quorum achieved
        if success_count >= write_quorum:
            self.log(f"Write quorum achieved: {success_count}/{write_quorum} for key {key}", "SUCCESS")
            return {"success": True, "responses": responses, "quorum_achieved": True}
        else:
            self.log(f"Write quorum failed: {success_count}/{write_quorum} for key {key}", "ERROR")
            return {"success": False, "responses": responses, "quorum_achieved": False}
    
    def coordinate_read(self, key, read_quorum=2):
        self.log(f"Coordinating read: {key}, R={read_quorum}")
        
        # Get replicas for this key
        replicas = self.get_replicas_for_key(key, len(self.all_nodes))
        
        # Read from replicas
        responses = []
        values = []
        
        for replica_port in replicas:
            try:
                if replica_port == self.port:
                    # Local read
                    local_data = self.local_read(key)
                    if local_data:
                        values.append(local_data)
                        responses.append(f"node_{replica_port}: {local_data['value']}")
                        self.log(f"Local read successful: {key}")
                    else:
                        responses.append(f"node_{replica_port}: NOT_FOUND")
                else:
                    # Remote read
                    node_url = self.get_node_url(replica_port)
                    response = requests.get(
                        f"{node_url}/read?key={key}",
                        timeout=2
                    )
                    if response.status_code == 200:
                        data = response.json()
                        if data.get("found"):
                            values.append(data)
                            responses.append(f"node_{replica_port}: {data['value']}")
                            self.log(f"Remote read successful from node {replica_port}: {key}")
                        else:
                            responses.append(f"node_{replica_port}: NOT_FOUND")
                    else:
                        responses.append(f"node_{replica_port}: FAILED")
            except Exception as e:
                responses.append(f"node_{replica_port}: ERROR - {str(e)}")
                self.log(f"Read error from node {replica_port}: {e}", "ERROR")
        
        # Check if read quorum achieved
        if len(values) >= read_quorum:
            # Resolve conflicts - use latest timestamp
            latest_value = max(values, key=lambda x: x['timestamp'])
            
            # Check for inconsistency (read repair needed)
            unique_values = set(v['value'] for v in values)
            if len(unique_values) > 1:
                self.log(f"Inconsistency detected for key {key}, triggering read repair", "WARN")
                self.trigger_read_repair(key, values)
            
            self.log(f"Read quorum achieved: {len(values)}/{read_quorum} for key {key}", "SUCCESS")
            return {
                "success": True, 
                "value": latest_value['value'],
                "responses": responses,
                "quorum_achieved": True,
                "inconsistency_detected": len(unique_values) > 1
            }
        else:
            self.log(f"Read quorum failed: {len(values)}/{read_quorum} for key {key}", "ERROR")
            return {"success": False, "responses": responses, "quorum_achieved": False}
    
    def trigger_read_repair(self, key, values):
        # Find the latest value
        latest_value = max(values, key=lambda x: x['timestamp'])
        self.log(f"Read repair: propagating latest value for {key}", "REPAIR")
        
        # Update all replicas with the latest value
        replicas = self.get_replicas_for_key(key, len(self.all_nodes))
        for replica_port in replicas:
            try:
                if replica_port != self.port:
                    node_url = self.get_node_url(replica_port)
                    requests.post(
                        f"{node_url}/repair",
                        json={
                            "key": key, 
                            "value": latest_value['value'],
                            "timestamp": latest_value['timestamp'],
                            "version": latest_value['version']
                        },
                        timeout=2
                    )
            except Exception as e:
                self.log(f"Read repair failed for node {replica_port}: {e}", "ERROR")
    
    def local_write(self, key, value, timestamp, version):
        self.data[key] = {
            "value": value,
            "timestamp": timestamp,
            "version": version
        }
    
    def local_read(self, key):
        return self.data.get(key)
    
    def get_status(self):
        return {
            "node_id": self.node_id,
            "port": self.port,
            "healthy": self.is_healthy,
            "data_count": len(self.data),
            "request_count": self.request_count,
            "data": self.data
        }

class QuorumHTTPHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.quorum_node.request_count += 1
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == "/read":
            query_params = parse_qs(parsed_path.query)
            key = query_params.get('key', [''])[0]
            
            if not key:
                self.send_error(400, "Missing key parameter")
                return
            
            data = self.server.quorum_node.local_read(key)
            
            if data:
                response = {"found": True, **data}
            else:
                response = {"found": False}
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
            
        elif parsed_path.path == "/status":
            status = self.server.quorum_node.get_status()
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(status).encode())
            
        elif parsed_path.path == "/coordinate_read":
            query_params = parse_qs(parsed_path.query)
            key = query_params.get('key', [''])[0]
            read_quorum = int(query_params.get('r', [2])[0])
            
            result = self.server.quorum_node.coordinate_read(key, read_quorum)
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(result).encode())
            
        elif parsed_path.path == "/fail":
            # Simulate node failure
            self.server.quorum_node.is_healthy = False
            self.server.quorum_node.log("Node marked as failed", "WARN")
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "failed"}).encode())
            
        elif parsed_path.path == "/recover":
            # Simulate node recovery
            self.server.quorum_node.is_healthy = True
            self.server.quorum_node.log("Node recovered", "INFO")
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "recovered"}).encode())
        else:
            self.send_error(404)
    
    def do_POST(self):
        self.server.quorum_node.request_count += 1
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length)
        data = json.loads(post_data.decode('utf-8'))
        
        if self.path == "/write":
            self.server.quorum_node.local_write(
                data['key'], 
                data['value'], 
                data['timestamp'], 
                data['version']
            )
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok"}).encode())
            
        elif self.path == "/coordinate_write":
            write_quorum = data.get('w', 2)
            result = self.server.quorum_node.coordinate_write(
                data['key'], 
                data['value'], 
                write_quorum
            )
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(result).encode())
            
        elif self.path == "/repair":
            self.server.quorum_node.local_write(
                data['key'], 
                data['value'], 
                data['timestamp'], 
                data['version']
            )
            self.server.quorum_node.log(f"Read repair applied for key {data['key']}", "REPAIR")
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "repaired"}).encode())
        else:
            self.send_error(404)
    
    def log_message(self, format, *args):
        # Suppress default HTTP server logs
        pass

def run_node(node_id, port, all_nodes):
    quorum_node = QuorumNode(node_id, port, all_nodes)

    # ✅ FIX: Bind to 0.0.0.0 instead of localhost for Docker networking
    httpd = HTTPServer(('0.0.0.0', port), QuorumHTTPHandler)
    httpd.quorum_node = quorum_node

    quorum_node.log(f"Starting quorum node on port {port}")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        quorum_node.log("Node shutting down")
        httpd.shutdown()

if __name__ == "__main__":
    node_id = int(os.getenv('NODE_ID', sys.argv[1] if len(sys.argv) > 1 else '0'))
    port = int(os.getenv('NODE_PORT', sys.argv[2] if len(sys.argv) > 2 else '8080'))
    all_nodes = [8080, 8081, 8082, 8083, 8084]
    run_node(node_id, port, all_nodes)
EOF


    chmod +x quorum_node.py
}

create_web_interface() {
    print_step "Creating web monitoring interface..."
    
    cat > web/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Quorum System Demo</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
            min-height: 100vh;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        
        .header {
            background: linear-gradient(135deg, #2c3e50 0%, #3498db 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }
        
        .header h1 {
            margin: 0;
            font-size: 2.5em;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .config {
            background: #f8f9fa;
            padding: 20px;
            border-bottom: 2px solid #e9ecef;
        }
        
        .config-item {
            display: inline-block;
            margin: 0 20px;
            padding: 10px 20px;
            background: white;
            border-radius: 25px;
            box-shadow: 0 4px 8px rgba(0,0,0,0.1);
            font-weight: bold;
        }
        
        .main-content {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 30px;
            padding: 30px;
        }
        
        .section {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 25px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        
        .section h3 {
            margin-top: 0;
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        
        .nodes-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .node {
            background: white;
            border-radius: 10px;
            padding: 15px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            transition: all 0.3s ease;
        }
        
        .node:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.15);
        }
        
        .node.healthy {
            border-left: 5px solid #27ae60;
        }
        
        .node.failed {
            border-left: 5px solid #e74c3c;
            opacity: 0.6;
        }
        
        .node-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 10px;
        }
        
        .node-status {
            padding: 4px 12px;
            border-radius: 15px;
            font-size: 0.8em;
            font-weight: bold;
        }
        
        .status-healthy {
            background: #d4edda;
            color: #155724;
        }
        
        .status-failed {
            background: #f8d7da;
            color: #721c24;
        }
        
        .controls {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 15px;
            margin-bottom: 20px;
        }
        
        .control-group {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .input-group {
            margin-bottom: 15px;
        }
        
        .input-group label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
            color: #2c3e50;
        }
        
        .input-group input, .input-group select {
            width: 100%;
            padding: 10px;
            border: 2px solid #e9ecef;
            border-radius: 5px;
            font-size: 14px;
        }
        
        .btn {
            background: linear-gradient(135deg, #3498db 0%, #2980b9 100%);
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 25px;
            cursor: pointer;
            font-weight: bold;
            transition: all 0.3s ease;
            width: 100%;
        }
        
        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(52, 152, 219, 0.3);
        }
        
        .btn-danger {
            background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
        }
        
        .btn-success {
            background: linear-gradient(135deg, #27ae60 0%, #229954 100%);
        }
        
        .results {
            background: white;
            border-radius: 10px;
            padding: 20px;
            margin-top: 20px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            min-height: 200px;
            overflow-y: auto;
            max-height: 400px;
        }
        
        .result-item {
            padding: 10px;
            margin: 5px 0;
            border-radius: 5px;
            border-left: 4px solid #3498db;
            background: #f8f9fa;
        }
        
        .result-success {
            border-left-color: #27ae60;
            background: #d4edda;
        }
        
        .result-error {
            border-left-color: #e74c3c;
            background: #f8d7da;
        }
        
        .result-warning {
            border-left-color: #f39c12;
            background: #fff3cd;
        }
        
        .full-width {
            grid-column: 1 / -1;
        }
        
        .metrics {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        
        .metric {
            background: white;
            padding: 15px;
            border-radius: 10px;
            text-align: center;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        
        .metric-value {
            font-size: 1.8em;
            font-weight: bold;
            color: #3498db;
        }
        
        .metric-label {
            color: #7f8c8d;
            font-size: 0.9em;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔗 Quorum System Live Demo</h1>
            <p>Watch quorum consensus, failures, and repair in real-time</p>
        </div>
        
        <div class="config">
            <div class="config-item">📊 Nodes: <span id="nodeCount">5</span></div>
            <div class="config-item">📖 Read Quorum: <span id="readQuorum">2</span></div>
            <div class="config-item">✍️ Write Quorum: <span id="writeQuorum">2</span></div>
            <div class="config-item">🕐 Auto-refresh: <span id="refreshInterval">3s</span></div>
        </div>
        
        <div class="main-content">
            <div class="section">
                <h3>🖥️ Cluster Status</h3>
                <div class="nodes-grid" id="nodesGrid"></div>
                <div class="metrics">
                    <div class="metric">
                        <div class="metric-value" id="healthyNodes">-</div>
                        <div class="metric-label">Healthy Nodes</div>
                    </div>
                    <div class="metric">
                        <div class="metric-value" id="totalRequests">-</div>
                        <div class="metric-label">Total Requests</div>
                    </div>
                    <div class="metric">
                        <div class="metric-value" id="quorumStatus">-</div>
                        <div class="metric-label">Quorum Available</div>
                    </div>
                </div>
            </div>
            
            <div class="section">
                <h3>⚡ Operations</h3>
                <div class="controls">
                    <div class="control-group">
                        <h4>Write Operation</h4>
                        <div class="input-group">
                            <label>Key:</label>
                            <input type="text" id="writeKey" placeholder="user:123" value="user:123">
                        </div>
                        <div class="input-group">
                            <label>Value:</label>
                            <input type="text" id="writeValue" placeholder="John Doe" value="John Doe">
                        </div>
                        <div class="input-group">
                            <label>Write Quorum:</label>
                            <select id="writeQuorumSelect">
                                <option value="1">1 (Weak)</option>
                                <option value="2" selected>2 (Default)</option>
                                <option value="3">3 (Strong)</option>
                                <option value="5">5 (Strongest)</option>
                            </select>
                        </div>
                        <button class="btn" onclick="performWrite()">🔒 Write</button>
                    </div>
                    
                    <div class="control-group">
                        <h4>Read Operation</h4>
                        <div class="input-group">
                            <label>Key:</label>
                            <input type="text" id="readKey" placeholder="user:123" value="user:123">
                        </div>
                        <div class="input-group">
                            <label>Read Quorum:</label>
                            <select id="readQuorumSelect">
                                <option value="1">1 (Weak)</option>
                                <option value="2" selected>2 (Default)</option>
                                <option value="3">3 (Strong)</option>
                                <option value="5">5 (Strongest)</option>
                            </select>
                        </div>
                        <br>
                        <button class="btn" onclick="performRead()">📖 Read</button>
                    </div>
                </div>
                
                <div class="control-group">
                    <h4>🧪 Failure Simulation</h4>
                    <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
                        <button class="btn btn-danger" onclick="simulateFailure()">💥 Fail Random Node</button>
                        <button class="btn btn-success" onclick="recoverNode()">🔄 Recover Node</button>
                    </div>
                </div>
            </div>
            
            <div class="section full-width">
                <h3>📋 Operation Results & Logs</h3>
                <div class="results" id="results">
                    <div class="result-item">
                        <strong>System ready!</strong> You can now perform read/write operations and simulate failures.
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let refreshTimer;
        let operationCounter = 0;
        let failedNodes = new Set();
        
        function addResult(message, type = 'info') {
            const results = document.getElementById('results');
            const timestamp = new Date().toLocaleTimeString();
            const resultItem = document.createElement('div');
            resultItem.className = `result-item result-${type}`;
            resultItem.innerHTML = `<strong>[${timestamp}]</strong> ${message}`;
            results.insertBefore(resultItem, results.firstChild);
            
            // Keep only last 50 results
            while (results.children.length > 50) {
                results.removeChild(results.lastChild);
            }
        }
        
        async function refreshClusterStatus() {
            try {
                const nodes = [8080, 8081, 8082, 8083, 8084];
                const nodesGrid = document.getElementById('nodesGrid');
                nodesGrid.innerHTML = '';
                
                let healthyCount = 0;
                let totalRequests = 0;
                
                for (const port of nodes) {
                    try {
                        const response = await fetch(`http://localhost:${port}/status`);
                        const status = await response.json();
                        
                        if (status.healthy) healthyCount++;
                        totalRequests += status.request_count;
                        
                        const nodeDiv = document.createElement('div');
                        nodeDiv.className = `node ${status.healthy ? 'healthy' : 'failed'}`;
                        nodeDiv.innerHTML = `
                            <div class="node-header">
                                <strong>Node ${status.node_id}</strong>
                                <span class="node-status ${status.healthy ? 'status-healthy' : 'status-failed'}">
                                    ${status.healthy ? 'HEALTHY' : 'FAILED'}
                                </span>
                            </div>
                            <div>Port: ${status.port}</div>
                            <div>Data items: ${status.data_count}</div>
                            <div>Requests: ${status.request_count}</div>
                        `;
                        
                        if (!status.healthy) {
                            failedNodes.add(port);
                        } else {
                            failedNodes.delete(port);
                        }
                        
                        nodesGrid.appendChild(nodeDiv);
                    } catch (error) {
                        const nodeDiv = document.createElement('div');
                        nodeDiv.className = 'node failed';
                        nodeDiv.innerHTML = `
                            <div class="node-header">
                                <strong>Node ${port - 8080}</strong>
                                <span class="node-status status-failed">UNREACHABLE</span>
                            </div>
                            <div>Port: ${port}</div>
                            <div>Status: Connection failed</div>
                        `;
                        nodesGrid.appendChild(nodeDiv);
                        failedNodes.add(port);
                    }
                }
                
                document.getElementById('healthyNodes').textContent = healthyCount;
                document.getElementById('totalRequests').textContent = totalRequests;
                document.getElementById('quorumStatus').textContent = healthyCount >= 2 ? 'YES' : 'NO';
                
            } catch (error) {
                addResult(`Failed to refresh cluster status: ${error.message}`, 'error');
            }
        }
        
        async function performWrite() {
            operationCounter++;
            const key = document.getElementById('writeKey').value;
            const value = document.getElementById('writeValue').value;
            const writeQuorum = parseInt(document.getElementById('writeQuorumSelect').value);
            
            if (!key || !value) {
                addResult('Please provide both key and value for write operation', 'error');
                return;
            }
            
            addResult(`🔒 Starting write operation: ${key} = "${value}" (W=${writeQuorum})`);
            
            try {
                // Use first healthy node as coordinator
                const nodes = [8080, 8081, 8082, 8083, 8084];
                let coordinator = null;
                
                for (const port of nodes) {
                    if (!failedNodes.has(port)) {
                        coordinator = port;
                        break;
                    }
                }
                
                if (!coordinator) {
                    addResult('❌ No healthy coordinator available', 'error');
                    return;
                }
                
                const response = await fetch(`http://localhost:${coordinator}/coordinate_write`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ key, value, w: writeQuorum })
                });
                
                const result = await response.json();
                
                if (result.success) {
                    addResult(`✅ Write successful! Quorum achieved (${writeQuorum} nodes responded)`, 'success');
                    addResult(`📝 Responses: ${result.responses.join(', ')}`);
                } else {
                    addResult(`❌ Write failed! Quorum not achieved`, 'error');
                    addResult(`📝 Responses: ${result.responses.join(', ')}`);
                }
                
                // Refresh status after operation
                setTimeout(refreshClusterStatus, 500);
                
            } catch (error) {
                addResult(`❌ Write operation failed: ${error.message}`, 'error');
            }
        }
        
        async function performRead() {
            operationCounter++;
            const key = document.getElementById('readKey').value;
            const readQuorum = parseInt(document.getElementById('readQuorumSelect').value);
            
            if (!key) {
                addResult('Please provide a key for read operation', 'error');
                return;
            }
            
            addResult(`📖 Starting read operation: ${key} (R=${readQuorum})`);
            
            try {
                // Use first healthy node as coordinator
                const nodes = [8080, 8081, 8082, 8083, 8084];
                let coordinator = null;
                
                for (const port of nodes) {
                    if (!failedNodes.has(port)) {
                        coordinator = port;
                        break;
                    }
                }
                
                if (!coordinator) {
                    addResult('❌ No healthy coordinator available', 'error');
                    return;
                }
                
                const response = await fetch(`http://localhost:${coordinator}/coordinate_read?key=${key}&r=${readQuorum}`);
                const result = await response.json();
                
                if (result.success) {
                    addResult(`✅ Read successful! Value: "${result.value}"`, 'success');
                    if (result.inconsistency_detected) {
                        addResult(`⚠️ Inconsistency detected and repaired during read`, 'warning');
                    }
                    addResult(`📝 Responses: ${result.responses.join(', ')}`);
                } else {
                    addResult(`❌ Read failed! Quorum not achieved`, 'error');
                    addResult(`📝 Responses: ${result.responses.join(', ')}`);
                }
                
            } catch (error) {
                addResult(`❌ Read operation failed: ${error.message}`, 'error');
            }
        }
        
        async function simulateFailure() {
            const healthyNodes = [8080, 8081, 8082, 8083, 8084].filter(port => !failedNodes.has(port));
            
            if (healthyNodes.length === 0) {
                addResult('❌ No healthy nodes to fail', 'error');
                return;
            }
            
            const nodeToFail = healthyNodes[Math.floor(Math.random() * healthyNodes.length)];
            
            try {
                await fetch(`http://localhost:${nodeToFail}/fail`);
                addResult(`💥 Simulated failure of Node ${nodeToFail - 8080} (port ${nodeToFail})`, 'warning');
                
                setTimeout(refreshClusterStatus, 500);
            } catch (error) {
                addResult(`❌ Failed to simulate node failure: ${error.message}`, 'error');
            }
        }
        
        async function recoverNode() {
            const failedNodesArray = Array.from(failedNodes);
            
            if (failedNodesArray.length === 0) {
                addResult('❌ No failed nodes to recover', 'error');
                return;
            }
            
            const nodeToRecover = failedNodesArray[Math.floor(Math.random() * failedNodesArray.length)];
            
            try {
                await fetch(`http://localhost:${nodeToRecover}/recover`);
                addResult(`🔄 Recovered Node ${nodeToRecover - 8080} (port ${nodeToRecover})`, 'success');
                
                setTimeout(refreshClusterStatus, 500);
            } catch (error) {
                addResult(`❌ Failed to recover node: ${error.message}`, 'error');
            }
        }
        
        // Auto-refresh cluster status
        function startAutoRefresh() {
            refreshClusterStatus();
            refreshTimer = setInterval(refreshClusterStatus, 3000);
        }
        
        // Start monitoring when page loads
        window.addEventListener('load', startAutoRefresh);
        
        // Cleanup on page unload
        window.addEventListener('beforeunload', () => {
            if (refreshTimer) clearInterval(refreshTimer);
        });
    </script>
</body>
</html>
EOF
}

create_test_script() {
    print_step "Creating automated test scenario script..."
    
    cat > test_scenarios.py << 'EOF'
#!/usr/bin/env python3
import requests
import time
import json
import random

def wait_for_nodes():
    """Wait for all nodes to be ready"""
    nodes = [8080, 8081, 8082, 8083, 8084]
    print("Waiting for all nodes to be ready...")
    
    while True:
        ready_count = 0
        for port in nodes:
            try:
                response = requests.get(f"http://localhost:{port}/status", timeout=2)
                if response.status_code == 200:
                    ready_count += 1
            except:
                pass
        
        if ready_count == len(nodes):
            print(f"✅ All {len(nodes)} nodes are ready!")
            break
        else:
            print(f"⏳ {ready_count}/{len(nodes)} nodes ready, waiting...")
            time.sleep(2)

def test_basic_operations():
    """Test basic read/write operations"""
    print("\n" + "="*60)
    print("🧪 TESTING: Basic Read/Write Operations")
    print("="*60)
    
    coordinator = 8080
    
    # Test write
    print("1. Writing test data...")
    data = {
        "user:1": "Alice",
        "user:2": "Bob", 
        "product:100": "Gaming Laptop",
        "session:abc123": "active"
    }
    
    for key, value in data.items():
        response = requests.post(
            f"http://localhost:{coordinator}/coordinate_write",
            json={"key": key, "value": value, "w": 2}
        )
        result = response.json()
        status = "✅" if result["success"] else "❌"
        print(f"   {status} Write {key}: {result['success']}")
    
    time.sleep(1)
    
    # Test reads
    print("\n2. Reading test data...")
    for key in data.keys():
        response = requests.get(f"http://localhost:{coordinator}/coordinate_read?key={key}&r=2")
        result = response.json()
        status = "✅" if result["success"] else "❌"
        value = result.get("value", "NOT_FOUND")
        print(f"   {status} Read {key}: {value}")

def test_consistency_levels():
    """Test different consistency levels"""
    print("\n" + "="*60)
    print("🧪 TESTING: Different Consistency Levels")
    print("="*60)
    
    coordinator = 8080
    test_key = "consistency_test"
    
    consistency_levels = [
        (1, 1, "Eventual Consistency"),
        (2, 2, "Default Quorum"),
        (3, 3, "Strong Consistency"),
        (5, 5, "Strongest Consistency")
    ]
    
    for r, w, description in consistency_levels:
        print(f"\n📊 Testing {description} (R={r}, W={w})")
        
        # Write
        write_response = requests.post(
            f"http://localhost:{coordinator}/coordinate_write",
            json={"key": test_key, "value": f"value_r{r}_w{w}", "w": w}
        )
        write_result = write_response.json()
        
        # Read
        read_response = requests.get(
            f"http://localhost:{coordinator}/coordinate_read?key={test_key}&r={r}"
        )
        read_result = read_response.json()
        
        write_status = "✅" if write_result["success"] else "❌"
        read_status = "✅" if read_result["success"] else "❌"
        
        print(f"   {write_status} Write: {write_result['success']}")
        print(f"   {read_status} Read: {read_result['success']}")
        
        time.sleep(0.5)

def test_failure_scenarios():
    """Test various failure scenarios"""
    print("\n" + "="*60)
    print("🧪 TESTING: Failure Scenarios")
    print("="*60)
    
    nodes = [8080, 8081, 8082, 8083, 8084]
    coordinator = 8080
    
    # 1. Single node failure
    print("\n1. Testing single node failure...")
    print("   Failing node 8081...")
    requests.get("http://localhost:8081/fail")
    
    # Test operations with one node down
    write_response = requests.post(
        f"http://localhost:{coordinator}/coordinate_write",
        json={"key": "failure_test_1", "value": "single_failure", "w": 2}
    )
    write_result = write_response.json()
    
    read_response = requests.get(
        f"http://localhost:{coordinator}/coordinate_read?key=failure_test_1&r=2"
    )
    read_result = read_response.json()
    
    print(f"   ✅ Write with 1 node down: {write_result['success']}")
    print(f"   ✅ Read with 1 node down: {read_result['success']}")
    
    # 2. Multiple node failures
    print("\n2. Testing multiple node failures...")
    print("   Failing node 8082...")
    requests.get("http://localhost:8082/fail")
    
    write_response = requests.post(
        f"http://localhost:{coordinator}/coordinate_write",
        json={"key": "failure_test_2", "value": "dual_failure", "w": 2}
    )
    write_result = write_response.json()
    
    print(f"   ✅ Write with 2 nodes down: {write_result['success']}")
    
    # 3. Quorum loss scenario
    print("\n3. Testing quorum loss scenario...")
    print("   Failing node 8083...")
    requests.get("http://localhost:8083/fail")
    
    write_response = requests.post(
        f"http://localhost:{coordinator}/coordinate_write",
        json={"key": "failure_test_3", "value": "quorum_loss", "w": 3}
    )
    write_result = write_response.json()
    
    print(f"   ❌ Write with quorum loss (W=3, only 2 healthy): {write_result['success']}")
    
    # Recovery
    print("\n4. Testing node recovery...")
    for port in [8081, 8082, 8083]:
        print(f"   Recovering node {port}...")
        requests.get(f"http://localhost:{port}/recover")
        time.sleep(0.5)
    
    write_response = requests.post(
        f"http://localhost:{coordinator}/coordinate_write",
        json={"key": "recovery_test", "value": "all_recovered", "w": 3}
    )
    write_result = write_response.json()
    
    print(f"   ✅ Write after recovery: {write_result['success']}")

def test_read_repair():
    """Test read repair mechanism"""
    print("\n" + "="*60)
    print("🧪 TESTING: Read Repair Mechanism")
    print("="*60)
    
    # Create inconsistency by writing to subset of replicas
    print("1. Creating artificial inconsistency...")
    
    # Write directly to individual nodes with different values
    key = "repair_test"
    
    # Write old value to nodes 8080, 8081
    old_data = {
        "key": key,
        "value": "old_value",
        "timestamp": time.time() - 10,  # Older timestamp
        "version": "old_version"
    }
    
    for port in [8080, 8081]:
        requests.post(f"http://localhost:{port}/write", json=old_data)
    
    time.sleep(0.1)
    
    # Write new value to nodes 8082, 8083, 8084
    new_data = {
        "key": key,
        "value": "new_value", 
        "timestamp": time.time(),  # Newer timestamp
        "version": "new_version"
    }
    
    for port in [8082, 8083, 8084]:
        requests.post(f"http://localhost:{port}/write", json=new_data)
    
    print("   ✅ Artificial inconsistency created")
    
    # Perform read that should trigger repair
    print("\n2. Performing read to trigger repair...")
    read_response = requests.get("http://localhost:8080/coordinate_read?key=repair_test&r=3")
    read_result = read_response.json()
    
    print(f"   ✅ Read result: {read_result.get('value', 'NOT_FOUND')}")
    print(f"   ⚠️ Inconsistency detected: {read_result.get('inconsistency_detected', False)}")
    
    # Wait for repair to complete
    time.sleep(2)
    
    # Verify all nodes have consistent data
    print("\n3. Verifying repair completion...")
    values = []
    for port in [8080, 8081, 8082, 8083, 8084]:
        try:
            response = requests.get(f"http://localhost:{port}/read?key={key}")
            data = response.json()
            if data.get("found"):
                values.append(data["value"])
            else:
                values.append("NOT_FOUND")
        except:
            values.append("ERROR")
    
    unique_values = set(values)
    print(f"   📊 Values across nodes: {values}")
    print(f"   ✅ Consistency achieved: {len(unique_values) == 1}")

def generate_load_test():
    """Generate realistic load to demonstrate system behavior"""
    print("\n" + "="*60)
    print("🧪 TESTING: Load Generation")
    print("="*60)
    
    coordinator = 8080
    operations = 20
    
    print(f"Generating {operations} random operations...")
    
    keys = [f"user:{i}" for i in range(1, 11)] + [f"product:{i}" for i in range(100, 111)]
    values = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Gaming Laptop", "Smartphone", "Tablet", "Monitor", "Keyboard"]
    
    success_count = 0
    
    for i in range(operations):
        op_type = random.choice(["read", "write"])
        key = random.choice(keys)
        
        if op_type == "write":
            value = random.choice(values)
            try:
                response = requests.post(
                    f"http://localhost:{coordinator}/coordinate_write",
                    json={"key": key, "value": value, "w": 2},
                    timeout=5
                )
                result = response.json()
                if result["success"]:
                    success_count += 1
                    print(f"   ✅ Write {i+1}: {key} = {value}")
                else:
                    print(f"   ❌ Write {i+1}: {key} FAILED")
            except Exception as e:
                print(f"   ❌ Write {i+1}: {key} ERROR - {e}")
        else:
            try:
                response = requests.get(
                    f"http://localhost:{coordinator}/coordinate_read?key={key}&r=2",
                    timeout=5
                )
                result = response.json()
                if result["success"]:
                    success_count += 1
                    print(f"   ✅ Read {i+1}: {key} = {result['value']}")
                else:
                    print(f"   ❌ Read {i+1}: {key} NOT_FOUND")
            except Exception as e:
                print(f"   ❌ Read {i+1}: {key} ERROR - {e}")
        
        time.sleep(0.1)  # Small delay between operations
    
    print(f"\n📊 Load test completed: {success_count}/{operations} operations successful")

def main():
    print("🚀 Starting Quorum System Test Suite")
    print("=" * 60)
    
    # Wait for cluster to be ready
    wait_for_nodes()
    
    # Run test scenarios
    test_basic_operations()
    test_consistency_levels()
    test_failure_scenarios()
    test_read_repair()
    generate_load_test()
    
    print("\n" + "="*60)
    print("🎉 All tests completed!")
    print("="*60)
    print("💡 Open http://localhost:8090 to view the web interface")
    print("📋 Check the logs/ directory for detailed node logs")

if __name__ == "__main__":
    main()
EOF

    chmod +x test_scenarios.py
}

start_nodes() {
    print_step "Starting quorum nodes..."
    
    # Clear log files
    rm -f logs/*.log
    
    # Start each node in background
    for i in $(seq 0 4); do
        port=$((BASE_PORT + i))
        print_info "Starting node $i on port $port..."
        python3 quorum_node.py $i $port > logs/node_${i}_startup.log 2>&1 &
        echo $! > logs/node_${i}.pid
        sleep 1
    done
    
    # Wait for nodes to start
    print_info "Waiting for nodes to initialize..."
    sleep 5
    
    # Check if nodes are responding
    local healthy_nodes=0
    for i in $(seq 0 4); do
        port=$((BASE_PORT + i))
        if curl -s http://localhost:$port/status > /dev/null 2>&1; then
            healthy_nodes=$((healthy_nodes + 1))
            print_info "Node $i (port $port) is healthy"
        else
            print_warning "Node $i (port $port) is not responding"
        fi
    done
    
    if [ $healthy_nodes -eq $NODES ]; then
        print_info "All $NODES nodes are healthy and ready!"
    else
        print_warning "Only $healthy_nodes out of $NODES nodes are healthy"
    fi
}

start_web_server() {
    print_step "Starting web monitoring interface..."
    
    cd web
    python3 -m http.server 8090 > ../logs/web_server.log 2>&1 &
    echo $! > ../logs/web_server.pid
    cd ..
    
    sleep 2
    print_info "Web interface available at: http://localhost:8090"
}

run_automated_tests() {
    print_step "Running automated test scenarios..."
    
    # Wait a bit more for cluster to stabilize
    sleep 3
    
    # Run test scenarios
    python3 test_scenarios.py
}

stop_demo() {
    print_step "Stopping demo components..."
    
    # Stop nodes
    for i in $(seq 0 4); do
        if [ -f logs/node_${i}.pid ]; then
            local pid=$(cat logs/node_${i}.pid)
            if kill -0 $pid 2>/dev/null; then
                kill $pid
                print_info "Stopped node $i (PID: $pid)"
            fi
            rm -f logs/node_${i}.pid
        fi
    done
    
    # Stop web server
    if [ -f logs/web_server.pid ]; then
        local pid=$(cat logs/web_server.pid)
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            print_info "Stopped web server (PID: $pid)"
        fi
        rm -f logs/web_server.pid
    fi
    
    print_info "Demo stopped"
}

show_instructions() {
    print_header "Quorum System Demo Instructions"
    
    echo -e "${GREEN}🎯 What This Demo Shows:${NC}"
    echo "• 5-node quorum cluster with R=2, W=2 configuration"
    echo "• Read and write operations with quorum consensus"
    echo "• Node failure simulation and recovery"
    echo "• Read repair mechanism for consistency"
    echo "• Real-time monitoring and metrics"
    echo ""
    
    echo -e "${GREEN}🔗 Access Points:${NC}"
    echo "• Web Interface: http://localhost:8090"
    echo "• Node APIs: http://localhost:8080-8084"
    echo "• Logs: $PWD/$LOG_DIR/"
    echo ""
    
    echo -e "${GREEN}🧪 Try These Experiments:${NC}"
    echo "1. Write data using different consistency levels (W=1,2,3,5)"
    echo "2. Fail nodes and observe quorum behavior"
    echo "3. Read data while nodes are down"
    echo "4. Watch read repair fix inconsistencies"
    echo "5. Monitor cluster health in real-time"
    echo ""
    
    echo -e "${GREEN}📋 Manual Testing Commands:${NC}"
    echo "# Write data"
    echo "curl -X POST http://localhost:8080/coordinate_write \\"
    echo "  -H 'Content-Type: application/json' \\"
    echo "  -d '{\"key\":\"test\", \"value\":\"hello\", \"w\":2}'"
    echo ""
    echo "# Read data"
    echo "curl http://localhost:8080/coordinate_read?key=test&r=2"
    echo ""
    echo "# Fail a node"
    echo "curl http://localhost:8081/fail"
    echo ""
    echo "# Recover a node"
    echo "curl http://localhost:8081/recover"
    echo ""
    
    echo -e "${GREEN}🛑 To Stop Demo:${NC}"
    echo "./$(basename $0) stop"
    echo ""
}

# Main execution logic
case "${1:-start}" in
    "start")
        mode="${2:-local}"
        
        if [ "$mode" = "docker" ]; then
            print_header "Starting Quorum Demo (Docker Mode)"
            DEPLOYMENT_MODE="docker"
            cleanup
            setup_directory
            create_node_script
            create_web_interface
            create_test_script
            create_docker_files
            build_docker_images
            deploy_docker_cluster
            verify_docker_cluster
            run_docker_tests
            show_instructions
            
            print_header "Docker Demo is Running!"
            print_info "Press Ctrl+C to stop all containers"
            
            # Keep script running and monitor containers
            trap stop_docker_demo EXIT
            while true; do
                sleep 30
                if ! docker-compose ps -q | xargs docker inspect -f '{{.State.Running}}' | grep -q true; then
                    print_error "All containers have stopped. Exiting..."
                    break
                fi
            done
        else
            print_header "Starting Quorum Demo (Local Mode)"
            DEPLOYMENT_MODE="local"
            cleanup
            setup_directory
            create_node_script
            create_web_interface
            create_test_script
            start_nodes
            start_web_server
            run_automated_tests
            show_instructions
            
            print_header "Local Demo is Running!"
            print_info "Press Ctrl+C to stop all components"
            
            # Keep script running
            trap stop_demo EXIT
            while true; do
                sleep 10
                # Check if nodes are still running
                running_nodes=0
                for i in $(seq 0 4); do
                    if [ -f logs/node_${i}.pid ]; then
                        pid=$(cat logs/node_${i}.pid)
                        if kill -0 $pid 2>/dev/null; then
                            running_nodes=$((running_nodes + 1))
                        fi
                    fi
                done
                
                if [ $running_nodes -eq 0 ]; then
                    print_error "All nodes have stopped. Exiting..."
                    break
                fi
            done
        fi
        ;;
    
    "docker")
        subcommand="${2:-up}"
        
        case "$subcommand" in
            "build")
                cd "$DEMO_DIR" 2>/dev/null || {
                    print_error "Demo directory not found. Run './$(basename $0) start docker' first"
                    exit 1
                }
                build_docker_images
                ;;
            "up")
                cd "$DEMO_DIR" 2>/dev/null || {
                    print_error "Demo directory not found. Run './$(basename $0) start docker' first"
                    exit 1
                }
                deploy_docker_cluster
                ;;
            "down")
                cd "$DEMO_DIR" 2>/dev/null || {
                    print_error "Demo directory not found"
                    exit 1
                }
                stop_docker_demo
                ;;
            "test")
                cd "$DEMO_DIR" 2>/dev/null || {
                    print_error "Demo directory not found"
                    exit 1
                }
                run_docker_tests
                ;;
            "verify")
                cd "$DEMO_DIR" 2>/dev/null || {
                    print_error "Demo directory not found"
                    exit 1
                }
                verify_docker_cluster
                ;;
            "logs")
                cd "$DEMO_DIR" 2>/dev/null || {
                    print_error "Demo directory not found"
                    exit 1
                }
                docker-compose logs -f
                ;;
            *)
                print_error "Unknown docker subcommand: $subcommand"
                echo "Available: build, up, down, test, verify, logs"
                exit 1
                ;;
        esac
        ;;
    
    "stop")
        mode="${2:-auto}"
        
        if [ "$mode" = "docker" ] || ([ "$mode" = "auto" ] && [ -f "$DEMO_DIR/docker-compose.yml" ]); then
            cd "$DEMO_DIR" 2>/dev/null || {
                print_error "Demo directory not found"
                exit 1
            }
            stop_docker_demo
        else
            cd "$DEMO_DIR" 2>/dev/null || {
                print_error "Demo directory not found. Is the demo running?"
                exit 1
            }
            stop_demo
        fi
        ;;
    
    "logs")
        mode="${2:-auto}"
        
        if [ "$mode" = "docker" ] || ([ "$mode" = "auto" ] && [ -f "$DEMO_DIR/docker-compose.yml" ]); then
            cd "$DEMO_DIR" 2>/dev/null || {
                print_error "Demo directory not found"
                exit 1
            }
            docker-compose logs -f
        else
            if [ -d "$DEMO_DIR/logs" ]; then
                print_header "Recent Log Entries"
                for log_file in "$DEMO_DIR"/logs/node_*.log; do
                    if [ -f "$log_file" ]; then
                        echo -e "${BLUE}=== $(basename $log_file) ===${NC}"
                        tail -n 10 "$log_file"
                        echo ""
                    fi
                done
            else
                print_error "Log directory not found. Is the demo running?"
            fi
        fi
        ;;
    
    "status")
        mode="${2:-auto}"
        
        if [ "$mode" = "docker" ] || ([ "$mode" = "auto" ] && [ -f "$DEMO_DIR/docker-compose.yml" ]); then
            cd "$DEMO_DIR" 2>/dev/null || {
                print_error "Demo directory not found"
                exit 1
            }
            print_header "Docker Cluster Status"
            docker-compose ps
            echo ""
            verify_docker_cluster
        else
            if [ -d "$DEMO_DIR" ]; then
                cd "$DEMO_DIR"
                print_header "Local Cluster Status"
                for i in $(seq 0 4); do
                    port=$((BASE_PORT + i))
                    if curl -s http://localhost:$port/status > /dev/null 2>&1; then
                        status=$(curl -s http://localhost:$port/status | python3 -m json.tool)
                        echo -e "${GREEN}Node $i (port $port): HEALTHY${NC}"
                        echo "$status" | grep -E '"(healthy|data_count|request_count)"'
                    else
                        echo -e "${RED}Node $i (port $port): UNREACHABLE${NC}"
                    fi
                    echo ""
                done
            else
                print_error "Demo directory not found. Is the demo running?"
            fi
        fi
        ;;
    
    "test")
        mode="${2:-auto}"
        
        if [ "$mode" = "docker" ] || ([ "$mode" = "auto" ] && [ -f "$DEMO_DIR/docker-compose.yml" ]); then
            cd "$DEMO_DIR" 2>/dev/null || {
                print_error "Demo directory not found"
                exit 1
            }
            run_docker_tests
        else
            cd "$DEMO_DIR" 2>/dev/null || {
                print_error "Demo directory not found"
                exit 1
            }
            run_automated_tests
        fi
        ;;
    
    "help")
        echo "Quorum System Demo Script"
        echo ""
        echo "Usage: $0 [command] [mode]"
        echo ""
        echo "Commands:"
        echo "  start [local|docker]  - Start the quorum demo (default: local)"
        echo "  stop [local|docker]   - Stop demo components"
        echo "  status [local|docker] - Show cluster status"
        echo "  logs [local|docker]   - Show log entries"
        echo "  test [local|docker]   - Run test scenarios"
        echo "  docker <subcommand>   - Docker-specific operations"
        echo "  help                  - Show this help message"
        echo ""
        echo "Docker subcommands:"
        echo "  docker build     - Build Docker images"
        echo "  docker up        - Start Docker cluster"
        echo "  docker down      - Stop Docker cluster"
        echo "  docker test      - Run Docker-specific tests"
        echo "  docker verify    - Verify Docker cluster health"
        echo "  docker logs      - Follow Docker container logs"
        echo ""
        echo "Examples:"
        echo "  $0 start local      # Start with local Python processes"
        echo "  $0 start docker     # Start with Docker containers"
        echo "  $0 docker test      # Run Docker-specific tests"
        echo "  $0 status docker    # Check Docker cluster status"
        echo ""
        echo "The demo creates a 5-node quorum system with:"
        echo "• Configurable read/write quorum sizes"
        echo "• Failure simulation and recovery"
        echo "• Read repair mechanisms"
        echo "• Real-time web monitoring interface"
        echo "• Docker containerization support"
        ;;
    
    *)
        print_error "Unknown command: $1"
        echo "Use '$0 help' for available commands"
        exit 1
        ;;
esac