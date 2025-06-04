#!/usr/bin/env python3
import requests
import time
import json
import random
import os
import threading

# Configure for Docker mode
DOCKER_MODE = True
BASE_URL = "http://localhost"

def wait_for_nodes():
    """Wait for all nodes to be ready"""
    nodes = [8080, 8081, 8082, 8083, 8084]
    print("🐳 Waiting for Docker nodes to be ready...")
    
    max_attempts = 30
    attempt = 0
    
    while attempt < max_attempts:
        ready_count = 0
        for port in nodes:
            try:
                response = requests.get(f"{BASE_URL}:{port}/status", timeout=2)
                if response.status_code == 200:
                    ready_count += 1
            except:
                pass
        
        if ready_count == len(nodes):
            print(f"✅ All {len(nodes)} Docker nodes are ready!")
            break
        else:
            print(f"⏳ {ready_count}/{len(nodes)} nodes ready, waiting... (attempt {attempt + 1}/{max_attempts})")
            time.sleep(2)
            attempt += 1
    
    if attempt >= max_attempts:
        print("❌ Timeout waiting for nodes to be ready")
        return False
    
    return True

def test_docker_networking():
    """Test inter-container communication"""
    print("\n🔗 Testing Docker networking...")
    
    coordinator = f"{BASE_URL}:8080"
    
    # Test write that requires inter-container communication
    try:
        response = requests.post(
            f"{coordinator}/coordinate_write",
            json={"key": "docker_test", "value": "networking_test", "w": 3},
            timeout=10
        )
        
        result = response.json()
        if result["success"]:
            print("✅ Docker inter-container communication working")
            return True
        else:
            print("❌ Docker networking issues detected")
            print(f"Responses: {result.get('responses', [])}")
            return False
    except Exception as e:
        print(f"❌ Docker networking test failed: {e}")
        return False

def test_docker_persistence():
    """Test data persistence across container operations"""
    print("\n💾 Testing Docker data persistence...")
    
    coordinator = f"{BASE_URL}:8080"
    
    # Write test data
    test_data = {
        "persistence_test_1": "data_1",
        "persistence_test_2": "data_2",
        "persistence_test_3": "data_3"
    }
    
    try:
        for key, value in test_data.items():
            response = requests.post(
                f"{coordinator}/coordinate_write",
                json={"key": key, "value": value, "w": 2},
                timeout=10
            )
            if not response.json()["success"]:
                print(f"❌ Failed to write {key}")
                return False
        
        # Verify reads
        for key, expected_value in test_data.items():
            response = requests.get(f"{coordinator}/coordinate_read?key={key}&r=2", timeout=10)
            result = response.json()
            
            if result["success"] and result["value"] == expected_value:
                print(f"✅ Persistence verified for {key}")
            else:
                print(f"❌ Persistence failed for {key}")
                return False
        
        return True
    except Exception as e:
        print(f"❌ Docker persistence test failed: {e}")
        return False

def test_docker_scaling():
    """Test behavior under Docker resource constraints"""
    print("\n📈 Testing Docker scaling behavior...")
    
    coordinator = f"{BASE_URL}:8080"
    
    # Generate concurrent load
    results = {"success": 0, "failed": 0}
    
    def worker():
        for i in range(5):
            try:
                response = requests.post(
                    f"{coordinator}/coordinate_write",
                    json={"key": f"scale_test_{threading.current_thread().ident}_{i}", 
                          "value": f"value_{i}", "w": 2},
                    timeout=10
                )
                if response.json()["success"]:
                    results["success"] += 1
                else:
                    results["failed"] += 1
            except:
                results["failed"] += 1
    
    # Create 3 worker threads
    threads = []
    for _ in range(3):
        t = threading.Thread(target=worker)
        threads.append(t)
        t.start()
    
    for t in threads:
        t.join()
    
    total_ops = results["success"] + results["failed"]
    success_rate = results["success"] / total_ops if total_ops > 0 else 0
    
    print(f"📊 Scale test: {results['success']}/{total_ops} operations successful ({success_rate:.1%})")
    
    return success_rate > 0.8

def main():
    print("🐳 Starting Docker-based Quorum System Tests")
    print("=" * 60)
    
    if not wait_for_nodes():
        return False
    
    tests = [
        ("Docker Networking", test_docker_networking),
        ("Data Persistence", test_docker_persistence), 
        ("Scaling Behavior", test_docker_scaling)
    ]
    
    passed = 0
    for test_name, test_func in tests:
        try:
            if test_func():
                print(f"✅ {test_name}: PASSED")
                passed += 1
            else:
                print(f"❌ {test_name}: FAILED")
        except Exception as e:
            print(f"❌ {test_name}: ERROR - {e}")
    
    print(f"\n🎯 Docker tests completed: {passed}/{len(tests)} passed")
    
    if passed == len(tests):
        print("🎉 All Docker tests passed!")
        return True
    else:
        print("⚠️  Some Docker tests failed")
        return False

if __name__ == "__main__":
    success = main()
    exit(0 if success else 1)
