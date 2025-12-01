#!/bin/bash

set -e

echo "🚀 Distributed Lock Failure Demo"
echo "=================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check dependencies
echo -e "${BLUE}Checking dependencies...${NC}"
command -v docker >/dev/null 2>&1 || { echo -e "${RED}Error: docker is required but not installed.${NC}" >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || command -v docker compose >/dev/null 2>&1 || { echo -e "${RED}Error: docker-compose is required but not installed.${NC}" >&2; exit 1; }

# Create project structure
echo -e "${BLUE}Creating project structure...${NC}"
mkdir -p distributed-lock-demo/{worker,dashboard,logs}
cd distributed-lock-demo

# Create Go worker with distributed lock implementation
cat > worker/main.go << 'EOF'
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/go-redis/redis/v8"
	"github.com/gorilla/websocket"
)

var (
	redisClient *redis.Client
	ctx         = context.Background()
	workerID    string
	counter     int
	counterMu   sync.Mutex
	useFencing  bool
	clients     = make(map[*websocket.Conn]bool)
	clientsMu   sync.Mutex
	upgrader    = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
)

type Status struct {
	WorkerID       string    `json:"worker_id"`
	Counter        int       `json:"counter"`
	HasLock        bool      `json:"has_lock"`
	CurrentToken   int64     `json:"current_token"`
	IsGCPaused     bool      `json:"is_gc_paused"`
	LastOperation  string    `json:"last_operation"`
	Timestamp      time.Time `json:"timestamp"`
	FencingEnabled bool      `json:"fencing_enabled"`
}

func main() {
	workerID = os.Getenv("WORKER_ID")
	if workerID == "" {
		workerID = "worker-unknown"
	}

	useFencing = os.Getenv("USE_FENCING") == "true"

	redisClient = redis.NewClient(&redis.Options{
		Addr: "redis:6379",
	})

	// Wait for Redis to be ready
	for i := 0; i < 30; i++ {
		if err := redisClient.Ping(ctx).Err(); err == nil {
			break
		}
		log.Printf("Waiting for Redis... (%d/30)", i+1)
		time.Sleep(time.Second)
	}

	log.Printf("Worker %s started (Fencing: %v)", workerID, useFencing)

	// Start WebSocket server for dashboard
	go startWebSocketServer()

	// Start worker loop
	go workerLoop()

	// Wait for interrupt signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("Shutting down...")
}

func startWebSocketServer() {
	http.HandleFunc("/ws", handleWebSocket)
	port := "8080"
	if workerID == "worker-2" {
		port = "8081"
	}
	log.Printf("WebSocket server starting on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatal("WebSocket server error:", err)
	}
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println("WebSocket upgrade error:", err)
		return
	}
	defer conn.Close()

	clientsMu.Lock()
	clients[conn] = true
	clientsMu.Unlock()

	defer func() {
		clientsMu.Lock()
		delete(clients, conn)
		clientsMu.Unlock()
	}()

	// Keep connection alive
	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			break
		}
	}
}

func broadcastStatus(status Status) {
	clientsMu.Lock()
	defer clientsMu.Unlock()

	data, _ := json.Marshal(status)
	for client := range clients {
		if err := client.WriteMessage(websocket.TextMessage, data); err != nil {
			client.Close()
			delete(clients, client)
		}
	}
}

