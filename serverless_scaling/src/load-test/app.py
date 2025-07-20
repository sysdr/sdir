import asyncio
import aiohttp
import time
import json
import os
import random
import logging
from typing import Dict, Any, List
import statistics

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class LoadTester:
    def __init__(self):
        self.target_url = os.getenv("TARGET_URL", "http://localhost")
        self.concurrent_users = int(os.getenv("CONCURRENT_USERS", "10"))
        self.duration = int(os.getenv("DURATION", "60"))
        self.results = []
        self.session = None
        
    async def create_session(self):
        """Create HTTP session with connection pooling"""
        connector = aiohttp.TCPConnector(limit=100, limit_per_host=50)
        timeout = aiohttp.ClientTimeout(total=30)
        self.session = aiohttp.ClientSession(connector=connector, timeout=timeout)
        
    async def close_session(self):
        """Close HTTP session"""
        if self.session:
            await self.session.close()
            
    async def make_request(self, user_id: int) -> Dict[str, Any]:
        """Make a single request and return timing data"""
        start_time = time.time()
        
        try:
            # Randomly choose between different endpoints
            endpoints = [
                "/api/task",
                "/api/status", 
                "/api/metrics"
            ]
            
            endpoint = random.choice(endpoints)
            url = f"{self.target_url}{endpoint}"
            
            if endpoint == "/api/task":
                # Create a task
                payload = {
                    "type": "test_task",
                    "user_id": user_id,
                    "data": {
                        "message": f"Test task from user {user_id}",
                        "timestamp": time.time(),
                        "random_value": random.randint(1, 1000)
                    }
                }
                
                async with self.session.post(url, json=payload) as response:
                    response_text = await response.text()
                    end_time = time.time()
                    
                    return {
                        "user_id": user_id,
                        "endpoint": endpoint,
                        "method": "POST",
                        "status_code": response.status_code,
                        "response_time": end_time - start_time,
                        "success": response.status_code == 200,
                        "response_size": len(response_text),
                        "timestamp": start_time
                    }
            else:
                # GET request
                async with self.session.get(url) as response:
                    response_text = await response.text()
                    end_time = time.time()
                    
                    return {
                        "user_id": user_id,
                        "endpoint": endpoint,
                        "method": "GET",
                        "status_code": response.status_code,
                        "response_time": end_time - start_time,
                        "success": response.status_code == 200,
                        "response_size": len(response_text),
                        "timestamp": start_time
                    }
                    
        except Exception as e:
            end_time = time.time()
            logger.error(f"Request failed for user {user_id}: {e}")
            
            return {
                "user_id": user_id,
                "endpoint": "unknown",
                "method": "GET",
                "status_code": 0,
                "response_time": end_time - start_time,
                "success": False,
                "response_size": 0,
                "error": str(e),
                "timestamp": start_time
            }
    
    async def user_worker(self, user_id: int, duration: int):
        """Simulate a user making requests for the specified duration"""
        end_time = time.time() + duration
        
        while time.time() < end_time:
            result = await self.make_request(user_id)
            self.results.append(result)
            
            # Random delay between requests (0.1 to 2 seconds)
            delay = random.uniform(0.1, 2.0)
            await asyncio.sleep(delay)
    
    async def run_load_test(self):
        """Run the complete load test"""
        logger.info(f"Starting load test with {self.concurrent_users} users for {self.duration} seconds")
        logger.info(f"Target URL: {self.target_url}")
        
        await self.create_session()
        
        try:
            # Create tasks for all users
            tasks = []
            for user_id in range(self.concurrent_users):
                task = asyncio.create_task(self.user_worker(user_id, self.duration))
                tasks.append(task)
            
            # Wait for all tasks to complete
            await asyncio.gather(*tasks)
            
        finally:
            await self.close_session()
    
    def generate_report(self) -> Dict[str, Any]:
        """Generate a comprehensive test report"""
        if not self.results:
            return {"error": "No results to analyze"}
        
        # Calculate statistics
        response_times = [r["response_time"] for r in self.results if r["success"]]
        successful_requests = [r for r in self.results if r["success"]]
        failed_requests = [r for r in self.results if not r["success"]]
        
        # Endpoint breakdown
        endpoint_stats = {}
        for result in self.results:
            endpoint = result["endpoint"]
            if endpoint not in endpoint_stats:
                endpoint_stats[endpoint] = {"total": 0, "successful": 0, "failed": 0}
            
            endpoint_stats[endpoint]["total"] += 1
            if result["success"]:
                endpoint_stats[endpoint]["successful"] += 1
            else:
                endpoint_stats[endpoint]["failed"] += 1
        
        # Calculate percentiles
        percentiles = {}
        if response_times:
            response_times.sort()
            percentiles = {
                "p50": statistics.quantiles(response_times, n=2)[0],
                "p90": statistics.quantiles(response_times, n=10)[8],
                "p95": statistics.quantiles(response_times, n=20)[18],
                "p99": statistics.quantiles(response_times, n=100)[98] if len(response_times) >= 100 else response_times[-1]
            }
        
        total_requests = len(self.results)
        success_rate = (len(successful_requests) / total_requests) * 100 if total_requests > 0 else 0
        
        report = {
            "test_configuration": {
                "target_url": self.target_url,
                "concurrent_users": self.concurrent_users,
                "duration_seconds": self.duration,
                "start_time": min(r["timestamp"] for r in self.results) if self.results else 0,
                "end_time": max(r["timestamp"] for r in self.results) if self.results else 0
            },
            "summary": {
                "total_requests": total_requests,
                "successful_requests": len(successful_requests),
                "failed_requests": len(failed_requests),
                "success_rate_percent": round(success_rate, 2),
                "requests_per_second": round(total_requests / self.duration, 2) if self.duration > 0 else 0
            },
            "response_time_stats": {
                "mean": round(statistics.mean(response_times), 3) if response_times else 0,
                "median": round(statistics.median(response_times), 3) if response_times else 0,
                "min": min(response_times) if response_times else 0,
                "max": max(response_times) if response_times else 0,
                "percentiles": percentiles
            },
            "endpoint_breakdown": endpoint_stats,
            "errors": [r["error"] for r in failed_requests if "error" in r]
        }
        
        return report

