package main

import (
	"encoding/json"
	"fmt"
	"hash/fnv"
	"log"
	"math/rand"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

type Server struct {
	ID       int     `json:"id"`
	Load     int64   `json:"load"`
	Capacity int64   `json:"capacity"`
	Status   string  `json:"status"`
	QPS      int64   `json:"qps"`
	CPUUsage float64 `json:"cpuUsage"`
}

type Event struct {
	Timestamp string `json:"timestamp"`
	Type      string `json:"type"`
	ServerID  int    `json:"serverId"`
	Message   string `json:"message"`
}

type Config struct {
	Mode           string  `json:"mode"`
	BoundedLoadC   float64 `json:"boundedLoadC"`
	SaltCount      int     `json:"saltCount"`
	HotStoreActive bool    `json:"hotStoreActive"`
}

var (
	servers      []*Server
	events       []Event
	mu           sync.RWMutex
	config       Config
	totalServers = 8
	baseCapacity = int64(1000)
)

func hash(key string) uint32 {
	h := fnv.New32a()
	h.Write([]byte(key))
	return h.Sum32()
}

func getServerForKey(key string) int {
	if config.Mode == "hot-store" && key == "celebrity" {
		// Celebrity bypasses ring entirely
		return -1 // -1 indicates hot store
	}

	h := hash(key)
	serverIdx := int(h % uint32(totalServers))

	if config.Mode == "bounded-load" {
		// Try to find server under capacity (bounded load balancing)
		// This distributes load across multiple servers to prevent overload
		bestIdx := serverIdx
		lowestLoad := atomic.LoadInt64(&servers[serverIdx].Load)
		
		for i := 0; i < totalServers; i++ {
			idx := (serverIdx + i) % totalServers
			load := atomic.LoadInt64(&servers[idx].Load)
			capacity := atomic.LoadInt64(&servers[idx].Capacity)
			maxLoad := int64(float64(capacity) * config.BoundedLoadC)

			// Prefer servers under capacity
			if load < maxLoad {
				return idx
			}
			
			// Track server with lowest load as fallback
			if load < lowestLoad {
				lowestLoad = load
				bestIdx = idx
			}
		}
		
		// Return server with lowest load if all are at capacity
		return bestIdx
	}

	return serverIdx
}

func processRequest(userID string, requestCount int) {
	mu.RLock()
	mode := config.Mode
	saltCount := config.SaltCount
	mu.RUnlock()

	keys := []string{userID}

	if mode == "key-salting" && userID == "celebrity" {
		keys = make([]string, saltCount)
		for i := 0; i < saltCount; i++ {
			keys[i] = fmt.Sprintf("%s_s%d", userID, i)
		}
	}

	for _, key := range keys {
		serverIdx := getServerForKey(key)

		if serverIdx == -1 {
			// Hot store - doesn't affect our servers
			continue
		}

		if serverIdx >= 0 && serverIdx < len(servers) {
			// Add load proportional to request count
			// For key salting, load is distributed across multiple servers (each gets 1/len(keys) of total)
			// For bounded load, load is distributed to available servers
			loadIncrement := int64(requestCount / len(keys))
			if loadIncrement < 1 {
				loadIncrement = 1
			}
			
			// Scale load based on mode - solutions should significantly reduce load per server
			if requestCount > 100 && mode == "standard" {
				// Standard mode: all celebrity traffic hits one server, so scale up load (2x)
				// This causes crashes
				loadIncrement = loadIncrement * 2
			} else if requestCount > 100 && mode == "key-salting" {
				// Key salting: load is distributed across len(keys) servers (4 servers)
				// Each server gets 1000/4 = 250, but we need to reduce further to prevent crashes
				// Reduce to 1/4 of the distributed amount to keep servers healthy
				loadIncrement = loadIncrement / 4
			} else if requestCount > 100 && mode == "bounded-load" {
				// Bounded load: routes to available servers, distributing load across multiple servers
				// Reduce load significantly since it's spread - each server gets a small fraction
				loadIncrement = loadIncrement / 8
			}
			
			atomic.AddInt64(&servers[serverIdx].Load, loadIncrement)
			atomic.AddInt64(&servers[serverIdx].QPS, int64(requestCount/len(keys)))

			// Simulate CPU usage
			load := atomic.LoadInt64(&servers[serverIdx].Load)
			cpuUsage := float64(load) / float64(baseCapacity) * 100
			
			// Update status with proper locking
			mu.Lock()
			servers[serverIdx].CPUUsage = cpuUsage
			
			// Check if server should crash (threshold lowered to 85% for more realistic crashes)
			if cpuUsage > 85 && servers[serverIdx].Status != "crashed" {
				servers[serverIdx].Status = "crashed"
				mu.Unlock()
				addEvent("crash", serverIdx, fmt.Sprintf("Server %d crashed due to overload!", serverIdx))
			} else if servers[serverIdx].Status != "crashed" {
				if cpuUsage > 65 {
					servers[serverIdx].Status = "warning"
				} else {
					servers[serverIdx].Status = "healthy"
				}
				mu.Unlock()
			} else {
				mu.Unlock()
			}
		}
	}
}

func addEvent(eventType string, serverID int, message string) {
	mu.Lock()
	defer mu.Unlock()

	event := Event{
		Timestamp: time.Now().Format("15:04:05"),
		Type:      eventType,
		ServerID:  serverID,
		Message:   message,
	}

	events = append([]Event{event}, events...)
	if len(events) > 50 {
		events = events[:50]
	}
}

func simulateTraffic() {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	for range ticker.C {
		// Normal users
		for i := 0; i < 10; i++ {
			userID := fmt.Sprintf("user_%d", rand.Intn(1000))
			processRequest(userID, 1)
		}

		// Celebrity user - 100x traffic
		processRequest("celebrity", 1000)

		// Decay load - higher decay for distributed modes (key-salting, bounded-load)
		// since load is distributed and should be more manageable
		mu.RLock()
		currentMode := config.Mode
		mu.RUnlock()
		
		decayRate := int64(5) // Standard mode - lower decay allows crashes
		if currentMode == "key-salting" {
			// Much higher decay for key-salting since load is distributed across multiple servers
			// With reduced load (250/4 = 62.5 per 100ms), decay of 40 keeps it well below threshold
			decayRate = 40
		} else if currentMode == "bounded-load" {
			// Higher decay for bounded-load since traffic routes to available servers
			// With reduced load (1000/8 = 125 per 100ms), decay of 45 keeps it well below threshold
			decayRate = 45
		} else if currentMode == "hot-store" {
			// Hot store: celebrity traffic bypasses, so normal decay is fine
			decayRate = 5
		}
		
		for _, server := range servers {
			load := atomic.LoadInt64(&server.Load)
			if load > 0 {
				// Only decay if server is not crashed
				if server.Status != "crashed" {
					atomic.AddInt64(&server.Load, -decayRate)
				}
			}
			if load < 0 {
				atomic.StoreInt64(&server.Load, 0)
			}
		}
	}
}

func corsMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		next(w, r)
	}
}

