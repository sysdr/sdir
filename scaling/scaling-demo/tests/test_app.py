import pytest
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), '..', 'backend'))

from app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_health_check(client):
    """Test health check endpoint"""
    response = client.get('/api/health')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'healthy'

def test_metrics_endpoint(client):
    """Test metrics endpoint"""
    response = client.get('/api/metrics')
    assert response.status_code == 200
    data = response.get_json()
    assert 'user_count' in data
    assert 'response_time' in data
    assert 'throughput' in data
    assert 'error_rate' in data

def test_architecture_endpoint(client):
    """Test architecture endpoint"""
    response = client.get('/api/architecture')
    assert response.status_code == 200
    data = response.get_json()
    assert 'current_stage' in data
    assert 'stage_info' in data

def test_scale_up(client):
    """Test scale up functionality"""
    response = client.post('/api/scale-up')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'Scaled up successfully'

def test_reset_demo(client):
    """Test demo reset"""
    response = client.post('/api/reset')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'Demo reset successfully'

def test_traffic_spike(client):
    """Test traffic spike simulation"""
    response = client.post('/api/traffic-spike')
    assert response.status_code == 200
    data = response.get_json()
    assert data['status'] == 'Traffic spike triggered'
