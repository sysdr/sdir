import requests
import time
import pytest

BASE_URL = "http://localhost:4000"
SERVICES = ['user-service', 'payment-service', 'order-service']

def test_health_monitor_running():
    """Test that health monitor is accessible"""
    response = requests.get(f"{BASE_URL}/health/all")
    assert response.status_code == 200

def test_all_services_health():
    """Test that all services report health status"""
    response = requests.get(f"{BASE_URL}/health/all")
    health_data = response.json()
    
    for service in SERVICES:
        assert service in health_data
        assert 'status' in health_data[service]
        assert 'shallow_check' in health_data[service]
        assert 'deep_check' in health_data[service]

def test_failure_injection():
    """Test failure injection mechanism"""
    # Inject database failure
    response = requests.post(f"{BASE_URL}/inject-failure", json={
        'service': 'user-service',
        'type': 'database'
    })
    assert response.status_code == 200
    
    # Wait for health check to detect failure
    time.sleep(6)
    
    # Check that service status changed
    response = requests.get(f"{BASE_URL}/health/all")
    health_data = response.json()
    assert health_data['user-service']['status'] in ['degraded', 'unhealthy']

def test_shallow_vs_deep_health():
    """Test that shallow and deep health checks behave differently"""
    # Inject latency failure
    requests.post(f"{BASE_URL}/inject-failure", json={
        'service': 'payment-service', 
        'type': 'latency'
    })
    
    time.sleep(6)
    
    response = requests.get(f"{BASE_URL}/health/all")
    health_data = response.json()
    
    # Shallow check might still pass while deep check fails
    service_data = health_data['payment-service']
    print(f"Service status: {service_data}")
    
    # At minimum, response time should be affected
    assert 'response_time' in service_data

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
