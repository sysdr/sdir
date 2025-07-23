"""
Comprehensive load testing for ML inference system
"""
import asyncio
import aiohttp
import time
import json
import statistics
from typing import List, Dict
import argparse

class LoadTester:
    def __init__(self, base_url: str = "http://localhost:8000"):
        self.base_url = base_url
        self.results = []
        
    async def single_request(self, session: aiohttp.ClientSession, 
                           text: str, request_id: str) -> Dict:
        """Send a single prediction request"""
        start_time = time.time()
        
        try:
            async with session.post(
                f"{self.base_url}/predict",
                json={"text": text, "id": request_id},
                timeout=aiohttp.ClientTimeout(total=30)
            ) as response:
                result = await response.json()
                latency = time.time() - start_time
                
                return {
                    "success": True,
                    "latency": latency,
                    "status_code": response.status,
                    "result": result
                }
                
        except Exception as e:
            return {
                "success": False,
                "latency": time.time() - start_time,
                "error": str(e)
            }
    
    async def run_concurrent_test(self, num_requests: int, 
                                concurrency: int, text: str):
        """Run concurrent load test"""
        print(f"Running load test: {num_requests} requests, {concurrency} concurrent")
        
        connector = aiohttp.TCPConnector(limit=concurrency * 2)
        async with aiohttp.ClientSession(connector=connector) as session:
            
            # Create semaphore to limit concurrency
            semaphore = asyncio.Semaphore(concurrency)
            
            async def bounded_request(i):
                async with semaphore:
                    return await self.single_request(
                        session, 
                        f"{text} (request {i})", 
                        f"load_test_{i}"
                    )
            
            # Run all requests
            start_time = time.time()
            tasks = [bounded_request(i) for i in range(num_requests)]
            results = await asyncio.gather(*tasks)
            total_time = time.time() - start_time
            
            # Analyze results
            self.analyze_results(results, total_time)
            
    def analyze_results(self, results: List[Dict], total_time: float):
        """Analyze and print load test results"""
        successful = [r for r in results if r["success"]]
        failed = [r for r in results if not r["success"]]
        
        if successful:
            latencies = [r["latency"] for r in successful]
            
            print(f"\n=== Load Test Results ===")
            print(f"Total requests: {len(results)}")
            print(f"Successful: {len(successful)}")
            print(f"Failed: {len(failed)}")
            print(f"Success rate: {len(successful)/len(results)*100:.1f}%")
            print(f"Total time: {total_time:.2f}s")
            print(f"Throughput: {len(successful)/total_time:.1f} req/s")
            print(f"\nLatency Statistics:")
            print(f"  Mean: {statistics.mean(latencies)*1000:.1f}ms")
            print(f"  Median: {statistics.median(latencies)*1000:.1f}ms")
            print(f"  P95: {self.percentile(latencies, 95)*1000:.1f}ms")
            print(f"  P99: {self.percentile(latencies, 99)*1000:.1f}ms")
            print(f"  Min: {min(latencies)*1000:.1f}ms")
            print(f"  Max: {max(latencies)*1000:.1f}ms")
            
        if failed:
            print(f"\nFailure Analysis:")
            error_types = {}
            for failure in failed:
                error = failure.get("error", "Unknown")
                error_types[error] = error_types.get(error, 0) + 1
            
            for error, count in error_types.items():
                print(f"  {error}: {count} failures")
    
    @staticmethod
    def percentile(data, p):
        """Calculate percentile"""
        sorted_data = sorted(data)
        index = (p / 100) * (len(sorted_data) - 1)
        if index.is_integer():
            return sorted_data[int(index)]
        else:
            lower = sorted_data[int(index)]
            upper = sorted_data[int(index) + 1]
            return lower + (upper - lower) * (index - int(index))

async def main():
    parser = argparse.ArgumentParser(description="ML Inference Load Tester")
    parser.add_argument("--requests", type=int, default=100, 
                       help="Number of requests to send")
    parser.add_argument("--concurrency", type=int, default=10,
                       help="Number of concurrent requests")
    parser.add_argument("--url", type=str, default="http://localhost:8000",
                       help="Base URL of the service")
    parser.add_argument("--text", type=str, 
                       default="This is a test message for load testing the ML inference system",
                       help="Text to send for prediction")
    
    args = parser.parse_args()
    
    tester = LoadTester(args.url)
    
    # Check if service is available
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{args.url}/health") as response:
                if response.status != 200:
                    print(f"Service health check failed: {response.status}")
                    return
                print("Service is healthy, starting load test...")
    except Exception as e:
        print(f"Cannot connect to service: {e}")
        return
    
    await tester.run_concurrent_test(args.requests, args.concurrency, args.text)

if __name__ == "__main__":
    asyncio.run(main())
