"""API Gateway - Entry point for all requests."""

import os
import asyncio
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import httpx
import structlog
from typing import Dict, Any
import uuid

# Import common tracing utilities
import sys
sys.path.append("/app")
from common.tracing import setup_tracing, trace_request, get_trace_context

app = FastAPI(title="API Gateway", version="1.0.0")

# Initialize logging and tracing
logger = structlog.get_logger()
tracer = setup_tracing("api-gateway", app)

# Service URLs from environment
ORDER_SERVICE_URL = os.getenv("ORDER_SERVICE_URL", "http://localhost:8001")

class OrderRequest(BaseModel):
    user_id: str
    items: list[Dict[str, Any]]
    payment_method: str = "credit_card"

class OrderResponse(BaseModel):
    order_id: str
    status: str
    message: str
    trace_id: str

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": "api-gateway"}

@app.get("/", response_class=HTMLResponse)
async def root():
    """Serve the demo web interface."""
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Distributed Tracing Demo</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .container { max-width: 800px; margin: 0 auto; }
            .form-group { margin-bottom: 20px; }
            label { display: block; margin-bottom: 5px; font-weight: bold; }
            input, select, textarea { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; }
            button { background: #007bff; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; }
            button:hover { background: #0056b3; }
            .result { margin-top: 20px; padding: 15px; border: 1px solid #ddd; border-radius: 4px; background: #f9f9f9; }
            .links { margin-top: 30px; }
            .links a { display: inline-block; margin-right: 20px; color: #007bff; text-decoration: none; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>🔍 Distributed Tracing Demo</h1>
            <p>This demo showcases distributed tracing across multiple microservices.</p>
            
            <div class="form-group">
                <label for="userId">User ID:</label>
                <input type="text" id="userId" value="user-123" placeholder="Enter user ID">
            </div>
            
            <div class="form-group">
                <label for="items">Items (JSON):</label>
                <textarea id="items" rows="4" placeholder='[{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 2}]'>[{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 2}, {"id": "item-2", "name": "Gadget", "price": 19.99, "quantity": 1}]</textarea>
            </div>
            
            <div class="form-group">
                <label for="paymentMethod">Payment Method:</label>
                <select id="paymentMethod">
                    <option value="credit_card">Credit Card</option>
                    <option value="paypal">PayPal</option>
                    <option value="bank_transfer">Bank Transfer</option>
                </select>
            </div>
            
            <button onclick="placeOrder()">Place Order</button>
            <button onclick="simulateError()">Simulate Error Scenario</button>
            
            <div id="result" class="result" style="display: none;"></div>
            
            <div class="links">
                <h3>🔗 Quick Links:</h3>
                <a href="http://localhost:16686" target="_blank">📊 Jaeger UI (View Traces)</a>
                <a href="http://localhost:8000/docs" target="_blank">📚 API Documentation</a>
                <a href="http://localhost:8001/docs" target="_blank">🛒 Order Service API</a>
                <a href="http://localhost:8002/docs" target="_blank">💳 Payment Service API</a>
            </div>
        </div>
        
        <script>
            async function placeOrder() {
                const userId = document.getElementById('userId').value;
                const itemsText = document.getElementById('items').value;
                const paymentMethod = document.getElementById('paymentMethod').value;
                
                try {
                    const items = JSON.parse(itemsText);
                    const response = await fetch('/orders', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            user_id: userId,
                            items: items,
                            payment_method: paymentMethod
                        })
                    });
                    
                    const result = await response.json();
                    displayResult(result, response.ok);
                } catch (error) {
                    displayResult({ error: error.message }, false);
                }
            }
            
            async function simulateError() {
                try {
                    const response = await fetch('/orders/simulate-error', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            user_id: "error-user",
                            items: [{"id": "error-item", "name": "Error Item", "price": 0, "quantity": 1}],
                            payment_method: "invalid_method"
                        })
                    });
                    
                    const result = await response.json();
                    displayResult(result, response.ok);
                } catch (error) {
                    displayResult({ error: error.message }, false);
                }
            }
            
            function displayResult(result, success) {
                const resultDiv = document.getElementById('result');
                resultDiv.style.display = 'block';
                resultDiv.style.backgroundColor = success ? '#d4edda' : '#f8d7da';
                resultDiv.style.borderColor = success ? '#c3e6cb' : '#f5c6cb';
                
                let html = '<h4>' + (success ? '✅ Success' : '❌ Error') + '</h4>';
                html += '<pre>' + JSON.stringify(result, null, 2) + '</pre>';
                
                if (result.trace_id) {
                    html += '<p><a href="http://localhost:16686/trace/' + result.trace_id + '" target="_blank">🔍 View Trace in Jaeger</a></p>';
                }
                
                resultDiv.innerHTML = html;
            }
        </script>
    </body>
    </html>
    """

@app.post("/orders", response_model=OrderResponse)
@trace_request("create_order")
async def create_order(order_request: OrderRequest):
    """Create a new order through the order service."""
    
    # Generate a correlation ID for this request
    correlation_id = str(uuid.uuid4())
    
    logger.info("Order creation started", 
                user_id=order_request.user_id,
                correlation_id=correlation_id,
                **get_trace_context())
    
    try:
        async with httpx.AsyncClient() as client:
            # Add tracing headers
            headers = {
                "X-Correlation-ID": correlation_id,
                "X-User-ID": order_request.user_id
            }
            
            response = await client.post(
                f"{ORDER_SERVICE_URL}/orders",
                json=order_request.dict(),
                headers=headers,
                timeout=30.0
            )
            
            if response.status_code == 200:
                result = response.json()
                logger.info("Order created successfully",
                           order_id=result.get("order_id"),
                           correlation_id=correlation_id,
                           **get_trace_context())
                
                return OrderResponse(
                    order_id=result["order_id"],
                    status=result["status"],
                    message=result["message"],
                    trace_id=get_trace_context().get("trace_id", "unknown")
                )
            else:
                logger.error("Order creation failed",
                            status_code=response.status_code,
                            response=response.text,
                            correlation_id=correlation_id,
                            **get_trace_context())
                
                raise HTTPException(
                    status_code=response.status_code,
                    detail=f"Order creation failed: {response.text}"
                )
                
    except httpx.TimeoutException:
        logger.error("Order service timeout", 
                    correlation_id=correlation_id,
                    **get_trace_context())
        raise HTTPException(status_code=504, detail="Order service timeout")
    except Exception as e:
        logger.error("Unexpected error during order creation",
                    error=str(e),
                    correlation_id=correlation_id,
                    **get_trace_context())
        raise HTTPException(status_code=500, detail=f"Internal server error: {str(e)}")

@app.post("/orders/simulate-error")
@trace_request("simulate_error_scenario")
async def simulate_error_scenario(order_request: OrderRequest):
    """Simulate various error scenarios for demonstration."""
    
    correlation_id = str(uuid.uuid4())
    trace_context = get_trace_context()
    
    logger.info("Error simulation started",
                scenario="payment_failure",
                correlation_id=correlation_id,
                **trace_context)
    
    try:
        async with httpx.AsyncClient() as client:
            headers = {
                "X-Correlation-ID": correlation_id,
                "X-User-ID": order_request.user_id,
                "X-Simulate-Error": "payment_failure"  # Signal to simulate payment failure
            }
            
            response = await client.post(
                f"{ORDER_SERVICE_URL}/orders",
                json=order_request.dict(),
                headers=headers,
                timeout=30.0
            )
            
            result = response.json()
            return {
                **result,
                "trace_id": trace_context.get("trace_id", "unknown"),
                "simulation": "payment_failure_scenario"
            }
            
    except Exception as e:
        logger.error("Error simulation failed",
                    error=str(e),
                    correlation_id=correlation_id,
                    **trace_context)
        return {
            "error": str(e),
            "trace_id": trace_context.get("trace_id", "unknown"),
            "simulation": "error_simulation_failed"
        }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
