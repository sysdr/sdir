#!/bin/bash

# Complete DBaaS Circuit Breaker with Web Interface
# This script demonstrates production-grade circuit breaker patterns used by major cloud providers
# Includes comprehensive debugging, Docker compatibility, and real-time web dashboard

set -euo pipefail

# Configuration Constants
readonly FAILURE_THRESHOLD=3
readonly SUCCESS_THRESHOLD=5
readonly TIMEOUT_BASE=5
readonly MAX_JITTER=3
readonly WEB_PORT="${PORT:-8080}"
readonly LOG_FILE="/app/circuit_breaker.log"
readonly STATE_FILE="/tmp/circuit_breaker_state"
readonly METRICS_FILE="/tmp/circuit_breaker_metrics"
readonly WEB_DIR="/tmp/circuit_breaker_web"
readonly PID_FILE="/tmp/web_server.pid"

# Circuit Breaker States
readonly STATE_CLOSED="CLOSED"
readonly STATE_OPEN="OPEN"
readonly STATE_HALF_OPEN="HALF_OPEN"

# Logging function with timestamps
log_message() {
    local level="$1"
    local message="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" | tee -a "$LOG_FILE"
}

# Initialize circuit breaker state files
initialize_state() {
    log_message "INIT" "Initializing circuit breaker state files"
    
    cat > "$STATE_FILE" << EOF
state=$STATE_CLOSED
failure_count=0
success_count=0
last_failure_time=0
open_timestamp=0
EOF
    
    cat > "$METRICS_FILE" << EOF
total_requests=0
successful_requests=0
failed_requests=0
circuit_trips=0
EOF
    
    log_message "INFO" "Circuit breaker initialized in CLOSED state"
}

# Read current circuit breaker state
read_state() {
    if [[ -f "$STATE_FILE" ]]; then
        source "$STATE_FILE"
    else
        log_message "WARN" "State file not found, reinitializing"
        initialize_state
        source "$STATE_FILE"
    fi
}

# Update circuit breaker state atomically
update_state() {
    local new_state="$1"
    local temp_file=$(mktemp)
    
    read_state
    cat > "$temp_file" << EOF
state=$new_state
failure_count=${2:-$failure_count}
success_count=${3:-$success_count}
last_failure_time=${4:-$last_failure_time}
open_timestamp=${5:-$open_timestamp}
EOF
    
    mv "$temp_file" "$STATE_FILE"
}

# Calculate jittered timeout for OPEN state
calculate_timeout() {
    local base_timeout="$TIMEOUT_BASE"
    local jitter=$((RANDOM % MAX_JITTER))
    echo $((base_timeout + jitter))
}

# Check if circuit should transition from OPEN to HALF_OPEN
should_attempt_reset() {
    read_state
    if [[ "$state" == "$STATE_OPEN" ]]; then
        local current_time=$(date +%s)
        local timeout=$(calculate_timeout)
        local elapsed=$((current_time - open_timestamp))
        
        if [[ $elapsed -gt $timeout ]]; then
            return 0
        fi
    fi
    return 1
}

# Simulate database connection with realistic failure patterns
simulate_database_call() {
    local failure_rate="${1:-25}"
    local latency_base="${2:-150}"
    
    # Simulate network latency
    local latency_jitter=$((RANDOM % 50))
    local total_latency=$((latency_base + latency_jitter))
    sleep $(echo "scale=3; $total_latency / 1000" | bc -l 2>/dev/null || echo "0.1")
    
    # Simulate failure based on failure rate
    local random_num=$((RANDOM % 100))
    if [[ $random_num -lt $failure_rate ]]; then
        return 1  # Failure
    else
        return 0  # Success
    fi
}

# Main circuit breaker execution logic
execute_with_circuit_breaker() {
    local operation_id="$1"
    local current_time=$(date +%s)
    local should_execute=true
    
    read_state
    
    case "$state" in
        "$STATE_CLOSED")
            # Normal operation - allow all requests
            ;;
        "$STATE_OPEN")
            if should_attempt_reset; then
                log_message "TRANSITION" "$STATE_OPEN -> $STATE_HALF_OPEN (timeout expired)"
                update_state "$STATE_HALF_OPEN" 0 0 "$last_failure_time" "$open_timestamp"
            else
                log_message "BLOCKED" "Request $operation_id blocked - circuit is OPEN"
                should_execute=false
            fi
            ;;
        "$STATE_HALF_OPEN")
            # Allow limited requests through for testing
            ;;
    esac
    
    if [[ "$should_execute" == "false" ]]; then
        # Update metrics for blocked request
        source "$METRICS_FILE"
        cat > "$METRICS_FILE" << EOF
