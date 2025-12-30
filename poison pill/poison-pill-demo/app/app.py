from flask import Flask, request, jsonify
import time
import os
import sys
import signal
import hashlib
import logging
from datetime import datetime

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

# In-memory request tracking
request_tracker = {}
poison_patterns = set()
circuit_breaker = {"open": False, "failures": 0, "threshold": 3}

SERVER_ID = os.environ.get('SERVER_ID', 'unknown')

def generate_request_hash(data):
    """Generate fingerprint for request"""
    return hashlib.md5(str(data).encode()).hexdigest()[:12]

def check_poison_pattern(data):
    """Check if request matches known poison patterns"""
    if not isinstance(data, dict):
        return False
    
    # Simulate various poison pill patterns
    payload = str(data)
    
    # Pattern 1: Deeply nested structures (simulates parser crash)
    if payload.count('[') > 10 or payload.count('{') > 10:
        return True
    
    # Pattern 2: Specific malformed input
    if '{{POISON}}' in payload or '${CRASH}' in payload:
        return True
    
    # Pattern 3: Regex catastrophic backtracking simulation
    if 'AAAAAAAAAAAAAAAAAAAAAA' in payload:
        return True
    
    return False

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    if circuit_breaker["open"]:
        return jsonify({"status": "unhealthy", "reason": "circuit_breaker_open"}), 503
    return jsonify({"status": "healthy", "server": SERVER_ID}), 200

@app.route('/process', methods=['POST'])
def process_request():
    """Main processing endpoint - vulnerable to poison pills"""
    try:
        data = request.get_json(force=True)
        req_id = request.headers.get('X-Request-ID', 'no-id')
        req_hash = generate_request_hash(data)
        
        # Track request
        if req_hash not in request_tracker:
            request_tracker[req_hash] = {"count": 0, "failures": 0}
        request_tracker[req_hash]["count"] += 1
        
        # Check if request matches known poison patterns
        if check_poison_pattern(data):
            app.logger.error(f"[{SERVER_ID}] POISON DETECTED - Request: {req_id}, Hash: {req_hash}")
            request_tracker[req_hash]["failures"] += 1
            
            # Update circuit breaker
            circuit_breaker["failures"] += 1
            if circuit_breaker["failures"] >= circuit_breaker["threshold"]:
                circuit_breaker["open"] = True
                app.logger.error(f"[{SERVER_ID}] CIRCUIT BREAKER OPENED")
            
            # Simulate crash (in reality this would be a segfault)
            # For demo purposes, we'll make it take a long time and then crash
            time.sleep(0.5)  # Simulate expensive operation
            os.kill(os.getpid(), signal.SIGTERM)  # Simulate crash
            
        # Normal request processing
        time.sleep(0.1)  # Simulate work
        app.logger.info(f"[{SERVER_ID}] Processed request {req_id} successfully")
        
        return jsonify({
            "status": "success",
            "server": SERVER_ID,
            "request_id": req_id,
            "request_hash": req_hash
        }), 200
        
    except Exception as e:
        app.logger.error(f"[{SERVER_ID}] Error processing request: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/process-safe', methods=['POST'])
def process_safe():
    """Safe endpoint with pre-validation"""
    try:
        # Fast validation before parsing
        raw_data = request.get_data()
        if len(raw_data) > 5 * 1024 * 1024:  # 5MB limit
            return jsonify({"status": "error", "message": "Payload too large"}), 413
        
        data = request.get_json(force=True)
        req_id = request.headers.get('X-Request-ID', 'no-id')
        req_hash = generate_request_hash(data)
        
        # Check against known poison patterns BEFORE processing
        if req_hash in poison_patterns or check_poison_pattern(data):
            app.logger.warning(f"[{SERVER_ID}] Blocked known poison pattern: {req_hash}")
            return jsonify({"status": "blocked", "reason": "known_poison_pattern"}), 400
        
        # Validate structure
        if isinstance(data, dict):
            # Check nesting depth
            def check_depth(obj, current_depth=0, max_depth=5):
                if current_depth > max_depth:
                    return False
                if isinstance(obj, dict):
                    return all(check_depth(v, current_depth + 1, max_depth) for v in obj.values())
                elif isinstance(obj, list):
                    return all(check_depth(item, current_depth + 1, max_depth) for item in obj)
                return True
            
            if not check_depth(data):
                return jsonify({"status": "error", "message": "Nesting too deep"}), 400
        
        # Normal processing
        time.sleep(0.1)
        app.logger.info(f"[{SERVER_ID}] Safely processed request {req_id}")
        
        return jsonify({
            "status": "success",
            "server": SERVER_ID,
            "request_id": req_id
        }), 200
        
    except Exception as e:
        app.logger.error(f"[{SERVER_ID}] Error in safe endpoint: {str(e)}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/metrics', methods=['GET'])
def metrics():
    """Expose metrics for monitoring"""
    return jsonify({
        "server": SERVER_ID,
        "request_tracker": request_tracker,
        "circuit_breaker": circuit_breaker,
        "poison_patterns": list(poison_patterns)
    })

@app.route('/haproxy-stats', methods=['GET'])
def haproxy_stats():
    """Proxy HAProxy stats to avoid CORS issues"""
    try:
        import urllib.request
        import urllib.error
        url = 'http://haproxy:8404/stats;csv'
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=2) as response:
            csv_data = response.read().decode('utf-8')
            # Return with CORS headers
            from flask import Response
            resp = Response(csv_data, mimetype='text/csv')
            resp.headers['Access-Control-Allow-Origin'] = '*'
            return resp
    except Exception as e:
        app.logger.error(f"Failed to fetch HAProxy stats: {str(e)}")
        from flask import Response
        resp = Response('', status=500, mimetype='text/plain')
        resp.headers['Access-Control-Allow-Origin'] = '*'
        return resp

@app.route('/reset', methods=['POST'])
def reset():
    """Reset server state"""
    request_tracker.clear()
    poison_patterns.clear()
    circuit_breaker["open"] = False
    circuit_breaker["failures"] = 0
    app.logger.info(f"[{SERVER_ID}] Server state reset")
    return jsonify({"status": "reset_complete"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
