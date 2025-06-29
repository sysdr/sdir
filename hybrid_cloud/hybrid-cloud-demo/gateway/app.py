from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import requests
import json
import time
import threading
from datetime import datetime

app = Flask(__name__)
CORS(app)

# Service endpoints
PRIVATE_CLOUD = "http://private-cloud:5001"
PUBLIC_CLOUD = "http://public-cloud:5002"

# System state
system_state = {
    "private_healthy": True,
    "public_healthy": True,
    "failover_active": False,
    "sync_enabled": True,
    "last_health_check": None
}

@app.route('/')
def dashboard():
    return render_template_string('''
<!DOCTYPE html>
<html>
<head>
    <title>Hybrid Cloud Dashboard</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { text-align: center; margin-bottom: 30px; }
        .status-grid { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 20px; margin-bottom: 30px; }
        .status-card { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .healthy { border-left: 4px solid #4caf50; }
        .unhealthy { border-left: 4px solid #f44336; }
        .degraded { border-left: 4px solid #ff9800; }
        .controls { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .logs { background: white; padding: 20px; border-radius: 8px; max-height: 300px; overflow-y: auto; }
        button { padding: 10px 20px; margin: 5px; border: none; border-radius: 4px; cursor: pointer; }
        .btn-danger { background: #f44336; color: white; }
        .btn-success { background: #4caf50; color: white; }
        .btn-primary { background: #2196f3; color: white; }
        .log-entry { margin: 5px 0; padding: 5px; background: #f9f9f9; border-radius: 3px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌉 Hybrid Cloud Architecture Demo</h1>
            <p>Monitor cross-cloud synchronization and failover behavior</p>
        </div>
        
        <div class="status-grid">
            <div class="status-card healthy" id="private-status">
                <h3>🏢 Private Cloud</h3>
                <p>Status: <span id="private-health">Checking...</span></p>
                <p>Customers: <span id="private-count">-</span></p>
            </div>
            
            <div class="status-card healthy" id="gateway-status">
                <h3>🌉 Gateway</h3>
                <p>Sync: <span id="sync-status">Enabled</span></p>
                <p>Failover: <span id="failover-status">Inactive</span></p>
            </div>
            
            <div class="status-card healthy" id="public-status">
                <h3>☁️ Public Cloud</h3>
                <p>Status: <span id="public-health">Checking...</span></p>
                <p>Cache: <span id="cache-count">-</span></p>
            </div>
        </div>
        
        <div class="controls">
            <h3>🎮 Demo Controls</h3>
            <button class="btn-primary" onclick="addCustomer()">Add Customer</button>
            <button class="btn-danger" onclick="simulateFailure('private')">Simulate Private Failure</button>
            <button class="btn-danger" onclick="simulateFailure('public')">Simulate Public Failure</button>
            <button class="btn-success" onclick="restoreService('private')">Restore Private</button>
            <button class="btn-success" onclick="restoreService('public')">Restore Public</button>
            <button class="btn-primary" onclick="forceSync()">Force Sync</button>
        </div>
        
        <div class="logs">
            <h3>📋 System Logs</h3>
            <div id="log-container">
                <div class="log-entry">System initialized</div>
            </div>
        </div>
    </div>

    <script>
        function addLog(message) {
            const container = document.getElementById('log-container');
            const entry = document.createElement('div');
            entry.className = 'log-entry';
            entry.textContent = new Date().toLocaleTimeString() + ': ' + message;
            container.insertBefore(entry, container.firstChild);
            
            // Keep only last 20 entries
            while (container.children.length > 20) {
                container.removeChild(container.lastChild);
            }
        }

        async function updateStatus() {
            try {
                const response = await fetch('/status');
                const status = await response.json();
                
                // Update private cloud status
                document.getElementById('private-health').textContent = 
                    status.private_healthy ? 'Healthy' : 'Failed';
                document.getElementById('private-status').className = 
                    'status-card ' + (status.private_healthy ? 'healthy' : 'unhealthy');
                
                // Update public cloud status
                document.getElementById('public-health').textContent = 
                    status.public_healthy ? 'Healthy' : 'Failed';
                document.getElementById('public-status').className = 
                    'status-card ' + (status.public_healthy ? 'healthy' : 'unhealthy');
                
                // Update gateway status
                document.getElementById('sync-status').textContent = 
                    status.sync_enabled ? 'Enabled' : 'Disabled';
                document.getElementById('failover-status').textContent = 
                    status.failover_active ? 'Active' : 'Inactive';
                document.getElementById('gateway-status').className = 
                    'status-card ' + (status.failover_active ? 'degraded' : 'healthy');
                    
            } catch (error) {
                addLog('Failed to update status: ' + error.message);
            }
        }

        async function addCustomer() {
            const name = prompt('Customer name:') || 'Test Customer';
            const email = prompt('Customer email:') || 'test@example.com';
            
            try {
                const response = await fetch('/api/customers', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({name, email})
                });
                
                if (response.ok) {
                    addLog(`Customer added: ${name}`);
                } else {
                    addLog('Failed to add customer');
                }
            } catch (error) {
                addLog('Error adding customer: ' + error.message);
            }
        }

        async function simulateFailure(service) {
            try {
                const response = await fetch(`/simulate/failure/${service}`, {method: 'POST'});
                if (response.ok) {
                    addLog(`Simulated ${service} failure`);
                }
            } catch (error) {
                addLog(`Error simulating failure: ${error.message}`);
            }
        }

        async function restoreService(service) {
            try {
                const response = await fetch(`/simulate/restore/${service}`, {method: 'POST'});
                if (response.ok) {
                    addLog(`Restored ${service} service`);
                }
            } catch (error) {
                addLog(`Error restoring service: ${error.message}`);
            }
        }

        async function forceSync() {
            try {
                const response = await fetch('/sync/force', {method: 'POST'});
                if (response.ok) {
                    addLog('Forced synchronization');
                }
            } catch (error) {
                addLog(`Sync error: ${error.message}`);
            }
        }

        // Update status every 3 seconds
        setInterval(updateStatus, 3000);
        updateStatus();
    </script>
</body>
</html>
    ''')

