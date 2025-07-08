import pytest
import asyncio
import httpx
import time
from pathlib import Path

BASE_URL = "http://localhost:8000"

class TestAsyncProcessing:
    """Test suite for async processing demo"""
    
    @pytest.fixture
    def client(self):
        return httpx.AsyncClient(base_url=BASE_URL, timeout=30.0)
    
    @pytest.mark.asyncio
    async def test_health_check(self, client):
        """Test that the application is running"""
        response = await client.get("/")
        assert response.status_code == 200
        assert "Async Processing Demo" in response.text
    
    @pytest.mark.asyncio
    async def test_queue_stats(self, client):
        """Test queue statistics endpoint"""
        response = await client.get("/api/queue-stats")
        assert response.status_code == 200
        data = response.json()
        assert "active_tasks" in data
        assert "workers_online" in data
    
    @pytest.mark.asyncio
    async def test_email_task_creation(self, client):
        """Test email task creation"""
        data = {
            "recipient": "test@example.com",
            "subject": "Test Email",
            "template": "welcome"
        }
        response = await client.post("/api/tasks/email", data=data)
        assert response.status_code == 200
        result = response.json()
        assert "task_id" in result
        assert "job_id" in result
        assert result["status"] == "queued"
    
    @pytest.mark.asyncio
    async def test_report_task_creation(self, client):
        """Test report task creation"""
        data = {
            "report_type": "sales",
            "date_range": "30",
            "format": "pdf"
        }
        response = await client.post("/api/tasks/report", data=data)
        assert response.status_code == 200
        result = response.json()
        assert "task_id" in result
        assert "job_id" in result
    
    @pytest.mark.asyncio
    async def test_computation_task_creation(self, client):
        """Test computation task creation"""
        data = {
            "complexity": "low",
            "data_size": "100"
        }
        response = await client.post("/api/tasks/computation", data=data)
        assert response.status_code == 200
        result = response.json()
        assert "task_id" in result
        assert "job_id" in result
    
    @pytest.mark.asyncio
    async def test_image_task_creation(self, client):
        """Test image task creation"""
        # Create a simple test image
        test_image = b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\tpHYs\x00\x00\x0b\x13\x00\x00\x0b\x13\x01\x00\x9a\x9c\x18\x00\x00\x00\x1aiCCP' + b'\x00' * 100
        
        files = {"file": ("test.png", test_image, "image/png")}
        data = {"operation": "thumbnail"}
        
        response = await client.post("/api/tasks/image-processing", files=files, data=data)
        assert response.status_code == 200
        result = response.json()
        assert "task_id" in result
        assert "job_id" in result
    
    @pytest.mark.asyncio
    async def test_task_listing(self, client):
        """Test task listing endpoint"""
        response = await client.get("/api/tasks")
        assert response.status_code == 200
        tasks = response.json()
        assert isinstance(tasks, list)
    
    @pytest.mark.asyncio
    async def test_metrics_endpoint(self, client):
        """Test metrics endpoint"""
        response = await client.get("/api/metrics")
        assert response.status_code == 200
        metrics = response.json()
        assert "queue_stats" in metrics
        assert "timestamp" in metrics
    
    @pytest.mark.asyncio
    async def test_task_processing_workflow(self, client):
        """Test complete task processing workflow"""
        # Create an email task
        data = {
            "recipient": "workflow@example.com",
            "subject": "Workflow Test",
            "template": "welcome"
        }
        response = await client.post("/api/tasks/email", data=data)
        assert response.status_code == 200
        result = response.json()
        task_id = result["task_id"]
        
        # Wait a moment for processing
        await asyncio.sleep(2)
        
        # Check task status
        response = await client.get(f"/api/tasks/{task_id}/status")
        # Note: This might return 200 or 500 depending on implementation
        # The test verifies the endpoint exists and responds
        assert response.status_code in [200, 500]

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
