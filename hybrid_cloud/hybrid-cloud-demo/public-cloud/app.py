from flask import Flask, request, jsonify
from flask_cors import CORS
import redis
import json
import time
from datetime import datetime

app = Flask(__name__)
CORS(app)

# Initialize Redis
try:
    r = redis.Redis(host='redis', port=6379, decode_responses=True)
    r.ping()
    print("✅ Connected to Redis")
except:
    print("❌ Redis connection failed")
    r = None

@app.route('/health')
def health():
    redis_status = "connected" if r and r.ping() else "disconnected"
    return jsonify({
        "status": "healthy",
        "service": "public-cloud",
        "timestamp": datetime.now().isoformat(),
        "redis_status": redis_status
    })

@app.route('/analytics', methods=['GET', 'POST'])
def analytics():
    if not r:
        return jsonify({"error": "Redis unavailable"}), 503
        
    if request.method == 'POST':
        data = request.json
        analytics_id = f"analytics:{int(time.time())}"
        r.hset(analytics_id, mapping={
            "customer_id": data.get('customer_id', ''),
            "event": data.get('event', ''),
            "timestamp": datetime.now().isoformat(),
            "source": "public"
        })
        return jsonify({"id": analytics_id, "status": "stored"})
    
    else:
        keys = r.keys("analytics:*")
        analytics = []
        for key in keys:
            data = r.hgetall(key)
            data['id'] = key
            analytics.append(data)
        return jsonify(analytics)

@app.route('/cache/<key>', methods=['GET', 'POST', 'DELETE'])
def cache_operations(key):
    if not r:
        return jsonify({"error": "Redis unavailable"}), 503
        
    if request.method == 'POST':
        data = request.json
        r.setex(f"cache:{key}", 3600, json.dumps(data))
        return jsonify({"status": "cached", "key": key})
    
    elif request.method == 'GET':
        cached = r.get(f"cache:{key}")
        if cached:
            return jsonify(json.loads(cached))
        return jsonify({"error": "Not found"}), 404
    
    elif request.method == 'DELETE':
        r.delete(f"cache:{key}")
        return jsonify({"status": "deleted"})

@app.route('/receive_sync', methods=['POST'])
def receive_sync():
    if not r:
        return jsonify({"error": "Redis unavailable"}), 503
        
    data = request.json
    sync_key = f"synced_data:{int(time.time())}"
    r.hset(sync_key, mapping={
        "data": json.dumps(data),
        "synced_at": datetime.now().isoformat(),
        "source": "private-cloud"
    })
    
    print(f"📥 Received sync data: {data}")
    return jsonify({"status": "sync_received", "key": sync_key})

if __name__ == '__main__':
    print("☁️  Public Cloud starting on port 5002...")
    app.run(host='0.0.0.0', port=5002, debug=True)
