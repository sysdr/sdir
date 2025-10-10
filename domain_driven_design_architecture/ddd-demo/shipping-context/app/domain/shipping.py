from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import List, Dict
import uuid

@dataclass
class Shipment:
    shipment_id: str
    order_id: str
    items: List[Dict]
    estimated_delivery: datetime
    status: str = "scheduled"
    created_at: datetime = None
    
    def __post_init__(self):
        if self.created_at is None:
            self.created_at = datetime.now()

class ShippingService:
    def __init__(self):
        self.shipments = {}
    
    def create_shipment(self, order_id: str, items: List[Dict]) -> str:
        """Create shipment for order"""
        shipment_id = str(uuid.uuid4())
        
        # Calculate estimated delivery (3-5 business days)
        estimated_delivery = datetime.now() + timedelta(days=4)
        
        shipment = Shipment(
            shipment_id=shipment_id,
            order_id=order_id,
            items=items,
            estimated_delivery=estimated_delivery
        )
        
        self.shipments[shipment_id] = shipment
        print(f"🚚 Created shipment {shipment_id} for order {order_id}")
        
        return shipment_id
    
    def get_shipment(self, shipment_id: str) -> Shipment:
        return self.shipments.get(shipment_id)
    
    def get_all_shipments(self) -> List[Shipment]:
        return list(self.shipments.values())

