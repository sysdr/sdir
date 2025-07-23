"""
Comprehensive test suite for ML inference system
"""
import pytest
import httpx
import asyncio
import time
import json

BASE_URL = "http://localhost:8000"

class TestMLInference:
    """Test suite for ML inference endpoints"""
    
    @pytest.fixture
    async def client(self):
        """Create HTTP client for testing"""
        async with httpx.AsyncClient(timeout=30.0) as client:
            yield client
    
    async def test_health_endpoint(self, client):
        """Test health check endpoint"""
        response = await client.get(f"{BASE_URL}/health")
        assert response.status_code == 200
        
        data = response.json()
        assert "status" in data
        assert data["status"] == "healthy"
        assert "timestamp" in data
        
    async def test_single_prediction(self, client):
        """Test single prediction request"""
        payload = {
            "text": "This is a great product!",
            "id": "test_single"
        }
        
        response = await client.post(f"{BASE_URL}/predict", json=payload)
        assert response.status_code == 200
        
        data = response.json()
        assert "sentiment" in data
        assert "confidence" in data
        assert "latency" in data
        assert "request_id" in data
        assert data["request_id"] == "test_single"
        
    async def test_batch_predictions(self, client):
        """Test multiple concurrent predictions"""
        tasks = []
        
        for i in range(10):
            payload = {
                "text": f"Test message number {i}",
                "id": f"batch_test_{i}"
            }
            task = client.post(f"{BASE_URL}/predict", json=payload)
            tasks.append(task)
            
        responses = await asyncio.gather(*tasks)
        
        assert all(r.status_code == 200 for r in responses)
        
        # Check all responses are valid
        for i, response in enumerate(responses):
            data = response.json()
            assert data["request_id"] == f"batch_test_{i}"
            assert "sentiment" in data
            assert "confidence" in data
            
    async def test_metrics_endpoint(self, client):
        """Test metrics endpoint"""
        response = await client.get(f"{BASE_URL}/metrics")
        assert response.status_code == 200
        
        # Should return Prometheus metrics format
        content = response.text
        assert "ml_inference_requests_total" in content
        
    async def test_stats_endpoint(self, client):
        """Test statistics endpoint"""
        response = await client.get(f"{BASE_URL}/stats")
        assert response.status_code == 200
        
        data = response.json()
        assert "service_stats" in data
        assert "batch_config" in data
        assert "system" in data
        
    async def test_error_handling(self, client):
        """Test error handling for invalid requests"""
        # Test empty text
        response = await client.post(f"{BASE_URL}/predict", json={"text": ""})
        assert response.status_code == 400
        
        # Test missing text field
        response = await client.post(f"{BASE_URL}/predict", json={"id": "test"})
        assert response.status_code == 400
        
    async def test_performance_characteristics(self, client):
        """Test performance under load"""
        start_time = time.time()
        
        # Send 20 concurrent requests
        tasks = []
        for i in range(20):
            payload = {
                "text": f"Performance test message {i}",
                "id": f"perf_test_{i}"
            }
            task = client.post(f"{BASE_URL}/predict", json=payload)
            tasks.append(task)
            
        responses = await asyncio.gather(*tasks)
        total_time = time.time() - start_time
        
        # Verify all succeeded
        assert all(r.status_code == 200 for r in responses)
        
        # Calculate performance metrics
        latencies = [r.json()["latency"] for r in responses]
        avg_latency = sum(latencies) / len(latencies)
        throughput = len(responses) / total_time
        
        print(f"Performance Test Results:")
        print(f"  Requests: {len(responses)}")
        print(f"  Total time: {total_time:.2f}s")
        print(f"  Throughput: {throughput:.1f} req/s")
        print(f"  Avg latency: {avg_latency*1000:.1f}ms")
        
        # Basic performance assertions
        assert avg_latency < 5.0  # Less than 5 seconds average
        assert throughput > 1.0   # At least 1 request per second

if __name__ == "__main__":
    # Run tests directly
    import asyncio
    
    async def run_tests():
        client_fixture = httpx.AsyncClient(timeout=30.0)
        test_instance = TestMLInference()
        
        try:
            print("Running ML Inference Tests...")
            
            await test_instance.test_health_endpoint(client_fixture)
            print("✅ Health endpoint test passed")
            
            await test_instance.test_single_prediction(client_fixture)
            print("✅ Single prediction test passed")
            
            await test_instance.test_batch_predictions(client_fixture)
            print("✅ Batch predictions test passed")
            
            await test_instance.test_metrics_endpoint(client_fixture)
            print("✅ Metrics endpoint test passed")
            
            await test_instance.test_stats_endpoint(client_fixture)
            print("✅ Stats endpoint test passed")
            
            await test_instance.test_error_handling(client_fixture)
            print("✅ Error handling test passed")
            
            await test_instance.test_performance_characteristics(client_fixture)
            print("✅ Performance test passed")
            
            print("\n🎉 All tests passed successfully!")
            
        except Exception as e:
            print(f"❌ Test failed: {e}")
        finally:
            await client_fixture.aclose()
    
    asyncio.run(run_tests())