func workerLoop() {
	for {
		var token int64
		var gotLock bool

		// Try to acquire lock
		if useFencing {
			token, gotLock = acquireLockWithFencing()
		} else {
			gotLock = acquireLockUnsafe()
			token = 0
		}

		if gotLock {
			log.Printf("[%s] Acquired lock (token: %d)", workerID, token)
			broadcastStatus(Status{
				WorkerID:       workerID,
				Counter:        counter,
				HasLock:        true,
				CurrentToken:   token,
				LastOperation:  "Acquired lock",
				Timestamp:      time.Now(),
				FencingEnabled: useFencing,
			})

			// Simulate work for 2 seconds
			time.Sleep(2 * time.Second)

			// Worker 1 gets "GC paused" for 8 seconds on its first lock acquisition
			if workerID == "worker-1" && counter == 0 {
				log.Printf("[%s] ⚠️  SIMULATING GC PAUSE (8 seconds)...", workerID)
				broadcastStatus(Status{
					WorkerID:       workerID,
					Counter:        counter,
					HasLock:        true,
					CurrentToken:   token,
					IsGCPaused:     true,
					LastOperation:  "GC PAUSE",
					Timestamp:      time.Now(),
					FencingEnabled: useFencing,
				})
				time.Sleep(8 * time.Second)
				log.Printf("[%s] ✓ Resumed from GC pause", workerID)
			}

			// Try to increment counter
			var success bool
			if useFencing {
				success = incrementCounterWithFencing(token)
			} else {
				success = incrementCounterUnsafe()
			}

			if success {
				log.Printf("[%s] ✓ Successfully incremented counter to %d (token: %d)", workerID, counter, token)
				broadcastStatus(Status{
					WorkerID:       workerID,
					Counter:        counter,
					HasLock:        true,
					CurrentToken:   token,
					LastOperation:  fmt.Sprintf("Incremented counter to %d", counter),
					Timestamp:      time.Now(),
					FencingEnabled: useFencing,
				})
			} else {
				log.Printf("[%s] ✗ Counter increment REJECTED - stale token %d", workerID, token)
				broadcastStatus(Status{
					WorkerID:       workerID,
					Counter:        counter,
					HasLock:        false,
					CurrentToken:   token,
					LastOperation:  "Operation REJECTED (stale token)",
					Timestamp:      time.Now(),
					FencingEnabled: useFencing,
				})
			}

			// Release lock (in unsafe mode, lock might already be gone)
			if !useFencing {
				releaseLockUnsafe()
			}
		}

		broadcastStatus(Status{
			WorkerID:       workerID,
			Counter:        counter,
			HasLock:        false,
			LastOperation:  "Waiting",
			Timestamp:      time.Now(),
			FencingEnabled: useFencing,
		})

		time.Sleep(1 * time.Second)
	}
}

func acquireLockUnsafe() bool {
	// Simple SETNX with 5-second TTL (UNSAFE!)
	success, err := redisClient.SetNX(ctx, "resource:lock", workerID, 5*time.Second).Result()
	if err != nil {
		log.Printf("Error acquiring lock: %v", err)
		return false
	}
	return success
}

func releaseLockUnsafe() {
	redisClient.Del(ctx, "resource:lock")
}

func acquireLockWithFencing() (int64, bool) {
	// Increment token counter and set lock with TTL
	pipe := redisClient.Pipeline()
	incrCmd := pipe.Incr(ctx, "fencing:token")
	setCmd := pipe.SetNX(ctx, "resource:lock", workerID, 5*time.Second)
	_, err := pipe.Exec(ctx)
	if err != nil {
		return 0, false
	}

	token := incrCmd.Val()
	success := setCmd.Val()

	if success {
		// Store token for this lock holder
		redisClient.Set(ctx, fmt.Sprintf("worker:%s:token", workerID), token, 10*time.Second)
	}

	return token, success
}

func incrementCounterUnsafe() bool {
	// No validation - just increment (UNSAFE!)
	counterMu.Lock()
	counter++
	counterMu.Unlock()
	return true
}

func incrementCounterWithFencing(token int64) bool {
	// Check if our token is still valid against the highest token seen
	highestToken, err := redisClient.Get(ctx, "resource:highest_token").Int64()
	if err != nil && err != redis.Nil {
		return false
	}

	// If our token is lower than the highest seen, reject the operation
	if token < highestToken {
		log.Printf("[%s] Token %d < highest %d - REJECTED", workerID, token, highestToken)
		return false
	}

	// Update highest token and increment counter
	redisClient.Set(ctx, "resource:highest_token", token, 0)
	counterMu.Lock()
	counter++
	counterMu.Unlock()
	return true
}
EOF

cat > worker/go.mod << 'EOF'
module distributed-lock-worker

go 1.21

require (
	github.com/go-redis/redis/v8 v8.11.5
	github.com/gorilla/websocket v1.5.1
)

require (
	github.com/cespare/xxhash/v2 v2.1.2 // indirect
	github.com/dgryski/go-rendezvous v0.0.0-20200823014737-9f7001d12a5f // indirect
)
EOF

cat > worker/Dockerfile << 'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod ./
COPY . .
RUN go mod tidy && go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -o worker .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/worker .
CMD ["./worker"]
EOF

