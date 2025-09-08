#!/usr/bin/env python3

import requests
import time
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from collections import defaultdict

def test_health_endpoints():
    """Test that all health endpoints are responding"""
    print("🏥 Testing health endpoints...")
    
    servers = [
        ("healthy-server", "http://localhost:8080/api/shallow/health"),
        ("zombie-server", "http://localhost:8080/api/shallow/health"),
    ]
    
    results = {}
    for name, url in servers:
        try:
            response = requests.get(url, timeout=5)
            results[name] = response.status_code == 200
            print(f"  ✅ {name}: {'PASS' if results[name] else 'FAIL'}")
        except Exception as e:
            results[name] = False
            print(f"  ❌ {name}: FAIL ({e})")
    
    return all(results.values())

def test_zombie_detection():
    """Test that deep health checks can detect zombie servers"""
    print("\n🧟 Testing zombie detection...")
    
    # Test deep health check on zombie server
    try:
        response = requests.get("http://localhost:8080/api/shallow/health/deep", timeout=10)
        if response.status_code == 503:
            print("  ✅ Zombie server correctly identified as unhealthy")
            return True
        else:
            print(f"  ❌ Zombie server not detected (status: {response.status_code})")
            return False
    except Exception as e:
        print(f"  ❌ Failed to test zombie detection: {e}")
        return False

def test_load_balancing_difference():
    """Test that smart routing performs better than shallow routing"""
    print("\n⚖️ Testing load balancing performance difference...")
    
    def make_requests(endpoint, count=10):
        successes = 0
        for _ in range(count):
            try:
                response = requests.get(endpoint, timeout=5)
                if response.status_code == 200:
                    successes += 1
            except:
                pass
        return successes / count

    # Test shallow routing (includes zombies)
    shallow_success = make_requests("http://localhost:8080/api/shallow/api/process", 20)
    
    # Test smart routing (excludes zombies)
    smart_success = make_requests("http://localhost:8080/api/smart/api/process", 20)
    
    print(f"  📊 Shallow routing success rate: {shallow_success*100:.1f}%")
    print(f"  📊 Smart routing success rate: {smart_success*100:.1f}%")
    
    if smart_success > shallow_success * 1.5:
        print("  ✅ Smart routing significantly outperforms shallow routing")
        return True
    else:
        print("  ❌ Smart routing advantage not demonstrated")
        return False

def test_dashboard():
    """Test that dashboard is accessible and functional"""
    print("\n📊 Testing dashboard...")
    
    try:
        # Test dashboard home page
        response = requests.get("http://localhost:8080/", timeout=10)
        if response.status_code == 200:
            print("  ✅ Dashboard accessible")
        else:
            print(f"  ❌ Dashboard not accessible (status: {response.status_code})")
            return False
        
        # Test health status API
        response = requests.get("http://localhost:8080/api/health-status", timeout=10)
        if response.status_code == 200:
            health_data = response.json()
            print(f"  ✅ Health status API working ({len(health_data)} servers)")
            return True
        else:
            print(f"  ❌ Health status API failed (status: {response.status_code})")
            return False
            
    except Exception as e:
        print(f"  ❌ Dashboard test failed: {e}")
        return False

def main():
    print("🧪 Running Zombie Server Detection Tests")
    print("=" * 50)
    
    # Wait for services to start
    print("⏳ Waiting for services to initialize...")
    time.sleep(15)
    
    tests = [
        ("Health Endpoints", test_health_endpoints),
        ("Zombie Detection", test_zombie_detection),
        ("Load Balancing Performance", test_load_balancing_difference),
        ("Dashboard Functionality", test_dashboard),
    ]
    
    results = {}
    for test_name, test_func in tests:
        results[test_name] = test_func()
    
    print("\n📋 Test Results Summary:")
    print("=" * 30)
    for test_name, passed in results.items():
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"{status} {test_name}")
    
    total_passed = sum(results.values())
    total_tests = len(results)
    
    print(f"\n🏆 Tests passed: {total_passed}/{total_tests}")
    
    if total_passed == total_tests:
        print("🎉 All tests passed! Zombie detection system working correctly.")
        return 0
    else:
        print("⚠️  Some tests failed. Check the output above for details.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
