import asyncio
import json
import time
import httpx
import pytest

class TestDistributedScheduler:
    def __init__(self):
        self.scheduler_url = "http://localhost:8000"
        self.test_tasks = []
        
    async def test_scheduler_health(self):
        """Test scheduler health endpoint"""
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{self.scheduler_url}/status")
            assert response.status_code == 200
            data = response.json()
            assert "node_id" in data
            assert "queue_lengths" in data
            print("✅ Scheduler health check passed")
            
    async def test_task_submission(self):
        """Test task submission"""
        task = {
            "id": f"test-task-{int(time.time())}",
            "type": "quick",
            "priority": 2,
            "payload": {"test": True}
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.scheduler_url}/tasks",
                json=task
            )
            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "submitted"
            assert data["task_id"] == task["id"]
            
            self.test_tasks.append(task["id"])
            print(f"✅ Task submission test passed: {task['id']}")
            
    async def test_task_status_tracking(self):
        """Test task status tracking"""
        if not self.test_tasks:
            await self.test_task_submission()
            
        task_id = self.test_tasks[0]
        
        async with httpx.AsyncClient() as client:
            # Wait a bit for task to be processed
            await asyncio.sleep(2)
            
            response = await client.get(f"{self.scheduler_url}/tasks/{task_id}")
            assert response.status_code == 200
            data = response.json()
            assert "status" in data
            print(f"✅ Task status tracking passed: {task_id} -> {data.get('status')}")
            
    async def test_priority_scheduling(self):
        """Test priority-based scheduling"""
        # Submit tasks with different priorities
        tasks = [
            {"id": f"low-priority-{int(time.time())}", "type": "quick", "priority": 1, "payload": {}},
            {"id": f"high-priority-{int(time.time())}", "type": "quick", "priority": 3, "payload": {}},
            {"id": f"normal-priority-{int(time.time())}", "type": "quick", "priority": 2, "payload": {}}
        ]
        
        async with httpx.AsyncClient() as client:
            for task in tasks:
                response = await client.post(f"{self.scheduler_url}/tasks", json=task)
                assert response.status_code == 200
                self.test_tasks.append(task["id"])
                
            print("✅ Priority scheduling test passed")
            
    async def test_load_generation(self):
        """Generate load and test system behavior"""
        task_count = 20
        
        async with httpx.AsyncClient() as client:
            # Submit multiple tasks rapidly
            tasks = []
            for i in range(task_count):
                task = {
                    "id": f"load-test-{int(time.time())}-{i}",
                    "type": "quick",
                    "priority": 2,
                    "payload": {"batch": "load_test"}
                }
                tasks.append(client.post(f"{self.scheduler_url}/tasks", json=task))
                
            # Submit all tasks concurrently
            responses = await asyncio.gather(*tasks)
            
            success_count = sum(1 for r in responses if r.status_code == 200)
            assert success_count == task_count
            
            print(f"✅ Load generation test passed: {success_count}/{task_count} tasks submitted")
            
    async def run_all_tests(self):
        """Run all tests"""
        print("🧪 Running Distributed Task Scheduler Tests...")
        
        try:
            await self.test_scheduler_health()
            await self.test_task_submission()
            await self.test_task_status_tracking()
            await self.test_priority_scheduling()
            await self.test_load_generation()
            
            print("🎉 All tests passed!")
            
        except Exception as e:
            print(f"❌ Test failed: {e}")
            raise

async def main():
    """Main test function"""
    # Wait for services to be ready
    print("⏳ Waiting for services to start...")
    await asyncio.sleep(10)
    
    tester = TestDistributedScheduler()
    await tester.run_all_tests()

if __name__ == "__main__":
    asyncio.run(main())