# Create web dashboard
cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Distributed Lock Demo - Live Dashboard</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
        }

        .header {
            background: white;
            border-radius: 16px;
            padding: 30px;
            margin-bottom: 30px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
        }

        h1 {
            color: #2d3748;
            font-size: 32px;
            margin-bottom: 10px;
        }

        .subtitle {
            color: #718096;
            font-size: 16px;
        }

        .mode-indicator {
            display: inline-block;
            padding: 8px 16px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 600;
            margin-left: 15px;
        }

        .mode-unsafe {
            background: #fed7d7;
            color: #c53030;
        }

        .mode-safe {
            background: #c6f6d5;
            color: #2f855a;
        }

        .workers {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(450px, 1fr));
            gap: 30px;
            margin-bottom: 30px;
        }

        .worker-card {
            background: white;
            border-radius: 16px;
            padding: 30px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.1);
            transition: transform 0.3s ease;
        }

        .worker-card:hover {
            transform: translateY(-5px);
        }

        .worker-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }

        .worker-name {
            font-size: 24px;
            font-weight: 700;
            color: #2d3748;
        }

        .worker-1 { color: #4A90E2; }
        .worker-2 { color: #50C878; }

        .status-badge {
            padding: 6px 14px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
        }

        .status-active {
            background: #c6f6d5;
            color: #2f855a;
        }

        .status-waiting {
            background: #e2e8f0;
            color: #4a5568;
        }

        .status-paused {
            background: #fed7d7;
            color: #c53030;
            animation: pulse 1.5s ease-in-out infinite;
        }

        @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: 0.6; }
        }

        .stat-row {
            display: flex;
            justify-content: space-between;
            padding: 15px 0;
            border-bottom: 1px solid #e2e8f0;
        }

        .stat-row:last-child {
            border-bottom: none;
        }

        .stat-label {
            color: #718096;
            font-size: 14px;
        }

        .stat-value {
            color: #2d3748;
            font-weight: 600;
            font-size: 16px;
        }

        .counter-display {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 12px;
            padding: 25px;
            text-align: center;
            margin: 20px 0;
        }

        .counter-label {
            font-size: 14px;
            opacity: 0.9;
            margin-bottom: 5px;
        }

        .counter-value {
            font-size: 48px;
            font-weight: 700;
        }

        .operation-log {
            background: #f7fafc;
            border-radius: 8px;
            padding: 15px;
            margin-top: 15px;
            max-height: 150px;
            overflow-y: auto;
        }

        .log-entry {
            font-size: 13px;
            color: #4a5568;
            padding: 5px 0;
            border-bottom: 1px solid #e2e8f0;
        }

        .log-entry:last-child {
            border-bottom: none;
        }

        .timestamp {
            color: #a0aec0;
            font-size: 11px;
        }

        .alert {
            background: #fff5f5;
            border-left: 4px solid #fc8181;
            padding: 20px;
            border-radius: 8px;
            margin-top: 20px;
        }

        .alert-title {
            color: #c53030;
            font-weight: 700;
            margin-bottom: 5px;
        }

        .alert-text {
            color: #742a2a;
            font-size: 14px;
        }

        .connection-status {
            position: fixed;
            top: 20px;
            right: 20px;
            padding: 10px 20px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            background: white;
            box-shadow: 0 4px 12px rgba(0,0,0,0.1);
        }

        .connected {
            color: #2f855a;
        }

        .disconnected {
            color: #c53030;
        }
    </style>
