#!/bin/bash
# ==============================================
# System Design Demo: The Clock Skew Conflict
# ==============================================
# This script sets up a distributed environment to demonstrate
# data loss due to clock skew when using LWW, and how HLC fixes it.
#
# Components:
# - 2x Python Flask Backends (simulating DB nodes)
# - 1x Nginx Frontend serving a modern dashboard
#
# Prerequisites: Docker and Docker Compose installed.
# ==============================================

set -e # Exit immediately if a command exits with a non-zero status

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}>>> Initializing Clock Skew Demo Environment...${NC}"

# 1. Clean up previous runs if they exist
if [ -d "skew-demo" ]; then
    echo -e "${CYAN}Cleaning up previous demo environment...${NC}"
    ./cleanup.sh > /dev/null 2>&1 || true
fi

# 2. Create Directory Structure
echo -e "${CYAN}Creating directory structure...${NC}"
mkdir -p skew-demo/{backend,frontend,nginx}

# ==============================================
# Backend Implementation (Python/Flask)
# ==============================================
# Simulates a DB node with configurable clock drift.
# Implements both LWW and HLC write paths.
echo -e "${CYAN}Generating backend code...${NC}"
cat << 'EOF' > skew-demo/backend/app.py
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
EOF

# Create Backend Dockerfile
cat << 'EOF' > skew-demo/backend/Dockerfile
FROM python:3.11-slim-bullseye
WORKDIR /app
# Install dependencies. Using Flask and Flask-CORS.
RUN pip install --no-cache-dir flask flask-cors
COPY app.py .
# Command to run the application
CMD ["python", "app.py"]
EOF

# ==============================================
# Frontend Implementation (HTML/JS/Tailwind)
# ==============================================
# Modern single-page dashboard to control simulation and visualize state.
echo -e "${CYAN}Generating frontend dashboard...${NC}"
cat << 'EOF' > skew-demo/frontend/index.html
<!DOCTYPE html>
<html lang="en" class="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Design Demo: Clock Skew Conflict</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            darkMode: 'class',
            theme: { 
                extend: { 
                    colors: { 
                        slate: { 850: '#1e293b', 950: '#0f172a' } 
                    },
                    fontFamily: { sans: ['Inter', 'sans-serif'] }
                } 
            }
        }
    </script>
    <style type="text/tailwindcss">
        @layer utilities {
            .card { @apply bg-slate-850 border border-slate-700 rounded-xl p-6 shadow-lg; }
            .btn-primary { @apply bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors duration-200; }
            .btn-success { @apply bg-emerald-600 hover:bg-emerald-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors duration-200; }
            .input-dark { @apply bg-slate-950 border border-slate-700 rounded-lg p-2 text-slate-200 focus:border-blue-500 outline-none; }
            .node-card { @apply transition-all duration-300 border-2; }
            .node-healthy { @apply border-emerald-500/50; }
            .node-skewed { @apply border-amber-500/50; }
        }
        body { font-family: 'Inter', sans-serif; }
    </style>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
