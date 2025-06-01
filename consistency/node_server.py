#!/usr/bin/env python3
import json
import time
import threading
import http.server
import socketserver
import urllib.request
import urllib.parse
from datetime import datetime
import sys
import os

class DistributedNode:
    def __init__(self, config_file):
        with open(config_file, 'r') as f:
            self.config = json.load(f)
        
        self.node_id = self.config['node_id']
        self.port = self.config['port']
        self.data = {}
        self.vector_clock = {}
        self.partition_mode = False
        self.load_data()
        
        # Initialize vector clock
        for peer in self.config['peers']:
            self.vector_clock[peer['id']] = 0
        self.vector_clock[self.node_id] = 0
    
    def load_data(self):
        """Load existing data from disk"""
        try:
            with open(self.config['data_file'], 'r') as f:
                content = f.read().strip()
                if content:  # Check if file has content
                    self.data = json.loads(content)
                else:
                    self.data = {}  # Empty file, initialize with empty dict
        except (FileNotFoundError, json.JSONDecodeError):
            self.data = {}  # Handle both missing file and invalid JSON
    
    def save_data(self):
        """Persist data to disk"""
        with open(self.config['data_file'], 'w') as f:
            json.dump(self.data, f, indent=2)
    
    def log(self, message):
        """Log message with timestamp"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log_entry = f"[{timestamp}] Node {self.node_id}: {message}\n"
        
        with open(self.config['log_file'], 'a') as f:
            f.write(log_entry)
        
        print(log_entry.strip())
    
    def increment_clock(self):
        """Increment local vector clock"""
        self.vector_clock[self.node_id] += 1
    
    def merge_clocks(self, remote_clock):
        """Merge vector clocks for causality"""
        for node_id, timestamp in remote_clock.items():
            if node_id in self.vector_clock:
                self.vector_clock[node_id] = max(self.vector_clock[node_id], timestamp)
    
    def get_available_peers(self):
        """Get list of reachable peers"""
        if self.partition_mode:
            # Simulate partition by making some peers unreachable
            return [peer for peer in self.config['peers'] if peer['id'] % 2 == self.node_id % 2]
        return self.config['peers']
    
    def replicate_to_peers(self, key, value, operation):
        """Replicate operation to peer nodes"""
        available_peers = self.get_available_peers()
        successful_replications = 0
        
        for peer in available_peers:
            try:
                data = {
                    'key': key,
                    'value': value,
                    'operation': operation,
                    'vector_clock': self.vector_clock,
                    'source_node': self.node_id
                }
                
                req = urllib.request.Request(
                    f"http://localhost:{peer['port']}/replicate",
                    data=json.dumps(data).encode('utf-8'),
                    headers={'Content-Type': 'application/json'}
                )
                
                with urllib.request.urlopen(req, timeout=2) as response:
                    if response.getcode() == 200:
                        successful_replications += 1
                        self.log(f"Replicated {operation} {key} to node {peer['id']}")
            
            except Exception as e:
                self.log(f"Failed to replicate to node {peer['id']}: {str(e)}")
        
        return successful_replications
    
    def strong_consistency_write(self, key, value):
        """Write with strong consistency (requires majority)"""
        self.increment_clock()
        
        # Calculate required replicas for majority
        total_nodes = len(self.config['peers']) + 1  # Including self
        required_replicas = (total_nodes // 2) + 1
        
        # Attempt replication
        successful_replications = self.replicate_to_peers(key, value, 'write')
        
        if successful_replications >= (required_replicas - 1):  # -1 because we count local write
            self.data[key] = {
                'value': value,
                'vector_clock': self.vector_clock.copy(),
                'timestamp': time.time()
            }
            self.save_data()
            self.log(f"Strong write successful: {key}={value}")
            return True, "Write successful"
        else:
            self.log(f"Strong write failed: {key}={value} (insufficient replicas)")
            return False, "Insufficient replicas for strong consistency"
    
    def eventual_consistency_write(self, key, value):
        """Write with eventual consistency (best effort)"""
        self.increment_clock()
        
        # Always accept local write
        self.data[key] = {
            'value': value,
            'vector_clock': self.vector_clock.copy(),
            'timestamp': time.time()
        }
        self.save_data()
        
        # Replicate in background (fire and forget)
        threading.Thread(
            target=self.replicate_to_peers,
            args=(key, value, 'write'),
            daemon=True
        ).start()
        
        self.log(f"Eventual write successful: {key}={value}")
        return True, "Write successful (eventual consistency)"
    
    def read_value(self, key):
        """Read value with current consistency mode"""
        if key in self.data:
            return True, self.data[key]['value']
        return False, "Key not found"

class NodeHTTPHandler(http.server.BaseHTTPRequestHandler):
    def __init__(self, node, *args, **kwargs):
        self.node = node
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        """Handle GET requests"""
        if self.path.startswith('/get/'):
            key = self.path[5:]  # Remove '/get/' prefix
            success, value = self.node.read_value(key)
            
            response = {
                'success': success,
                'value': value if success else None,
                'node_id': self.node.node_id,
                'vector_clock': self.node.vector_clock
            }
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        
        elif self.path == '/status':
            status = {
                'node_id': self.node.node_id,
                'data_count': len(self.node.data),
                'vector_clock': self.node.vector_clock,
                'partition_mode': self.node.partition_mode,
                'consistency_mode': self.node.config['consistency_mode']
            }
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(status).encode())
        
        else:
            self.send_response(404)
            self.end_headers()
    
    def do_POST(self):
        """Handle POST requests"""
        content_length = int(self.headers['Content-Length'])
        post_data = self.rfile.read(content_length).decode('utf-8')
        data = json.loads(post_data)
        
        if self.path == '/put':
            key = data['key']
            value = data['value']
            consistency_mode = data.get('consistency_mode', 'strong')
            
            if consistency_mode == 'strong':
                success, message = self.node.strong_consistency_write(key, value)
            else:
                success, message = self.node.eventual_consistency_write(key, value)
            
            response = {
                'success': success,
                'message': message,
                'node_id': self.node.node_id
            }
            
            self.send_response(200 if success else 500)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
        
        elif self.path == '/replicate':
            # Handle replication from other nodes
            key = data['key']
            value = data['value']
            remote_clock = data['vector_clock']
            
            self.node.merge_clocks(remote_clock)
            self.node.data[key] = {
                'value': value,
                'vector_clock': remote_clock,
                'timestamp': time.time()
            }
            self.node.save_data()
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'success': True}).encode())
        
        elif self.path == '/partition':
            # Toggle partition mode
            self.node.partition_mode = data.get('enabled', False)
            self.node.log(f"Partition mode {'enabled' if self.node.partition_mode else 'disabled'}")
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'success': True}).encode())

def create_handler(node):
    def handler(*args, **kwargs):
        return NodeHTTPHandler(node, *args, **kwargs)
    return handler

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 node_server.py <config_file>")
        sys.exit(1)
    
    config_file = sys.argv[1]
    node = DistributedNode(config_file)
    
    handler = create_handler(node)
    with socketserver.TCPServer(("", node.port), handler) as httpd:
        node.log(f"Node {node.node_id} started on port {node.port}")
        httpd.serve_forever()
