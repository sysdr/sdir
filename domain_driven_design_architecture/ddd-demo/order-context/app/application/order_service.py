from typing import Optional, List
from app.domain.order import Order, OrderItem, Address
from shared.infrastructure import EventBus

class OrderService:
    """Application service - orchestrates domain operations"""
    
    def __init__(self, event_bus: EventBus):
        self.event_bus = event_bus
        self.orders = {}  # In-memory storage for demo
    
    def create_order(self, customer_id: str) -> str:
        """Create new order"""
        order = Order(customer_id=customer_id)
        self.orders[order.order_id] = order
        return order.order_id
    
    def add_item_to_order(self, order_id: str, product_id: str, 
                         product_name: str, quantity: int, price: float):
        """Add item to existing order"""
        order = self._get_order(order_id)
        order.add_item(product_id, product_name, quantity, price)
    
    def set_shipping_address(self, order_id: str, address_data: dict):
        """Set shipping address"""
        order = self._get_order(order_id)
        order.shipping_address = Address(**address_data)
    
    def confirm_order(self, order_id: str):
        """Confirm order and publish events"""
        order = self._get_order(order_id)
        events = order.confirm()
        
        # Publish domain events
        for event in events:
            self.event_bus.publish(event)
    
    def get_order(self, order_id: str) -> Optional[Order]:
        """Get order details"""
        return self.orders.get(order_id)
    
    def get_all_orders(self) -> List[Order]:
        """Get all orders"""
        return list(self.orders.values())
    
    def _get_order(self, order_id: str) -> Order:
        """Get order or raise exception"""
        if order_id not in self.orders:
            raise ValueError(f"Order {order_id} not found")
        return self.orders[order_id]

