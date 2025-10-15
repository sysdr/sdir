import time
from flask import Flask, jsonify
from datetime import datetime

app = Flask(__name__)

# Dead server - will be killed after startup
@app.route('/health')
def health():
    return jsonify({"status": "healthy", "timestamp": datetime.now().isoformat()})

@app.route('/api/process')
def process():
    return jsonify({"status": "success", "processed_by": "dead_server"})

if __name__ == '__main__':
    # Server starts then dies
    import threading
    def kill_server():
        time.sleep(10)  # Stay alive for 10 seconds then die
        import os
        os._exit(1)
    
    threading.Thread(target=kill_server, daemon=True).start()
    app.run(host='0.0.0.0', port=5000, debug=False)
