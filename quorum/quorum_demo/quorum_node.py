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
