import json
import structlog
from fastapi import FastAPI, HTTPException, Depends
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import create_engine, and_
from sqlalchemy.orm import sessionmaker, Session
from contextlib import asynccontextmanager
import redis.asyncio as redis
import os
from models import *

# Configure logging
logger = structlog.get_logger()

# Database setup
DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://cqrs_user:cqrs_password@localhost:5432/command_db")
engine = create_engine(DATABASE_URL)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Redis setup
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
redis_client = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global redis_client
    redis_client = redis.from_url(REDIS_URL, decode_responses=True)
    
    # Create tables
    Base.metadata.create_all(bind=engine)
    logger.info("Command service started")
    
    yield
    
    # Shutdown
    if redis_client:
        await redis_client.close()
    logger.info("Command service stopped")

app = FastAPI(
    title="CQRS Command Service",
    description="Handles all write operations and business logic",
    version="1.0.0",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

async def publish_event(event: dict):
    """Publish event to Redis event bus"""
    try:
        await redis_client.publish("events", json.dumps(event))
        logger.info("Event published", event_type=event.get("event_type"))
    except Exception as e:
        logger.error("Failed to publish event", error=str(e))

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "command"}

@app.post("/commands/products")
async def create_product(command: CreateProductCommand, db: Session = Depends(get_db)):
    """Create a new product - Command Handler"""
    try:
        # Business logic validation
        if command.price <= 0:
            raise HTTPException(status_code=400, detail="Price must be positive")
        
        if command.stock_quantity < 0:
            raise HTTPException(status_code=400, detail="Stock quantity cannot be negative")
        
        # Create product
        product = Product(
            name=command.name,
            description=command.description,
            price=command.price,
            stock_quantity=command.stock_quantity,
            category=command.category
        )
        
        db.add(product)
        db.commit()
        db.refresh(product)
        
        # Publish event
        event = ProductCreatedEvent(
            product_id=product.id,
            name=product.name,
            description=product.description,
            price=product.price,
            stock_quantity=product.stock_quantity,
            category=product.category
        )
        
        await publish_event(event.model_dump(mode='json'))
        
        logger.info("Product created", product_id=product.id)
        return {"message": "Product created successfully", "product_id": product.id}
        
    except Exception as e:
        db.rollback()
        logger.error("Failed to create product", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.put("/commands/products/{product_id}/stock")
async def update_stock(product_id: int, command: UpdateStockCommand, db: Session = Depends(get_db)):
    """Update product stock - Command Handler"""
    try:
        product = db.query(Product).filter(Product.id == product_id).first()
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        if command.quantity < 0:
            raise HTTPException(status_code=400, detail="Stock quantity cannot be negative")
        
        old_quantity = product.stock_quantity
        product.stock_quantity = command.quantity
        
        db.commit()
        
        # Publish event
        event = StockUpdatedEvent(
            product_id=product_id,
            old_quantity=old_quantity,
            new_quantity=command.quantity
        )
        
        await publish_event(event.model_dump(mode='json'))
        
        logger.info("Stock updated", product_id=product_id, old_quantity=old_quantity, new_quantity=command.quantity)
        return {"message": "Stock updated successfully"}
        
    except Exception as e:
        db.rollback()
        logger.error("Failed to update stock", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/commands/orders")
async def create_order(command: CreateOrderCommand, db: Session = Depends(get_db)):
    """Create a new order - Command Handler"""
    try:
        # Validate product exists and has sufficient stock
        product = db.query(Product).filter(Product.id == command.product_id).first()
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        if product.stock_quantity < command.quantity:
            raise HTTPException(status_code=400, detail="Insufficient stock")
        
        if command.quantity <= 0:
            raise HTTPException(status_code=400, detail="Quantity must be positive")
        
        # Calculate total
        total_amount = product.price * command.quantity
        
        # Create order
        order = Order(
            customer_id=command.customer_id,
            product_id=command.product_id,
            quantity=command.quantity,
            total_amount=total_amount,
            status="confirmed"
        )
        
        # Update stock
        product.stock_quantity -= command.quantity
        
        db.add(order)
        db.commit()
        db.refresh(order)
        
        # Publish events
        order_event = OrderCreatedEvent(
            order_id=order.id,
            customer_id=command.customer_id,
            product_id=command.product_id,
            quantity=command.quantity,
            total_amount=total_amount
        )
        
        stock_event = StockUpdatedEvent(
            product_id=command.product_id,
            old_quantity=product.stock_quantity + command.quantity,
            new_quantity=product.stock_quantity
        )
        
        await publish_event(order_event.model_dump(mode='json'))
        await publish_event(stock_event.model_dump(mode='json'))
        
        logger.info("Order created", order_id=order.id)
        return {"message": "Order created successfully", "order_id": order.id, "total_amount": total_amount}
        
    except Exception as e:
        db.rollback()
        logger.error("Failed to create order", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/commands/stats")
async def get_command_stats(db: Session = Depends(get_db)):
    """Get command side statistics"""
    try:
        product_count = db.query(Product).count()
        order_count = db.query(Order).count()
        total_stock = db.query(func.sum(Product.stock_quantity)).scalar() or 0
        
        return {
            "products": product_count,
            "orders": order_count,
            "total_stock_items": total_stock,
            "service": "command"
        }
    except Exception as e:
        logger.error("Failed to get stats", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
