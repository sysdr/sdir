from fastapi import FastAPI, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
import redis
import httpx
import json
import numpy as np
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.model_selection import train_test_split
import joblib
import time
from datetime import datetime
import io

app = FastAPI(title="Training Service")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "http://127.0.0.1:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def get_db():
    return psycopg2.connect("postgresql://mluser:mlpass@postgres:5432/mlsystem")

def init_db():
    time.sleep(8)
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute("""
        CREATE TABLE IF NOT EXISTS models (
            model_id VARCHAR(100) PRIMARY KEY,
            model_name VARCHAR(100),
            model_version VARCHAR(50),
            model_data BYTEA,
            accuracy FLOAT,
            training_samples INT,
            trained_at TIMESTAMP DEFAULT NOW(),
            is_production BOOLEAN DEFAULT FALSE
        )
    """)
    
    cur.execute("""
        CREATE TABLE IF NOT EXISTS training_jobs (
            job_id SERIAL PRIMARY KEY,
            status VARCHAR(50),
            model_type VARCHAR(100),
            accuracy FLOAT,
            started_at TIMESTAMP DEFAULT NOW(),
            completed_at TIMESTAMP
        )
    """)
    
    conn.commit()
    cur.close()
    conn.close()

init_db()

async def train_model_task(model_type: str, job_id: int):
    """Background task to train a model"""
    try:
        # Fetch features from feature store
        async with httpx.AsyncClient(timeout=60.0) as client:
            # Generate user IDs for training
            user_ids = [f"user_{i}" for i in range(1000)]
            response = await client.post(
                "http://feature-store:8001/batch_features",
                json=user_ids
            )
            feature_data = response.json()
        
        # Prepare training data
        X = []
        y = []
        for item in feature_data:
            features = item["features"]
            feature_vec = [
                features["user_age"],
                features["session_count"],
                features["avg_session_duration"],
                features["days_since_signup"],
                features["purchase_count"],
                features["avg_purchase_value"],
                features["click_through_rate"],
                features["engagement_score"]
            ]
            X.append(feature_vec)
            # Simulate target: convert if engagement > 0.5 and purchases > 2
            y.append(1 if features["engagement_score"] > 0.5 and features["purchase_count"] > 2 else 0)
        
        X = np.array(X)
        y = np.array(y)
        
        # Train model
        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
        
        if model_type == "random_forest":
            model = RandomForestClassifier(n_estimators=100, random_state=42)
        else:
            model = GradientBoostingClassifier(n_estimators=100, random_state=42)
        
        model.fit(X_train, y_train)
        accuracy = model.score(X_test, y_test)
        
        # Serialize model
        model_bytes = io.BytesIO()
        joblib.dump(model, model_bytes)
        model_bytes.seek(0)
        
        # Save to model registry
        conn = get_db()
        cur = conn.cursor()
        
        model_id = f"{model_type}_v{int(time.time())}"
        
        # Check if there's already a production model
        cur.execute("SELECT COUNT(*) FROM models WHERE is_production = TRUE")
        has_production = cur.fetchone()[0] > 0
        
        # Auto-promote first model to production if none exists
        is_production = not has_production
        
        cur.execute("""
            INSERT INTO models (model_id, model_name, model_version, model_data, accuracy, training_samples, is_production)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
        """, (model_id, model_type, "1.0", model_bytes.read(), accuracy, len(X_train), is_production))
        
        # Clear production model cache if this is the new production model
        if is_production:
            redis_client = redis.Redis(host='redis', port=6379, decode_responses=True)
            redis_client.delete("production_model")
        
        # Update job status
        cur.execute("""
            UPDATE training_jobs 
            SET status = 'completed', accuracy = %s, completed_at = NOW()
            WHERE job_id = %s
        """, (accuracy, job_id))
        
        conn.commit()
        cur.close()
        conn.close()
        
    except Exception as e:
        conn = get_db()
        cur = conn.cursor()
        cur.execute("""
            UPDATE training_jobs 
            SET status = 'failed', completed_at = NOW()
            WHERE job_id = %s
        """, (job_id,))
        conn.commit()
        cur.close()
        conn.close()

@app.post("/train")
async def train_model(background_tasks: BackgroundTasks, model_type: str = "random_forest"):
    """Start training a new model"""
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute("""
        INSERT INTO training_jobs (status, model_type)
        VALUES ('running', %s)
        RETURNING job_id
    """, (model_type,))
    job_id = cur.fetchone()[0]
    
    conn.commit()
    cur.close()
    conn.close()
    
    background_tasks.add_task(train_model_task, model_type, job_id)
    
    return {"job_id": job_id, "status": "started", "model_type": model_type}

@app.get("/models")
async def list_models():
    """List all trained models"""
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT model_id, model_name, model_version, accuracy, training_samples, trained_at, is_production
        FROM models
        ORDER BY trained_at DESC
    """)
    
    models = []
    for row in cur.fetchall():
        models.append({
            "model_id": row[0],
            "model_name": row[1],
            "version": row[2],
            "accuracy": float(row[3]),
            "training_samples": row[4],
            "trained_at": row[5].isoformat(),
            "is_production": row[6]
        })
    
    cur.close()
    conn.close()
    return models

@app.post("/promote/{model_id}")
async def promote_model(model_id: str):
    """Promote a model to production"""
    conn = get_db()
    cur = conn.cursor()
    
    # Demote all other models
    cur.execute("UPDATE models SET is_production = FALSE")
    
    # Promote this model
    cur.execute("UPDATE models SET is_production = TRUE WHERE model_id = %s", (model_id,))
    
    conn.commit()
    cur.close()
    conn.close()
    
    return {"model_id": model_id, "status": "promoted"}

@app.get("/jobs")
async def list_jobs():
    """List training jobs"""
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        SELECT job_id, status, model_type, accuracy, started_at, completed_at
        FROM training_jobs
        ORDER BY started_at DESC
        LIMIT 20
    """)
    
    jobs = []
    for row in cur.fetchall():
        jobs.append({
            "job_id": row[0],
            "status": row[1],
            "model_type": row[2],
            "accuracy": float(row[3]) if row[3] else None,
            "started_at": row[4].isoformat(),
            "completed_at": row[5].isoformat() if row[5] else None
        })
    
    cur.close()
    conn.close()
    return jobs

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "training"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
