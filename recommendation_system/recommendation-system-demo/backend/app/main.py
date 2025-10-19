from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from typing import List, Optional
import redis
import json
from . import models, database, recommendation_service
from .database import get_db

app = FastAPI(title="Recommendation System API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Redis connection
redis_client = redis.Redis(host='redis', port=6379, db=0, decode_responses=True)

@app.on_event("startup")
async def startup_event():
    models.Base.metadata.create_all(bind=database.engine)

@app.get("/")
async def root():
    return {"message": "Recommendation System API"}

@app.get("/users")
async def get_users(db: Session = Depends(get_db)):
    users = db.query(models.User).all()
    return users

@app.get("/items")
async def get_items(db: Session = Depends(get_db)):
    items = db.query(models.Item).all()
    return items

@app.post("/interactions")
async def create_interaction(
    user_id: int,
    item_id: int,
    interaction_type: str = "view",
    rating: Optional[float] = None,
    db: Session = Depends(get_db)
):
    interaction = models.Interaction(
        user_id=user_id,
        item_id=item_id,
        interaction_type=interaction_type,
        rating=rating
    )
    db.add(interaction)
    db.commit()
    db.refresh(interaction)
    
    # Invalidate cache for user recommendations
    redis_client.delete(f"recommendations:user:{user_id}")
    
    return interaction

@app.get("/recommendations/{user_id}")
async def get_recommendations(
    user_id: int,
    algorithm: str = "hybrid",
    db: Session = Depends(get_db)
):
    # Check cache first
    cache_key = f"recommendations:user:{user_id}:{algorithm}"
    cached_recs = redis_client.get(cache_key)
    
    if cached_recs:
        return json.loads(cached_recs)
    
    # Generate recommendations
    rec_service = recommendation_service.RecommendationService(db, redis_client)
    recommendations = rec_service.get_recommendations(user_id, algorithm)
    
    # Cache for 5 minutes
    redis_client.setex(cache_key, 300, json.dumps(recommendations))
    
    return recommendations

@app.get("/analytics/performance")
async def get_performance_metrics():
    # Simulate performance metrics
    return {
        "avg_response_time_ms": 45,
        "cache_hit_rate": 0.85,
        "recommendations_served": 12450,
        "active_users": 1250,
        "algorithms": {
            "collaborative": {"accuracy": 0.78, "coverage": 0.92},
            "content_based": {"accuracy": 0.71, "coverage": 0.98},
            "hybrid": {"accuracy": 0.82, "coverage": 0.95}
        }
    }

@app.get("/analytics/ab-testing")
async def get_ab_testing_results():
    return {
        "experiment_name": "Algorithm Comparison",
        "variants": {
            "collaborative": {"ctr": 0.12, "engagement": 0.68},
            "content_based": {"ctr": 0.09, "engagement": 0.61},
            "hybrid": {"ctr": 0.15, "engagement": 0.74}
        },
        "winner": "hybrid",
        "confidence": 0.95
    }