</head>
<body class="bg-slate-950 text-slate-300 p-4 md:p-8 min-h-screen font-sans">
    <div class="max-w-6xl mx-auto space-y-8">
        <header>
            <h1 class="text-4xl font-bold text-white mb-2">The Clock Skew Conflict</h1>
            <p class="text-lg text-slate-400">Demonstrating silent data loss in distributed systems due to physical clock drift.</p>
        </header>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
            <div class="lg:col-span-1 space-y-8">
                <section class="card">
                    <h2 class="text-xl font-bold text-white mb-4 flex items-center">
                        1. Conflict Resolution Strategy
                    </h2>
                    <p class="text-sm text-slate-400 mb-4">Choose how the database resolves conflicting writes.</p>
                    <select id="strategySelect" class="input-dark w-full">
                        <option value="lww">Last Write Wins (Physical Time) - DANGEROUS</option>
                        <option value="hlc">Hybrid Logical Clock (HLC) - SAFE</option>
                    </select>
                    <div id="strategyDesc" class="mt-4 text-xs p-3 bg-slate-900/50 rounded border border-slate-700/50 text-slate-400">
                        LWW uses local system time. If a node's clock is slow, its writes will be discarded by nodes with faster clocks.
                    </div>
                </section>

                <section class="card border-amber-500/30">
                    <h2 class="text-xl font-bold text-white mb-4 flex items-center text-amber-400">
                        2. Inject Clock Drift (Node B)
                    </h2>
                    <p class="text-sm text-slate-400 mb-6">Force Node B's clock to run behind real-time.</p>
                    
                    <div class="space-y-6">
                        <div>
                             <div class="flex justify-between text-sm font-medium mb-2">
                                <span class="text-amber-400">Past (-10s)</span>
                                <span id="skewValueDisplay" class="text-white font-bold text-lg">0.0s</span>
                                <span class="text-slate-400">In Sync (0s)</span>
                            </div>
                            <input type="range" id="skewRange" min="-10" max="0" step="0.5" value="0" 
                                class="w-full h-3 bg-slate-700 rounded-lg appearance-none cursor-pointer accent-amber-500">
                        </div>
                        <button id="applySkewBtn" class="w-full bg-amber-600 hover:bg-amber-700 text-white font-semibold py-3 px-4 rounded-lg transition-colors duration-200 flex items-center justify-center">
                            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 mr-2" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm1-12a1 1 0 10-2 0v4a1 1 0 00.293.707l2.828 2.829a1 1 0 101.415-1.415L11 9.586V6z" clip-rule="evenodd" /></svg>
                            Apply Drift to Node B
                        </button>
                    </div>
                </section>
            </div>

            <div class="lg:col-span-2 space-y-8">
                 <section class="card border-blue-500/30">
                    <h2 class="text-xl font-bold text-white mb-4 flex items-center text-blue-400">
                        3. Simulate Distributed Writes
                    </h2>
                    <p class="text-sm text-slate-400 mb-6">This simulates a client writing to Node A, then immediately writing an update to Node B.</p>
                    
                    <div class="flex flex-col sm:flex-row gap-4">
                        <input type="text" id="payloadInput" placeholder="Enter data (e.g., 'Final Draft')" class="input-dark flex-grow font-mono">
                        <button id="simulateWriteBtn" class="btn-success flex-shrink-0 flex items-center justify-center sm:w-auto w-full py-3">
                            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 mr-2" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M3 17a1 1 0 011-1h12a1 1 0 110 2H4a1 1 0 01-1-1zM6.293 6.707a1 1 0 010-1.414l3-3a1 1 0 011.414 0l3 3a1 1 0 01-1.414 1.414L11 5.414V13a1 1 0 11-2 0V5.414L7.707 6.707a1 1 0 01-1.414 0z" clip-rule="evenodd" /></svg>
                            Execute Concurrent Writes
                        </button>
                    </div>

                    <div class="mt-6">
                        <h3 class="text-sm font-bold text-slate-300 mb-2">Simulation Log</h3>
                        <div id="simLog" class="h-48 bg-slate-950 rounded-lg border border-slate-800 p-4 overflow-y-auto font-mono text-xs space-y-2">
                            <div class="text-slate-500">> System ready. Waiting for input...</div>
                        </div>
                    </div>
                </section>

                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div id="nodeACard" class="card node-card node-healthy">
                        <div class="flex justify-between items-start mb-4">
                            <div>
                                <h3 class="text-xl font-bold text-white">Node A</h3>
                                <div class="flex items-center mt-1">
                                    <span class="h-2.5 w-2.5 bg-emerald-500 rounded-full mr-2"></span>
                                    <span class="text-xs text-emerald-400 font-medium">Reference Clock</span>
                                </div>
                            </div>
                            <div class="text-right">
                                <div class="text-xs text-slate-400">Offset</div>
                                <div class="font-mono font-bold text-white">0.00s</div>
                            </div>
                        </div>
                        
                        <div class="space-y-4">
                             <div>
                                <div class="text-xs text-slate-400 mb-1">Virtual Time</div>
                                <div id="timeA" class="font-mono text-lg text-slate-200">Loading...</div>
                            </div>
                            <div class="bg-slate-900/50 p-4 rounded-lg border border-slate-700/50">
                                <div class="text-xs text-slate-500 uppercase font-bold mb-2 tracking-wider">Database State</div>
                                <div id="dataValueA" class="text-xl font-bold text-white truncate mb-2">...</div>
                                <div class="flex justify-between text-xs font-mono text-slate-400">
                                    <span>Phys TS: <span id="tsPhysA">0.000</span></span>
                                    <span>Logical: <span id="tsLogA">0</span></span>
                                </div>
                            </div>
                        </div>
                    </div>

                     <div id="nodeBCard" class="card node-card node-healthy">
                        <div class="flex justify-between items-start mb-4">
                            <div>
                                <h3 class="text-xl font-bold text-white">Node B</h3>
                                <div id="nodeBStatus" class="flex items-center mt-1">
                                    <span class="h-2.5 w-2.5 bg-emerald-500 rounded-full mr-2"></span>
                                    <span class="text-xs text-emerald-400 font-medium">In Sync</span>
                                </div>
                            </div>
                            <div class="text-right">
                                <div class="text-xs text-slate-400">Offset</div>
                                <div id="offsetDisplayB" class="font-mono font-bold text-white transition-colors duration-300">0.00s</div>
                            </div>
                        </div>
                        
                        <div class="space-y-4">
                             <div>
                                <div class="text-xs text-slate-400 mb-1">Virtual Time</div>
                                <div id="timeB" class="font-mono text-lg text-slate-200">Loading...</div>
                            </div>
                            <div class="bg-slate-900/50 p-4 rounded-lg border border-slate-700/50">
                                <div class="text-xs text-slate-500 uppercase font-bold mb-2 tracking-wider">Database State</div>
                                <div id="dataValueB" class="text-xl font-bold text-white truncate mb-2">...</div>
                                <div class="flex justify-between text-xs font-mono text-slate-400">
                                    <span>Phys TS: <span id="tsPhysB">0.000</span></span>
                                    <span>Logical: <span id="tsLogB">0</span></span>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        // Configuration endpoint IPs (mapped via Docker Compose / Nginx)
        const NODE_A_API = '/api/node-a';
        const NODE_B_API = '/api/node-b';

        // UI Elements
        const strategySelect = document.getElementById('strategySelect');
        const strategyDesc = document.getElementById('strategyDesc');
        const skewRange = document.getElementById('skewRange');
        const skewValueDisplay = document.getElementById('skewValueDisplay');
        const applySkewBtn = document.getElementById('applySkewBtn');
        const payloadInput = document.getElementById('payloadInput');
        const simulateWriteBtn = document.getElementById('simulateWriteBtn');
        const simLog = document.getElementById('simLog');
        const nodeBCard = document.getElementById('nodeBCard');
        const nodeBStatus = document.getElementById('nodeBStatus');
        const offsetDisplayB = document.getElementById('offsetDisplayB');

        // --- Event Listeners ---

        // Update strategy description on change
        strategySelect.addEventListener('change', () => {
            const strategy = strategySelect.value;
            if (strategy === 'lww') {
                strategyDesc.textContent = "LWW uses local system time. If a node's clock is slow, its writes will be discarded by nodes with faster clocks.";
                strategyDesc.classList.add('text-slate-400'); strategyDesc.classList.remove('text-blue-400');
            } else {
                strategyDesc.textContent = "HLC combines physical time with a logical counter. It ensures timestamps always move forward, preserving causal order even during clock skew.";
                strategyDesc.classList.remove('text-slate-400'); strategyDesc.classList.add('text-blue-400');
            }
        });

        // Update skew value display on slider drag
        skewRange.addEventListener('input', () => {
            skewValueDisplay.textContent = parseFloat(skewRange.value).toFixed(1) + "s";
        });

        // Apply skew to Node B
        applySkewBtn.addEventListener('click', async () => {
            const offset = parseFloat(skewRange.value);
            addLog(`Applying ${offset}s clock drift to Node B...`, 'info');
            try {
                await fetch(`${NODE_B_API}/config`, {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ offset: offset })
                });
                addLog(`Node B clock offset updated successfully.`, 'success');
                updateNodeBVisuals(offset);
            } catch (e) {
                addLog(`Error updating Node B offset: ${e}`, 'error');
            }
        });

        // Execute Write Simulation
        simulateWriteBtn.addEventListener('click', async () => {
            const baseValue = payloadInput.value || `Doc_v${Math.floor(Math.random() * 1000)}`;
            const strategy = strategySelect.value;
            const endpoint = strategy === 'lww' ? '/write_lww' : '/write_hlc';
            
            payloadInput.value = ""; // Clear input
            simulateWriteBtn.disabled = true;
            simulateWriteBtn.classList.add('opacity-50', 'cursor-not-allowed');

            addLog(`--- Starting Simulation (${strategy.toUpperCase()}) ---`, 'info');

            try {
                // 1. Write initial version to Node A (Reference Node)
                const valA = `${baseValue} (Step 1 on Node A)`;
                addLog(`Step 1: Writing "${valA}" to Node A...`);
                const resA = await fetch(`${NODE_A_API}${endpoint}`, {
                    method: 'POST', headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ value: valA })
                });
                const jsonA = await resA.json();
                addLog(`Node A response: ${jsonA.status.toUpperCase()} [TS: ${getTsStr(jsonA, strategy)}]`, jsonA.status === 'accepted' ? 'success' : 'error');
                
                // Small delay to visually separate events
                await new Promise(r => setTimeout(r, 500));

                // 2. Write updated version to Node B (Potentially Skewed Node)
                const valB = `${baseValue} (Step 2 on Node B - NEWER)`;
                addLog(`Step 2: Writing "${valB}" to Node B (This should win)...`);
                const resB = await fetch(`${NODE_B_API}${endpoint}`, {
                    method: 'POST', headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ value: valB })
                });
                const jsonB = await resB.json();
                
                // Analyze result based on strategy
                if (strategy === 'lww' && jsonB.status === 'rejected_stale') {
                     addLog(`FAILURE: Node B rejected the write! It thought its clock (skewed past) was older than the DB's existing data.`, 'error');
                     addLog(`>> DATA LOSS OCCURRED due to LWW and Clock Skew.`, 'error');
                } else if (jsonB.status === 'accepted') {
                     addLog(`Node B response: ACCEPTED [TS: ${getTsStr(jsonB, strategy)}]`, 'success');
                     if (strategy === 'lww' && parseFloat(skewRange.value) < 0) {
                         addLog(`NOTE: Write accepted, but with an OLDER timestamp due to skew. It will lose during replication against Node A's future writes.`, 'warning');
                     } else if (strategy === 'hlc' && parseFloat(skewRange.value) < 0) {
                         addLog(`SUCCESS: HLC preserved causality! Despite the skewed physical clock, the logical counter ensured the timestamp moved forward.`, 'success');
                     }
                }

            } catch (e) {
                 addLog(`Simulation error: ${e}`, 'error');
            } finally {
                addLog(`--- Simulation Complete ---`, 'info');
                simulateWriteBtn.disabled = false;
                simulateWriteBtn.classList.remove('opacity-50', 'cursor-not-allowed');
                // Trigger immediate state refresh
                fetchState();
            }
        });

        // --- Helper Functions ---

        function addLog(msg, type = 'default') {
            const div = document.createElement('div');
            let classes = ['py-1'];
            if (type === 'error') classes.push('text-red-400', 'font-bold');
            else if (type === 'success') classes.push('text-emerald-400');
            else if (type === 'warning') classes.push('text-amber-400');
            else if (type === 'info') classes.push('text-blue-300');
            else classes.push('text-slate-400');
            
            div.classList.add(...classes);
            div.innerHTML = `> ${msg}`;
            simLog.appendChild(div);
            simLog.scrollTop = simLog.scrollHeight;
        }

        function getTsStr(json, strategy) {
            return strategy === 'lww' ? json.write_ts.toFixed(3) : json.hlc_ts;
        }

        function updateNodeBVisuals(offset) {
            offsetDisplayB.textContent = offset.toFixed(2) + "s";
            if (offset < -0.1) {
                nodeBCard.classList.remove('node-healthy');
                nodeBCard.classList.add('node-skewed');
                nodeBStatus.innerHTML = '<span class="h-2.5 w-2.5 bg-amber-500 rounded-full mr-2 animate-pulse"></span><span class="text-xs text-amber-400 font-medium">Drifting Behind</span>';
                offsetDisplayB.classList.add('text-amber-400');
            } else {
                nodeBCard.classList.add('node-healthy');
                nodeBCard.classList.remove('node-skewed');
                nodeBStatus.innerHTML = '<span class="h-2.5 w-2.5 bg-emerald-500 rounded-full mr-2"></span><span class="text-xs text-emerald-400 font-medium">In Sync</span>';
                offsetDisplayB.classList.remove('text-amber-400');
            }
        }

        async function fetchState() {
            try {
                const [resA, resB] = await Promise.all([
                    fetch(`${NODE_A_API}/state`),
                    fetch(`${NODE_B_API}/state`)
                ]);
                updateNodeState('A', await resA.json());
                updateNodeState('B', await resB.json());
            } catch (e) {
                // Silent fail on connection error during startup/shutdown
            }
        }

        function updateNodeState(nodeChar, data) {
            document.getElementById(`time${nodeChar}`).textContent = data.virtual_time_str;
            const valContainer = document.getElementById(`dataValue${nodeChar}`);
            valContainer.textContent = data.data.value;
            // Highlight value if it looks like initial state
            if(data.data.value === "Initial State") valContainer.classList.add('text-slate-500');
            else valContainer.classList.remove('text-slate-500');

            document.getElementById(`tsPhys${nodeChar}`).textContent = data.data.timestamp.toFixed(3);
            document.getElementById(`tsLog${nodeChar}`).textContent = data.data.logical_counter;
        }

        // --- Initialization ---
        async function init() {
            addLog("Dashboard initialized.", 'success');
            // Set initial offsets to 0
            try {
                await Promise.all([
                    fetch(`${NODE_A_API}/config`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({offset:0})}),
                    fetch(`${NODE_B_API}/config`, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({offset:0})})
                ]);
            } catch(e) { console.log("Initial config failed, nodes might be starting up."); }

            // Start polling for state every 500ms
            setInterval(fetchState, 500);
        }

        init();

    </script>
