import asyncio
import json
import random
import sys
import os
from typing import Dict, List

from base_service import BaseService

import uvicorn
from fastapi import HTTPException

class UserService(BaseService):
    """User service with service discovery capabilities"""
    
    def __init__(self):
        service_name = os.getenv('SERVICE_NAME', 'user-service')
        service_id = os.getenv('SERVICE_ID', 'user-service-1')
        port = int(os.getenv('SERVICE_PORT', '8001'))
        
        super().__init__(service_name, service_id, port)
        
        # Mock user data
        self.users = {
            "1": {"id": "1", "name": "Alice Johnson", "email": "alice@example.com"},
            "2": {"id": "2", "name": "Bob Smith", "email": "bob@example.com"},
            "3": {"id": "3", "name": "Carol Davis", "email": "carol@example.com"}
        }
        
        self.setup_user_routes()
    
    def setup_user_routes(self):
        """Setup user-specific routes"""
        
        @self.app.get("/users")
        async def list_users():
            """List all users"""
            # Simulate some processing time
            await asyncio.sleep(random.uniform(0.1, 0.3))
            
            return {
                "users": list(self.users.values()),
                "served_by": self.service_id,
                "total": len(self.users)
            }
        
        @self.app.get("/users/{user_id}")
        async def get_user(user_id: str):
            """Get specific user"""
            # Simulate random failures
            if random.random() < self.failure_rate:
                raise HTTPException(status_code=500, detail="Internal server error")
            
            if user_id not in self.users:
                raise HTTPException(status_code=404, detail="User not found")
            
            await asyncio.sleep(random.uniform(0.05, 0.15))
            
            return {
                "user": self.users[user_id],
                "served_by": self.service_id
            }

if __name__ == "__main__":
    service = UserService()
    uvicorn.run(
        service.app,
        host="0.0.0.0",
        port=service.port,
        access_log=False
    )