total_requests=$((total_requests + 1))
successful_requests=$successful_requests
failed_requests=$((failed_requests + 1))
circuit_trips=$circuit_trips
EOF
        return 1
    fi
    
    # Execute the database operation
    log_message "EXECUTE" "Attempting database operation $operation_id"
    
    if simulate_database_call 25 150; then
        handle_success "$operation_id"
        return 0
    else
        handle_failure "$operation_id" "$current_time"
        return 1
    fi
}

# Handle successful operations
handle_success() {
    local operation_id="$1"
    read_state
    
    case "$state" in
        "$STATE_CLOSED")
            update_state "$STATE_CLOSED" 0 0 "$last_failure_time" "$open_timestamp"
            ;;
        "$STATE_HALF_OPEN")
            local new_success_count=$((success_count + 1))
            if [[ $new_success_count -ge $SUCCESS_THRESHOLD ]]; then
                log_message "TRANSITION" "$STATE_HALF_OPEN -> $STATE_CLOSED (recovery confirmed)"
                update_state "$STATE_CLOSED" 0 0 "$last_failure_time" "$open_timestamp"
            else
                update_state "$STATE_HALF_OPEN" "$failure_count" "$new_success_count" "$last_failure_time" "$open_timestamp"
            fi
            ;;
    esac
    
    # Update success metrics
    source "$METRICS_FILE"
    cat > "$METRICS_FILE" << EOF
total_requests=$((total_requests + 1))
successful_requests=$((successful_requests + 1))
failed_requests=$failed_requests
circuit_trips=$circuit_trips
EOF
    
    log_message "SUCCESS" "Operation $operation_id completed successfully"
}

# Handle failed operations
handle_failure() {
    local operation_id="$1"
    local current_time="$2"
    read_state
    
    local new_failure_count=$((failure_count + 1))
    
    case "$state" in
        "$STATE_CLOSED")
            if [[ $new_failure_count -ge $FAILURE_THRESHOLD ]]; then
                log_message "TRANSITION" "$STATE_CLOSED -> $STATE_OPEN (failure threshold exceeded)"
                update_state "$STATE_OPEN" "$new_failure_count" 0 "$current_time" "$current_time"
                
                # Increment circuit trip counter
                source "$METRICS_FILE"
                cat > "$METRICS_FILE" << EOF
total_requests=$((total_requests + 1))
successful_requests=$successful_requests
failed_requests=$((failed_requests + 1))
circuit_trips=$((circuit_trips + 1))
EOF
            else
                update_state "$STATE_CLOSED" "$new_failure_count" 0 "$current_time" "$open_timestamp"
                source "$METRICS_FILE"
                cat > "$METRICS_FILE" << EOF
total_requests=$((total_requests + 1))
successful_requests=$successful_requests
failed_requests=$((failed_requests + 1))
circuit_trips=$circuit_trips
EOF
            fi
            ;;
        "$STATE_HALF_OPEN")
            log_message "TRANSITION" "$STATE_HALF_OPEN -> $STATE_OPEN (still failing)"
            update_state "$STATE_OPEN" "$new_failure_count" 0 "$current_time" "$current_time"
            source "$METRICS_FILE"
            cat > "$METRICS_FILE" << EOF
total_requests=$((total_requests + 1))
successful_requests=$successful_requests
failed_requests=$((failed_requests + 1))
circuit_trips=$circuit_trips
EOF
            ;;
    esac
    
    log_message "FAILURE" "Operation $operation_id failed"
}

