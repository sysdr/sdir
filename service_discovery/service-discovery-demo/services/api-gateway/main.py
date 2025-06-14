import asyncio
import json
import random
import sys
import os
from typing import Dict, List

from base_service import ServiceDiscoveryClient

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
import aiohttp

class APIGateway:
    """API Gateway with service discovery and load balancing"""
    
    def __init__(self):
        self.port = int(os.getenv('GATEWAY_PORT', '8000'))
        self.consul_host = os.getenv('CONSUL_HOST', 'localhost')
        
        self.app = FastAPI(title="API Gateway")
        self.app.add_middleware(
            CORSMiddleware,
            allow_origins=["*"],
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
        )
        
        self.discovery_client = ServiceDiscoveryClient(self.consul_host)
        self.setup_routes()
    
    def setup_routes(self):
        """Setup gateway routes"""
        
        @self.app.get("/health")
        async def health():
            return {"status": "healthy", "service": "api-gateway"}
        
        @self.app.get("/api/users")
        async def proxy_users():
            """Proxy to user service"""
            return await self.proxy_request("user-service", "/users")
        
        @self.app.get("/api/users/{user_id}")
        async def proxy_user(user_id: str):
            """Proxy to user service"""
            return await self.proxy_request("user-service", f"/users/{user_id}")
        
        @self.app.get("/api/orders")
        async def proxy_orders():
            """Proxy to order service"""
            return await self.proxy_request("order-service", "/orders")
        
        @self.app.get("/api/orders/{order_id}")
        async def proxy_order(order_id: str):
            """Proxy to order service"""
            return await self.proxy_request("order-service", f"/orders/{order_id}")
        
        @self.app.get("/api/discovery/services")
        async def list_services():
            """List all discovered services"""
            user_services = await self.discovery_client.discover_services("user-service")
            order_services = await self.discovery_client.discover_services("order-service")
            
            return {
                "services": {
                    "user-service": user_services,
                    "order-service": order_services
                },
                "total_instances": len(user_services) + len(order_services)
            }
    
    async def proxy_request(self, service_name: str, path: str):
        """Proxy request to discovered service with load balancing"""
        try:
            services = await self.discovery_client.discover_services(service_name)
            
            if not services:
                raise HTTPException(status_code=503, detail=f"No healthy {service_name} instances found")
            
            # Simple round-robin load balancing
            selected_service = random.choice(services)
            target_url = f"http://{selected_service['address']}:{selected_service['port']}{path}"
            
            async with aiohttp.ClientSession() as session:
                async with session.get(target_url, timeout=aiohttp.ClientTimeout(total=10)) as response:
                    if response.status == 200:
                        data = await response.json()
                        # Add gateway metadata
                        data['gateway_routing'] = {
                            'target_service': selected_service['id'],
                            'service_address': f"{selected_service['address']}:{selected_service['port']}",
                            'discovery_time': asyncio.get_event_loop().time()
                        }
                        return data
                    else:
                        error_text = await response.text()
                        raise HTTPException(status_code=response.status, detail=error_text)
                        
        except aiohttp.ClientError as e:
            raise HTTPException(status_code=503, detail=f"Service communication error: {str(e)}")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Gateway error: {str(e)}")

if __name__ == "__main__":
    gateway = APIGateway()
    uvicorn.run(
        gateway.app,
        host="0.0.0.0",
        port=gateway.port,
        access_log=True
    )
