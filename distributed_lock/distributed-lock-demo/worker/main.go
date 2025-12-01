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
