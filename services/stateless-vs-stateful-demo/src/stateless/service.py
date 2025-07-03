"""
Stateless Shopping Cart Service
Demonstrates scaling characteristics of stateless architecture
"""
import json
import time
import redis
from fastapi import FastAPI, HTTPException, Request, Depends, Cookie
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from typing import Optional, List
from datetime import datetime

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common.models import CartItem, ShoppingCart, ServiceMetrics
from common.utils import (
    logger, create_jwt_token, verify_jwt_token, 
    get_system_metrics, generate_user_id, simulate_processing_delay
)

app = FastAPI(title="Stateless Shopping Cart Service", version="1.0.0")

# Mount static files and templates
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# Redis for shared data (not session state)
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

# In-memory metrics (shared across requests, not user-specific)
service_metrics = {
    'request_count': 0,
    'total_response_time': 0,
    'start_time': time.time()
}

def get_current_user(cart_token: Optional[str] = Cookie(None)):
    """Extract user info from JWT token (stateless)"""
    if not cart_token:
        return None
    
    user_data = verify_jwt_token(cart_token)
    if not user_data:
        return None
    
    return user_data

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """Home page for stateless service"""
    return templates.TemplateResponse("stateless.html", {"request": request})

@app.post("/login")
async def login(username: str, email: str):
    """Stateless login - returns JWT token"""
    simulate_processing_delay(50)  # Simulate authentication
    
    user_id = generate_user_id()
    user_data = {
        'user_id': user_id,
        'username': username,
        'email': email,
        'login_time': datetime.utcnow().isoformat()
    }
    
    # Create JWT token containing user info
    token = create_jwt_token(user_data)
    
    # Update metrics
    service_metrics['request_count'] += 1
    
    logger.info("User logged in", user_id=user_id, username=username, service="stateless")
    
    response = JSONResponse(content={
        'status': 'success',
        'user_id': user_id,
        'username': username
    })
    response.set_cookie(
        key="cart_token",
        value=token,
        httponly=True,
        max_age=86400  # 24 hours
    )
    
    return response

@app.get("/cart")
async def get_cart(user_data: dict = Depends(get_current_user)):
    """Get shopping cart - JWT contains cart state"""
    if not user_data:
        raise HTTPException(status_code=401, detail="Not authenticated")
    
    simulate_processing_delay(20)
    
    # Cart state is embedded in JWT token
    cart_items = user_data.get('cart_items', [])
    cart = ShoppingCart(
        user_id=user_data['user_id'],
        items=[CartItem(**item) for item in cart_items],
        created_at=datetime.fromisoformat(user_data.get('login_time', datetime.utcnow().isoformat()))
    )
    cart.calculate_total()
    
    service_metrics['request_count'] += 1
    
    return {
        'cart': cart.dict(),
        'service_info': {
            'type': 'stateless',
            'instance_id': f'stateless-{os.getpid()}',
            'request_count': service_metrics['request_count']
        }
    }

@app.post("/cart/add")
async def add_to_cart(item: CartItem, user_data: dict = Depends(get_current_user)):
    """Add item to cart - updates JWT token"""
    if not user_data:
        raise HTTPException(status_code=401, detail="Not authenticated")
    
    simulate_processing_delay(30)
    
    # Get current cart from JWT
    cart_items = user_data.get('cart_items', [])
    
    # Add new item
    cart_items.append(item.dict())
    
    # Create new JWT with updated cart
    updated_user_data = {**user_data, 'cart_items': cart_items}
    new_token = create_jwt_token(updated_user_data)
    
    service_metrics['request_count'] += 1
    
    logger.info("Item added to cart", 
                user_id=user_data['user_id'], 
                item=item.name, 
                service="stateless")
    
    response = JSONResponse(content={
        'status': 'success',
        'item_added': item.dict(),
        'total_items': len(cart_items)
    })
    response.set_cookie(
        key="cart_token",
        value=new_token,
        httponly=True,
        max_age=86400
    )
    
    return response

@app.get("/metrics")
async def get_metrics():
    """Get service metrics for monitoring"""
    system_metrics = get_system_metrics()
    uptime = time.time() - service_metrics['start_time']
    
    avg_response_time = (
        service_metrics['total_response_time'] / service_metrics['request_count']
        if service_metrics['request_count'] > 0 else 0
    )
    
    return ServiceMetrics(
        service_type="stateless",
        active_sessions=0,  # Stateless = no server-side sessions
        memory_usage=system_metrics['memory_percent'],
        cpu_usage=system_metrics['cpu_percent'],
        request_count=service_metrics['request_count'],
        average_response_time=avg_response_time,
        timestamp=datetime.utcnow()
    )

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        'status': 'healthy',
        'service': 'stateless',
        'timestamp': datetime.utcnow().isoformat(),
        'uptime_seconds': time.time() - service_metrics['start_time']
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
