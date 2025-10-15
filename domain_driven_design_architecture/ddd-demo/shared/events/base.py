from abc import ABC
from dataclasses import dataclass
from datetime import datetime
from typing import Dict, Any
import json

@dataclass
class DomainEvent(ABC):
    event_id: str
    occurred_at: datetime
    event_type: str
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'event_id': self.event_id,
            'occurred_at': self.occurred_at.isoformat(),
            'event_type': self.event_type,
            'payload': self._get_payload()
        }
    
    def _get_payload(self) -> Dict[str, Any]:
        return {}
    
    def to_json(self) -> str:
        return json.dumps(self.to_dict())

@dataclass  
class OrderPlaced(DomainEvent):
    order_id: str
    customer_id: str
    items: list
    total_amount: float
    
    def __post_init__(self):
        self.event_type = "OrderPlaced"
    
    def _get_payload(self) -> Dict[str, Any]:
        return {
            'order_id': self.order_id,
            'customer_id': self.customer_id,
            'items': self.items,
            'total_amount': self.total_amount
        }

@dataclass
class ItemsReserved(DomainEvent):
    order_id: str
    items: list
    reservation_id: str
    
    def __post_init__(self):
        self.event_type = "ItemsReserved"
    
    def _get_payload(self) -> Dict[str, Any]:
        return {
            'order_id': self.order_id,
            'items': self.items,
            'reservation_id': self.reservation_id
        }

@dataclass
class ShipmentCreated(DomainEvent):
    order_id: str
    shipment_id: str
    estimated_delivery: str
    
    def __post_init__(self):
        self.event_type = "ShipmentCreated"
    
    def _get_payload(self) -> Dict[str, Any]:
        return {
            'order_id': self.order_id,
            'shipment_id': self.shipment_id,
            'estimated_delivery': self.estimated_delivery
        }

