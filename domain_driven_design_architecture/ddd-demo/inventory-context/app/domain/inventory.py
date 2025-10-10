from dataclasses import dataclass
from typing import Dict, List
import uuid
from datetime import datetime

@dataclass
class Product:
    product_id: str
    name: str
    stock_quantity: int
    reserved_quantity: int = 0
    
    @property
    def available_quantity(self) -> int:
        return self.stock_quantity - self.reserved_quantity
    
    def can_reserve(self, quantity: int) -> bool:
        return self.available_quantity >= quantity
    
    def reserve(self, quantity: int) -> str:
        if not self.can_reserve(quantity):
            raise ValueError("Insufficient stock")
        
        self.reserved_quantity += quantity
        return str(uuid.uuid4())  # Reservation ID

@dataclass
class InventoryService:
    def __init__(self):
        # Sample inventory for demo
        self.products = {
            "LAPTOP001": Product("LAPTOP001", "Gaming Laptop", 10),
            "MOUSE001": Product("MOUSE001", "Wireless Mouse", 50), 
            "KEYBOARD001": Product("KEYBOARD001", "Mechanical Keyboard", 25)
        }
        self.reservations = {}
    
    def reserve_items(self, items: List[Dict]) -> str:
        """Reserve items for order"""
        reservation_id = str(uuid.uuid4())
        
        # Check availability first
        for item in items:
            product_id = item['product_id']
            quantity = item['quantity']
            
            if product_id not in self.products:
                raise ValueError(f"Product {product_id} not found")
            
            if not self.products[product_id].can_reserve(quantity):
                raise ValueError(f"Insufficient stock for {product_id}")
        
        # Reserve items
        reserved_items = []
        for item in items:
            product_id = item['product_id']
            quantity = item['quantity']
            
            item_reservation_id = self.products[product_id].reserve(quantity)
            reserved_items.append({
                'product_id': product_id,
                'quantity': quantity,
                'item_reservation_id': item_reservation_id
            })
        
        self.reservations[reservation_id] = {
            'items': reserved_items,
            'created_at': datetime.now()
        }
        
        return reservation_id
    
    def get_product(self, product_id: str) -> Product:
        return self.products.get(product_id)
    
    def get_all_products(self) -> List[Product]:
        return list(self.products.values())