</head>
<body>
    <div class="connection-status" id="connectionStatus">
        <span class="disconnected">⚫ Connecting...</span>
    </div>

    <div class="container">
        <div class="header">
            <h1>
                Distributed Lock Race Condition Demo
                <span class="mode-indicator mode-unsafe" id="modeIndicator">UNSAFE MODE</span>
            </h1>
            <p class="subtitle">Watch two processes compete for a distributed lock. Worker 1 will experience a simulated GC pause.</p>
        </div>

        <div class="workers">
            <div class="worker-card">
                <div class="worker-header">
                    <div class="worker-name worker-1">⚡ Worker 1</div>
                    <div class="status-badge status-waiting" id="status1">Waiting</div>
                </div>
                
                <div class="stat-row">
                    <span class="stat-label">Lock Status</span>
                    <span class="stat-value" id="lock1">Not Held</span>
                </div>
                
                <div class="stat-row">
                    <span class="stat-label">Fencing Token</span>
                    <span class="stat-value" id="token1">-</span>
                </div>
                
                <div class="counter-display">
                    <div class="counter-label">Local Counter</div>
                    <div class="counter-value" id="counter1">0</div>
                </div>
                
                <div class="stat-row">
                    <span class="stat-label">Last Operation</span>
                    <span class="stat-value" id="operation1">Initializing...</span>
                </div>
                
                <div class="operation-log" id="log1"></div>
            </div>

            <div class="worker-card">
                <div class="worker-header">
                    <div class="worker-name worker-2">⚡ Worker 2</div>
                    <div class="status-badge status-waiting" id="status2">Waiting</div>
                </div>
                
                <div class="stat-row">
                    <span class="stat-label">Lock Status</span>
                    <span class="stat-value" id="lock2">Not Held</span>
                </div>
                
                <div class="stat-row">
                    <span class="stat-label">Fencing Token</span>
                    <span class="stat-value" id="token2">-</span>
                </div>
                
                <div class="counter-display">
                    <div class="counter-label">Local Counter</div>
                    <div class="counter-value" id="counter2">0</div>
                </div>
                
                <div class="stat-row">
                    <span class="stat-label">Last Operation</span>
                    <span class="stat-value" id="operation2">Initializing...</span>
                </div>
                
                <div class="operation-log" id="log2"></div>
            </div>
        </div>

        <div class="header" id="alertBox" style="display: none;">
            <div class="alert-title">⚠️ Race Condition Detected!</div>
            <div class="alert-text">Both workers incremented the counter. In unsafe mode, this causes data corruption. With fencing tokens, stale operations are rejected.</div>
        </div>
    </div>

    <script>
        let ws1, ws2;
        const logs = { '1': [], '2': [] };
        let lastCounters = { '1': 0, '2': 0 };

        function connectWebSocket(workerId, port) {
            const ws = new WebSocket(`ws://localhost:${port}/ws`);
            
            ws.onopen = () => {
                console.log(`Worker ${workerId} connected`);
                updateConnectionStatus(true);
            };

            ws.onmessage = (event) => {
                const data = JSON.parse(event.data);
                updateWorkerDisplay(workerId, data);
            };

            ws.onclose = () => {
                console.log(`Worker ${workerId} disconnected`);
                updateConnectionStatus(false);
                setTimeout(() => connectWebSocket(workerId, port), 2000);
            };

            return ws;
        }

        function updateWorkerDisplay(workerId, data) {
            const id = workerId === 'worker-1' ? '1' : '2';
            
            // Update mode indicator
            const modeIndicator = document.getElementById('modeIndicator');
            if (data.fencing_enabled) {
                modeIndicator.textContent = 'SAFE MODE (Fencing Tokens)';
                modeIndicator.className = 'mode-indicator mode-safe';
            } else {
                modeIndicator.textContent = 'UNSAFE MODE';
                modeIndicator.className = 'mode-indicator mode-unsafe';
            }

            // Update status badge
            const statusBadge = document.getElementById(`status${id}`);
            if (data.is_gc_paused) {
                statusBadge.textContent = 'GC PAUSED';
                statusBadge.className = 'status-badge status-paused';
            } else if (data.has_lock) {
                statusBadge.textContent = 'Active';
                statusBadge.className = 'status-badge status-active';
            } else {
                statusBadge.textContent = 'Waiting';
                statusBadge.className = 'status-badge status-waiting';
            }

            // Update lock status
            document.getElementById(`lock${id}`).textContent = data.has_lock ? '🔒 Held' : 'Not Held';
            
            // Update token
            document.getElementById(`token${id}`).textContent = data.current_token || '-';
            
            // Update counter
            document.getElementById(`counter${id}`).textContent = data.counter;
            
            // Update operation
            document.getElementById(`operation${id}`).textContent = data.last_operation;

            // Add to log
            const timestamp = new Date(data.timestamp).toLocaleTimeString();
            addLogEntry(id, `${timestamp} - ${data.last_operation}`);

            // Check for race condition
            if (data.counter > lastCounters[id]) {
                lastCounters[id] = data.counter;
                checkRaceCondition();
            }
        }

        function addLogEntry(workerId, message) {
            logs[workerId].unshift(message);
            if (logs[workerId].length > 10) logs[workerId].pop();

            const logContainer = document.getElementById(`log${workerId}`);
            logContainer.innerHTML = logs[workerId]
                .map(log => `<div class="log-entry">${log}</div>`)
                .join('');
        }

        function checkRaceCondition() {
            const counter1 = lastCounters['1'];
            const counter2 = lastCounters['2'];
            
            if (counter1 > 0 && counter2 > 0 && Math.abs(counter1 - counter2) <= 1) {
                document.getElementById('alertBox').style.display = 'block';
            }
        }

        function updateConnectionStatus(connected) {
            const status = document.getElementById('connectionStatus');
            if (connected) {
                status.innerHTML = '<span class="connected">🟢 Connected</span>';
            } else {
                status.innerHTML = '<span class="disconnected">🔴 Disconnected</span>';
            }
        }

        // Connect to both workers
        ws1 = connectWebSocket('worker-1', 8080);
        ws2 = connectWebSocket('worker-2', 8081);
    </script>
