#!/usr/bin/env python3
import requests
import time
import json
import sys

def test_service_health(service_name, port):
    """Test service health endpoint"""
    try:
        response = requests.get(f"http://localhost:{port}/health", timeout=10)
        print(f"✅ {service_name} health check: {response.status_code}")
        return response.status_code == 200
    except Exception as e:
        print(f"❌ {service_name} health check failed: {e}")
        return False

def test_service_content(service_name, port):
    """Test service content endpoint"""
    try:
        response = requests.get(f"http://localhost:{port}/", timeout=10)
        print(f"✅ {service_name} content check: {response.status_code}")
        return response.status_code == 200
    except Exception as e:
        print(f"❌ {service_name} content check failed: {e}")
        return False

def test_dashboard():
    """Test dashboard accessibility"""
    try:
        response = requests.get("http://localhost:3000", timeout=10)
        print(f"✅ Dashboard check: {response.status_code}")
        return response.status_code == 200
    except Exception as e:
        print(f"❌ Dashboard check failed: {e}")
        return False

def test_nginx_proxy():
    """Test nginx proxy functionality"""
    try:
        response = requests.get("http://localhost:8000", timeout=10)
        print(f"✅ Nginx proxy check: {response.status_code}")
        return response.status_code == 200
    except Exception as e:
        print(f"❌ Nginx proxy check failed: {e}")
        return False

def test_traffic_switching():
    """Test traffic switching functionality"""
    try:
        # Test switching to green
        response = requests.post("http://localhost:3000/api/switch", 
                               json={"target": "green"}, timeout=10)
        if response.status_code == 200:
            print("✅ Traffic switching to green: SUCCESS")
        else:
            print(f"⚠️ Traffic switching to green: {response.status_code}")
        
        time.sleep(2)
        
        # Test switching back to blue
        response = requests.post("http://localhost:3000/api/switch", 
                               json={"target": "blue"}, timeout=10)
        if response.status_code == 200:
            print("✅ Traffic switching to blue: SUCCESS")
            return True
        else:
            print(f"⚠️ Traffic switching to blue: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Traffic switching test failed: {e}")
        return False

def main():
    print("🧪 Running Blue-Green Deployment Tests")
    print("=" * 50)
    
    # Wait for services to start
    print("⏳ Waiting for services to start...")
    time.sleep(30)
    
    tests = [
        ("Blue Service Health", lambda: test_service_health("Blue", 8001)),
        ("Green Service Health", lambda: test_service_health("Green", 8002)),
        ("Blue Service Content", lambda: test_service_content("Blue", 8001)),
        ("Green Service Content", lambda: test_service_content("Green", 8002)),
        ("Dashboard Access", test_dashboard),
        ("Nginx Proxy", test_nginx_proxy),
        ("Traffic Switching", test_traffic_switching)
    ]
    
    passed = 0
    failed = 0
    
    for test_name, test_func in tests:
        print(f"\n🔍 Testing: {test_name}")
        try:
            if test_func():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"❌ {test_name} failed with exception: {e}")
            failed += 1
    
    print("\n" + "=" * 50)
    print(f"📊 Test Results: {passed} passed, {failed} failed")
    
    if failed == 0:
        print("🎉 All tests passed! Blue-Green deployment is working correctly.")
        return 0
    else:
        print("⚠️ Some tests failed. Check the logs above for details.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
