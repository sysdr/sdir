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