</body>
</html>
EOF

# ==============================================
# Nginx Configuration (Reverse Proxy)
# ==============================================
# Routes / to the frontend and /api/node-x to the respective backends.
echo -e "${CYAN}Creating Nginx configuration...${NC}"
cat << 'EOF' > skew-demo/nginx/nginx.conf
events {}
http {
    server {
        listen 80;
        
        # Serve Frontend
        location / {
            root /usr/share/nginx/html;
            index index.html;
            try_files $uri $uri/ /index.html;
        }

        # Proxy to Node A Backend
        location /api/node-a/ {
            proxy_pass http://node-a:5000/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }

        # Proxy to Node B Backend
        location /api/node-b/ {
            proxy_pass http://node-b:5000/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

# ==============================================
# Docker Compose Configuration
# ==============================================
# Orchestrates the two backend nodes and the frontend proxy.
echo -e "${CYAN}Creating docker-compose.yml...${NC}"
cat << 'EOF' > skew-demo/docker-compose.yml
version: '3.8'
services:
  # Simulated DB Node A (Reference Clock)
  node-a:
    build: ./backend
    environment:
      - NODE_ID=Node A
      - FLASK_ENV=production
    networks:
      - demo-net

  # Simulated DB Node B (Drifting Clock)
  node-b:
    build: ./backend
    environment:
      - NODE_ID=Node B
      - FLASK_ENV=production
    networks:
      - demo-net

  # Frontend Dashboard + Reverse Proxy
  frontend:
    image: nginx:alpine
    volumes:
      - ./frontend:/usr/share/nginx/html
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    ports:
      - "3000:80"
    depends_on:
      - node-a
      - node-b
    networks:
      - demo-net

networks:
  demo-net:
    driver: bridge
EOF

# ==============================================
# Build and Run
# ==============================================
echo -e "${GREEN}>>> Building and Starting Demo Environment...${NC}"
cd skew-demo
# Build images and start containers in detached mode
docker-compose up -d --build

echo -e "\n${GREEN}>>> Demo Environment Ready! <<<${NC}"
echo -e "Access the dashboard at: ${BLUE}http://localhost:3000${NC}"
echo -e "To stop the demo, run: ${CYAN}./cleanup.sh${NC}\n"