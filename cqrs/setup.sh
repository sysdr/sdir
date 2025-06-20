#!/bin/bash

# CQRS Pattern Demo - Complete Implementation
# Author: System Design Interview Roadmap
# Date: August 18, 2025

set -e

echo "🚀 CQRS Pattern Demo Setup Starting..."
echo "=================================="

# Create project structure
create_project_structure() {
    echo "📁 Creating project structure..."
    
    mkdir -p cqrs-demo/{command-service,query-service,web-ui,scripts}
    cd cqrs-demo
    
    echo "✅ Project structure created"
}

# Create requirements.txt with latest compatible versions
create_requirements() {
    echo "📝 Creating requirements.txt..."
    
    cat > requirements.txt << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
sqlalchemy==2.0.23
psycopg2-binary==2.9.9
redis==5.0.1
pymongo==4.6.0
pydantic==2.5.0
python-multipart==0.0.6
aiofiles==23.2.0
httpx==0.25.2
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
structlog==23.2.0
motor==3.3.2
asyncio==3.4.3
jinja2==3.1.2
websockets==12.0
EOF
    
    echo "✅ Requirements file created"
}

# Create Docker Compose configuration
create_docker_compose() {
    echo "🐳 Creating Docker Compose configuration..."
    
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Command Database (PostgreSQL)
  command-db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: command_db
      POSTGRES_USER: cqrs_user
      POSTGRES_PASSWORD: cqrs_password
    ports:
      - "5432:5432"
    volumes:
      - command_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U cqrs_user -d command_db"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Query Database (MongoDB)
  query-db:
    image: mongo:7.0
    environment:
      MONGO_INITDB_ROOT_USERNAME: cqrs_user
      MONGO_INITDB_ROOT_PASSWORD: cqrs_password
      MONGO_INITDB_DATABASE: query_db
    ports:
      - "27017:27017"
    volumes:
      - query_data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Event Bus (Redis)
  event-bus:
    image: redis:7.2-alpine
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

  # Command Service
  command-service:
    build:
      context: ./command-service
      dockerfile: Dockerfile
    ports:
      - "8001:8000"
    environment:
      - DATABASE_URL=postgresql://cqrs_user:cqrs_password@command-db:5432/command_db
      - REDIS_URL=redis://event-bus:6379
    depends_on:
      command-db:
        condition: service_healthy
      event-bus:
        condition: service_healthy
    volumes:
      - ./command-service:/app
    restart: unless-stopped

  # Query Service
  query-service:
    build:
      context: ./query-service
      dockerfile: Dockerfile
    ports:
      - "8002:8000"
    environment:
      - MONGODB_URL=mongodb://cqrs_user:cqrs_password@query-db:27017/query_db?authSource=admin
      - REDIS_URL=redis://event-bus:6379
    depends_on:
      query-db:
        condition: service_healthy
      event-bus:
        condition: service_healthy
    volumes:
      - ./query-service:/app
    restart: unless-stopped

  # Web UI
  web-ui:
    image: nginx:alpine
    ports:
      - "3000:80"
    volumes:
      - ./web-ui:/usr/share/nginx/html
    depends_on:
      - command-service
      - query-service

volumes:
  command_data:
  query_data:
  redis_data:
EOF
    
    echo "✅ Docker Compose configuration created"
}

# Create Command Service
create_command_service() {
    echo "⚡ Creating Command Service..."
    
    # Command Service Dockerfile
    cat > command-service/Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
EOF

    # Command Service Requirements
    cp requirements.txt command-service/

    # Command Service Models
    cat > command-service/models.py << 'EOF'
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
EOF

    # Command Service Main Application
    cat > command-service/app.py << 'EOF'
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
EOF
    
    echo "✅ Command Service created"
}

