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
