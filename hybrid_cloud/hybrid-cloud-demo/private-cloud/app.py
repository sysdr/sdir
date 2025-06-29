from flask import Flask, request, jsonify
from flask_cors import CORS
import sqlite3
import json
import time
import threading
import requests
from datetime import datetime

app = Flask(__name__)
CORS(app)

# Initialize database
def init_db():
    conn = sqlite3.connect('private.db', check_same_thread=False)
    conn.execute('''CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        synced_at TIMESTAMP
    )''')
    
    conn.execute('''CREATE TABLE IF NOT EXISTS sync_log (
        id INTEGER PRIMARY KEY,
        action TEXT NOT NULL,
        data TEXT NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        synced BOOLEAN DEFAULT FALSE
    )''')
    conn.commit()
    return conn

db = init_db()
sync_status = {"healthy": True, "last_sync": None}

@app.route('/health')
def health():
    return jsonify({
        "status": "healthy",
        "service": "private-cloud",
        "timestamp": datetime.now().isoformat(),
        "sync_status": sync_status
    })

@app.route('/customers', methods=['GET', 'POST'])
def customers():
    if request.method == 'POST':
        data = request.json
        cursor = db.cursor()
        cursor.execute(
            "INSERT INTO customers (name, email) VALUES (?, ?)",
            (data['name'], data['email'])
        )
        customer_id = cursor.lastrowid
        
        # Log for sync
        cursor.execute(
            "INSERT INTO sync_log (action, data) VALUES (?, ?)",
            ('CREATE', json.dumps({
                'id': customer_id,
                'name': data['name'],
                'email': data['email']
            }))
        )
        db.commit()
        
        return jsonify({
            "id": customer_id,
            "name": data['name'],
            "email": data['email'],
            "source": "private"
        })
    
    else:
        cursor = db.cursor()
        cursor.execute("SELECT * FROM customers")
        customers = [
            {"id": row[0], "name": row[1], "email": row[2], "created_at": row[3]}
            for row in cursor.fetchall()
        ]
        return jsonify(customers)

@app.route('/sync/status')
def sync_status_endpoint():
    return jsonify(sync_status)

@app.route('/sync/pending')
def pending_sync():
    cursor = db.cursor()
    cursor.execute("SELECT * FROM sync_log WHERE synced = FALSE")
    pending = [
        {"id": row[0], "action": row[1], "data": json.loads(row[2]), "timestamp": row[3]}
        for row in cursor.fetchall()
    ]
    return jsonify(pending)

@app.route('/sync/mark_synced/<int:log_id>', methods=['POST'])
def mark_synced(log_id):
    cursor = db.cursor()
    cursor.execute("UPDATE sync_log SET synced = TRUE WHERE id = ?", (log_id,))
    db.commit()
    sync_status["last_sync"] = datetime.now().isoformat()
    return jsonify({"status": "success"})

# Background sync process
def background_sync():
    while True:
        try:
            if sync_status["healthy"]:
                # Attempt to sync with public cloud
                response = requests.get('http://gateway:5000/sync/private-to-public', timeout=5)
                if response.status_code == 200:
                    sync_status["last_sync"] = datetime.now().isoformat()
                    print(f"✅ Sync successful at {sync_status['last_sync']}")
                else:
                    print("⚠️  Sync failed - gateway unreachable")
            time.sleep(10)
        except Exception as e:
            print(f"❌ Sync error: {e}")
            time.sleep(5)

# Start background sync thread
threading.Thread(target=background_sync, daemon=True).start()

if __name__ == '__main__':
    print("🏢 Private Cloud starting on port 5001...")
    app.run(host='0.0.0.0', port=5001, debug=True)