# Create Query Service
create_query_service() {
    echo "🔍 Creating Query Service..."
    
    # Query Service Dockerfile
    cat > query-service/Dockerfile << 'EOF'
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
EOF

    # Query Service Requirements
    cp requirements.txt query-service/

    # Query Service Models
    cat > query-service/models.py << 'EOF'
from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

class ProductView(BaseModel):
    id: int
    name: str
    description: Optional[str]
    price: float
    stock_quantity: int
    category: Optional[str]
    is_active: bool
    created_at: datetime
    last_updated: datetime

class OrderView(BaseModel):
    id: int
    customer_id: str
    product_id: int
    product_name: str
    quantity: int
    total_amount: float
    status: str
    created_at: datetime

class CustomerOrdersView(BaseModel):
    customer_id: str
    orders: List[OrderView]
    total_orders: int
    total_spent: float

class ProductStatsView(BaseModel):
    product_id: int
    product_name: str
    total_orders: int
    total_quantity_sold: int
    total_revenue: float
    current_stock: int
EOF

    # Query Service Main Application
    cat > query-service/app.py << 'EOF'
import json
import asyncio
import structlog
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
from contextlib import asynccontextmanager
import redis.asyncio as redis
import os
from datetime import datetime
from typing import List, Optional
from models import *

# Configure logging
logger = structlog.get_logger()

# MongoDB setup
MONGODB_URL = os.getenv("MONGODB_URL", "mongodb://cqrs_user:cqrs_password@localhost:27017/query_db?authSource=admin")
mongodb_client = None
db = None

# Redis setup
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
redis_client = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global mongodb_client, db, redis_client
    
    mongodb_client = AsyncIOMotorClient(MONGODB_URL)
    db = mongodb_client.query_db
    
    redis_client = redis.from_url(REDIS_URL, decode_responses=True)
    
    # Start event listener
    asyncio.create_task(listen_for_events())
    
    # Create indexes
    await create_indexes()
    
    logger.info("Query service started")
    
    yield
    
    # Shutdown
    if mongodb_client:
        mongodb_client.close()
    if redis_client:
        await redis_client.close()
    logger.info("Query service stopped")

app = FastAPI(
    title="CQRS Query Service",
    description="Handles all read operations with optimized read models",
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

async def create_indexes():
    """Create MongoDB indexes for optimized queries"""
    try:
        await db.products.create_index("id", unique=True)
        await db.products.create_index("category")
        await db.products.create_index("name")
        await db.orders.create_index("id", unique=True)
        await db.orders.create_index("customer_id")
        await db.orders.create_index("product_id")
        logger.info("Indexes created")
    except Exception as e:
        logger.error("Failed to create indexes", error=str(e))

async def listen_for_events():
    """Listen for events from Redis and update read models"""
    while True:
        try:
            pubsub = redis_client.pubsub()
            await pubsub.subscribe("events")
            
            async for message in pubsub.listen():
                if message["type"] == "message":
                    try:
                        event = json.loads(message["data"])
                        await process_event(event)
                    except Exception as e:
                        logger.error("Failed to process event", error=str(e))
                        
        except Exception as e:
            logger.error("Event listener error", error=str(e))
            await asyncio.sleep(5)  # Wait before retrying

async def process_event(event: dict):
    """Process events and update read models"""
    event_type = event.get("event_type")
    
    try:
        if event_type == "ProductCreated":
            await handle_product_created(event)
        elif event_type == "StockUpdated":
            await handle_stock_updated(event)
        elif event_type == "OrderCreated":
            await handle_order_created(event)
        
        logger.info("Event processed", event_type=event_type)
        
    except Exception as e:
        logger.error("Failed to process event", event_type=event_type, error=str(e))

async def handle_product_created(event: dict):
    """Handle ProductCreated event"""
    product_doc = {
        "id": event["product_id"],
        "name": event["name"],
        "description": event.get("description"),
        "price": event["price"],
        "stock_quantity": event["stock_quantity"],
        "category": event.get("category"),
        "is_active": True,
        "created_at": datetime.fromisoformat(event["timestamp"].replace('Z', '+00:00')),
        "last_updated": datetime.now()
    }
    
    await db.products.replace_one(
        {"id": event["product_id"]},
        product_doc,
        upsert=True
    )

async def handle_stock_updated(event: dict):
    """Handle StockUpdated event"""
    await db.products.update_one(
        {"id": event["product_id"]},
        {
            "$set": {
                "stock_quantity": event["new_quantity"],
                "last_updated": datetime.now()
            }
        }
    )

async def handle_order_created(event: dict):
    """Handle OrderCreated event"""
    # Get product info for denormalized order view
    product = await db.products.find_one({"id": event["product_id"]})
    
    order_doc = {
        "id": event["order_id"],
        "customer_id": event["customer_id"],
        "product_id": event["product_id"],
        "product_name": product["name"] if product else "Unknown",
        "quantity": event["quantity"],
        "total_amount": event["total_amount"],
        "status": "confirmed",
        "created_at": datetime.fromisoformat(event["timestamp"].replace('Z', '+00:00'))
    }
    
    await db.orders.replace_one(
        {"id": event["order_id"]},
        order_doc,
        upsert=True
    )

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "query"}

@app.get("/queries/products", response_model=List[ProductView])
async def get_products(category: Optional[str] = None, limit: int = 20, skip: int = 0):
    """Get products with optional filtering"""
    try:
        filter_query = {}
        if category:
            filter_query["category"] = category
        
        cursor = db.products.find(filter_query).skip(skip).limit(limit)
        products = await cursor.to_list(length=limit)
        
        return [ProductView(**product) for product in products]
        
    except Exception as e:
        logger.error("Failed to get products", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/queries/products/{product_id}", response_model=ProductView)
async def get_product(product_id: int):
    """Get specific product by ID"""
    try:
        product = await db.products.find_one({"id": product_id})
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        return ProductView(**product)
        
    except Exception as e:
        logger.error("Failed to get product", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/queries/orders", response_model=List[OrderView])
async def get_orders(customer_id: Optional[str] = None, limit: int = 20, skip: int = 0):
    """Get orders with optional filtering"""
    try:
        filter_query = {}
        if customer_id:
            filter_query["customer_id"] = customer_id
        
        cursor = db.orders.find(filter_query).skip(skip).limit(limit).sort("created_at", -1)
        orders = await cursor.to_list(length=limit)
        
        return [OrderView(**order) for order in orders]
        
    except Exception as e:
        logger.error("Failed to get orders", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/queries/customers/{customer_id}/orders", response_model=CustomerOrdersView)
async def get_customer_orders(customer_id: str):
    """Get all orders for a specific customer - Optimized denormalized view"""
    try:
        cursor = db.orders.find({"customer_id": customer_id}).sort("created_at", -1)
        orders = await cursor.to_list(length=None)
        
        order_views = [OrderView(**order) for order in orders]
        total_spent = sum(order.total_amount for order in order_views)
        
        return CustomerOrdersView(
            customer_id=customer_id,
            orders=order_views,
            total_orders=len(order_views),
            total_spent=total_spent
        )
        
    except Exception as e:
        logger.error("Failed to get customer orders", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/queries/products/{product_id}/stats", response_model=ProductStatsView)
async def get_product_stats(product_id: int):
    """Get aggregated statistics for a product - Complex analytical query"""
    try:
        # Get product info
        product = await db.products.find_one({"id": product_id})
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")
        
        # Aggregate order statistics
        pipeline = [
            {"$match": {"product_id": product_id}},
            {"$group": {
                "_id": None,
                "total_orders": {"$sum": 1},
                "total_quantity_sold": {"$sum": "$quantity"},
                "total_revenue": {"$sum": "$total_amount"}
            }}
        ]
        
        result = await db.orders.aggregate(pipeline).to_list(length=1)
        stats = result[0] if result else {
            "total_orders": 0,
            "total_quantity_sold": 0,
            "total_revenue": 0.0
        }
        
        return ProductStatsView(
            product_id=product_id,
            product_name=product["name"],
            total_orders=stats["total_orders"],
            total_quantity_sold=stats["total_quantity_sold"],
            total_revenue=stats["total_revenue"],
            current_stock=product["stock_quantity"]
        )
        
    except Exception as e:
        logger.error("Failed to get product stats", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/queries/stats")
async def get_query_stats():
    """Get query side statistics"""
    try:
        product_count = await db.products.count_documents({})
        order_count = await db.orders.count_documents({})
        
        # Calculate total revenue
        pipeline = [
            {"$group": {
                "_id": None,
                "total_revenue": {"$sum": "$total_amount"}
            }}
        ]
        result = await db.orders.aggregate(pipeline).to_list(length=1)
        total_revenue = result[0]["total_revenue"] if result else 0.0
        
        return {
            "products": product_count,
            "orders": order_count,
            "total_revenue": total_revenue,
            "service": "query"
        }
        
    except Exception as e:
        logger.error("Failed to get stats", error=str(e))
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF
    
    echo "✅ Query Service created"
}

# Create Web UI
create_web_ui() {
    echo "🌐 Creating Web UI..."
    
    # HTML
    cat > web-ui/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CQRS Pattern Demo</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <header>
            <h1>🚀 CQRS Pattern Demo</h1>
            <p>Command Query Responsibility Segregation in Action</p>
        </header>

        <div class="services-status">
            <div class="service-card" id="command-status">
                <h3>⚡ Command Service</h3>
                <div class="status-indicator" id="command-indicator">Checking...</div>
                <div class="stats" id="command-stats"></div>
            </div>
            <div class="service-card" id="query-status">
                <h3>🔍 Query Service</h3>
                <div class="status-indicator" id="query-indicator">Checking...</div>
                <div class="stats" id="query-stats"></div>
            </div>
        </div>

        <div class="demo-sections">
            <!-- Command Section -->
            <div class="section">
                <h2>📝 Commands (Write Operations)</h2>
                
                <div class="command-form">
                    <h3>Create Product</h3>
                    <form id="product-form">
                        <input type="text" id="product-name" placeholder="Product Name" required>
                        <textarea id="product-description" placeholder="Description"></textarea>
                        <input type="number" id="product-price" placeholder="Price" step="0.01" required>
                        <input type="number" id="product-stock" placeholder="Stock Quantity" required>
                        <input type="text" id="product-category" placeholder="Category">
                        <button type="submit">Create Product</button>
                    </form>
                </div>

                <div class="command-form">
                    <h3>Update Stock</h3>
                    <form id="stock-form">
                        <input type="number" id="stock-product-id" placeholder="Product ID" required>
                        <input type="number" id="stock-quantity" placeholder="New Quantity" required>
                        <button type="submit">Update Stock</button>
                    </form>
                </div>

                <div class="command-form">
                    <h3>Create Order</h3>
                    <form id="order-form">
                        <input type="text" id="order-customer-id" placeholder="Customer ID" required>
                        <input type="number" id="order-product-id" placeholder="Product ID" required>
                        <input type="number" id="order-quantity" placeholder="Quantity" required>
                        <button type="submit">Create Order</button>
                    </form>
                </div>
            </div>

            <!-- Query Section -->
            <div class="section">
                <h2>📊 Queries (Read Operations)</h2>
                
                <div class="query-controls">
                    <button onclick="loadProducts()">Load Products</button>
                    <button onclick="loadOrders()">Load Orders</button>
                    <button onclick="loadStats()">Load Statistics</button>
                </div>

                <div class="results">
                    <div class="result-section">
                        <h3>Products</h3>
                        <div id="products-list" class="data-grid"></div>
                    </div>
                    
                    <div class="result-section">
                        <h3>Orders</h3>
                        <div id="orders-list" class="data-grid"></div>
                    </div>
                    
                    <div class="result-section">
                        <h3>Statistics</h3>
                        <div id="stats-display" class="stats-grid"></div>
                    </div>
                </div>
            </div>
        </div>

        <div class="logs-section">
            <h2>📋 Real-time Logs</h2>
            <div id="logs" class="logs-container"></div>
            <button onclick="clearLogs()">Clear Logs</button>
        </div>
    </div>

    <script src="app.js"></script>
</body>
</html>
EOF

    # CSS
    cat > web-ui/style.css << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    color: #333;
}

.container {
    max-width: 1400px;
    margin: 0 auto;
    padding: 20px;
}

header {
    text-align: center;
    margin-bottom: 30px;
    color: white;
}

header h1 {
    font-size: 2.5em;
    margin-bottom: 10px;
    text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
}

.services-status {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 20px;
    margin-bottom: 30px;
}

.service-card {
    background: white;
    padding: 20px;
    border-radius: 12px;
    box-shadow: 0 8px 32px rgba(31, 38, 135, 0.37);
    backdrop-filter: blur(4px);
    border: 1px solid rgba(255, 255, 255, 0.18);
}

.status-indicator {
    padding: 8px 16px;
    border-radius: 20px;
    font-weight: bold;
    margin: 10px 0;
    text-align: center;
}

.status-healthy {
    background: #d4edda;
    color: #155724;
}

.status-error {
    background: #f8d7da;
    color: #721c24;
}

.demo-sections {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 30px;
    margin-bottom: 30px;
}

.section {
    background: white;
    padding: 25px;
    border-radius: 12px;
    box-shadow: 0 8px 32px rgba(31, 38, 135, 0.37);
}

.section h2 {
    margin-bottom: 20px;
    color: #4c63d2;
    border-bottom: 2px solid #f0f2f5;
    padding-bottom: 10px;
}

.command-form {
    margin-bottom: 25px;
    padding: 20px;
    background: #f8f9fa;
    border-radius: 8px;
    border-left: 4px solid #4c63d2;
}

.command-form h3 {
    margin-bottom: 15px;
    color: #333;
}

.command-form form {
    display: flex;
    flex-direction: column;
    gap: 12px;
}

.command-form input,
.command-form textarea {
    padding: 12px;
    border: 2px solid #e9ecef;
    border-radius: 6px;
    font-size: 14px;
    transition: border-color 0.3s;
}

.command-form input:focus,
.command-form textarea:focus {
    outline: none;
    border-color: #4c63d2;
}

.command-form button {
    padding: 12px 20px;
    background: #4c63d2;
    color: white;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-weight: bold;
    transition: all 0.3s;
}

.command-form button:hover {
    background: #3c52c7;
    transform: translateY(-2px);
}

.query-controls {
    margin-bottom: 20px;
    display: flex;
    gap: 10px;
    flex-wrap: wrap;
}

.query-controls button {
    padding: 10px 20px;
    background: #17a2b8;
    color: white;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-weight: bold;
    transition: all 0.3s;
}

.query-controls button:hover {
    background: #138496;
    transform: translateY(-2px);
}

.results {
    display: flex;
    flex-direction: column;
    gap: 20px;
}

.result-section h3 {
    margin-bottom: 15px;
    color: #495057;
}

.data-grid {
    display: grid;
    gap: 10px;
    max-height: 300px;
    overflow-y: auto;
}

.data-item {
    padding: 15px;
    background: #f8f9fa;
    border-radius: 6px;
    border-left: 4px solid #17a2b8;
}

.data-item h4 {
    margin-bottom: 8px;
    color: #495057;
}

.data-item p {
    margin: 4px 0;
    font-size: 14px;
    color: #6c757d;
}

.stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
    gap: 15px;
}

.stat-card {
    padding: 20px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    border-radius: 8px;
    text-align: center;
}

.stat-card .value {
    font-size: 2em;
    font-weight: bold;
    margin-bottom: 5px;
}

.stat-card .label {
    font-size: 0.9em;
    opacity: 0.9;
}

.logs-section {
    background: white;
    padding: 25px;
    border-radius: 12px;
    box-shadow: 0 8px 32px rgba(31, 38, 135, 0.37);
}

.logs-section h2 {
    margin-bottom: 20px;
    color: #4c63d2;
}

.logs-container {
    background: #1a1a1a;
    color: #00ff41;
    padding: 20px;
    border-radius: 8px;
    height: 300px;
    overflow-y: auto;
    font-family: 'Courier New', monospace;
    font-size: 13px;
    line-height: 1.4;
    white-space: pre-wrap;
}

.logs-container::-webkit-scrollbar {
    width: 8px;
}

.logs-container::-webkit-scrollbar-track {
    background: #2a2a2a;
}

.logs-container::-webkit-scrollbar-thumb {
    background: #555;
    border-radius: 4px;
}

@media (max-width: 768px) {
    .demo-sections {
        grid-template-columns: 1fr;
    }
    
    .services-status {
        grid-template-columns: 1fr;
    }
    
    .query-controls {
        justify-content: center;
    }
}

.loading {
    opacity: 0.6;
    pointer-events: none;
}

@keyframes pulse {
    0% { opacity: 1; }
    50% { opacity: 0.5; }
    100% { opacity: 1; }
}

.loading * {
    animation: pulse 1.5s infinite;
}
EOF

    # JavaScript
    cat > web-ui/app.js << 'EOF'
// CQRS Demo Application
class CQRSDemo {
    constructor() {
        this.commandBaseUrl = 'http://localhost:8001';
        this.queryBaseUrl = 'http://localhost:8002';
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.checkServices();
        this.startPeriodicUpdates();
        this.log('🚀 CQRS Demo initialized');
    }

    setupEventListeners() {
        // Product form
        document.getElementById('product-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.createProduct();
        });

        // Stock form
        document.getElementById('stock-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.updateStock();
        });

        // Order form
        document.getElementById('order-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.createOrder();
        });
    }

    async checkServices() {
        try {
            // Check Command Service
            const commandResponse = await fetch(`${this.commandBaseUrl}/health`);
            const commandHealth = await commandResponse.json();
            this.updateServiceStatus('command', commandResponse.ok, commandHealth);

            // Check Query Service
            const queryResponse = await fetch(`${this.queryBaseUrl}/health`);
            const queryHealth = await queryResponse.json();
            this.updateServiceStatus('query', queryResponse.ok, queryHealth);

            this.log(`✅ Services checked - Command: ${commandResponse.ok ? 'Healthy' : 'Error'}, Query: ${queryResponse.ok ? 'Healthy' : 'Error'}`);
        } catch (error) {
            this.log(`❌ Service check failed: ${error.message}`);
        }
    }

    updateServiceStatus(service, isHealthy, health) {
        const indicator = document.getElementById(`${service}-indicator`);
        const stats = document.getElementById(`${service}-stats`);
        
        indicator.textContent = isHealthy ? 'Healthy ✅' : 'Error ❌';
        indicator.className = `status-indicator ${isHealthy ? 'status-healthy' : 'status-error'}`;
        
        if (health && health.service) {
            stats.innerHTML = `<small>Service: ${health.service}</small>`;
        }
    }

    async createProduct() {
        this.log('📝 Creating product...');
        
        const productData = {
            name: document.getElementById('product-name').value,
            description: document.getElementById('product-description').value,
            price: parseFloat(document.getElementById('product-price').value),
            stock_quantity: parseInt(document.getElementById('product-stock').value),
            category: document.getElementById('product-category').value
        };

        try {
            const response = await fetch(`${this.commandBaseUrl}/commands/products`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(productData)
            });

            const result = await response.json();
            
            if (response.ok) {
                this.log(`✅ Product created: ${result.message} (ID: ${result.product_id})`);
                document.getElementById('product-form').reset();
                
                // Auto-refresh products after a short delay to show eventual consistency
                setTimeout(() => this.loadProducts(), 2000);
            } else {
                this.log(`❌ Failed to create product: ${result.detail}`);
            }
        } catch (error) {
            this.log(`❌ Error creating product: ${error.message}`);
        }
    }

    async updateStock() {
        this.log('📦 Updating stock...');
        
        const productId = parseInt(document.getElementById('stock-product-id').value);
        const stockData = {
            product_id: productId,
            quantity: parseInt(document.getElementById('stock-quantity').value)
        };

        try {
            const response = await fetch(`${this.commandBaseUrl}/commands/products/${productId}/stock`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(stockData)
            });

            const result = await response.json();
            
            if (response.ok) {
                this.log(`✅ Stock updated: ${result.message}`);
                document.getElementById('stock-form').reset();
                
                setTimeout(() => this.loadProducts(), 2000);
            } else {
                this.log(`❌ Failed to update stock: ${result.detail}`);
            }
        } catch (error) {
            this.log(`❌ Error updating stock: ${error.message}`);
        }
    }

    async createOrder() {
        this.log('🛒 Creating order...');
        
        const orderData = {
            customer_id: document.getElementById('order-customer-id').value,
            product_id: parseInt(document.getElementById('order-product-id').value),
            quantity: parseInt(document.getElementById('order-quantity').value)
        };

        try {
            const response = await fetch(`${this.commandBaseUrl}/commands/orders`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(orderData)
            });

            const result = await response.json();
            
            if (response.ok) {
                this.log(`✅ Order created: ${result.message} (ID: ${result.order_id}, Total: $${result.total_amount})`);
                document.getElementById('order-form').reset();
                
                setTimeout(() => {
                    this.loadOrders();
                    this.loadProducts(); // Stock will be updated
                }, 2000);
            } else {
                this.log(`❌ Failed to create order: ${result.detail}`);
            }
        } catch (error) {
            this.log(`❌ Error creating order: ${error.message}`);
        }
    }

    async loadProducts() {
        this.log('🔍 Loading products from query service...');
        
        try {
            const response = await fetch(`${this.queryBaseUrl}/queries/products`);
            const products = await response.json();
            
            if (response.ok) {
                this.displayProducts(products);
                this.log(`✅ Loaded ${products.length} products`);
            } else {
                this.log(`❌ Failed to load products: ${products.detail}`);
            }
        } catch (error) {
            this.log(`❌ Error loading products: ${error.message}`);
        }
    }

    async loadOrders() {
        this.log('🔍 Loading orders from query service...');
        
        try {
            const response = await fetch(`${this.queryBaseUrl}/queries/orders`);
            const orders = await response.json();
            
            if (response.ok) {
                this.displayOrders(orders);
                this.log(`✅ Loaded ${orders.length} orders`);
            } else {
                this.log(`❌ Failed to load orders: ${orders.detail}`);
            }
        } catch (error) {
            this.log(`❌ Error loading orders: ${error.message}`);
        }
    }

    async loadStats() {
        this.log('📊 Loading statistics...');
        
        try {
            const [commandResponse, queryResponse] = await Promise.all([
                fetch(`${this.commandBaseUrl}/commands/stats`),
                fetch(`${this.queryBaseUrl}/queries/stats`)
            ]);

            const commandStats = await commandResponse.json();
            const queryStats = await queryResponse.json();
            
            if (commandResponse.ok && queryResponse.ok) {
                this.displayStats(commandStats, queryStats);
                this.log(`✅ Statistics loaded`);
            } else {
                this.log(`❌ Failed to load statistics`);
            }
        } catch (error) {
            this.log(`❌ Error loading statistics: ${error.message}`);
        }
    }

    displayProducts(products) {
        const container = document.getElementById('products-list');
        
        if (products.length === 0) {
            container.innerHTML = '<p>No products found. Create some products using the command form!</p>';
            return;
        }
        
        container.innerHTML = products.map(product => `
            <div class="data-item">
                <h4>${product.name} (ID: ${product.id})</h4>
                <p><strong>Price:</strong> $${product.price.toFixed(2)}</p>
                <p><strong>Stock:</strong> ${product.stock_quantity}</p>
                <p><strong>Category:</strong> ${product.category || 'N/A'}</p>
                <p><strong>Description:</strong> ${product.description || 'No description'}</p>
                <p><strong>Created:</strong> ${new Date(product.created_at).toLocaleString()}</p>
            </div>
        `).join('');
    }

    displayOrders(orders) {
        const container = document.getElementById('orders-list');
        
        if (orders.length === 0) {
            container.innerHTML = '<p>No orders found. Create some orders using the command form!</p>';
            return;
        }
        
        container.innerHTML = orders.map(order => `
            <div class="data-item">
                <h4>Order #${order.id}</h4>
                <p><strong>Customer:</strong> ${order.customer_id}</p>
                <p><strong>Product:</strong> ${order.product_name} (ID: ${order.product_id})</p>
                <p><strong>Quantity:</strong> ${order.quantity}</p>
                <p><strong>Total:</strong> $${order.total_amount.toFixed(2)}</p>
                <p><strong>Status:</strong> ${order.status}</p>
                <p><strong>Created:</strong> ${new Date(order.created_at).toLocaleString()}</p>
            </div>
        `).join('');
    }

    displayStats(commandStats, queryStats) {
        const container = document.getElementById('stats-display');
        
        container.innerHTML = `
            <div class="stat-card">
                <div class="value">${commandStats.products}</div>
                <div class="label">Products (Command)</div>
            </div>
            <div class="stat-card">
                <div class="value">${queryStats.products}</div>
                <div class="label">Products (Query)</div>
            </div>
            <div class="stat-card">
                <div class="value">${commandStats.orders}</div>
                <div class="label">Orders (Command)</div>
            </div>
            <div class="stat-card">
                <div class="value">${queryStats.orders}</div>
                <div class="label">Orders (Query)</div>
            </div>
            <div class="stat-card">
                <div class="value">${commandStats.total_stock_items || 0}</div>
                <div class="label">Total Stock Items</div>
            </div>
            <div class="stat-card">
                <div class="value">$${(queryStats.total_revenue || 0).toFixed(2)}</div>
                <div class="label">Total Revenue</div>
            </div>
        `;
    }

    startPeriodicUpdates() {
        // Check services every 30 seconds
        setInterval(() => this.checkServices(), 30000);
        
        // Auto-refresh stats every 15 seconds
        setInterval(() => {
            this.loadStats();
        }, 15000);
    }

    log(message) {
        const logsContainer = document.getElementById('logs');
        const timestamp = new Date().toLocaleTimeString();
        const logEntry = `[${timestamp}] ${message}\n`;
        
        logsContainer.textContent += logEntry;
        logsContainer.scrollTop = logsContainer.scrollHeight;
    }

    clearLogs() {
        document.getElementById('logs').textContent = '';
        this.log('📋 Logs cleared');
    }
}

