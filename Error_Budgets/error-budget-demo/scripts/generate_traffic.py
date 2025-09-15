import asyncio
import aiohttp
import random
import time
from datetime import datetime

class TrafficGenerator:
    def __init__(self):
        self.services = [
            'http://localhost:8001',
            'http://localhost:8002',
            'http://localhost:8003',
        ]
        
    async def generate_realistic_traffic(self):
        """Generate realistic traffic patterns"""
        while True:
            try:
                async with aiohttp.ClientSession() as session:
                    # Generate burst traffic patterns
                    tasks = []
                    
                    # Simulate peak hours with more traffic
                    current_hour = datetime.now().hour
                    base_requests = 50 if 9 <= current_hour <= 17 else 10
                    
                    for _ in range(random.randint(base_requests//2, base_requests)):
                        tasks.append(self.make_request(session))
                    
                    await asyncio.gather(*tasks, return_exceptions=True)
                    
                await asyncio.sleep(random.uniform(2, 8))
                
            except Exception as e:
                print(f"Traffic generation error: {e}")
                await asyncio.sleep(5)
    
    async def make_request(self, session):
        """Make a request to a random service endpoint"""
        service_url = random.choice(self.services)
        endpoint = random.choice(['/api/data', '/api/process', '/health'])
        
        try:
            method = 'POST' if endpoint != '/health' else 'GET'
            async with session.request(method, f"{service_url}{endpoint}") as response:
                await response.read()
        except Exception as e:
            pass  # Expected for error simulation

if __name__ == "__main__":
    generator = TrafficGenerator()
    asyncio.run(generator.generate_realistic_traffic())