# Create comprehensive web interface
setup_web_interface() {
    log_message "SETUP" "Creating web interface at $WEB_DIR"
    mkdir -p "$WEB_DIR"
    
    # Create main dashboard HTML
    cat > "$WEB_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DBaaS Circuit Breaker Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            padding: 30px;
        }
        .header {
            text-align: center;
            margin-bottom: 40px;
            border-bottom: 2px solid #f0f0f0;
            padding-bottom: 20px;
        }
        .status-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .status-card {
            background: #f8f9fa;
            border-radius: 12px;
            padding: 24px;
            border-left: 5px solid;
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }
        .status-card:hover {
            transform: translateY(-3px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.15);
        }
        .state-closed { border-left-color: #28a745; }
        .state-open { border-left-color: #dc3545; }
        .state-half-open { border-left-color: #ffc107; }
        .state-indicator {
            display: inline-block;
            width: 14px;
            height: 14px;
            border-radius: 50%;
            margin-right: 10px;
            animation: pulse 2s infinite;
        }
        .card-title {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 15px;
            color: #2c3e50;
        }
        .card-value {
            font-size: 24px;
            font-weight: 700;
            margin-bottom: 8px;
        }
        .card-subtitle {
            font-size: 14px;
            color: #6c757d;
            margin-bottom: 12px;
        }
        .metrics-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 30px;
            margin-top: 30px;
        }
        .log-container {
            background: #1a1a1a;
            color: #00ff41;
            border-radius: 12px;
            padding: 20px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            max-height: 400px;
            overflow-y: auto;
            line-height: 1.6;
            border: 1px solid #333;
        }
        .controls {
            display: flex;
            gap: 15px;
            margin-bottom: 25px;
            justify-content: center;
        }
        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-weight: 600;
            transition: all 0.2s ease;
            text-decoration: none;
            display: inline-block;
        }
        .btn-primary {
            background: #007bff;
            color: white;
        }
        .btn-primary:hover {
            background: #0056b3;
            transform: translateY(-1px);
        }
        .btn-success {
            background: #28a745;
            color: white;
        }
        .btn-success:hover {
            background: #1e7e34;
        }
        @keyframes pulse {
            0% { opacity: 1; }
            50% { opacity: 0.5; }
            100% { opacity: 1; }
        }
        .chart-container {
            background: white;
            border-radius: 12px;
            padding: 20px;
            border: 1px solid #e9ecef;
        }
        .loading {
            text-align: center;
            color: #6c757d;
            font-style: italic;
        }
        .timestamp {
            font-size: 12px;
            color: #6c757d;
            margin-top: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🛡️ DBaaS Circuit Breaker Dashboard</h1>
            <p>Real-time monitoring of advanced failure handling patterns used by AWS RDS, Netflix Hystrix, and Google Cloud SQL</p>
            <div class="controls">
                <button class="btn btn-primary" onclick="refreshData()">🔄 Refresh Now</button>
                <button class="btn btn-success" onclick="toggleAutoRefresh()" id="autoRefreshBtn">⏸️ Pause Auto-Refresh</button>
            </div>
        </div>
        
        <div class="status-grid">
            <div class="status-card" id="state-card">
                <div class="card-title">
                    <span class="state-indicator" id="state-indicator"></span>
                    Circuit State
                </div>
                <div class="card-value" id="current-state">Loading...</div>
                <div class="card-subtitle" id="state-description">Determining current state</div>
                <div class="timestamp" id="state-timestamp"></div>
            </div>
            
            <div class="status-card">
                <div class="card-title">📊 Request Metrics</div>
                <div class="card-value" id="success-rate">---%</div>
                <div class="card-subtitle">Success Rate</div>
                <div>Total: <span id="total-requests">0</span> | Failed: <span id="failed-requests">0</span></div>
            </div>
            
            <div class="status-card">
                <div class="card-title">⚡ Circuit Activity</div>
                <div class="card-value" id="circuit-trips">0</div>
                <div class="card-subtitle">Circuit Trips</div>
                <div>Failures: <span id="failure-count">0</span> | Successes: <span id="success-count">0</span></div>
            </div>
            
            <div class="status-card">
                <div class="card-title">⏱️ Timing Info</div>
                <div class="card-value" id="open-duration">N/A</div>
                <div class="card-subtitle">Open Duration</div>
                <div class="timestamp" id="last-update">Never updated</div>
            </div>
        </div>
        
        <div class="metrics-grid">
            <div class="chart-container">
                <h3>📈 Performance Trends</h3>
                <div id="trend-display">
                    <div class="loading">Collecting performance data...</div>
                </div>
            </div>
            
            <div>
                <h3>📝 Activity Log</h3>
                <div class="log-container" id="activity-log">
                    <div class="loading">Waiting for circuit breaker activity...</div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let refreshInterval;
        let autoRefresh = true;
        let performanceHistory = [];
        
        function refreshData() {
            Promise.all([
                fetch('/api/status').then(r => r.json()).catch(() => ({error: 'Status unavailable'})),
                fetch('/api/metrics').then(r => r.json()).catch(() => ({error: 'Metrics unavailable'})),
                fetch('/api/logs').then(r => r.text()).catch(() => 'Logs unavailable')
            ]).then(([status, metrics, logs]) => {
                updateStatusDisplay(status, metrics);
                updateActivityLog(logs);
                updatePerformanceTrend(metrics);
            }).catch(err => {
                console.error('Failed to refresh data:', err);
                document.getElementById('current-state').textContent = 'Connection Error';
            });
        }
        
        function updateStatusDisplay(status, metrics) {
            const stateCard = document.getElementById('state-card');
            const stateIndicator = document.getElementById('state-indicator');
            const stateText = document.getElementById('current-state');
            const stateDesc = document.getElementById('state-description');
            const stateTimestamp = document.getElementById('state-timestamp');
            
            if (status.error) {
                stateText.textContent = 'System Starting...';
                stateDesc.textContent = 'Initializing circuit breaker';
                return;
            }
            
            // Update state display
            stateCard.className = 'status-card state-' + status.state.toLowerCase();
            stateText.textContent = status.state;
            stateIndicator.style.backgroundColor = getStateColor(status.state);
            stateDesc.textContent = getStateDescription(status.state);
            stateTimestamp.textContent = 'Updated: ' + new Date().toLocaleTimeString();
            
            // Update metrics
            if (!metrics.error) {
                document.getElementById('total-requests').textContent = metrics.total_requests || 0;
                document.getElementById('failed-requests').textContent = metrics.failed_requests || 0;
                document.getElementById('circuit-trips').textContent = metrics.circuit_trips || 0;
                document.getElementById('failure-count').textContent = status.failure_count || 0;
                document.getElementById('success-count').textContent = status.success_count || 0;
                
                const successRate = (metrics.total_requests > 0) 
                    ? ((metrics.successful_requests / metrics.total_requests) * 100).toFixed(1)
                    : '0.0';
                document.getElementById('success-rate').textContent = successRate + '%';
            }
            
            // Update timing
            const openDuration = (status.state === 'OPEN' && status.open_duration) 
                ? status.open_duration + 's' 
                : 'N/A';
            document.getElementById('open-duration').textContent = openDuration;
            document.getElementById('last-update').textContent = 'Last update: ' + new Date().toLocaleTimeString();
        }
        
        function updateActivityLog(logs) {
            const logContainer = document.getElementById('activity-log');
            if (logs && logs !== 'Logs unavailable') {
                logContainer.innerHTML = '<pre>' + logs + '</pre>';
                logContainer.scrollTop = logContainer.scrollHeight;
            }
        }
        
        function updatePerformanceTrend(metrics) {
            if (metrics && !metrics.error) {
                performanceHistory.push({
                    timestamp: new Date().toLocaleTimeString(),
                    successRate: metrics.total_requests > 0 ? 
                        ((metrics.successful_requests / metrics.total_requests) * 100).toFixed(1) : 0,
                    totalRequests: metrics.total_requests || 0
                });
                
                // Keep only last 10 data points
                if (performanceHistory.length > 10) {
                    performanceHistory.shift();
                }
                
                const trendDisplay = document.getElementById('trend-display');
                trendDisplay.innerHTML = performanceHistory.map((point, index) => 
                    `<div style="margin: 5px 0; padding: 8px; background: ${point.successRate > 90 ? '#d4edda' : point.successRate > 70 ? '#fff3cd' : '#f8d7da'}; border-radius: 4px;">
                        ${point.timestamp}: ${point.successRate}% success (${point.totalRequests} total)
                    </div>`
                ).join('');
            }
        }
        
        function getStateColor(state) {
            switch(state) {
                case 'CLOSED': return '#28a745';
                case 'OPEN': return '#dc3545';
                case 'HALF_OPEN': return '#ffc107';
                default: return '#6c757d';
            }
        }
        
        function getStateDescription(state) {
            switch(state) {
                case 'CLOSED': return 'All requests allowed - normal operation';
                case 'OPEN': return 'Blocking requests - service appears unhealthy';
                case 'HALF_OPEN': return 'Testing recovery - limited requests allowed';
                default: return 'Unknown state - system initializing';
            }
        }
        
        function toggleAutoRefresh() {
            const btn = document.getElementById('autoRefreshBtn');
            if (autoRefresh) {
                clearInterval(refreshInterval);
                btn.textContent = '▶️ Resume Auto-Refresh';
                autoRefresh = false;
            } else {
                refreshInterval = setInterval(refreshData, 3000);
                btn.textContent = '⏸️ Pause Auto-Refresh';
                autoRefresh = true;
            }
        }
        
        // Initialize
        document.addEventListener('DOMContentLoaded', function() {
            refreshData();
            refreshInterval = setInterval(refreshData, 3000);
        });
        
        window.addEventListener('beforeunload', function() {
            if (refreshInterval) clearInterval(refreshInterval);
        });
    </script>
</body>
</html>
EOF

    # Create API server
    cat > "$WEB_DIR/server.py" << 'EOF'
#!/usr/bin/env python3
import http.server
import socketserver
import json
import os
import sys
import time
import threading
from urllib.parse import urlparse

class CircuitBreakerHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # Suppress default logging
        
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        try:
            if parsed_path.path == '/api/status':
                self.send_json_response(self.get_status())
            elif parsed_path.path == '/api/metrics':
                self.send_json_response(self.get_metrics())
            elif parsed_path.path == '/api/logs':
                self.send_text_response(self.get_logs())
            else:
                super().do_GET()
        except Exception as e:
            self.send_error(500, f"Server error: {str(e)}")
    
    def get_status(self):
        try:
            with open('/tmp/circuit_breaker_state', 'r') as f:
                status = {}
                for line in f:
                    if '=' in line:
                        key, value = line.strip().split('=', 1)
                        status[key] = value
                
                if status.get('state') == 'OPEN' and status.get('open_timestamp'):
                    open_duration = int(time.time()) - int(status.get('open_timestamp', 0))
                    status['open_duration'] = max(0, open_duration)
                
                return status
        except FileNotFoundError:
            return {'state': 'INITIALIZING', 'error': 'Circuit breaker starting up'}
        except Exception as e:
            return {'error': f'Failed to read status: {str(e)}'}
    
    def get_metrics(self):
        try:
            with open('/tmp/circuit_breaker_metrics', 'r') as f:
                metrics = {}
                for line in f:
                    if '=' in line:
                        key, value = line.strip().split('=', 1)
                        metrics[key] = int(value) if value.isdigit() else value
                return metrics
        except FileNotFoundError:
            return {'total_requests': 0, 'successful_requests': 0, 'failed_requests': 0, 'circuit_trips': 0}
        except Exception as e:
            return {'error': f'Failed to read metrics: {str(e)}'}
    
    def get_logs(self):
        try:
            with open('/app/circuit_breaker.log', 'r') as f:
                lines = f.readlines()
                return ''.join(lines[-50:])  # Last 50 lines
        except FileNotFoundError:
            return 'Circuit breaker starting up...'
        except Exception as e:
            return f'Error reading logs: {str(e)}'
    
    def send_json_response(self, data):
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(json.dumps(data, indent=2).encode())
    
    def send_text_response(self, data):
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache')
        self.end_headers()
        self.wfile.write(str(data).encode())

class ThreadingHTTPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True

def start_server():
    PORT = int(os.environ.get('PORT', 8080))
    os.chdir('/tmp/circuit_breaker_web')
    
    try:
        with ThreadingHTTPServer(("0.0.0.0", PORT), CircuitBreakerHandler) as httpd:
            print(f"Web dashboard running on port {PORT}")
            sys.stdout.flush()
            httpd.serve_forever()
    except Exception as e:
        print(f"Server error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    start_server()
EOF
    
    log_message "INFO" "Web interface files created successfully"
}

# Start the web server
start_web_server() {
    log_message "WEB" "Starting web server on port $WEB_PORT"
    
    cd "$WEB_DIR"
    python3 server.py > /dev/null 2>&1 &
    local server_pid=$!
    
    sleep 3
    
    if kill -0 "$server_pid" 2>/dev/null; then
        echo "$server_pid" > "$PID_FILE"
        log_message "INFO" "Web server started successfully (PID: $server_pid)"
        echo "🌐 Web dashboard available at: http://localhost:$WEB_PORT"
        return 0
    else
        log_message "ERROR" "Failed to start web server"
        return 1
    fi
}

# Display terminal status
show_status() {
    read_state
    source "$METRICS_FILE" 2>/dev/null || return
    
    local current_time=$(date +%s)
    local uptime="N/A"
    if [[ "$state" == "$STATE_OPEN" ]] && [[ $open_timestamp -gt 0 ]]; then
        uptime=$((current_time - open_timestamp))
    fi
    
    clear
    echo "=========================================================="
    echo "           DBaaS Circuit Breaker Status Dashboard"
    echo "=========================================================="
    echo "🔧 Current State: $state"
    echo "📊 Failure Count: $failure_count"
    echo "✅ Success Count: $success_count"
    echo "⏱️  Open Duration: ${uptime}s"
    echo ""
    echo "📈 Performance Metrics:"
    echo "  🔄 Total Requests: $total_requests"
    echo "  ✅ Successful: $successful_requests"
    echo "  ❌ Failed: $failed_requests"
    echo "  🚨 Circuit Trips: $circuit_trips"
    
    if [[ $total_requests -gt 0 ]]; then
        local success_rate=$(echo "scale=1; $successful_requests * 100 / $total_requests" | bc -l 2>/dev/null || echo "0")
        echo "  📊 Success Rate: ${success_rate}%"
    else
        echo "  📊 Success Rate: ---%"
    fi
    
    echo ""
    echo "🌐 Web Dashboard: http://localhost:$WEB_PORT"
    echo "📝 Log File: $LOG_FILE"
    echo ""
    echo "Press Ctrl+C to stop the simulation"
    echo "=========================================================="
}

# Main simulation loop
run_simulation() {
    local request_id=1
    
    log_message "START" "Beginning circuit breaker simulation"
    
    while true; do
        show_status
        
        # Execute request through circuit breaker
        if execute_with_circuit_breaker "$request_id"; then
            echo "✅ Request $request_id: SUCCESS"
        else
            echo "❌ Request $request_id: FAILED"
        fi
        
        request_id=$((request_id + 1))
        sleep 3
    done
}

# Cleanup function
cleanup() {
    log_message "CLEANUP" "Shutting down circuit breaker system"
    
    # Stop web server
    if [[ -f "$PID_FILE" ]]; then
        local server_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
            log_message "INFO" "Stopping web server (PID: $server_pid)"
            kill "$server_pid" 2>/dev/null
        fi
        rm -f "$PID_FILE"
    fi
    
    log_message "INFO" "Cleanup completed - check $LOG_FILE for full execution log"
    
    # Final status
    echo ""
    echo "=== Final System Status ==="
    show_status 2>/dev/null || echo "System stopped"
}

# Set up signal handlers
trap cleanup EXIT INT TERM

# Main function
main() {
    # Set terminal for Docker compatibility
    export TERM=${TERM:-xterm}
    
    log_message "START" "=== Starting DBaaS Circuit Breaker System ==="
    
    echo "🚀 Starting Advanced DBaaS Circuit Breaker Simulation..."
    echo ""
    echo "This demonstrates sophisticated failure handling patterns used by:"
    echo "  • AWS RDS Multi-AZ failover systems"
    echo "  • Netflix's Hystrix circuit breakers"
    echo "  • Google Cloud SQL connection routing"
    echo ""
    
    # Environment check
    log_message "INFO" "Environment check:"
    log_message "INFO" "- Working directory: $(pwd)"
    log_message "INFO" "- Python version: $(python3 --version 2>&1)"
    log_message "INFO" "- Port: $WEB_PORT"
    
    # Check dependencies
    if ! command -v python3 &> /dev/null; then
        log_message "ERROR" "Python 3 is required but not found"
        exit 1
    fi
    
    if ! command -v bc &> /dev/null; then
        log_message "WARN" "bc calculator not found, using fallback calculations"
    fi
    
    # Initialize system
    echo "🏗️  Setting up circuit breaker system..."
    initialize_state
    setup_web_interface
    
    if ! start_web_server; then
        log_message "ERROR" "Failed to start web server - continuing with terminal mode only"
        echo "❌ Web dashboard unavailable - running in terminal mode"
    fi
    
    echo ""
    echo "✅ System ready!"
    echo "🌐 Web Dashboard: http://localhost:$WEB_PORT"
    echo "📝 Logs: $LOG_FILE"
    echo ""
    echo "⏱️  Starting simulation in 5 seconds..."
    sleep 5
    
    # Start simulation
    run_simulation
}

# Execute main function
main "$@"