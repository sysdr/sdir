from sqlalchemy import Column, Integer, String, DateTime, Float, Boolean, Text
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func
from pydantic import BaseModel
from datetime import datetime
from typing import Optional

Base = declarative_base()

class Product(Base):
    __tablename__ = "products"
    
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(255), nullable=False)
    description = Column(Text)
    price = Column(Float, nullable=False)
    stock_quantity = Column(Integer, default=0)
    category = Column(String(100))
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class Order(Base):
    __tablename__ = "orders"
    
    id = Column(Integer, primary_key=True, index=True)
    customer_id = Column(String(100), nullable=False)
    product_id = Column(Integer, nullable=False)
    quantity = Column(Integer, nullable=False)
    total_amount = Column(Float, nullable=False)
    status = Column(String(50), default="pending")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

# Command DTOs
class CreateProductCommand(BaseModel):
    name: str
    description: Optional[str] = None
    price: float
    stock_quantity: int = 0
    category: Optional[str] = None

class UpdateStockCommand(BaseModel):
    product_id: int
    quantity: int

class CreateOrderCommand(BaseModel):
    customer_id: str
    product_id: int
    quantity: int

# Event DTOs
class ProductCreatedEvent(BaseModel):
    event_type: str = "ProductCreated"
    product_id: int
    name: str
    description: Optional[str]
    price: float
    stock_quantity: int
    category: Optional[str]
    timestamp: datetime = datetime.now()

class StockUpdatedEvent(BaseModel):
    event_type: str = "StockUpdated"
    product_id: int
    old_quantity: int
    new_quantity: int
    timestamp: datetime = datetime.now()

class OrderCreatedEvent(BaseModel):
    event_type: str = "OrderCreated"
    order_id: int
    customer_id: str
    product_id: int
    quantity: int
    total_amount: float
    timestamp: datetime = datetime.now()
