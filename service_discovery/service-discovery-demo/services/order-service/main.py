import asyncio
import json
import random
import sys
import os
from typing import Dict, List

from base_service import BaseService

import uvicorn
from fastapi import HTTPException

class OrderService(BaseService):
    """Order service with user service discovery"""
    
    def __init__(self):
        service_name = os.getenv('SERVICE_NAME', 'order-service')
        service_id = os.getenv('SERVICE_ID', 'order-service-1')
        port = int(os.getenv('SERVICE_PORT', '8003'))
        
        super().__init__(service_name, service_id, port)
        
        # Mock orders data
        self.orders = {
            "1": {"id": "1", "user_id": "1", "items": ["laptop", "mouse"], "total": 1299.99},
            "2": {"id": "2", "user_id": "2", "items": ["phone"], "total": 599.99},
            "3": {"id": "3", "user_id": "1", "items": ["keyboard"], "total": 99.99}
        }
        
        self.setup_order_routes()
    
    def setup_order_routes(self):
        """Setup order-specific routes"""
        
        @self.app.get("/orders")
        async def list_orders():
            """List all orders"""
            await asyncio.sleep(random.uniform(0.1, 0.2))
            
            return {
                "orders": list(self.orders.values()),
                "served_by": self.service_id,
                "total": len(self.orders)
            }
        
        @self.app.get("/orders/{order_id}")
        async def get_order(order_id: str):
            """Get specific order with user information"""
            if random.random() < self.failure_rate:
                raise HTTPException(status_code=500, detail="Internal server error")
            
            if order_id not in self.orders:
                raise HTTPException(status_code=404, detail="Order not found")
            
            order = self.orders[order_id].copy()
            
            # Discover and call user service
            try:
                user_services = await self.discovery_client.discover_services("user-service")
                if user_services:
                    # Simple load balancing - random selection
                    selected_service = random.choice(user_services)
                    user_url = f"http://{selected_service['address']}:{selected_service['port']}/users/{order['user_id']}"
                    
                    import aiohttp
                    async with aiohttp.ClientSession() as session:
                        async with session.get(user_url, timeout=aiohttp.ClientTimeout(total=5)) as response:
                            if response.status == 200:
                                user_data = await response.json()
                                order['user'] = user_data['user']
                                order['discovery_used'] = selected_service['id']
                            else:
                                order['user'] = {"error": "User service unavailable"}
                else:
                    order['user'] = {"error": "No user service instances found"}
                    
            except Exception as e:
                order['user'] = {"error": f"Failed to fetch user: {str(e)}"}
            
            return {
                "order": order,
                "served_by": self.service_id
            }

if __name__ == "__main__":
    service = OrderService()
    uvicorn.run(
        service.app,
        host="0.0.0.0",
        port=service.port,
        access_log=False
    )
