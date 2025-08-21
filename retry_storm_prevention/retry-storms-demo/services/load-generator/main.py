import asyncio
import httpx
import time
import random
import os
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

app = FastAPI(title="Load Generator")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

gateway_url = os.getenv("GATEWAY_URL", "http://localhost:8000")

class LoadConfig(BaseModel):
    rps: int = 10
    duration_seconds: int = 60
    concurrent_clients: int = 5

load_config = LoadConfig()
is_running = False
stats = {
    "requests_sent": 0,
    "requests_successful": 0,
    "requests_failed": 0,
    "average_latency_ms": 0
}

@app.post("/start")
async def start_load_test(config: LoadConfig):
    global load_config, is_running
    if is_running:
        return {"error": "Load test already running"}
    
    load_config = config
    is_running = True
    asyncio.create_task(run_load_test())
    return {"status": "Load test started", "config": config.dict()}

@app.post("/stop")
async def stop_load_test():
    global is_running
    is_running = False
    return {"status": "Load test stopped"}

@app.get("/stats")
async def get_stats():
    return {"stats": stats, "is_running": is_running}

async def run_load_test():
    global stats, is_running
    
    stats = {
        "requests_sent": 0,
        "requests_successful": 0,
        "requests_failed": 0,
        "average_latency_ms": 0,
        "latencies": []
    }
    
    tasks = []
    for i in range(load_config.concurrent_clients):
        task = asyncio.create_task(client_worker(i))
        tasks.append(task)
    
    # Wait for completion or stop signal
    start_time = time.time()
    while is_running and (time.time() - start_time) < load_config.duration_seconds:
        await asyncio.sleep(1)
    
    is_running = False
    
    # Cancel remaining tasks
    for task in tasks:
        task.cancel()
    
    await asyncio.gather(*tasks, return_exceptions=True)

async def client_worker(client_id: int):
    global stats
    request_interval = load_config.concurrent_clients / load_config.rps
    
    async with httpx.AsyncClient(timeout=10.0) as client:
        while is_running:
            start_time = time.time()
            
            try:
                response = await client.post(
                    f"{gateway_url}/api/process",
                    json={"client_id": client_id, "timestamp": time.time(), "data": f"test-data-{random.randint(1, 1000)}"}
                )
                
                latency_ms = (time.time() - start_time) * 1000
                
                stats["requests_sent"] += 1
                if response.status_code == 200:
                    stats["requests_successful"] += 1
                else:
                    stats["requests_failed"] += 1
                
                stats["latencies"].append(latency_ms)
                if len(stats["latencies"]) > 100:
                    stats["latencies"] = stats["latencies"][-100:]
                
                stats["average_latency_ms"] = sum(stats["latencies"]) / len(stats["latencies"])
                
            except Exception as e:
                stats["requests_sent"] += 1
                stats["requests_failed"] += 1
                print(f"Request failed: {e}")
            
            await asyncio.sleep(request_interval)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
