package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

type Stats struct {
	ActiveConnections int64     `json:"active_connections"`
	TotalRequests     int64     `json:"total_requests"`
	SuccessRequests   int64     `json:"success_requests"`
	FailedRequests    int64     `json:"failed_requests"`
	AvgResponseTime   float64   `json:"avg_response_time_ms"`
	Uptime            float64   `json:"uptime_seconds"`
	MaxConnections    int       `json:"max_connections"`
	StartTime         time.Time `json:"-"`
}

var (
	stats = &Stats{
		MaxConnections: 100,
		StartTime:      time.Now(),
	}
	connectionSemaphore chan struct{}
	responseTimes       []float64
	responseTimeMutex   sync.Mutex
)

func init() {
	connectionSemaphore = make(chan struct{}, stats.MaxConnections)
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	startTime := time.Now()
	
	select {
	case connectionSemaphore <- struct{}{}:
		defer func() { <-connectionSemaphore }()
		atomic.AddInt64(&stats.ActiveConnections, 1)
		defer atomic.AddInt64(&stats.ActiveConnections, -1)
		
		atomic.AddInt64(&stats.TotalRequests, 1)
		
		// Read body slowly to simulate processing
		buf := make([]byte, 1024)
		totalRead := 0
		for {
			n, err := r.Body.Read(buf)
			totalRead += n
			if err != nil {
				break
			}
			time.Sleep(10 * time.Millisecond)
		}
		r.Body.Close()
		
		duration := time.Since(startTime).Milliseconds()
		
		responseTimeMutex.Lock()
		responseTimes = append(responseTimes, float64(duration))
		if len(responseTimes) > 1000 {
			responseTimes = responseTimes[1:]
		}
		responseTimeMutex.Unlock()
		
		atomic.AddInt64(&stats.SuccessRequests, 1)
		
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status":       "success",
			"bytes_read":   totalRead,
			"duration_ms":  duration,
			"worker_id":    fmt.Sprintf("worker-%d", atomic.LoadInt64(&stats.ActiveConnections)),
		})
		
	default:
		atomic.AddInt64(&stats.TotalRequests, 1)
		atomic.AddInt64(&stats.FailedRequests, 1)
		
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]interface{}{
			"status": "error",
			"error":  "Connection pool exhausted",
		})
	}
}

func handleStats(w http.ResponseWriter, r *http.Request) {
	responseTimeMutex.Lock()
	var avgTime float64
	if len(responseTimes) > 0 {
		sum := 0.0
		for _, t := range responseTimes {
			sum += t
		}
		avgTime = sum / float64(len(responseTimes))
	}
	responseTimeMutex.Unlock()
	
	stats.AvgResponseTime = avgTime
	stats.Uptime = time.Since(stats.StartTime).Seconds()
	
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	json.NewEncoder(w).Encode(stats)
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	
	http.HandleFunc("/api/upload", handleRequest)
	http.HandleFunc("/api/stats", handleStats)
	http.HandleFunc("/health", handleHealth)
	
	log.Printf("Backend server starting on port %s (max connections: %d)", port, stats.MaxConnections)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
