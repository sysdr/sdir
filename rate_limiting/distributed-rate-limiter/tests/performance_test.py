#!/usr/bin/env python3
import asyncio
import aiohttp
import time
import statistics
from concurrent.futures import ThreadPoolExecutor

async def make_request(session, url, client_id):
    """Make a single request and return response time and status"""
    start_time = time.time()
    try:
        headers = {'X-Client-ID': client_id}
        async with session.get(url, headers=headers) as response:
            end_time = time.time()
            return {
                'status': response.status,
                'response_time': end_time - start_time,
                'client_id': client_id
            }
    except Exception as e:
        end_time = time.time()
        return {
            'status': 500,
            'response_time': end_time - start_time,
            'error': str(e),
            'client_id': client_id
        }

async def run_performance_test():
    """Run comprehensive performance test"""
    base_url = "http://localhost:5000/api"
    algorithms = ['token-bucket', 'sliding-window', 'fixed-window']
    
    print("🚀 Starting Performance Test...")
    print("=" * 50)
    
    async with aiohttp.ClientSession() as session:
        for algorithm in algorithms:
            print(f"\n📊 Testing {algorithm.upper()}")
            url = f"{base_url}/{algorithm}"
            
            # Test with single client
            tasks = []
            for i in range(50):
                task = make_request(session, url, 'perf-client-1')
                tasks.append(task)
            
            results = await asyncio.gather(*tasks)
            
            # Calculate statistics
            response_times = [r['response_time'] for r in results]
            success_count = len([r for r in results if r['status'] == 200])
            rate_limited_count = len([r for r in results if r['status'] == 429])
            
            print(f"  ✅ Successful requests: {success_count}/50")
            print(f"  🚫 Rate limited: {rate_limited_count}/50")
            print(f"  ⏱️  Avg response time: {statistics.mean(response_times):.3f}s")
            print(f"  ⏱️  95th percentile: {statistics.quantiles(response_times, n=20)[18]:.3f}s")
            
            # Test with multiple clients
            print(f"  🔄 Testing with multiple clients...")
            tasks = []
            for i in range(30):
                client_id = f'perf-client-{i % 5}'  # 5 different clients
                task = make_request(session, url, client_id)
                tasks.append(task)
            
            multi_results = await asyncio.gather(*tasks)
            multi_success = len([r for r in multi_results if r['status'] == 200])
            
            print(f"  ✅ Multi-client success: {multi_success}/30")

if __name__ == '__main__':
    asyncio.run(run_performance_test())
