from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
import os
import uvicorn
from datetime import datetime
from typing import List
import sys
sys.path.append('/app')

from services.shared.database import SessionLocal, engine, database, connect_database, disconnect_database
from services.shared.models import Order, Base

SERVICE_PORT = int(os.getenv("SERVICE_PORT", 8003))

app = FastAPI(title="Order Service")

# Create tables
Base.metadata.create_all(bind=engine)

class OrderCreate(BaseModel):
    user_id: int
    product_id: int
    quantity: int
    total_price: float

class OrderResponse(BaseModel):
    id: int
    user_id: int
    product_id: int
    quantity: int
    total_price: float
    status: str
    created_at: datetime

    class Config:
        from_attributes = True

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.on_event("startup")
async def startup():
    await connect_database()

@app.on_event("shutdown")
async def shutdown():
    await disconnect_database()

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "order_service",
        "scaling_axis": "Y-axis (Functional Decomposition)"
    }

@app.post("/api/orders/", response_model=OrderResponse)
async def create_order(order: OrderCreate, db: Session = Depends(get_db)):
    """Create a new order"""
    db_order = Order(**order.dict())
    db.add(db_order)
    db.commit()
    db.refresh(db_order)
    return db_order

@app.get("/api/orders/{order_id}", response_model=OrderResponse)
async def get_order(order_id: int, db: Session = Depends(get_db)):
    """Get order by ID"""
    order = db.query(Order).filter(Order.id == order_id).first()
    if not order:
        raise HTTPException(status_code=404, detail="Order not found")
    return order

@app.get("/api/orders/", response_model=List[OrderResponse])
async def list_orders(db: Session = Depends(get_db)):
    """List all orders"""
    orders = db.query(Order).all()
    return orders

@app.get("/api/orders/user/{user_id}", response_model=List[OrderResponse])
async def get_user_orders(user_id: int, db: Session = Depends(get_db)):
    """Get orders for a specific user"""
    orders = db.query(Order).filter(Order.user_id == user_id).all()
    return orders

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=SERVICE_PORT)
