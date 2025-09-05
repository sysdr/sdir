import asyncio
import httpx
import random
import time

services = [
    "http://user-service:8000",
    "http://payment-service:8000", 
    "http://order-service:8000"
]

endpoints = {
    "http://user-service:8000": ["/users/1", "/users/2", "/users/3", "/users"],
    "http://payment-service:8000": ["/payments"],
    "http://order-service:8000": ["/orders"]
}

async def make_request(session, service, endpoint):
    try:
        if endpoint == "/payments":
            response = await session.post(f"{service}{endpoint}", json={"amount": 100})
        elif endpoint == "/orders":
            response = await session.post(f"{service}{endpoint}", json={"user_id": "1", "items": []})
        else:
            response = await session.get(f"{service}{endpoint}")
        
        print(f"Request to {service}{endpoint}: {response.status_code}")
    except Exception as e:
        print(f"Error requesting {service}{endpoint}: {e}")

async def generate_load():
    async with httpx.AsyncClient(timeout=10.0) as session:
        while True:
            # Generate random load
            service = random.choice(services)
            endpoint = random.choice(endpoints[service])
            
            await make_request(session, service, endpoint)
            
            # Random delay between requests
            await asyncio.sleep(random.uniform(0.5, 2.0))

async def main():
    # Run multiple concurrent load generators
    tasks = [generate_load() for _ in range(5)]
    await asyncio.gather(*tasks)

if __name__ == "__main__":
    print("Starting load generator...")
    asyncio.run(main())
