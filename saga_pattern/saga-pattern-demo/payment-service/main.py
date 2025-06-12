import sys
sys.path.append('/app/shared')

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import random
import asyncio
from saga_utils import setup_logging

app = FastAPI(title="Payment Service")
logger = setup_logging("payment-service")
payments = {}

class PaymentRequest(BaseModel):
    transaction_id: str
    customer_id: str
    amount: float
    should_fail: bool = False

class RefundRequest(BaseModel):
    transaction_id: str
    customer_id: str = None
    amount: float = None
    payment_id: str = None

@app.post("/charge")
async def charge_payment(payment: PaymentRequest):
    logger.info(f"Processing payment {payment.transaction_id}")
    await asyncio.sleep(random.uniform(0.5, 1.5))
    
    if payment.should_fail:
        raise HTTPException(status_code=400, detail="Payment failed")
    
    payment_id = f"pay_{payment.transaction_id[:8]}"
    payments[payment_id] = {
        "transaction_id": payment.transaction_id,
        "customer_id": payment.customer_id,
        "amount": payment.amount,
        "status": "charged"
    }
    
    return {"payment_id": payment_id, "status": "charged", "amount": payment.amount}

@app.post("/refund")
async def refund_payment(refund: RefundRequest):
    logger.info(f"Processing refund {refund.transaction_id}")
    
    payment_id = refund.payment_id or f"pay_{refund.transaction_id[:8]}"
    if payment_id in payments:
        payments[payment_id]["status"] = "refunded"
        return {"payment_id": payment_id, "status": "refunded"}
    
    return {"status": "not_found"}

@app.get("/health")
async def health():
    return {"status": "healthy"}
