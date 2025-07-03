"""
Stateful Shopping Cart Service
Demonstrates scaling characteristics of stateful architecture
"""
import json
import time
import redis
import uuid
from fastapi import FastAPI, HTTPException, Request, Depends, Cookie
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from typing import Optional, Dict, Any
from datetime import datetime

import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common.models import CartItem, ShoppingCart, User, ServiceMetrics
from common.utils import (
    logger, get_system_metrics, generate_user_id, simulate_processing_delay
)

app = FastAPI(title="Stateful Shopping Cart Service", version="1.0.0")

# Mount static files and templates
app.mount("/static", StaticFiles(directory="static"), name="static")
templates = Jinja2Templates(directory="templates")

# In-memory session storage (this is what makes it stateful)
active_sessions: Dict[str, User] = {}
user_carts: Dict[str, ShoppingCart] = {}

# Service metrics
service_metrics = {
    'request_count': 0,
    'total_response_time': 0,
    'start_time': time.time()
}

def get_current_user(session_id: Optional[str] = Cookie(None)):
    """Get user from server-side session storage"""
    if not session_id:
        return None
    
    return active_sessions.get(session_id)

@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    """Home page for stateful service"""
    return templates.TemplateResponse("stateful.html", {"request": request})

@app.post("/login")
async def login(username: str, email: str):
    """Stateful login - stores session in memory"""
    simulate_processing_delay(50)
    
    user_id = generate_user_id()
    session_id = str(uuid.uuid4())
    
    # Store user session in server memory
    user = User(
        user_id=user_id,
        username=username,
        email=email,
        session_data={'login_time': datetime.utcnow().isoformat()}
    )
    active_sessions[session_id] = user
    
    # Initialize empty cart in server memory
    cart = ShoppingCart(
        user_id=user_id,
        items=[],
        created_at=datetime.utcnow()
    )
    user_carts[user_id] = cart
    
    service_metrics['request_count'] += 1
    
    logger.info("User logged in", 
                user_id=user_id, 
                username=username, 
                session_id=session_id,
                service="stateful",
                active_sessions=len(active_sessions))
    
    response = JSONResponse(content={
        'status': 'success',
        'user_id': user_id,
        'username': username
    })
    response.set_cookie(
        key="session_id",
        value=session_id,
        httponly=True,
        max_age=86400
    )
    
    return response

@app.get("/cart")
async def get_cart(user: User = Depends(get_current_user)):
    """Get shopping cart from server memory"""
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")
    
    simulate_processing_delay(20)
    
    cart = user_carts.get(user.user_id)
    if not cart:
        cart = ShoppingCart(
            user_id=user.user_id,
            items=[],
            created_at=datetime.utcnow()
        )
        user_carts[user.user_id] = cart
    
    cart.calculate_total()
    service_metrics['request_count'] += 1
    
    return {
        'cart': cart.dict(),
        'service_info': {
            'type': 'stateful',
            'instance_id': f'stateful-{os.getpid()}',
            'active_sessions': len(active_sessions),
            'request_count': service_metrics['request_count']
        }
    }

@app.post("/cart/add")
async def add_to_cart(item: CartItem, user: User = Depends(get_current_user)):
    """Add item to cart in server memory"""
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")
    
    simulate_processing_delay(30)
    
    # Get cart from server memory
    cart = user_carts.get(user.user_id)
    if not cart:
        cart = ShoppingCart(
            user_id=user.user_id,
            items=[],
            created_at=datetime.utcnow()
        )
        user_carts[user.user_id] = cart
    
    # Add item to server-side cart
    cart.items.append(item)
    cart.calculate_total()
    
    service_metrics['request_count'] += 1
    
    logger.info("Item added to cart", 
                user_id=user.user_id, 
                item=item.name,
                cart_total=cart.total,
                service="stateful")
    
    return {
        'status': 'success',
        'item_added': item.dict(),
        'total_items': len(cart.items),
        'cart_total': cart.total
    }

@app.get("/metrics")
async def get_metrics():
    """Get service metrics including active sessions"""
    system_metrics = get_system_metrics()
    uptime = time.time() - service_metrics['start_time']
    
    avg_response_time = (
        service_metrics['total_response_time'] / service_metrics['request_count']
        if service_metrics['request_count'] > 0 else 0
    )
    
    # Calculate memory usage of active sessions
    session_memory_mb = len(active_sessions) * 0.1  # Rough estimate
    
    return ServiceMetrics(
        service_type="stateful",
        active_sessions=len(active_sessions),
        memory_usage=system_metrics['memory_percent'],
        cpu_usage=system_metrics['cpu_percent'],
        request_count=service_metrics['request_count'],
        average_response_time=avg_response_time,
        timestamp=datetime.utcnow()
    )

@app.get("/sessions")
async def get_active_sessions():
    """Debug endpoint to view active sessions"""
    return {
        'active_sessions': len(active_sessions),
        'active_carts': len(user_carts),
        'session_ids': list(active_sessions.keys())[:10],  # Show first 10
        'memory_usage_estimate_mb': len(active_sessions) * 0.1
    }

@app.post("/logout")
async def logout(user: User = Depends(get_current_user)):
    """Logout and clean up server-side session"""
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated")
    
    # Find and remove session
    session_to_remove = None
    for session_id, stored_user in active_sessions.items():
        if stored_user.user_id == user.user_id:
            session_to_remove = session_id
            break
    
    if session_to_remove:
        del active_sessions[session_to_remove]
    
    # Remove cart
    if user.user_id in user_carts:
        del user_carts[user.user_id]
    
    logger.info("User logged out", 
                user_id=user.user_id,
                remaining_sessions=len(active_sessions),
                service="stateful")
    
    response = JSONResponse(content={'status': 'logged out'})
    response.delete_cookie(key="session_id")
    return response

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {
        'status': 'healthy',
        'service': 'stateful',
        'active_sessions': len(active_sessions),
        'timestamp': datetime.utcnow().isoformat(),
        'uptime_seconds': time.time() - service_metrics['start_time']
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
