from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import os
import sys
import threading
import uuid
from datetime import datetime

sys.path.append('/app')
sys.path.append('/app/shared')

from app.domain.shipping import ShippingService
from shared.infrastructure import EventBus
from shared.events.base import ShipmentCreated

app = FastAPI(title="Shipping Context API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize services
redis_url = os.getenv("REDIS_URL", "redis://localhost:6379")
event_bus = EventBus(redis_url)
shipping_service = ShippingService()

def handle_items_reserved(event_data):
    """Handle ItemsReserved event"""
    try:
        order_id = event_data['payload']['order_id']
        items = event_data['payload']['items']
        
        print(f"🚚 Creating shipment for order {order_id}")
        
        # Create shipment
        shipment_id = shipping_service.create_shipment(order_id, items)
        shipment = shipping_service.get_shipment(shipment_id)
        
        # Generate ShipmentCreated event
        shipment_created_event = ShipmentCreated(
            event_id=str(uuid.uuid4()),
            occurred_at=datetime.now(),
            event_type="ShipmentCreated",
            order_id=order_id,
            shipment_id=shipment_id,
            estimated_delivery=shipment.estimated_delivery.isoformat()
        )
        
        event_bus.publish(shipment_created_event)
        print(f"✅ Shipment created for order {order_id}")
        
    except Exception as e:
        print(f"❌ Failed to create shipment: {e}")

@app.on_event("startup")
async def startup_event():
    print("🚚 Shipping Context started")
    
    # Subscribe to events
    event_bus.subscribe("ItemsReserved", handle_items_reserved)
    
    # Start event listener in background thread
    def start_listener():
        event_bus.start_listening()
    
    listener_thread = threading.Thread(target=start_listener, daemon=True)
    listener_thread.start()

@app.get("/")
async def root():
    return {"service": "Shipping Context", "status": "running"}

@app.get("/shipments")
async def get_shipments():
    shipments = shipping_service.get_all_shipments()
    return [
        {
            "shipment_id": s.shipment_id,
            "order_id": s.order_id,
            "status": s.status,
            "estimated_delivery": s.estimated_delivery.isoformat(),
            "item_count": len(s.items),
            "created_at": s.created_at.isoformat()
        }
        for s in shipments
    ]

@app.get("/shipments/{shipment_id}")
async def get_shipment(shipment_id: str):
    shipment = shipping_service.get_shipment(shipment_id)
    if not shipment:
        raise HTTPException(status_code=404, detail="Shipment not found")
    
    return {
        "shipment_id": shipment.shipment_id,
        "order_id": shipment.order_id,
        "status": shipment.status,
        "estimated_delivery": shipment.estimated_delivery.isoformat(),
        "items": shipment.items,
        "created_at": shipment.created_at.isoformat()
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

