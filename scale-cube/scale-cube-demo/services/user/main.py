from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
import os
import uvicorn
from datetime import datetime
import sys
sys.path.append('/app')

from services.shared.database import SessionLocal, engine, database, connect_database, disconnect_database
from services.shared.models import User, Base

# Shard identification for Z-axis scaling
SHARD_ID = int(os.getenv("SHARD_ID", 1))
SERVICE_PORT = int(os.getenv("SERVICE_PORT", 8001))

app = FastAPI(title=f"User Service - Shard {SHARD_ID}")

# Create tables
Base.metadata.create_all(bind=engine)

class UserCreate(BaseModel):
    username: str
    email: str
    full_name: str

class UserResponse(BaseModel):
    id: int
    username: str
    email: str
    full_name: str
    shard_id: int
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
        "service": "user_service",
        "shard_id": SHARD_ID,
        "scaling_axis": "Z-axis (Data Partitioning)"
    }

@app.post("/api/users/", response_model=UserResponse)
async def create_user(user: UserCreate, db: Session = Depends(get_db)):
    """Create a new user in this shard"""
    db_user = User(
        username=user.username,
        email=user.email,
        full_name=user.full_name,
        shard_id=SHARD_ID
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user

@app.get("/api/users/{user_id}", response_model=UserResponse)
async def get_user(user_id: int, db: Session = Depends(get_db)):
    """Get user by ID from this shard"""
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found in this shard")
    return user

@app.get("/api/users/")
async def list_users(db: Session = Depends(get_db)):
    """List all users in this shard"""
    users = db.query(User).all()
    return {
        "users": users,
        "shard_id": SHARD_ID,
        "count": len(users)
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=SERVICE_PORT)
