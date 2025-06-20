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
