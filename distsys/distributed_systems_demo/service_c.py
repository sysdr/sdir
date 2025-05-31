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
