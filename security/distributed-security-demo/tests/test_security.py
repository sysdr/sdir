"""
Security test suite
"""
import asyncio
import pytest
import httpx
import time
import json

class TestSecurityFeatures:
    
    @pytest.mark.asyncio
    async def test_api_gateway_health(self):
        """Test API gateway health endpoint"""
        async with httpx.AsyncClient(verify=False) as client:
            response = await client.get("https://localhost:8000/health")
            assert response.status_code == 200
            data = response.json()
            assert "gateway" in data
            assert data["gateway"] == "healthy"
    
    @pytest.mark.asyncio
    async def test_service_authentication(self):
        """Test service-to-service authentication"""
        async with httpx.AsyncClient(verify=False) as client:
            # Test without authentication
            response = await client.get("https://localhost:8001/security/status")
            assert response.status_code == 401
    
    @pytest.mark.asyncio
    async def test_security_monitor(self):
        """Test security monitoring service"""
        async with httpx.AsyncClient() as client:
            response = await client.get("http://localhost:8080/api/security/status")
            assert response.status_code == 200
            data = response.json()
            assert "threat_detector_trained" in data
    
    @pytest.mark.asyncio
    async def test_threat_detection(self):
        """Test threat detection functionality"""
        async with httpx.AsyncClient() as client:
            malicious_request = {
                "client_ip": "10.0.0.666",
                "requests_per_minute": 200,
                "unique_endpoints": 50,
                "error_rate": 0.9,
                "user_agent": "AttackBot/1.0",
                "payload": "' OR '1'='1' UNION SELECT password FROM users--",
                "response_time": 0.1
            }
            
            response = await client.post(
                "http://localhost:8080/api/security/analyze",
                json=malicious_request
            )
            
            assert response.status_code == 200
            data = response.json()
            assert data["risk_level"] in ["medium", "high"]
            assert data["threats_detected"] > 0

def run_tests():
    """Run all security tests"""
    import subprocess
    import sys
    
    print("Running security tests...")
    
    # Wait for services to be ready
    time.sleep(10)
    
    # Run pytest
    result = subprocess.run([
        sys.executable, "-m", "pytest", 
        "tests/test_security.py", "-v"
    ], capture_output=True, text=True)
    
    print(result.stdout)
    if result.stderr:
        print("Errors:", result.stderr)
    
    return result.returncode == 0

if __name__ == "__main__":
    run_tests()
