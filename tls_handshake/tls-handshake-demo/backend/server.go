package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "sync"
    "sync/atomic"
    "time"
)

type Metrics struct {
    TotalConnections    int64     `json:"total_connections"`
    ActiveConnections   int64     `json:"active_connections"`
    HandshakeLatencyP50 float64   `json:"handshake_latency_p50_ms"`
    HandshakeLatencyP99 float64   `json:"handshake_latency_p99_ms"`
    FailedHandshakes    int64     `json:"failed_handshakes"`
    LastUpdated         time.Time `json:"last_updated"`
}

var (
    totalConns    int64
    activeConns   int64
    failedConns   int64
    latencies     []float64
    latencyMutex  sync.RWMutex
)

func recordConnection(duration time.Duration) {
    atomic.AddInt64(&totalConns, 1)
    atomic.AddInt64(&activeConns, 1)
    
    latencyMutex.Lock()
    latencies = append(latencies, duration.Seconds()*1000) // Convert to ms
    if len(latencies) > 1000 {
        latencies = latencies[len(latencies)-1000:] // Keep last 1000
    }
    latencyMutex.Unlock()
    
    // Simulate connection lifetime
    go func() {
        time.Sleep(time.Duration(100+time.Now().Unix()%400) * time.Millisecond)
        atomic.AddInt64(&activeConns, -1)
    }()
}

func calculatePercentile(data []float64, percentile float64) float64 {
    if len(data) == 0 {
        return 0
    }
    sorted := make([]float64, len(data))
    copy(sorted, data)
    
    // Simple sort
    for i := 0; i < len(sorted); i++ {
        for j := i + 1; j < len(sorted); j++ {
            if sorted[i] > sorted[j] {
                sorted[i], sorted[j] = sorted[j], sorted[i]
            }
        }
    }
    
    idx := int(float64(len(sorted)) * percentile)
    if idx >= len(sorted) {
        idx = len(sorted) - 1
    }
    return sorted[idx]
}

func getMetrics() Metrics {
    latencyMutex.RLock()
    latencyCopy := make([]float64, len(latencies))
    copy(latencyCopy, latencies)
    latencyMutex.RUnlock()
    
    return Metrics{
        TotalConnections:    atomic.LoadInt64(&totalConns),
        ActiveConnections:   atomic.LoadInt64(&activeConns),
        HandshakeLatencyP50: calculatePercentile(latencyCopy, 0.50),
        HandshakeLatencyP99: calculatePercentile(latencyCopy, 0.99),
        FailedHandshakes:    atomic.LoadInt64(&failedConns),
        LastUpdated:         time.Now(),
    }
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    w.Header().Set("Access-Control-Allow-Origin", "*")
    json.NewEncoder(w).Encode(getMetrics())
}

func rootHandler(w http.ResponseWriter, r *http.Request) {
    start := time.Now()
    recordConnection(time.Since(start))
    
    w.Header().Set("Content-Type", "application/json")
    fmt.Fprintf(w, `{"status":"ok","message":"Connection established"}`)
}

func main() {
    http.HandleFunc("/", rootHandler)
    http.HandleFunc("/metrics", metricsHandler)
    
    log.Println("Backend service starting on :8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
