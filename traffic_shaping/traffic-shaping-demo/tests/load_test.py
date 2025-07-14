import asyncio
import aiohttp
import time
import json
from typing import Dict, List
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class LoadTester:
    def __init__(self, base_url: str = "http://localhost:8000"):
        self.base_url = base_url
        self.results: Dict[str, List] = {
            "token_bucket": [],
            "sliding_window": [],
            "fixed_window": []
        }
    
    async def test_limiter(self, session: aiohttp.ClientSession, limiter_type: str, user_id: str = "load_test_user"):
        """Test a specific rate limiter"""
        start_time = time.time()
        
        try:
            async with session.post(f"{self.base_url}/api/request/{limiter_type}") as response:
                result = await response.json()
                processing_time = (time.time() - start_time) * 1000
                
                self.results[limiter_type].append({
                    "timestamp": start_time,
                    "allowed": result.get("allowed", False),
                    "status_code": response.status,
                    "processing_time": processing_time,
                    "metadata": result.get("metadata", {})
                })
                
                return result.get("allowed", False), processing_time
                
        except Exception as e:
            logger.error(f"Request failed: {e}")
            self.results[limiter_type].append({
                "timestamp": start_time,
                "allowed": False,
                "status_code": 0,
                "processing_time": (time.time() - start_time) * 1000,
                "error": str(e)
            })
            return False, 0
    
    async def burst_test(self, limiter_type: str, burst_size: int = 20, delay: float = 0.1):
        """Test burst handling capability"""
        logger.info(f"Starting burst test for {limiter_type}: {burst_size} requests with {delay}s delay")
        
        async with aiohttp.ClientSession() as session:
            tasks = []
            for i in range(burst_size):
                task = self.test_limiter(session, limiter_type)
                tasks.append(task)
                if delay > 0:
                    await asyncio.sleep(delay)
            
            results = await asyncio.gather(*tasks, return_exceptions=True)
            
            # Analyze results
            allowed_count = sum(1 for r in results if isinstance(r, tuple) and r[0])
            blocked_count = burst_size - allowed_count
            
            logger.info(f"Burst test results - Allowed: {allowed_count}, Blocked: {blocked_count}")
            return allowed_count, blocked_count
    
    async def sustained_load_test(self, limiter_type: str, duration: int = 60, rps: float = 5.0):
        """Test sustained load over time"""
        logger.info(f"Starting sustained load test for {limiter_type}: {rps} RPS for {duration}s")
        
        interval = 1.0 / rps
        end_time = time.time() + duration
        request_count = 0
        
        async with aiohttp.ClientSession() as session:
            while time.time() < end_time:
                start = time.time()
                
                await self.test_limiter(session, limiter_type)
                request_count += 1
                
                # Maintain rate
                elapsed = time.time() - start
                sleep_time = max(0, interval - elapsed)
                if sleep_time > 0:
                    await asyncio.sleep(sleep_time)
        
        logger.info(f"Sustained load test completed: {request_count} requests sent")
        return request_count
    
    async def comparative_test(self, requests_per_limiter: int = 50):
        """Compare all limiters under identical load"""
        logger.info(f"Starting comparative test: {requests_per_limiter} requests per limiter")
        
        async with aiohttp.ClientSession() as session:
            for limiter_type in ["token_bucket", "sliding_window", "fixed_window"]:
                logger.info(f"Testing {limiter_type}...")
                
                # Reset limiter first
                try:
                    await session.post(f"{self.base_url}/api/reset/{limiter_type}")
                except:
                    pass
                
                # Send requests with small delay to avoid overwhelming
                for i in range(requests_per_limiter):
                    await self.test_limiter(session, limiter_type)
                    await asyncio.sleep(0.05)  # 50ms delay
                
                await asyncio.sleep(1)  # Pause between limiters
    
    def analyze_results(self):
        """Analyze test results and generate report"""
        report = {
            "summary": {},
            "detailed_analysis": {}
        }
        
        for limiter_type, results in self.results.items():
            if not results:
                continue
            
            total_requests = len(results)
            allowed_requests = sum(1 for r in results if r.get("allowed", False))
            blocked_requests = total_requests - allowed_requests
            
            processing_times = [r["processing_time"] for r in results if "processing_time" in r]
            avg_processing_time = sum(processing_times) / len(processing_times) if processing_times else 0
            
            # Calculate success rate
            success_rate = (allowed_requests / total_requests * 100) if total_requests > 0 else 0
            
            report["summary"][limiter_type] = {
                "total_requests": total_requests,
                "allowed_requests": allowed_requests,
                "blocked_requests": blocked_requests,
                "success_rate": round(success_rate, 2),
                "avg_processing_time": round(avg_processing_time, 2)
            }
            
            # Time-based analysis
            if len(results) > 1:
                start_time = min(r["timestamp"] for r in results)
                end_time = max(r["timestamp"] for r in results)
                duration = end_time - start_time
                rps = total_requests / duration if duration > 0 else 0
                
                report["detailed_analysis"][limiter_type] = {
                    "duration": round(duration, 2),
                    "requests_per_second": round(rps, 2),
                    "min_processing_time": min(processing_times) if processing_times else 0,
                    "max_processing_time": max(processing_times) if processing_times else 0
                }
        
        return report
    
    def print_report(self):
        """Print formatted test report"""
        report = self.analyze_results()
        
        print("\n" + "="*80)
        print("LOAD TEST REPORT")
        print("="*80)
        
        print("\nSUMMARY:")
        print("-"*40)
        for limiter, stats in report["summary"].items():
            print(f"\n{limiter.upper()}:")
            print(f"  Total Requests: {stats['total_requests']}")
            print(f"  Allowed: {stats['allowed_requests']} ({stats['success_rate']}%)")
            print(f"  Blocked: {stats['blocked_requests']}")
            print(f"  Avg Processing Time: {stats['avg_processing_time']}ms")
        
        print("\nDETAILED ANALYSIS:")
        print("-"*40)
        for limiter, stats in report["detailed_analysis"].items():
            print(f"\n{limiter.upper()}:")
            print(f"  Test Duration: {stats['duration']}s")
            print(f"  Actual RPS: {stats['requests_per_second']}")
            print(f"  Processing Time Range: {stats['min_processing_time']:.2f}ms - {stats['max_processing_time']:.2f}ms")

async def main():
    """Run comprehensive load tests"""
    target_url = os.getenv("TARGET_URL", "http://localhost:8000")
    tester = LoadTester(target_url)
    
    # Wait for service to be ready
    logger.info("Waiting for service to be ready...")
    await asyncio.sleep(10)
    
    try:
        # Test 1: Burst testing
        logger.info("Running burst tests...")
        for limiter in ["token_bucket", "sliding_window", "fixed_window"]:
            await tester.burst_test(limiter, burst_size=15, delay=0.1)
            await asyncio.sleep(2)
        
        # Test 2: Sustained load
        logger.info("Running sustained load tests...")
        for limiter in ["token_bucket", "sliding_window", "fixed_window"]:
            await tester.sustained_load_test(limiter, duration=30, rps=3.0)
            await asyncio.sleep(5)
        
        # Test 3: Comparative test
        logger.info("Running comparative test...")
        await tester.comparative_test(requests_per_limiter=30)
        
        # Generate and print report
        tester.print_report()
        
    except Exception as e:
        logger.error(f"Load test failed: {e}")
        raise

if __name__ == "__main__":
    asyncio.run(main())
