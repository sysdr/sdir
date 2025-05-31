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
