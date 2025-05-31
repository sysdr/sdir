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
