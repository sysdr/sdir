#!/usr/bin/env python3
"""
Docker-specific test runner for Paxos demonstration
Tests containerized deployment and multi-container orchestration
"""

import subprocess
import time
import json
import requests
import sys

def run_command(cmd, description):
    """Run shell command and return success status"""
    print(f"🔧 {description}")
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        if result.returncode == 0:
            print(f"✅ Success: {description}")
            return True
        else:
            print(f"❌ Failed: {description}")
            print(f"Error: {result.stderr}")
            return False
    except subprocess.TimeoutExpired:
        print(f"⏰ Timeout: {description}")
        return False

def test_docker_build():
    """Test Docker image builds successfully"""
    return run_command("docker build -t paxos-demo .", "Building Docker image")

def test_container_health():
    """Test container starts and responds to health checks"""
    print("🔧 Testing container health")
    
    # Start container in detached mode
    start_cmd = "docker run -d -p 8080:8080 --name paxos-test paxos-demo"
    if not run_command(start_cmd, "Starting test container"):
        return False
    
    # Wait for container to be ready
    time.sleep(10)
    
    # Check if container is running
    check_cmd = "docker ps --filter name=paxos-test --format '{{.Status}}'"
    result = subprocess.run(check_cmd, shell=True, capture_output=True, text=True)
    
    # Cleanup
    run_command("docker stop paxos-test", "Stopping test container")
    run_command("docker rm paxos-test", "Removing test container")
    
    if "Up" in result.stdout:
        print("✅ Container health check passed")
        return True
    else:
        print("❌ Container health check failed")
        return False

def test_docker_compose():
    """Test docker-compose orchestration"""
    print("🔧 Testing Docker Compose orchestration")
    
    # Start services
    if not run_command("docker-compose up -d", "Starting Docker Compose services"):
        return False
    
    # Wait for services to be ready
    time.sleep(15)
    
    # Check service status
    status_cmd = "docker-compose ps --format json"
    try:
        result = subprocess.run(status_cmd, shell=True, capture_output=True, text=True)
        services = json.loads(result.stdout) if result.stdout else []
        
        running_services = [s for s in services if 'running' in s.get('State', '').lower()]
        print(f"✅ Docker Compose: {len(running_services)} services running")
        
        # Cleanup
        run_command("docker-compose down", "Stopping Docker Compose services")
        return len(running_services) > 0
        
    except (json.JSONDecodeError, Exception) as e:
        print(f"❌ Error checking service status: {e}")
        run_command("docker-compose down", "Cleanup after error")
        return False

def test_web_interface_accessibility():
    """Test web interface is accessible in container"""
    print("🔧 Testing web interface accessibility")
    
    # Start web service
    start_cmd = "docker run -d -p 8081:8080 --name paxos-web-test paxos-demo python3 start_web_server.py"
    if not run_command(start_cmd, "Starting web interface container"):
        return False
    
    # Wait for service to start
    time.sleep(5)
    
    # Test web accessibility
    try:
        response = requests.get("http://localhost:8081", timeout=10)
        accessible = response.status_code == 200
        
        if accessible:
            print("✅ Web interface accessible")
        else:
            print(f"❌ Web interface returned status {response.status_code}")
            
    except requests.RequestException as e:
        print(f"❌ Web interface not accessible: {e}")
        accessible = False
    
    # Cleanup
    run_command("docker stop paxos-web-test", "Stopping web test container")
    run_command("docker rm paxos-web-test", "Removing web test container")
    
    return accessible

def test_volume_persistence():
    """Test that volumes persist data correctly"""
    print("🔧 Testing volume persistence")
    
    # Start container with volume
    start_cmd = "docker run -d -v $(pwd)/test_logs:/app/logs --name paxos-volume-test paxos-demo"
    if not run_command(start_cmd, "Starting container with volume"):
        return False
    
    # Wait for simulation to generate some logs
    time.sleep(10)
    
    # Check if logs were created in volume
    check_cmd = "test -f test_logs/paxos_simulation.log"
    log_exists = run_command(check_cmd, "Checking log file in volume")
    
    # Cleanup
    run_command("docker stop paxos-volume-test", "Stopping volume test container")
    run_command("docker rm paxos-volume-test", "Removing volume test container")
    run_command("rm -rf test_logs", "Cleaning up test logs")
    
    return log_exists

def main():
    """Run all Docker tests"""
    print("🐳 Docker Integration Test Suite for Paxos Demo")
    print("=" * 60)
    
    tests = [
        ("Docker Build", test_docker_build),
        ("Container Health", test_container_health),
        ("Docker Compose", test_docker_compose),
        ("Web Interface", test_web_interface_accessibility),
        ("Volume Persistence", test_volume_persistence)
    ]
    
    results = {}
    
    for test_name, test_func in tests:
        print(f"\n📋 Running {test_name} Test")
        print("-" * 40)
        results[test_name] = test_func()
    
    # Summary
    print("\n📊 Test Results Summary")
    print("=" * 30)
    
    passed = sum(results.values())
    total = len(results)
    
    for test_name, result in results.items():
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{test_name}: {status}")
    
    print(f"\nOverall: {passed}/{total} tests passed")
    
    if passed == total:
        print("🎉 All Docker tests passed! The containerized Paxos demo is ready.")
        return 0
    else:
        print("⚠️  Some tests failed. Check the output above for details.")
        return 1

if __name__ == "__main__":
    sys.exit(main())