// Global functions for buttons
function loadProducts() {
    window.cqrsDemo.loadProducts();
}

function loadOrders() {
    window.cqrsDemo.loadOrders();
}

function loadStats() {
    window.cqrsDemo.loadStats();
}

function clearLogs() {
    window.cqrsDemo.clearLogs();
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.cqrsDemo = new CQRSDemo();
});
EOF
    
    echo "✅ Web UI created"
}

# Create test and verification scripts
create_scripts() {
    echo "🧪 Creating test scripts..."
    
    # Test script
    cat > scripts/test_cqrs.py << 'EOF'
#!/usr/bin/env python3
"""
CQRS Demo Test Suite
Tests all CQRS functionality end-to-end
"""

import asyncio
import httpx
import json
import time
from typing import Dict, Any

class CQRSTests:
    def __init__(self):
        self.command_url = "http://localhost:8001"
        self.query_url = "http://localhost:8002"
        self.test_results = []
    
    async def run_all_tests(self):
        """Run comprehensive CQRS tests"""
        print("🧪 Starting CQRS Pattern Tests")
        print("=" * 50)
        
        tests = [
            self.test_service_health,
            self.test_create_product,
            self.test_eventual_consistency,
            self.test_update_stock,
            self.test_create_order,
            self.test_complex_queries,
            self.test_performance_separation
        ]
        
        for test in tests:
            try:
                await test()
                self.test_results.append(f"✅ {test.__name__}")
            except Exception as e:
                self.test_results.append(f"❌ {test.__name__}: {str(e)}")
        
        self.print_results()
    
    async def test_service_health(self):
        """Test service health endpoints"""
        print("\n🏥 Testing Service Health...")
        
        async with httpx.AsyncClient() as client:
            command_health = await client.get(f"{self.command_url}/health")
            query_health = await client.get(f"{self.query_url}/health")
            
            assert command_health.status_code == 200
            assert query_health.status_code == 200
            
            print("✅ Both services are healthy")
    
    async def test_create_product(self):
        """Test product creation command"""
        print("\n📦 Testing Product Creation...")
        
        product_data = {
            "name": "Test Laptop",
            "description": "High-performance laptop for testing",
            "price": 999.99,
            "stock_quantity": 50,
            "category": "Electronics"
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.command_url}/commands/products",
                json=product_data
            )
            
            assert response.status_code == 200
            result = response.json()
            assert "product_id" in result
            
            self.test_product_id = result["product_id"]
            print(f"✅ Product created with ID: {self.test_product_id}")
    
    async def test_eventual_consistency(self):
        """Test eventual consistency between command and query sides"""
        print("\n⏰ Testing Eventual Consistency...")
        
        # Wait for event propagation
        await asyncio.sleep(3)
        
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{self.query_url}/queries/products/{self.test_product_id}")
            
            assert response.status_code == 200
            product = response.json()
            assert product["name"] == "Test Laptop"
            assert product["price"] == 999.99
            
            print("✅ Product appears in query side - eventual consistency working")
    
    async def test_update_stock(self):
        """Test stock update command"""
        print("\n📊 Testing Stock Update...")
        
        stock_data = {
            "product_id": self.test_product_id,
            "quantity": 25
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.put(
                f"{self.command_url}/commands/products/{self.test_product_id}/stock",
                json=stock_data
            )
            
            assert response.status_code == 200
            print("✅ Stock updated successfully")
            
            # Wait and verify in query side
            await asyncio.sleep(2)
            
            response = await client.get(f"{self.query_url}/queries/products/{self.test_product_id}")
            product = response.json()
            assert product["stock_quantity"] == 25
            
            print("✅ Stock update reflected in query side")
    
    async def test_create_order(self):
        """Test order creation with business logic"""
        print("\n🛒 Testing Order Creation...")
        
        order_data = {
            "customer_id": "test_customer_123",
            "product_id": self.test_product_id,
            "quantity": 5
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.command_url}/commands/orders",
                json=order_data
            )
            
            assert response.status_code == 200
            result = response.json()
            assert "order_id" in result
            assert "total_amount" in result
            
            self.test_order_id = result["order_id"]
            print(f"✅ Order created with ID: {self.test_order_id}")
            
            # Verify stock was decremented
            await asyncio.sleep(2)
            
            response = await client.get(f"{self.query_url}/queries/products/{self.test_product_id}")
            product = response.json()
            assert product["stock_quantity"] == 20  # 25 - 5
            
            print("✅ Stock automatically decremented after order")
    
    async def test_complex_queries(self):
        """Test complex read model queries"""
        print("\n🔍 Testing Complex Queries...")
        
        async with httpx.AsyncClient() as client:
            # Test customer orders view
            response = await client.get(f"{self.query_url}/queries/customers/test_customer_123/orders")
            assert response.status_code == 200
            
            customer_orders = response.json()
            assert customer_orders["customer_id"] == "test_customer_123"
            assert customer_orders["total_orders"] >= 1
            
            # Test product statistics
            response = await client.get(f"{self.query_url}/queries/products/{self.test_product_id}/stats")
            assert response.status_code == 200
            
            stats = response.json()
            assert stats["total_orders"] >= 1
            assert stats["total_quantity_sold"] >= 5
            
            print("✅ Complex queries working correctly")
    
    async def test_performance_separation(self):
        """Test that read and write operations are truly separated"""
        print("\n⚡ Testing Performance Separation...")
        
        # Measure command latency
        start_time = time.time()
        
        async with httpx.AsyncClient() as client:
            await client.get(f"{self.command_url}/commands/stats")
            
        command_latency = (time.time() - start_time) * 1000
        
        # Measure query latency
        start_time = time.time()
        
        async with httpx.AsyncClient() as client:
            await client.get(f"{self.query_url}/queries/products")
            
        query_latency = (time.time() - start_time) * 1000
        
        print(f"✅ Command latency: {command_latency:.2f}ms")
        print(f"✅ Query latency: {query_latency:.2f}ms")
        print("✅ Services are operating independently")
    
    def print_results(self):
        """Print test results summary"""
        print("\n" + "=" * 50)
        print("🧪 CQRS Test Results Summary")
        print("=" * 50)
        
        passed = sum(1 for result in self.test_results if result.startswith("✅"))
        total = len(self.test_results)
        
        for result in self.test_results:
            print(result)
        
        print(f"\n📊 Tests Passed: {passed}/{total}")
        
        if passed == total:
            print("🎉 All tests passed! CQRS implementation is working correctly.")
        else:
            print("⚠️ Some tests failed. Check the logs for details.")

