import asyncio
import aiohttp
import time
import random
import os

TARGET_URL = os.getenv('TARGET_URL', 'http://localhost:8080')

async def generate_load():
    """Generate realistic load patterns"""
    session = aiohttp.ClientSession()
    
    while True:
        try:
            # Simulate user browsing pattern
            endpoints = [
                f'{TARGET_URL}/api/products',
                f'{TARGET_URL}/api/recommendations/{random.randint(1, 1000)}',
                f'{TARGET_URL}/api/reviews/{random.randint(1, 10)}',
            ]
            
            # Random load intensity
            load_intensity = random.choice([10, 30, 50, 70, 90])
            
            tasks = []
            for _ in range(load_intensity):
                endpoint = random.choice(endpoints)
                tasks.append(session.get(endpoint))
            
            responses = await asyncio.gather(*tasks, return_exceptions=True)
            
            success_count = sum(1 for r in responses if not isinstance(r, Exception))
            print(f"Load burst: {load_intensity} requests, {success_count} successful")
            
            # Vary the interval
            await asyncio.sleep(random.uniform(2, 8))
            
        except Exception as e:
            print(f"Load generation error: {e}")
            await asyncio.sleep(5)

if __name__ == "__main__":
    print(f"Starting load generator targeting {TARGET_URL}")
    asyncio.run(generate_load())
