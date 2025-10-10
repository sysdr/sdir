from dataclasses import dataclass, field
from typing import List, Optional
from enum import Enum
from datetime import datetime
import uuid

class OrderStatus(Enum):
    PENDING = "pending"
    CONFIRMED = "confirmed"
    CANCELLED = "cancelled"
    SHIPPED = "shipped"

@dataclass
class OrderItem:
    """Entity within Order aggregate"""
    product_id: str
    product_name: str
    quantity: int
    price: float
    
    def line_total(self) -> float:
        return self.quantity * self.price

@dataclass  
class Address:
    """Value object for shipping address"""
    street: str
    city: str
    state: str
    zip_code: str
    country: str = "US"
    
    def is_valid(self) -> bool:
        return all([self.street, self.city, self.state, self.zip_code])

@dataclass
class Order:
    """Order Aggregate Root - enforces business invariants"""
    order_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    customer_id: str = ""
    items: List[OrderItem] = field(default_factory=list)
    shipping_address: Optional[Address] = None
    status: OrderStatus = OrderStatus.PENDING
    created_at: datetime = field(default_factory=datetime.now)
    
    def add_item(self, product_id: str, product_name: str, quantity: int, price: float):
        """Business logic: Add item with validation"""
        if self.status != OrderStatus.PENDING:
            raise ValueError("Cannot modify non-pending order")
        
        if quantity <= 0:
            raise ValueError("Quantity must be positive")
            
        if price < 0:
            raise ValueError("Price cannot be negative")
        
        # Check if item already exists
        for item in self.items:
            if item.product_id == product_id:
                item.quantity += quantity
                return
        
        # Add new item
        self.items.append(OrderItem(product_id, product_name, quantity, price))
    
    def calculate_total(self) -> float:
        """Business logic: Calculate order total"""
        return sum(item.line_total() for item in self.items)
    
    def confirm(self) -> List:
        """Business logic: Confirm order and generate events"""
        if not self.items:
            raise ValueError("Cannot confirm empty order")
        
        if not self.shipping_address or not self.shipping_address.is_valid():
            raise ValueError("Valid shipping address required")
        
        if self.status != OrderStatus.PENDING:
            raise ValueError("Only pending orders can be confirmed")
        
        self.status = OrderStatus.CONFIRMED
        
        # Generate domain event
        from shared.events.base import OrderPlaced
        event = OrderPlaced(
            event_id=str(uuid.uuid4()),
            occurred_at=datetime.now(),
            event_type="OrderPlaced",
            order_id=self.order_id,
            customer_id=self.customer_id,
            items=[{
                'product_id': item.product_id,
                'product_name': item.product_name,
                'quantity': item.quantity,
                'price': item.price
            } for item in self.items],
            total_amount=self.calculate_total()
        )
        
        return [event]  # Return events for publishing
    
    def cancel(self, reason: str) -> List:
        """Business logic: Cancel order"""
        if self.status == OrderStatus.SHIPPED:
            raise ValueError("Cannot cancel shipped order")
        
        self.status = OrderStatus.CANCELLED
        return []  # Could generate OrderCancelled event

