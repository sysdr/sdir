import sys
import os
sys.path.append('/app/shared')

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import asyncio
import uuid
from saga_utils import SAGAOrchestrator, SAGAStep, setup_logging

app = FastAPI(title="Order Service")
logger = setup_logging("order-service")

class OrderRequest(BaseModel):
    customer_id: str
    product_id: str
    quantity: int
    amount: float
    should_fail: str = "none"

orchestrator = None

@app.on_event("startup")
async def startup():
    global orchestrator
    orchestrator = SAGAOrchestrator()
    
    # Retry Redis connection
    for attempt in range(30):
        try:
            await orchestrator.init_redis()
            logger.info("Order Service ready")
            break
        except Exception as e:
            logger.error(f"Redis connection attempt {attempt + 1}: {e}")
            await asyncio.sleep(2)
    else:
        raise Exception("Failed to connect to Redis")

@app.post("/create-order")
async def create_order(order: OrderRequest):
    transaction_id = str(uuid.uuid4())
    logger.info(f"Creating order {transaction_id}")
    
    steps = [
        SAGAStep("inventory", "reserve", "release", {
            "transaction_id": transaction_id,
            "product_id": order.product_id,
            "quantity": order.quantity,
            "should_fail": order.should_fail == "inventory"
        }),
        SAGAStep("payment", "charge", "refund", {
            "transaction_id": transaction_id,
            "customer_id": order.customer_id,
            "amount": order.amount,
            "should_fail": order.should_fail == "payment"
        }),
        SAGAStep("shipping", "allocate", "cancel", {
            "transaction_id": transaction_id,
            "customer_id": order.customer_id,
            "product_id": order.product_id,
            "quantity": order.quantity,
            "should_fail": order.should_fail == "shipping"
        })
    ]
    
    await orchestrator.create_saga(transaction_id, steps)
    result = await orchestrator.execute_saga(transaction_id)
    
    return {"transaction_id": transaction_id, "saga_result": result}

@app.get("/saga/{transaction_id}")
async def get_saga_status(transaction_id: str):
    saga = await orchestrator.get_saga(transaction_id)
    if not saga:
        raise HTTPException(status_code=404, detail="SAGA not found")
    return saga

@app.get("/health")
async def health():
    return {"status": "healthy"}
