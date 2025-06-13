"""Inventory Service - Manages product inventory and reservations."""

import os
import asyncio
import uuid
import random
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import redis.asyncio as redis
import structlog
from typing import Optional, List, Dict, Any
import json

# Import common tracing utilities
import sys
sys.path.append("/app")
from common.tracing import setup_tracing, trace_request, get_trace_context

# Initialize logging and tracing
logger = structlog.get_logger()
tracer = setup_tracing("inventory-service")

app = FastAPI(title="Inventory Service", version="1.0.0")

# Redis connection
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
redis_client = None

# Mock inventory data
INVENTORY_DATA = {
    "item-1": {"name": "Widget", "price": 29.99, "stock": 100},
    "item-2": {"name": "Gadget", "price": 19.99, "stock": 50},
    "error-item": {"name": "Error Item", "price": 0, "stock": 0}  # For error simulation
}

@app.on_event("startup")
async def startup_event():
    global redis_client
    redis_client = redis.from_url(REDIS_URL, decode_responses=True)
    
    # Initialize inventory in Redis
    for item_id, item_data in INVENTORY_DATA.items():
        await redis_client.hset(f"inventory:{item_id}", mapping=item_data)
    
    logger.info("Inventory service started", redis_url=REDIS_URL)

@app.on_event("shutdown")
async def shutdown_event():
    if redis_client:
        await redis_client.close()

class InventoryItem(BaseModel):
    id: str
    name: str
    price: float
    quantity: int

class InventoryCheckRequest(BaseModel):
    items: List[InventoryItem]

class InventoryReserveRequest(BaseModel):
    order_id: str
    items: List[InventoryItem]

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "inventory-service"}

