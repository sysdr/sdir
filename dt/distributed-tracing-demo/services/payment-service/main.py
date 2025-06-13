"""Payment Service - Handles payment processing."""

import os
import asyncio
import uuid
import random
from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
import structlog
from typing import Optional
import json

# Import common tracing utilities
import sys
sys.path.append("/app")
from common.tracing import setup_tracing, trace_request, get_trace_context

# Initialize logging and tracing
logger = structlog.get_logger()
tracer = setup_tracing("payment-service")

app = FastAPI(title="Payment Service", version="1.0.0")

class PaymentRequest(BaseModel):
    user_id: str
    amount: float
    payment_method: str = "credit_card"

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "payment-service"}

@app.post("/payments/process")
@trace_request("process_payment")
async def process_payment(
    payment_request: PaymentRequest,
    x_correlation_id: Optional[str] = Header(None),
    x_user_id: Optional[str] = Header(None),
    x_simulate_error: Optional[str] = Header(None)
):
    """Process a payment with simulated payment gateway interaction."""
    
    payment_id = f"pay-{uuid.uuid4()}"
    correlation_id = x_correlation_id or str(uuid.uuid4())
    
    logger.info("Payment processing started",
                payment_id=payment_id,
                user_id=payment_request.user_id,
                amount=payment_request.amount,
                payment_method=payment_request.payment_method,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        # Simulate payment gateway delay
        await asyncio.sleep(random.uniform(0.1, 0.5))
        
        # Simulate error scenarios
        if x_simulate_error == "payment_declined":
            logger.warning("Payment declined (simulated)",
                          payment_id=payment_id,
                          correlation_id=correlation_id,
                          **get_trace_context())
            return {
                "success": False,
                "payment_id": payment_id,
                "message": "Payment declined by bank",
                "error_code": "CARD_DECLINED"
            }
        
        # Simulate random payment failures (5% chance)
        if random.random() < 0.05:
            logger.warning("Payment failed due to random error",
                          payment_id=payment_id,
                          correlation_id=correlation_id,
                          **get_trace_context())
            return {
                "success": False,
                "payment_id": payment_id,
                "message": "Payment processing failed",
                "error_code": "PROCESSING_ERROR"
            }
        
        # Validate payment method
        valid_methods = ["credit_card", "paypal", "bank_transfer"]
        if payment_request.payment_method not in valid_methods:
            logger.error("Invalid payment method",
                        payment_method=payment_request.payment_method,
                        payment_id=payment_id,
                        correlation_id=correlation_id,
                        **get_trace_context())
            return {
                "success": False,
                "payment_id": payment_id,
                "message": f"Invalid payment method: {payment_request.payment_method}",
                "error_code": "INVALID_METHOD"
            }
        
        # Simulate payment gateway interaction
        await simulate_payment_gateway_call(payment_request, payment_id, correlation_id)
        
        # Process successful payment
        logger.info("Payment processed successfully",
                   payment_id=payment_id,
                   user_id=payment_request.user_id,
                   amount=payment_request.amount,
                   correlation_id=correlation_id,
                   **get_trace_context())
        
        return {
            "success": True,
            "payment_id": payment_id,
            "message": "Payment processed successfully",
            "amount": payment_request.amount,
            "transaction_id": f"txn-{uuid.uuid4()}"
        }
        
    except Exception as e:
        logger.error("Payment processing failed",
                    payment_id=payment_id,
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        return {
            "success": False,
            "payment_id": payment_id,
            "message": f"Payment processing error: {str(e)}",
            "error_code": "INTERNAL_ERROR"
        }

@trace_request("payment_gateway_call")
async def simulate_payment_gateway_call(payment_request: PaymentRequest, 
                                       payment_id: str, correlation_id: str):
    """Simulate external payment gateway interaction."""
    
    logger.info("Calling payment gateway",
                payment_id=payment_id,
                gateway="stripe-simulation",
                correlation_id=correlation_id,
                **get_trace_context())
    
    # Simulate gateway response time
    await asyncio.sleep(random.uniform(0.2, 0.8))
    
    # Simulate gateway validation steps
    await validate_card_details(payment_request, correlation_id)
    await check_fraud_rules(payment_request, correlation_id)
    await authorize_payment(payment_request, correlation_id)
    
    logger.info("Payment gateway call completed",
                payment_id=payment_id,
                correlation_id=correlation_id,
                **get_trace_context())

@trace_request("validate_card_details")
async def validate_card_details(payment_request: PaymentRequest, correlation_id: str):
    """Simulate card validation."""
    await asyncio.sleep(random.uniform(0.05, 0.15))
    logger.debug("Card details validated",
                user_id=payment_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())

@trace_request("check_fraud_rules")
async def check_fraud_rules(payment_request: PaymentRequest, correlation_id: str):
    """Simulate fraud detection."""
    await asyncio.sleep(random.uniform(0.1, 0.3))
    
    # Simulate fraud check result
    fraud_score = random.uniform(0, 100)
    
    logger.debug("Fraud check completed",
                user_id=payment_request.user_id,
                fraud_score=fraud_score,
                correlation_id=correlation_id,
                **get_trace_context())
    
    if fraud_score > 85:
        raise Exception("Transaction flagged for fraud review")

@trace_request("authorize_payment")
async def authorize_payment(payment_request: PaymentRequest, correlation_id: str):
    """Simulate payment authorization."""
    await asyncio.sleep(random.uniform(0.1, 0.2))
    logger.debug("Payment authorized",
                user_id=payment_request.user_id,
                amount=payment_request.amount,
                correlation_id=correlation_id,
                **get_trace_context())

@app.get("/payments/{payment_id}")
@trace_request("get_payment_status")
async def get_payment_status(payment_id: str):
    """Get payment status by ID."""
    
    logger.info("Payment status requested",
                payment_id=payment_id,
                **get_trace_context())
    
    # In a real system, this would query a database
    return {
        "payment_id": payment_id,
        "status": "completed",
        "message": "Payment processed successfully"
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
