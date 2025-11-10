from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import psycopg2
import redis
import httpx
import json
import numpy as np
import joblib
import io
import time
from datetime import datetime
from typing import List

app = FastAPI(title="Inference Service")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Exception handler to ensure CORS headers are included in error responses
@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    response = JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail}
    )
    # CORS headers are already added by middleware, but ensure they're present
    response.headers["Access-Control-Allow-Origin"] = "http://localhost:3000"
    response.headers["Access-Control-Allow-Credentials"] = "true"
    return response

# General exception handler to catch all unhandled exceptions
@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    response = JSONResponse(
        status_code=500,
        content={"detail": f"Internal server error: {str(exc)}"}
    )
    response.headers["Access-Control-Allow-Origin"] = "http://localhost:3000"
    response.headers["Access-Control-Allow-Credentials"] = "true"
    return response

def get_db():
    return psycopg2.connect("postgresql://mluser:mlpass@postgres:5432/mlsystem")

redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)
redis_binary = redis.Redis(host='redis', port=6379, decode_responses=False)

# Prediction cache
prediction_cache = {}
model_cache = None

def load_production_model():
    """Load the production model from registry"""
    global model_cache
    
    # Try to load from Redis cache (binary data)
    try:
        cached_model = redis_binary.get("production_model")
        if cached_model:
            model_bytes = io.BytesIO(cached_model)
            model_cache = joblib.load(model_bytes)
            return model_cache
    except Exception as e:
        # If cache is corrupted, clear it and load from database
        print(f"Error loading model from cache: {e}, falling back to database")
        redis_binary.delete("production_model")
    
    conn = get_db()
    cur = conn.cursor()
    cur.execute("SELECT model_data FROM models WHERE is_production = TRUE LIMIT 1")
    row = cur.fetchone()
    
    if not row:
        cur.close()
        conn.close()
        return None
    
    try:
        model_bytes = io.BytesIO(row[0])
        model_cache = joblib.load(model_bytes)
        
        # Cache the model binary data in Redis (without decoding)
        redis_binary.setex("production_model", 300, row[0])
    except Exception as e:
        cur.close()
        conn.close()
        print(f"Error loading model from database: {e}")
        raise
    
    cur.close()
    conn.close()
    return model_cache

def init_db():
    time.sleep(10)
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute("""
        CREATE TABLE IF NOT EXISTS predictions (
            prediction_id SERIAL PRIMARY KEY,
            user_id VARCHAR(50),
            prediction FLOAT,
            model_id VARCHAR(100),
            latency_ms FLOAT,
            created_at TIMESTAMP DEFAULT NOW()
        )
    """)
    
    conn.commit()
    cur.close()
    conn.close()

init_db()

class PredictionRequest(BaseModel):
    user_id: str

class BatchPredictionRequest(BaseModel):
    user_ids: List[str]

@app.post("/predict")
async def predict(req: PredictionRequest):
    """Make a prediction for a single user"""
    start_time = time.time()
    user_id = req.user_id
    
    # Check cache
    cached = redis_client.get(f"pred:{user_id}")
    if cached:
        return json.loads(cached)
    
    # Load model
    model = load_production_model()
    if not model:
        raise HTTPException(status_code=503, detail="No production model available")
    
    # Get features
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(
                "http://feature-store:8001/compute_features",
                json={"user_id": user_id}
            )
            response.raise_for_status()
            feature_data = response.json()
        
        # Handle both response formats:
        # 1. {"user_id": "...", "features": {...}} - when not cached
        # 2. {...} - when cached (just the features dict)
        if "features" in feature_data:
            features = feature_data["features"]
        elif isinstance(feature_data, dict) and "user_age" in feature_data:
            # Response is directly the features dict (cached format)
            features = feature_data
        else:
            raise HTTPException(
                status_code=500, 
                detail=f"Invalid response from feature store: {feature_data}"
            )
    except httpx.HTTPStatusError as e:
        raise HTTPException(
            status_code=502,
            detail=f"Feature store returned error: {e.response.status_code}"
        )
    except httpx.RequestError as e:
        raise HTTPException(
            status_code=503,
            detail=f"Failed to connect to feature store: {str(e)}"
        )
    except KeyError as e:
        raise HTTPException(
            status_code=500,
            detail=f"Missing key in feature store response: {str(e)}"
        )
    feature_vec = np.array([[
        features["user_age"],
        features["session_count"],
        features["avg_session_duration"],
        features["days_since_signup"],
        features["purchase_count"],
        features["avg_purchase_value"],
        features["click_through_rate"],
        features["engagement_score"]
    ]])
    
    # Predict
    prediction = model.predict_proba(feature_vec)[0][1]
    latency_ms = (time.time() - start_time) * 1000
    
    # Store prediction
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        INSERT INTO predictions (user_id, prediction, model_id, latency_ms)
        VALUES (%s, %s, 'production', %s)
    """, (user_id, float(prediction), latency_ms))
    conn.commit()
    cur.close()
    conn.close()
    
    result = {
        "user_id": user_id,
        "prediction": float(prediction),
        "latency_ms": latency_ms
    }
    
    # Cache result
    redis_client.setex(f"pred:{user_id}", 60, json.dumps(result))
    
    return result

@app.post("/batch_predict")
async def batch_predict(req: BatchPredictionRequest):
    """Batch predictions for multiple users - demonstrates request batching"""
    start_time = time.time()
    
    model = load_production_model()
    if not model:
        raise HTTPException(status_code=503, detail="No production model available")
    
    # Fetch all features in batch
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            "http://feature-store:8001/batch_features",
            json=req.user_ids
        )
        feature_data = response.json()
    
    # Prepare batch
    X_batch = []
    user_ids = []
    for item in feature_data:
        features = item["features"]
        X_batch.append([
            features["user_age"],
            features["session_count"],
            features["avg_session_duration"],
            features["days_since_signup"],
            features["purchase_count"],
            features["avg_purchase_value"],
            features["click_through_rate"],
            features["engagement_score"]
        ])
        user_ids.append(item["user_id"])
    
    X_batch = np.array(X_batch)
    predictions = model.predict_proba(X_batch)[:, 1]
    
    latency_ms = (time.time() - start_time) * 1000
    
    results = []
    for user_id, pred in zip(user_ids, predictions):
        results.append({
            "user_id": user_id,
            "prediction": float(pred)
        })
    
    return {
        "predictions": results,
        "batch_size": len(user_ids),
        "latency_ms": latency_ms,
        "throughput": len(user_ids) / (latency_ms / 1000)
    }

@app.get("/stats")
async def get_stats():
    """Get inference statistics"""
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute("SELECT COUNT(*), AVG(latency_ms), AVG(prediction) FROM predictions")
    row = cur.fetchone()
    
    cur.execute("""
        SELECT COUNT(*) FROM predictions 
        WHERE created_at > NOW() - INTERVAL '1 hour'
    """)
    recent_count = cur.fetchone()[0]
    
    cur.close()
    conn.close()
    
    return {
        "total_predictions": row[0],
        "avg_latency_ms": float(row[1] or 0),
        "avg_prediction": float(row[2] or 0),
        "predictions_last_hour": recent_count
    }

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "inference"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8003)
