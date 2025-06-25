"""
Mock Microservices for Chaos Engineering Testing
Simulates a distributed system with multiple services
"""

import asyncio
import random
import time
from fastapi import FastAPI
from typing import Dict
import uvicorn
import logging

logger = logging.getLogger(__name__)

class MockService:
    """Simulates a microservice with realistic behavior"""
    
    def __init__(self, name: str, port: int):
        self.name = name
        self.port = port
        self.app = FastAPI(title=f"Mock {name} Service")
        self.health_status = "healthy"
        self.response_delay = 0
        self.error_rate = 0.0
        
        self.setup_routes()
    
    def setup_routes(self):
        """Setup service endpoints"""
        
        @self.app.get("/health")
        async def health():
            await asyncio.sleep(self.response_delay)
            
            if random.random() < self.error_rate:
                return {"status": "error", "service": self.name}
            
            return {"status": self.health_status, "service": self.name}
        
        @self.app.get("/api/data")
        async def get_data():
            await asyncio.sleep(self.response_delay)
            
            if random.random() < self.error_rate:
                return {"error": "Service unavailable"}
            
            return {
                "service": self.name,
                "data": [{"id": i, "value": random.randint(1, 100)} for i in range(10)],
                "timestamp": time.time()
            }
        
        @self.app.post("/api/process")
        async def process_data(data: dict):
            # Simulate processing time
            processing_time = random.uniform(0.1, 0.5) + self.response_delay
            await asyncio.sleep(processing_time)
            
            if random.random() < self.error_rate:
                return {"error": "Processing failed"}
            
            return {
                "service": self.name,
                "processed": True,
                "input_size": len(str(data)),
                "processing_time": processing_time
            }
    
    def start(self):
        """Start the service"""
        uvicorn.run(self.app, host="0.0.0.0", port=self.port)

# Create mock services
services = [
    MockService("user-service", 8001),
    MockService("order-service", 8002),
    MockService("payment-service", 8003),
    MockService("inventory-service", 8004)
]
