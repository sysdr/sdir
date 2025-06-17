from flask import Flask, render_template, jsonify
import asyncio
import threading
import time
from lock_mechanisms import LockingScenarios, metrics, run_all_scenarios

app = Flask(__name__, template_folder='../templates', static_folder='../static')

# Global scenario runner
scenario_runner = None
demo_thread = None

@app.route('/')
def dashboard():
    return render_template('dashboard.html')

@app.route('/api/events')
def get_events():
    return jsonify(metrics.get_recent_events())

@app.route('/api/locks')
def get_active_locks():
    return jsonify(metrics.active_locks)

@app.route('/api/start_demo')
def start_demo():
    global demo_thread, scenario_runner
    
    if demo_thread is None or not demo_thread.is_alive():
        # Reset metrics
        metrics.events.clear()
        metrics.active_locks.clear()
        
        # Start demo in background thread
        def run_demo():
            asyncio.run(run_all_scenarios())
        
        demo_thread = threading.Thread(target=run_demo)
        demo_thread.daemon = True
        demo_thread.start()
        
        return jsonify({"status": "started"})
    else:
        return jsonify({"status": "already_running"})

@app.route('/api/status')
def get_status():
    return jsonify({
        "demo_running": demo_thread is not None and demo_thread.is_alive(),
        "total_events": len(metrics.events),
        "active_locks": len(metrics.active_locks)
    })

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
