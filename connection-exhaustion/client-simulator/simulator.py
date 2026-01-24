import asyncio
import aiohttp
import time
import random
import json
from datetime import datetime

class SlowClientSimulator:
    def __init__(self, target_url, num_clients=50, slow_ratio=0.7):
        self.target_url = target_url
        self.num_clients = num_clients
        self.slow_ratio = slow_ratio
        self.stats = {
            'total_sent': 0,
            'success': 0,
            'failed': 0,
            'timeouts': 0
        }
    
    async def send_slow_request(self, session, client_id):
        """Simulate a slow 3G client uploading data"""
        data_size = random.randint(50000, 200000)
        chunk_size = random.randint(500, 2000)
        
        async def data_generator():
            sent = 0
            while sent < data_size:
                chunk = b'x' * min(chunk_size, data_size - sent)
                yield chunk
                sent += len(chunk)
                await asyncio.sleep(random.uniform(0.1, 0.5))
        
        start_time = time.time()
        try:
            async with session.post(
                f"{self.target_url}/api/upload",
                data=data_generator(),
                timeout=aiohttp.ClientTimeout(total=60)
            ) as resp:
                await resp.text()
                duration = time.time() - start_time
                
                if resp.status == 200:
                    self.stats['success'] += 1
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: SUCCESS ({duration:.1f}s)")
                else:
                    self.stats['failed'] += 1
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: FAILED {resp.status}")
                
                self.stats['total_sent'] += 1
                
        except asyncio.TimeoutError:
            self.stats['timeouts'] += 1
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: TIMEOUT")
        except Exception as e:
            self.stats['failed'] += 1
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: ERROR {str(e)}")
    
    async def send_fast_request(self, session, client_id):
        """Simulate a fast client"""
        data = b'x' * random.randint(1000, 5000)
        
        start_time = time.time()
        try:
            async with session.post(
                f"{self.target_url}/api/upload",
                data=data,
                timeout=aiohttp.ClientTimeout(total=10)
            ) as resp:
                await resp.text()
                duration = time.time() - start_time
                
                if resp.status == 200:
                    self.stats['success'] += 1
                    print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: FAST SUCCESS ({duration:.2f}s)")
                else:
                    self.stats['failed'] += 1
                
                self.stats['total_sent'] += 1
                
        except Exception as e:
            self.stats['failed'] += 1
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Client {client_id}: FAST ERROR {str(e)}")
    
    async def run_client(self, client_id):
        """Run a single client that sends requests continuously"""
        async with aiohttp.ClientSession() as session:
            while True:
                if random.random() < self.slow_ratio:
                    await self.send_slow_request(session, client_id)
                else:
                    await self.send_fast_request(session, client_id)
                
                await asyncio.sleep(random.uniform(1, 3))
    
    async def print_stats(self):
        """Periodically print statistics"""
        while True:
            await asyncio.sleep(10)
            print(f"\n{'='*60}")
            print(f"STATISTICS:")
            print(f"  Total Requests: {self.stats['total_sent']}")
            print(f"  Success: {self.stats['success']}")
            print(f"  Failed: {self.stats['failed']}")
            print(f"  Timeouts: {self.stats['timeouts']}")
            print(f"  Success Rate: {(self.stats['success']/max(1, self.stats['total_sent'])*100):.1f}%")
            print(f"{'='*60}\n")
    
    async def run(self):
        """Start all clients"""
        print(f"Starting {self.num_clients} clients ({int(self.slow_ratio*100)}% slow)...")
        print(f"Target: {self.target_url}")
        
        tasks = [
            self.run_client(i) for i in range(self.num_clients)
        ]
        tasks.append(self.print_stats())
        
        await asyncio.gather(*tasks)

if __name__ == "__main__":
    import sys
    
    target = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8080"
    num_clients = int(sys.argv[2]) if len(sys.argv) > 2 else 50
    
    simulator = SlowClientSimulator(target, num_clients=num_clients)
    asyncio.run(simulator.run())