async def main():
    """Run the test suite"""
    tester = CQRSTests()
    await tester.run_all_tests()

if __name__ == "__main__":
    asyncio.run(main())
EOF

    chmod +x scripts/test_cqrs.py
    
    # Verification script
    cat > scripts/verify_setup.sh << 'EOF'
#!/bin/bash

echo "🔍 Verifying CQRS Demo Setup..."
echo "================================"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

echo "✅ Docker is running"

# Check if services are up
echo "🐳 Checking Docker services..."

services=("command-db" "query-db" "event-bus" "command-service" "query-service" "web-ui")

for service in "${services[@]}"; do
    if docker-compose ps | grep -q "$service.*Up"; then
        echo "✅ $service is running"
    else
        echo "❌ $service is not running"
    fi
done

# Test API endpoints
echo "🌐 Testing API endpoints..."

# Command service
if curl -s -f http://localhost:8001/health > /dev/null; then
    echo "✅ Command service API is responding"
else
    echo "❌ Command service API is not responding"
fi

# Query service
if curl -s -f http://localhost:8002/health > /dev/null; then
    echo "✅ Query service API is responding"
else
    echo "❌ Query service API is not responding"
fi

# Web UI
if curl -s -f http://localhost:3000 > /dev/null; then
    echo "✅ Web UI is accessible"
