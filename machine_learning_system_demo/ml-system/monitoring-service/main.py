from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
import numpy as np
from scipy import stats
import time
from datetime import datetime, timedelta

app = FastAPI(title="Monitoring Service")

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
    time.sleep(12)
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute("""
        CREATE TABLE IF NOT EXISTS drift_alerts (
            alert_id SERIAL PRIMARY KEY,
            metric_name VARCHAR(100),
            drift_score FLOAT,
            threshold FLOAT,
            status VARCHAR(50),
            created_at TIMESTAMP DEFAULT NOW()
        )
    """)
    
    conn.commit()
    cur.close()
    conn.close()

init_db()

@app.get("/drift_detection")
async def detect_drift():
    """Detect data drift in predictions"""
    conn = get_db()
    cur = conn.cursor()
    
    # Get recent predictions
    cur.execute("""
        SELECT prediction FROM predictions 
        WHERE created_at > NOW() - INTERVAL '1 hour'
    """)
    recent_preds = [row[0] for row in cur.fetchall()]
    
    # Get historical baseline
    cur.execute("""
        SELECT prediction FROM predictions 
        WHERE created_at BETWEEN NOW() - INTERVAL '2 days' AND NOW() - INTERVAL '1 day'
        LIMIT 1000
    """)
    baseline_preds = [row[0] for row in cur.fetchall()]
    
    drift_detected = False
    drift_score = 0.0
    
    if len(recent_preds) > 30 and len(baseline_preds) > 30:
        # Kolmogorov-Smirnov test for distribution drift
        ks_statistic, p_value = stats.ks_2samp(recent_preds, baseline_preds)
        drift_score = ks_statistic
        
        if p_value < 0.05:  # Significant drift
            drift_detected = True
            cur.execute("""
                INSERT INTO drift_alerts (metric_name, drift_score, threshold, status)
                VALUES ('prediction_distribution', %s, 0.05, 'warning')
            """, (drift_score,))
            conn.commit()
    
    # Performance drift (latency)
    cur.execute("""
        SELECT AVG(latency_ms) FROM predictions 
        WHERE created_at > NOW() - INTERVAL '1 hour'
    """)
    recent_latency = cur.fetchone()[0] or 0
    
    cur.execute("""
        SELECT AVG(latency_ms) FROM predictions 
        WHERE created_at BETWEEN NOW() - INTERVAL '2 days' AND NOW() - INTERVAL '1 day'
    """)
    baseline_latency = cur.fetchone()[0] or 1
    
    latency_drift = abs(recent_latency - baseline_latency) / baseline_latency if baseline_latency > 0 else 0
    
    cur.close()
    conn.close()
    
    return {
        "drift_detected": drift_detected,
        "drift_score": float(drift_score),
        "recent_samples": len(recent_preds),
        "baseline_samples": len(baseline_preds),
        "recent_avg_latency": float(recent_latency),
        "baseline_avg_latency": float(baseline_latency),
        "latency_drift_pct": float(latency_drift * 100)
    }

@app.get("/alerts")
async def get_alerts():
    """Get recent drift alerts"""
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute("""
        SELECT alert_id, metric_name, drift_score, threshold, status, created_at
        FROM drift_alerts
        ORDER BY created_at DESC
        LIMIT 10
    """)
    
    alerts = []
    for row in cur.fetchall():
        alerts.append({
            "alert_id": row[0],
            "metric": row[1],
            "drift_score": float(row[2]),
            "threshold": float(row[3]),
            "status": row[4],
            "created_at": row[5].isoformat()
        })
    
    cur.close()
    conn.close()
    return alerts

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "monitoring"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8004)
