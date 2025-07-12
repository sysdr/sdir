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
from services.shared.models import Product, Base

SERVICE_PORT = int(os.getenv("SERVICE_PORT", 8002))

app = FastAPI(title="Product Service")

# Create tables
Base.metadata.create_all(bind=engine)

class ProductCreate(BaseModel):
    name: str
    description: str
    price: float
    stock: int

class ProductResponse(BaseModel):
    id: int
    name: str
    description: str
    price: float
    stock: int
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
    # Create sample products
    db = SessionLocal()
    if db.query(Product).count() == 0:
        sample_products = [
            Product(name="Laptop", description="High-performance laptop", price=999.99, stock=50),
            Product(name="Smartphone", description="Latest smartphone", price=699.99, stock=100),
            Product(name="Headphones", description="Wireless headphones", price=199.99, stock=75),
        ]
        for product in sample_products:
            db.add(product)
        db.commit()
    db.close()

@app.on_event("shutdown")
async def shutdown():
    await disconnect_database()

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "service": "product_service",
        "scaling_axis": "Y-axis (Functional Decomposition)"
    }

@app.post("/api/products/", response_model=ProductResponse)
async def create_product(product: ProductCreate, db: Session = Depends(get_db)):
    """Create a new product"""
    db_product = Product(**product.dict())
    db.add(db_product)
    db.commit()
    db.refresh(db_product)
    return db_product

@app.get("/api/products/{product_id}", response_model=ProductResponse)
async def get_product(product_id: int, db: Session = Depends(get_db)):
    """Get product by ID"""
    product = db.query(Product).filter(Product.id == product_id).first()
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")
    return product

@app.get("/api/products/", response_model=List[ProductResponse])
async def list_products(db: Session = Depends(get_db)):
    """List all products"""
    products = db.query(Product).all()
    return products

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=SERVICE_PORT)
