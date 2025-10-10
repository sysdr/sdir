from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import os
import sys
import threading

# Add paths for imports
sys.path.append('/app')
sys.path.append('/app/shared')

from app.application.order_service import OrderService
from shared.infrastructure import EventBus

# Pydantic models for API
class CreateOrderRequest(BaseModel):
    customer_id: str

class AddItemRequest(BaseModel):
    product_id: str
    product_name: str
    quantity: int
    price: float

class AddressRequest(BaseModel):
    street: str
    city: str
    state: str
    zip_code: str
    country: str = "US"

app = FastAPI(title="Order Context API", version="1.0.0")

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
order_service = OrderService(event_bus)

@app.on_event("startup")
async def startup_event():
    print("🛒 Order Context started")

@app.get("/")
async def root():
    return {"service": "Order Context", "status": "running"}

@app.post("/orders")
async def create_order(request: CreateOrderRequest):
    try:
        order_id = order_service.create_order(request.customer_id)
        return {"order_id": order_id, "status": "created"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/orders/{order_id}/items")
async def add_item(order_id: str, request: AddItemRequest):
    try:
        order_service.add_item_to_order(
            order_id, request.product_id, request.product_name, 
            request.quantity, request.price
        )
        return {"status": "item_added"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.put("/orders/{order_id}/address")
async def set_address(order_id: str, request: AddressRequest):
    try:
        order_service.set_shipping_address(order_id, request.dict())
        return {"status": "address_set"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/orders/{order_id}/confirm")
async def confirm_order(order_id: str):
    try:
        order_service.confirm_order(order_id)
        return {"status": "confirmed"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/orders/{order_id}")
async def get_order(order_id: str):
    order = order_service.get_order(order_id)
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    
    return {
        "order_id": order.order_id,
        "customer_id": order.customer_id,
        "status": order.status.value,
        "items": [
            {
                "product_id": item.product_id,
                "product_name": item.product_name,
                "quantity": item.quantity,
                "price": item.price,
                "line_total": item.line_total()
            }
            for item in order.items
        ],
        "total": order.calculate_total(),
        "created_at": order.created_at.isoformat()
    }

@app.get("/orders")
async def get_all_orders():
    orders = order_service.get_all_orders()
    return [
        {
            "order_id": order.order_id,
            "customer_id": order.customer_id,
            "status": order.status.value,
            "total": order.calculate_total(),
            "item_count": len(order.items),
            "created_at": order.created_at.isoformat()
        }
        for order in orders
    ]

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)

