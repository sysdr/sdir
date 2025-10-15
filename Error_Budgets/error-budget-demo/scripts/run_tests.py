import subprocess
import time
import requests
import sys

def wait_for_service(url, timeout=60):
    """Wait for service to be ready"""
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            response = requests.get(url, timeout=5)
            if response.status_code == 200:
                return True
        except:
            pass
        time.sleep(2)
    return False

def run_tests():
    """Run all tests after services are ready"""
    print("⏳ Waiting for services to be ready...")
    
    if not wait_for_service('http://localhost:3000'):
        print("❌ Dashboard service not ready")
        return False
        
    print("✅ Services ready, running tests...")
    
    # Run pytest
    result = subprocess.run(['python', '-m', 'pytest', 'tests/', '-v'], 
                          capture_output=True, text=True)
    
    print(result.stdout)
    if result.stderr:
        print("Errors:", result.stderr)
        
    return result.returncode == 0

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