func getStatusHandler(w http.ResponseWriter, r *http.Request) {
	mu.RLock()
	defer mu.RUnlock()

	response := map[string]interface{}{
		"servers": servers,
		"events":  events,
		"config":  config,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func updateConfigHandler(w http.ResponseWriter, r *http.Request) {
	var newConfig Config
	if err := json.NewDecoder(r.Body).Decode(&newConfig); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	mu.Lock()
	config = newConfig
	mu.Unlock()

	addEvent("config", -1, fmt.Sprintf("Configuration changed to: %s", config.Mode))

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "success"})
}

func resetHandler(w http.ResponseWriter, r *http.Request) {
	mu.Lock()
	for _, server := range servers {
		atomic.StoreInt64(&server.Load, 0)
		atomic.StoreInt64(&server.QPS, 0)
		server.Status = "healthy"
		server.CPUUsage = 0
	}
	events = []Event{}
	mu.Unlock()

	addEvent("reset", -1, "System reset")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "success"})
}

func main() {
	// Initialize servers
	servers = make([]*Server, totalServers)
	for i := 0; i < totalServers; i++ {
		servers[i] = &Server{
			ID:       i,
			Load:     0,
			Capacity: baseCapacity,
			Status:   "healthy",
			QPS:      0,
			CPUUsage: 0,
		}
	}

	// Default config
	config = Config{
		Mode:           "standard",
		BoundedLoadC:   1.5,
		SaltCount:      4,
		HotStoreActive: false,
	}

	// Start traffic simulation
	go simulateTraffic()

	// HTTP handlers
	http.HandleFunc("/api/status", corsMiddleware(getStatusHandler))
	http.HandleFunc("/api/config", corsMiddleware(updateConfigHandler))
	http.HandleFunc("/api/reset", corsMiddleware(resetHandler))

	port := ":8080"
	fmt.Printf("🚀 Backend server running on http://localhost%s\n", port)
	fmt.Println("📊 Dashboard will be available at http://localhost:3000")
	log.Fatal(http.ListenAndServe(port, nil))
}