else
    echo "❌ Web UI is not accessible"
fi

echo ""
echo "🎯 Access Points:"
echo "   🌐 Web UI: http://localhost:3000"
echo "   ⚡ Command API: http://localhost:8001/docs"
echo "   🔍 Query API: http://localhost:8002/docs"
echo ""
echo "🧪 Run tests with: python3 scripts/test_cqrs.py"
EOF

    chmod +x scripts/verify_setup.sh
    
    echo "✅ Test scripts created"
}

# Main setup function
main_setup() {
    create_project_structure
    create_requirements
    create_docker_compose
    create_command_service
    create_query_service
    create_web_ui
    create_scripts
    
    echo ""
    echo "🚀 Starting CQRS Demo Services..."
    echo "=================================="
    
    # Build and start services
    docker-compose build --no-cache
    docker-compose up -d
    
    echo ""
    echo "⏳ Waiting for services to initialize..."
    sleep 30
    
    # Verify setup
    ./scripts/verify_setup.sh
    
    echo ""
    echo "🎉 CQRS Pattern Demo Setup Complete!"
    echo "===================================="
    echo ""
    echo "📱 Access Points:"
    echo "   🌐 Web UI:        http://localhost:3000"
    echo "   ⚡ Command API:   http://localhost:8001/docs"
    echo "   🔍 Query API:     http://localhost:8002/docs"
    echo ""
    echo "🧪 Testing:"
    echo "   Run tests:       python3 scripts/test_cqrs.py"
    echo "   Verify setup:    ./scripts/verify_setup.sh"
    echo ""
    echo "📋 Logs:"
    echo "   View logs:       docker-compose logs -f"
    echo "   Service logs:    docker-compose logs [service-name]"
    echo ""
    echo "🛑 Management:"
    echo "   Stop services:   docker-compose down"
    echo "   Clean data:      docker-compose down -v"
    echo ""
    echo "💡 Try the demo:"
    echo "   1. Open http://localhost:3000 in your browser"
    echo "   2. Create products using the Command side"
    echo "   3. Watch them appear in the Query side"
    echo "   4. Observe the eventual consistency in action"
    echo "   5. Create orders and see stock updates"
    echo ""
    echo "Happy learning! 🚀"
}

# Check prerequisites
check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker is not installed. Please install Docker first."
        echo "   Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        echo "❌ Docker Compose is not installed. Please install Docker Compose first."
        echo "   Visit: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    echo "✅ All prerequisites met"
}

# Error handling
set -e
trap 'echo "❌ Setup failed. Check the error above."; exit 1' ERR

# Run setup
check_prerequisites
main_setup