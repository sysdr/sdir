from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import psycopg2
import redis
import json
import numpy as np
import statistics
from typing import List, Dict
import time
from datetime import datetime

app = FastAPI(title="Feature Store")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Database connection
def get_db():
    return psycopg2.connect(
        "postgresql://mluser:mlpass@postgres:5432/mlsystem"
    )

# Redis connection
redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)

# Initialize database
def init_db():
    time.sleep(5)  # Wait for postgres
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute("""
        CREATE TABLE IF NOT EXISTS features (
            user_id VARCHAR(50) PRIMARY KEY,
            feature_vector JSONB,
            computed_at TIMESTAMP DEFAULT NOW()
        )
    """)
    
    cur.execute("""
        CREATE TABLE IF NOT EXISTS feature_stats (
            feature_name VARCHAR(100),
            mean FLOAT,
            std FLOAT,
            min FLOAT,
            max FLOAT,
            updated_at TIMESTAMP DEFAULT NOW()
        )
    """)
    
    conn.commit()
    cur.close()
    conn.close()

init_db()

class FeatureRequest(BaseModel):
    user_id: str

class FeatureVector(BaseModel):
    user_id: str
    features: Dict[str, float]

@app.post("/compute_features")
async def compute_features(req: FeatureRequest):
    """Compute features for a user - simulating real feature engineering"""
    user_id = req.user_id
    
    # Check cache first
    cached = redis_client.get(f"features:{user_id}")
    if cached:
        return json.loads(cached)
    
    # Simulate feature computation (in real systems, this queries multiple data sources)
    np.random.seed(hash(user_id) % (2**32))
    features = {
        "user_age": float(np.random.randint(18, 70)),
        "session_count": float(np.random.poisson(10)),
        "avg_session_duration": float(np.random.exponential(300)),
        "days_since_signup": float(np.random.randint(1, 1000)),
        "purchase_count": float(np.random.poisson(3)),
        "avg_purchase_value": float(np.random.gamma(50, 2)),
        "click_through_rate": float(np.random.beta(2, 5)),
        "engagement_score": float(np.random.uniform(0, 1))
    }
    
    # Store in database
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO features (user_id, feature_vector, computed_at)
        VALUES (%s, %s, NOW())
        ON CONFLICT (user_id) DO UPDATE SET
        feature_vector = EXCLUDED.feature_vector,
        computed_at = NOW()
    """, (user_id, json.dumps(features)))
    conn.commit()
    cur.close()
    conn.close()
    
    # Cache for fast serving
    redis_client.setex(f"features:{user_id}", 300, json.dumps(features))
    
    return {"user_id": user_id, "features": features}

@app.post("/batch_features")
async def batch_features(user_ids: List[str]):
    """Batch feature computation for training"""
    results = []
    for user_id in user_ids:
        result = await compute_features(FeatureRequest(user_id=user_id))
        results.append(result)
    return results

@app.get("/stats")
async def get_stats():
    """Get feature statistics for drift detection"""
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM features")
    count = cur.fetchone()[0]
    
    # Get all feature vectors and compute statistics
    cur.execute("SELECT feature_vector FROM features")
    rows = cur.fetchall()
    
    if count == 0:
        cur.close()
        conn.close()
        return {"total_features": 0, "statistics": {}}
    
    # Aggregate statistics across all features
    all_features = {}
    for row in rows:
        feature_vector = row[0]
        if feature_vector:
            for key, value in feature_vector.items():
                if key not in all_features:
                    all_features[key] = []
                try:
                    all_features[key].append(float(value))
                except (ValueError, TypeError):
                    continue
    
    # Compute statistics for each feature
    stats = {}
    for feature_name, values in all_features.items():
        if values:
            stats[feature_name] = {
                "mean": float(statistics.mean(values)),
                "std": float(statistics.stdev(values)) if len(values) > 1 else 0.0,
                "min": float(min(values)),
                "max": float(max(values))
            }
    
    cur.close()
    conn.close()
    
    return {"total_features": count, "statistics": stats}

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "feature-store"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
