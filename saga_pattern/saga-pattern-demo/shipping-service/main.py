import sys
sys.path.append('/app/shared')

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import random
import asyncio
from saga_utils import setup_logging

app = FastAPI(title="Shipping Service")
logger = setup_logging("shipping-service")
shipments = {}

class ShippingRequest(BaseModel):
    transaction_id: str
    customer_id: str
    product_id: str
    quantity: int
    should_fail: bool = False

class CancelRequest(BaseModel):
    transaction_id: str
    shipment_id: str = None

@app.post("/allocate")
async def allocate_shipping(request: ShippingRequest):
    logger.info(f"Allocating shipping {request.transaction_id}")
    await asyncio.sleep(random.uniform(0.8, 2.0))
    
    if request.should_fail:
        raise HTTPException(status_code=500, detail="Shipping unavailable")
    
    shipment_id = f"ship_{request.transaction_id[:8]}"
    shipments[shipment_id] = {
        "transaction_id": request.transaction_id,
        "customer_id": request.customer_id,
        "product_id": request.product_id,
        "quantity": request.quantity,
        "status": "allocated",
        "tracking_number": f"TRK{random.randint(100000, 999999)}"
    }
    
    return {"shipment_id": shipment_id, "status": "allocated"}

@app.post("/cancel")
async def cancel_shipping(request: CancelRequest):
    logger.info(f"Cancelling shipping {request.transaction_id}")
    
    shipment_id = request.shipment_id or f"ship_{request.transaction_id[:8]}"
    if shipment_id in shipments:
        shipments[shipment_id]["status"] = "cancelled"
        return {"shipment_id": shipment_id, "status": "cancelled"}
    
    return {"status": "not_found"}

@app.get("/health")
async def health():
    return {"status": "healthy"}
