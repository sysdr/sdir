from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import os
import sys
import threading
import json

sys.path.append('/app')
sys.path.append('/app/shared')

from app.domain.inventory import InventoryService
from shared.infrastructure import EventBus
from shared.events.base import ItemsReserved
import uuid
from datetime import datetime

app = FastAPI(title="Inventory Context API", version="1.0.0")

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
inventory_service = InventoryService()

def handle_order_placed(event_data):
    """Handle OrderPlaced event"""
    try:
        order_id = event_data['payload']['order_id']
        items = event_data['payload']['items']
        
        print(f"📦 Processing inventory reservation for order {order_id}")
        
        # Reserve items
        reservation_id = inventory_service.reserve_items(items)
        
        # Generate ItemsReserved event
        items_reserved_event = ItemsReserved(
            event_id=str(uuid.uuid4()),
            occurred_at=datetime.now(),
            event_type="ItemsReserved",
            order_id=order_id,
            items=items,
            reservation_id=reservation_id
        )
        
        event_bus.publish(items_reserved_event)
        print(f"✅ Items reserved for order {order_id}")
        
    except Exception as e:
        print(f"❌ Failed to reserve items: {e}")

@app.on_event("startup")
async def startup_event():
    print("📦 Inventory Context started")
    
    # Subscribe to events
    event_bus.subscribe("OrderPlaced", handle_order_placed)
    
    # Start event listener in background thread
    def start_listener():
        event_bus.start_listening()
    
    listener_thread = threading.Thread(target=start_listener, daemon=True)
    listener_thread.start()

@app.get("/")
async def root():
    return {"service": "Inventory Context", "status": "running"}

@app.get("/products")
async def get_products():
    products = inventory_service.get_all_products()
    return [
        {
            "product_id": p.product_id,
            "name": p.name,
            "stock_quantity": p.stock_quantity,
            "reserved_quantity": p.reserved_quantity,
            "available_quantity": p.available_quantity
        }
        for p in products
    ]

@app.get("/products/{product_id}")
async def get_product(product_id: str):
    product = inventory_service.get_product(product_id)
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    
    return {
        "product_id": product.product_id,
        "name": product.name,
        "stock_quantity": product.stock_quantity,
        "reserved_quantity": product.reserved_quantity,
        "available_quantity": product.available_quantity
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

