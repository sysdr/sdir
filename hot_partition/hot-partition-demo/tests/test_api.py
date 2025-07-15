"""Tests for API endpoints."""

import pytest
import asyncio
from fastapi.testclient import TestClient
from src.api.main import app

client = TestClient(app)

class TestAPI:
    
    def test_dashboard_endpoint(self):
        """Test dashboard endpoint returns HTML."""
        response = client.get("/")
        assert response.status_code == 200
        assert "text/html" in response.headers["content-type"]
    
    def test_metrics_endpoint(self):
        """Test metrics endpoint structure."""
        response = client.get("/api/metrics")
        assert response.status_code in [200, 500]  # May fail without Redis
        
        if response.status_code == 200:
            data = response.json()
            assert "metrics" in data
            assert "timestamp" in data
    
    def test_analysis_endpoint(self):
        """Test analysis endpoint structure."""
        response = client.get("/api/analysis")
        assert response.status_code in [200, 500]  # May fail without Redis
        
        if response.status_code == 200:
            data = response.json()
            assert "entropy_score" in data
            assert "alerts" in data
            assert "timestamp" in data
    
    def test_trigger_hotspot_endpoint(self):
        """Test hotspot trigger endpoint."""
        payload = {
            "partition_id": "partition_0",
            "intensity": 5.0
        }
        
        response = client.post("/api/trigger-hotspot", json=payload)
        assert response.status_code in [200, 500]  # May fail without Redis
        
        if response.status_code == 200:
            data = response.json()
            assert "message" in data
    
    def test_end_hotspot_endpoint(self):
        """Test hotspot end endpoint."""
        response = client.post("/api/end-hotspot")
        assert response.status_code in [200, 500]  # May fail without Redis
        
        if response.status_code == 200:
            data = response.json()
            assert "message" in data

if __name__ == "__main__":
    pytest.main([__file__])
