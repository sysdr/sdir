from flask import Flask, render_template, jsonify
from flask_cors import CORS
import subprocess
import json
import time
import threading
from collections import deque
import re

app = Flask(__name__)
CORS(app)

# Store metrics for each scenario
metrics = {
    'normal': deque(maxlen=100),
    'bloated': deque(maxlen=100),
    'aqm': deque(maxlen=100)
}

running = True

def check_interface_exists(interface):
    """Check if network interface exists"""
    try:
        result = subprocess.run(
            ['ip', 'link', 'show', interface],
            capture_output=True, text=True, timeout=1
        )
        return result.returncode == 0
    except:
        return False

def run_ping_test(scenario, interface, target_ip):
    """Continuously ping and record latency"""
    print(f"Starting ping test for {scenario} on {interface} to {target_ip}")
    
    # Wait for interface to be available
    max_wait = 30  # Wait up to 30 seconds
    waited = 0
    while not check_interface_exists(interface) and waited < max_wait:
        print(f"Waiting for interface {interface} to be available... ({waited}s)")
        time.sleep(1)
        waited += 1
    
    if not check_interface_exists(interface):
        print(f"ERROR: Interface {interface} not found after {max_wait} seconds!")
        return
    
    print(f"Interface {interface} is ready, starting ping tests")
    
    while running:
        try:
            # Use iputils-ping format (Linux)
            result = subprocess.run(
                ['ping', '-c', '1', '-W', '1', '-I', interface, target_ip],
                capture_output=True, text=True, timeout=3
            )
            
            latency = None
            if result.returncode == 0:
                # Try different ping output formats
                # Format: "time=12.345 ms" or "time<1.234"
                match = re.search(r'time[=<]([\d.]+)', result.stdout)
                if match:
                    latency = float(match.group(1))
                else:
                    # Alternative format: "64 bytes from ...: icmp_seq=1 ttl=64 time=12.3 ms"
                    match = re.search(r'time=([\d.]+)\s*ms', result.stdout)
                    if match:
                        latency = float(match.group(1))
                    else:
                        # Last resort: find any decimal number after "time"
                        match = re.search(r'time.*?([\d.]+)', result.stdout)
                        if match:
                            latency = float(match.group(1))
            
            metrics[scenario].append({
                'timestamp': time.time(),
                'latency': latency,
                'packet_loss': 1 if latency is None else 0
            })
            
            if latency:
                print(f"{scenario}: {latency:.2f}ms")
            else:
                print(f"{scenario}: ping failed (returncode={result.returncode}, stderr={result.stderr[:100]})")
        except subprocess.TimeoutExpired:
            metrics[scenario].append({
                'timestamp': time.time(),
                'latency': None,
                'packet_loss': 1
            })
            print(f"{scenario}: ping timeout")
        except Exception as e:
            print(f"Ping error in {scenario}: {e}")
            metrics[scenario].append({
                'timestamp': time.time(),
                'latency': None,
                'packet_loss': 1
            })
        time.sleep(0.5)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/metrics')
def get_metrics():
    return jsonify({
        'normal': list(metrics['normal']),
        'bloated': list(metrics['bloated']),
        'aqm': list(metrics['aqm'])
    })

@app.route('/api/status')
def get_status():
    """Check if network interfaces are ready"""
    interfaces = ['veth-norm', 'veth-bloat', 'veth-aqm']
    status = {}
    for interface in interfaces:
        status[interface] = check_interface_exists(interface)
    
    return jsonify({
        'interfaces': status,
        'metrics_count': {
            'normal': len(metrics['normal']),
            'bloated': len(metrics['bloated']),
            'aqm': len(metrics['aqm'])
        }
    })

@app.route('/api/start')
def start_tests():
    """Start background ping tests"""
    global running
    running = True
    
    scenarios = [
        ('normal', 'veth-norm', '10.0.0.2'),
        ('bloated', 'veth-bloat', '10.0.1.2'),
        ('aqm', 'veth-aqm', '10.0.2.2')
    ]
    
    # Wait a moment for network to be ready
    time.sleep(1)
    
    for scenario, interface, target_ip in scenarios:
        thread = threading.Thread(target=run_ping_test, args=(scenario, interface, target_ip), daemon=True)
        thread.start()
        print(f"Started ping thread for {scenario}")
    
    return jsonify({'status': 'started', 'scenarios': len(scenarios)})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)
