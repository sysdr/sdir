import pytest
import requests
import time
import json

# API base URL
BASE_URL = "http://localhost:5000"

class TestConnectionPoolAPI:
    """Test suite for Connection Pool API endpoints"""
    
    @pytest.fixture(scope="class", autouse=True)
    def wait_for_service(self):
        """Wait for the service to be ready"""
        max_retries = 30
        for _ in range(max_retries):
            try:
                response = requests.get(f"{BASE_URL}/api/health", timeout=5)
                if response.status_code == 200:
                    break
            except:
                pass
            time.sleep(1)
        else:
            pytest.fail("Service did not start within timeout period")
    
    def test_health_endpoint(self):
        """Test health check endpoint"""
        response = requests.get(f"{BASE_URL}/api/health")
        
        assert response.status_code == 200
        data = response.json()
        assert 'app' in data
        assert data['app'] == 'healthy'
    
    def test_config_get(self):
        """Test getting current configuration"""
        response = requests.get(f"{BASE_URL}/api/config")
        
        assert response.status_code == 200
        data = response.json()
        assert 'max_pool_size' in data
        assert 'min_pool_size' in data
        assert 'pool_timeout' in data
    
    def test_config_update(self):
        """Test updating configuration"""
        new_config = {
            'max_pool_size': 8,
            'min_pool_size': 3,
            'pool_timeout': 25
        }
        
        response = requests.post(
            f"{BASE_URL}/api/config",
            json=new_config,
            headers={'Content-Type': 'application/json'}
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'updated'
    
    def test_metrics_endpoint(self):
        """Test metrics retrieval"""
        response = requests.get(f"{BASE_URL}/api/metrics")
        
        assert response.status_code == 200
        data = response.json()
        assert 'pool_size' in data
        assert 'checked_out' in data
        assert 'available' in data
    
    def test_normal_load_scenario(self):
        """Test normal load scenario execution"""
        response = requests.post(f"{BASE_URL}/api/scenarios/normal_load")
        
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'running'
        assert data['scenario'] == 'normal_load'
    
    def test_high_load_scenario(self):
        """Test high load scenario execution"""
        response = requests.post(f"{BASE_URL}/api/scenarios/high_load")
        
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'running'
        assert data['scenario'] == 'high_load'
    
    def test_pool_exhaustion_scenario(self):
        """Test pool exhaustion scenario execution"""
        response = requests.post(f"{BASE_URL}/api/scenarios/pool_exhaustion")
        
        assert response.status_code == 200
        data = response.json()
        assert data['status'] == 'running'
        assert data['scenario'] == 'pool_exhaustion'
    
    def test_invalid_scenario(self):
        """Test invalid scenario handling"""
        response = requests.post(f"{BASE_URL}/api/scenarios/invalid_scenario")
        
        assert response.status_code == 400
        data = response.json()
        assert 'error' in data

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