</body>
</html>
EOF

cat > dashboard/Dockerfile << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/
EXPOSE 80
EOF

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    networks:
      - lock-network

  worker-1:
    build: ./worker
    environment:
      - WORKER_ID=worker-1
      - USE_FENCING=${USE_FENCING:-false}
    ports:
      - "8080:8080"
    depends_on:
      - redis
    networks:
      - lock-network

  worker-2:
    build: ./worker
    environment:
      - WORKER_ID=worker-2
      - USE_FENCING=${USE_FENCING:-false}
    ports:
      - "8081:8081"
    depends_on:
      - redis
    networks:
      - lock-network

  dashboard:
    build: ./dashboard
    ports:
      - "3000:80"
    networks:
      - lock-network

networks:
  lock-network:
    driver: bridge
EOF

echo -e "${GREEN}✓ Project structure created${NC}"
echo ""

# Build and run
echo -e "${BLUE}Building Docker images...${NC}"
docker-compose build

echo ""
echo -e "${GREEN}✓ Build complete${NC}"
echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Starting Demo - UNSAFE MODE${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# Run in unsafe mode first
export USE_FENCING=false
docker-compose up -d

echo -e "${GREEN}✓ Demo is running!${NC}"
echo ""
echo -e "${BLUE}📊 Open the dashboard:${NC}"
echo -e "   ${GREEN}http://localhost:3000${NC}"
echo ""
echo -e "${BLUE}Watch the race condition happen:${NC}"
echo -e "   • Worker 1 will acquire the lock"
echo -e "   • Worker 1 will pause for 8 seconds (simulated GC)"
echo -e "   • Lock TTL expires after 5 seconds"
echo -e "   • Worker 2 acquires the lock"
echo -e "   • Worker 1 resumes and increments counter"
echo -e "   • Worker 2 also increments counter"
echo -e "   • ${RED}Both workers modify the same resource!${NC}"
echo ""
echo -e "${YELLOW}Press Enter to see the SAFE MODE (with fencing tokens)...${NC}"
read

echo ""
echo -e "${BLUE}Stopping unsafe mode...${NC}"
docker-compose down

echo ""
echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Starting Demo - SAFE MODE${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

export USE_FENCING=true
docker-compose up -d

echo -e "${GREEN}✓ Demo is running with fencing tokens!${NC}"
echo ""
echo -e "${BLUE}📊 Dashboard still at:${NC}"
echo -e "   ${GREEN}http://localhost:3000${NC}"
echo ""
echo -e "${BLUE}Watch how fencing tokens prevent the race:${NC}"
echo -e "   • Worker 1 acquires lock with token 1"
echo -e "   • Worker 1 pauses (simulated GC)"
echo -e "   • Worker 2 acquires lock with token 2"
echo -e "   • Worker 2 successfully increments (token 2 valid)"
echo -e "   • Worker 1 resumes with token 1"
echo -e "   • ${GREEN}Worker 1's operation is REJECTED (stale token)${NC}"
echo ""
echo -e "${GREEN}View logs: docker-compose logs -f${NC}"
echo -e "${RED}Stop demo: docker-compose down${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop watching logs${NC}"
echo ""

# Follow logs
docker-compose logs -f