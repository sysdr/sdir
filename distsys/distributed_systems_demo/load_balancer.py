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
