import asyncio
import random
from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
import httpx
import os
import uvicorn

app = FastAPI(title="Observability Demo UI")
templates = Jinja2Templates(directory="templates")

# Service URLs
USER_SERVICE_URL = os.getenv("USER_SERVICE_URL", "http://localhost:8001")
PAYMENT_SERVICE_URL = os.getenv("PAYMENT_SERVICE_URL", "http://localhost:8002")
ORDER_SERVICE_URL = os.getenv("ORDER_SERVICE_URL", "http://localhost:8003")

@app.get("/", response_class=HTMLResponse)
async def dashboard(request: Request):
    return templates.TemplateResponse("dashboard.html", {"request": request})

@app.post("/create-order")
async def create_order(request: Request, user_id: int = Form(...), amount: float = Form(...)):
    try:
        async with httpx.AsyncClient() as client:
            order_data = {
                "user_id": user_id,
                "items": [
                    {"product_id": "prod_123", "quantity": 1, "price": amount}
                ],
                "total_amount": amount
            }
            
            response = await client.post(f"{ORDER_SERVICE_URL}/orders", json=order_data)
            
            if response.status_code == 200:
                result = response.json()
                return templates.TemplateResponse("dashboard.html", {
                    "request": request,
                    "success": f"Order created successfully! Order ID: {result['order_id']}",
                    "order_data": result
                })
            else:
                error_msg = response.json().get("detail", "Unknown error")
                return templates.TemplateResponse("dashboard.html", {
                    "request": request,
                    "error": f"Order creation failed: {error_msg}"
                })
    
    except Exception as e:
        return templates.TemplateResponse("dashboard.html", {
            "request": request,
            "error": f"Service error: {str(e)}"
        })

@app.get("/load-test")
async def load_test():
    """Generate load for testing observability"""
    tasks = []
    
    for i in range(10):
        user_id = random.randint(1, 3)
        amount = random.uniform(10, 500)
        
        task = create_test_order(user_id, amount)
        tasks.append(task)
    
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    success_count = sum(1 for r in results if not isinstance(r, Exception))
    error_count = len(results) - success_count
    
    return {
        "message": "Load test completed",
        "total_requests": len(results),
        "successful": success_count,
        "errors": error_count
    }

async def create_test_order(user_id: int, amount: float):
    try:
        async with httpx.AsyncClient() as client:
            order_data = {
                "user_id": user_id,
                "items": [
                    {"product_id": f"prod_{random.randint(100, 999)}", "quantity": 1, "price": amount}
                ],
                "total_amount": amount
            }
            
            response = await client.post(f"{ORDER_SERVICE_URL}/orders", json=order_data, timeout=30)
            return response.status_code == 200
    except Exception:
        return False

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
