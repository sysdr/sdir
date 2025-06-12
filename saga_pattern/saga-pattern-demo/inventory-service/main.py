import sys
sys.path.append('/app/shared')

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import random
import asyncio
from saga_utils import setup_logging

app = FastAPI(title="Inventory Service")
logger = setup_logging("inventory-service")

inventory = {"product-1": 100, "product-2": 50, "product-3": 25}
reservations = {}

class InventoryRequest(BaseModel):
    transaction_id: str
    product_id: str
    quantity: int
    should_fail: bool = False

class ReleaseRequest(BaseModel):
    transaction_id: str
    product_id: str = None
    quantity: int = None
    reservation_id: str = None

@app.post("/reserve")
async def reserve_inventory(request: InventoryRequest):
    logger.info(f"Reserving {request.quantity} of {request.product_id}")
    await asyncio.sleep(random.uniform(0.3, 1.0))
    
    if request.should_fail:
        raise HTTPException(status_code=400, detail="Inventory unavailable")
    
    if request.product_id not in inventory:
        raise HTTPException(status_code=404, detail="Product not found")
    
    if inventory[request.product_id] < request.quantity:
        raise HTTPException(status_code=400, detail="Insufficient inventory")
    
    inventory[request.product_id] -= request.quantity
    reservation_id = f"res_{request.transaction_id[:8]}"
    reservations[reservation_id] = {
        "transaction_id": request.transaction_id,
        "product_id": request.product_id,
        "quantity": request.quantity,
        "status": "reserved"
    }
    
    return {"reservation_id": reservation_id, "status": "reserved"}

@app.post("/release")
async def release_inventory(request: ReleaseRequest):
    logger.info(f"Releasing inventory {request.transaction_id}")
    
    reservation_id = request.reservation_id or f"res_{request.transaction_id[:8]}"
    if reservation_id in reservations:
        reservation = reservations[reservation_id]
        inventory[reservation["product_id"]] += reservation["quantity"]
        reservation["status"] = "released"
        return {"reservation_id": reservation_id, "status": "released"}
    
    return {"status": "not_found"}

@app.get("/inventory")
async def get_inventory():
    return {"inventory": inventory, "reservations": reservations}

@app.get("/health")
async def health():
    return {"status": "healthy"}