@app.post("/inventory/check")
@trace_request("check_inventory_availability")
async def check_inventory_availability(
    request: InventoryCheckRequest,
    x_correlation_id: Optional[str] = Header(None)
):
    """Check if requested items are available in inventory."""
    
    correlation_id = x_correlation_id or str(uuid.uuid4())
    
    logger.info("Inventory availability check started",
                items_count=len(request.items),
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate database query delay
        await asyncio.sleep(random.uniform(0.05, 0.2))
        
        total_amount = 0.0
        availability_results = []
        all_available = True
        
        for item in request.items:
            # Get current inventory from Redis
            inventory_data = await redis_client.hgetall(f"inventory:{item.id}")
            
            if not inventory_data:
                logger.warning("Item not found in inventory",
                              item_id=item.id,
                              correlation_id=correlation_id,
                              **get_trace_context())
                availability_results.append({
                    "item_id": item.id,
                    "available": False,
                    "reason": "Item not found"
                })
                all_available = False
                continue
            
            current_stock = int(inventory_data.get("stock", 0))
            item_price = float(inventory_data.get("price", 0))
            
            if current_stock >= item.quantity:
                availability_results.append({
                    "item_id": item.id,
                    "available": True,
                    "current_stock": current_stock,
                    "requested_quantity": item.quantity,
                    "unit_price": item_price
                })
                total_amount += item_price * item.quantity
            else:
                logger.warning("Insufficient inventory",
                              item_id=item.id,
                              current_stock=current_stock,
                              requested_quantity=item.quantity,
                              correlation_id=correlation_id,
                              **get_trace_context())
                availability_results.append({
                    "item_id": item.id,
                    "available": False,
                    "current_stock": current_stock,
                    "requested_quantity": item.quantity,
                    "reason": "Insufficient stock"
                })
                all_available = False
        
        logger.info("Inventory availability check completed",
                   all_available=all_available,
                   total_amount=total_amount,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return {
            "available": all_available,
            "total_amount": total_amount,
            "items": availability_results,
            "checked_at": "2025-06-13T10:00:00Z"
        }
        
    except Exception as e:
        logger.error("Inventory availability check failed",
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        raise HTTPException(status_code=500, detail=f"Inventory check failed: {str(e)}")

@app.post("/inventory/reserve")
@trace_request("reserve_inventory_items")
async def reserve_inventory_items(
    request: InventoryReserveRequest,
    x_correlation_id: Optional[str] = Header(None)
):
    """Reserve inventory items for an order."""
    
    correlation_id = x_correlation_id or str(uuid.uuid4())
    
    logger.info("Inventory reservation started",
                order_id=request.order_id,
                items_count=len(request.items),
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate database transaction delay
        await asyncio.sleep(random.uniform(0.1, 0.3))
        
        reservation_results = []
        all_reserved = True
        
        # Start transaction simulation
        async with redis_client.pipeline(transaction=True) as pipe:
            for item in request.items:
                try:
                    # Watch the inventory key for changes
                    await pipe.watch(f"inventory:{item.id}")
                    
                    # Get current inventory
                    inventory_data = await redis_client.hgetall(f"inventory:{item.id}")
                    
                    if not inventory_data:
                        logger.error("Item not found during reservation",
                                   item_id=item.id,
                                   order_id=request.order_id,
                                   correlation_id=correlation_id,
                                   **get_trace_context())
                        reservation_results.append({
                            "item_id": item.id,
                            "reserved": False,
                            "reason": "Item not found"
                        })
                        all_reserved = False
                        continue
                    
                    current_stock = int(inventory_data.get("stock", 0))
                    
                    if current_stock >= item.quantity:
                        # Reserve the items by reducing stock
                        new_stock = current_stock - item.quantity
                        
                        # Update inventory with reservation
                        pipe.multi()
                        await pipe.hset(f"inventory:{item.id}", "stock", new_stock)
                        
                        # Store reservation record
                        reservation_data = {
                            "order_id": request.order_id,
                            "item_id": item.id,
                            "quantity": item.quantity,
                            "reserved_at": "2025-06-13T10:00:00Z"
                        }
                        await pipe.setex(
                            f"reservation:{request.order_id}:{item.id}",
                            3600,
                            json.dumps(reservation_data)
                        )
                        
                        await pipe.execute()
                        
                        reservation_results.append({
                            "item_id": item.id,
                            "reserved": True,
                            "quantity": item.quantity,
                            "remaining_stock": new_stock
                        })
                        
                        logger.debug("Item reserved successfully",
                                   item_id=item.id,
                                   quantity=item.quantity,
                                   remaining_stock=new_stock,
                                   order_id=request.order_id,
                                   correlation_id=correlation_id,
                                   **get_trace_context())
                    else:
                        logger.warning("Cannot reserve item - insufficient stock",
                                     item_id=item.id,
                                     current_stock=current_stock,
                                     requested_quantity=item.quantity,
                                     order_id=request.order_id,
                                     correlation_id=correlation_id,
                                     **get_trace_context())
                        reservation_results.append({
                            "item_id": item.id,
                            "reserved": False,
                            "current_stock": current_stock,
                            "requested_quantity": item.quantity,
                            "reason": "Insufficient stock"
                        })
                        all_reserved = False
                        
                except redis.WatchError:
                    logger.warning("Inventory changed during reservation",
                                 item_id=item.id,
                                 order_id=request.order_id,
                                 correlation_id=correlation_id,
                                 **get_trace_context())
                    reservation_results.append({
                        "item_id": item.id,
                        "reserved": False,
                        "reason": "Inventory changed during transaction"
                    })
                    all_reserved = False
        
        logger.info("Inventory reservation completed",
                   order_id=request.order_id,
                   all_reserved=all_reserved,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return {
            "success": all_reserved,
            "order_id": request.order_id,
            "items": reservation_results,
            "reserved_at": "2025-06-13T10:00:00Z"
        }
        
    except Exception as e:
        logger.error("Inventory reservation failed",
                    order_id=request.order_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        raise HTTPException(status_code=500, detail=f"Inventory reservation failed: {str(e)}")

@app.get("/inventory/{item_id}")
@trace_request("get_item_inventory")
async def get_item_inventory(item_id: str):
    """Get current inventory for a specific item."""
    
    logger.info("Getting item inventory",
                item_id=item_id,
                **get_trace_context())
    
    try:
        inventory_data = await redis_client.hgetall(f"inventory:{item_id}")
        
        if not inventory_data:
            raise HTTPException(status_code=404, detail="Item not found")
        
        return {
            "item_id": item_id,
            "name": inventory_data.get("name"),
            "price": float(inventory_data.get("price", 0)),
            "stock": int(inventory_data.get("stock", 0))
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get item inventory",
                    item_id=item_id,
                    error=str(e),
                    **get_trace_context())
        raise HTTPException(status_code=500, detail=f"Failed to get inventory: {str(e)}")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)