async def main():
    """Main function to run the load test"""
    load_tester = LoadTester()
    
    try:
        await load_tester.run_load_test()
        
        # Generate and print report
        report = load_tester.generate_report()
        
        print("\n" + "="*60)
        print("LOAD TEST RESULTS")
        print("="*60)
        print(f"Target URL: {report['test_configuration']['target_url']}")
        print(f"Concurrent Users: {report['test_configuration']['concurrent_users']}")
        print(f"Duration: {report['test_configuration']['duration_seconds']} seconds")
        print(f"Total Requests: {report['summary']['total_requests']}")
        print(f"Success Rate: {report['summary']['success_rate_percent']}%")
        print(f"Requests/Second: {report['summary']['requests_per_second']}")
        print(f"Mean Response Time: {report['response_time_stats']['mean']}s")
        print(f"Median Response Time: {report['response_time_stats']['median']}s")
        print(f"95th Percentile: {report['response_time_stats']['percentiles'].get('p95', 0):.3f}s")
        
        print("\nEndpoint Breakdown:")
        for endpoint, stats in report['endpoint_breakdown'].items():
            success_rate = (stats['successful'] / stats['total']) * 100 if stats['total'] > 0 else 0
            print(f"  {endpoint}: {stats['total']} requests, {success_rate:.1f}% success")
        
        if report['errors']:
            print(f"\nErrors encountered: {len(report['errors'])}")
            for error in set(report['errors'][:5]):  # Show first 5 unique errors
                print(f"  - {error}")
        
        print("="*60)
        
        # Save detailed report to file
        with open("/app/load_test_report.json", "w") as f:
            json.dump(report, f, indent=2)
        
        logger.info("Load test completed successfully")
        
    except Exception as e:
        logger.error(f"Load test failed: {e}")
        raise

if __name__ == "__main__":
    asyncio.run(main()) 