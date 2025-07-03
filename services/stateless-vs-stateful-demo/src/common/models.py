"""
Common data models for the demo
"""
from pydantic import BaseModel
from typing import List, Optional, Dict, Any
from datetime import datetime

class CartItem(BaseModel):
    product_id: str
    name: str
    price: float
    quantity: int = 1

class ShoppingCart(BaseModel):
    user_id: str
    items: List[CartItem] = []
    created_at: datetime
    total: float = 0.0
    
    def calculate_total(self):
        self.total = sum(item.price * item.quantity for item in self.items)
        return self.total

class User(BaseModel):
    user_id: str
    username: str
    email: str
    session_data: Dict[str, Any] = {}

class ServiceMetrics(BaseModel):
    service_type: str
    active_sessions: int
    memory_usage: float
    cpu_usage: float
    request_count: int
    average_response_time: float
    timestamp: datetime
