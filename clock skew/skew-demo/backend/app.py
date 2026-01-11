import time
import threading
from flask import Flask, request, jsonify
from flask_cors import CORS
import os

app = Flask(__name__)
CORS(app) # Enable CORS for frontend access

# --- Simulation State ---
NODE_ID = os.environ.get("NODE_ID", "UNKNOWN")
# clock_offset: Difference between "real" time and this node's time in seconds.
clock_offset = 0.0
# data_store: The simulated database record.
# timestamp is physical time for LWW, or the physical part of HLC.
# logical_counter is used only for HLC.
data_store = {"value": "Initial State", "timestamp": 0.0, "logical_counter": 0}
# lock: Ensures atomicity of reads/writes to the data_store.
state_lock = threading.Lock()

def get_virtual_time():
    """Returns the simulated physical time of this node (Real Time + Drift)."""
    return time.time() + clock_offset

@app.route('/config', methods=['POST'])
def config():
    """API to dynamically adjust the clock skew of this node."""
    global clock_offset
    payload = request.json
    if 'offset' in payload:
        # Ensure offset is a float
        clock_offset = float(payload['offset'])
    return jsonify({"status": "ok", "node": NODE_ID, "offset": clock_offset})

@app.route('/state', methods=['GET'])
def get_state():
    """Returns current node state for the dashboard."""
    with state_lock:
        return jsonify({
            "node": NODE_ID,
            "offset": clock_offset,
            "data": data_store,
            "virtual_time_str": time.strftime('%H:%M:%S', time.localtime(get_virtual_time())),
            "virtual_time_raw": get_virtual_time()
        })

# --- STRATEGY 1: Last Write Wins (LWW) ---
@app.route('/write_lww', methods=['POST'])
def write_lww():
    global data_store
    payload = request.json
    new_value = payload.get('value')
    
    # 1. Determine the timestamp for this write based on local node time.
    write_timestamp = get_virtual_time()
    
    with state_lock:
        current_db_timestamp = data_store['timestamp']
        
        # 2. LWW Rule: Only accept if new timestamp > existing timestamp.
        # This is where clock skew causes data loss.
        if write_timestamp > current_db_timestamp:
            data_store['value'] = new_value
            data_store['timestamp'] = write_timestamp
            # Reset logical counter as it's not used in pure LWW
            data_store['logical_counter'] = 0 
            status = "accepted"
        else:
            status = "rejected_stale"

    return jsonify({
        "status": status,
        "strategy": "LWW",
        "node": NODE_ID,
        "write_ts": write_timestamp,
        "db_ts": current_db_timestamp,
        "value": new_value
    })

# --- STRATEGY 2: Hybrid Logical Clock (HLC) ---
@app.route('/write_hlc', methods=['POST'])
def write_hlc():
    global data_store
    payload = request.json
    new_value = payload.get('value')
    
    # In a real HLC, the client would send its HLC timestamp. 
    # For this demo, we simulate an incoming timestamp based on the node's current virtual time,
    # representing a causal event happening "now" at this node.
    incoming_phys = get_virtual_time()
    # We assume incoming logical is 0 for a fresh client write for simplicity.
    incoming_logical = 0
    
    with state_lock:
        local_phys = data_store['timestamp']
        local_logical = data_store['logical_counter']
        
        # HLC Algorithm: Maintain max of all seen times to ensure monotonicity.
        # new_phys = max(local_phys, incoming_phys, current_wall_clock)
        # For simplicity in demo, we compare local state vs 'incoming' event time.
        
        if incoming_phys > local_phys:
            # Physical time has moved forward. Reset logical counter.
            final_phys = incoming_phys
            final_logical = incoming_logical # Or 0 if treating as fresh event
        elif incoming_phys == local_phys:
            # Physical time collision. Increment logical counter.
            final_phys = local_phys
            final_logical = max(local_logical, incoming_logical) + 1
        else:
            # Clock regression or receiving message from "past".
            # Force physical time to stay at current max, increment logical.
            final_phys = local_phys
            final_logical = local_logical + 1

        data_store['value'] = new_value
        data_store['timestamp'] = final_phys
        data_store['logical_counter'] = final_logical
        status = "accepted"

    return jsonify({
        "status": status,
        "strategy": "HLC",
        "node": NODE_ID,
        "hlc_ts": f"{final_phys:.3f}.{final_logical}",
        "value": new_value
    })

if __name__ == '__main__':
    # Run Flask without reloader for Docker stability
    app.run(host='0.0.0.0', port=5000, use_reloader=False)