@app.route('/status')
def status():
    return jsonify(system_state)

@app.route('/api/customers', methods=['GET', 'POST'])
def customers_proxy():
    if request.method == 'POST':
        # Try private first, failover to public if needed
        if system_state["private_healthy"]:
            try:
                response = requests.post(f"{PRIVATE_CLOUD}/customers", json=request.json, timeout=5)
                if response.status_code == 200:
                    print("✅ Customer added to private cloud")
                    return response.json()
            except Exception as e:
                print(f"❌ Private cloud failed: {e}")
                system_state["private_healthy"] = False
                system_state["failover_active"] = True
        
        # Failover to public cloud
        if system_state["public_healthy"]:
            try:
                # Store in public cloud cache
                response = requests.post(f"{PUBLIC_CLOUD}/cache/customers", json=request.json, timeout=5)
                print("⚠️  Customer stored in public cache (failover mode)")
                return jsonify({"status": "stored_in_cache", "failover": True})
            except Exception as e:
                print(f"❌ Public cloud also failed: {e}")
                system_state["public_healthy"] = False
        
        return jsonify({"error": "All services unavailable"}), 503
    
    else:
        # Try to get from private cloud
        if system_state["private_healthy"]:
            try:
                response = requests.get(f"{PRIVATE_CLOUD}/customers", timeout=5)
                return response.json()
            except:
                system_state["private_healthy"] = False
        
        return jsonify([])

@app.route('/sync/private-to-public')
def sync_private_to_public():
    if not system_state["sync_enabled"]:
        return jsonify({"status": "sync_disabled"})
    
    try:
        # Get pending sync data from private cloud
        pending_response = requests.get(f"{PRIVATE_CLOUD}/sync/pending", timeout=5)
        if pending_response.status_code != 200:
            return jsonify({"error": "Cannot reach private cloud"}), 503
            
        pending_data = pending_response.json()
        synced_count = 0
        
        for item in pending_data:
            try:
                # Send to public cloud
                sync_response = requests.post(f"{PUBLIC_CLOUD}/receive_sync", json=item, timeout=5)
                if sync_response.status_code == 200:
                    # Mark as synced in private cloud
                    requests.post(f"{PRIVATE_CLOUD}/sync/mark_synced/{item['id']}", timeout=5)
                    synced_count += 1
            except Exception as e:
                print(f"❌ Failed to sync item {item['id']}: {e}")
        
        return jsonify({
            "status": "success",
            "synced_items": synced_count,
            "total_pending": len(pending_data)
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/simulate/failure/<service>', methods=['POST'])
def simulate_failure(service):
    if service == 'private':
        system_state["private_healthy"] = False
        system_state["failover_active"] = True
        print("🔥 Simulated private cloud failure")
    elif service == 'public':
        system_state["public_healthy"] = False
        print("🔥 Simulated public cloud failure")
    
    return jsonify({"status": f"{service}_failed"})

@app.route('/simulate/restore/<service>', methods=['POST'])
def restore_service(service):
    if service == 'private':
        system_state["private_healthy"] = True
        system_state["failover_active"] = False
        print("✅ Restored private cloud")
    elif service == 'public':
        system_state["public_healthy"] = True
        print("✅ Restored public cloud")
    
    return jsonify({"status": f"{service}_restored"})

@app.route('/sync/force', methods=['POST'])
def force_sync():
    result = sync_private_to_public()
    return result

# Background health monitoring
def health_monitor():
    while True:
        try:
            # Check private cloud
            try:
                response = requests.get(f"{PRIVATE_CLOUD}/health", timeout=3)
                system_state["private_healthy"] = response.status_code == 200
            except:
                if system_state["private_healthy"]:
                    print("❌ Private cloud became unhealthy")
                system_state["private_healthy"] = False
                system_state["failover_active"] = True
            
            # Check public cloud
            try:
                response = requests.get(f"{PUBLIC_CLOUD}/health", timeout=3)
                system_state["public_healthy"] = response.status_code == 200
            except:
                if system_state["public_healthy"]:
                    print("❌ Public cloud became unhealthy")
                system_state["public_healthy"] = False
            
            system_state["last_health_check"] = datetime.now().isoformat()
            
        except Exception as e:
            print(f"❌ Health monitor error: {e}")
        
        time.sleep(5)

# Start health monitoring thread
threading.Thread(target=health_monitor, daemon=True).start()

if __name__ == '__main__':
    print("🌉 Gateway starting on port 5000...")
    app.run(host='0.0.0.0', port=5000, debug=True)
