package main

import (
    "context"
    "encoding/json"
    "fmt"
    "log"
    "net"
    "net/http"
    "time"
)

type StatusResponse struct {
    Status      string    `json:"status"`
    Backend     string    `json:"backend"`
    DNSTime     int64     `json:"dns_time_ms"`
    TotalTime   int64     `json:"total_time_ms"`
    Error       string    `json:"error,omitempty"`
    Timestamp   time.Time `json:"timestamp"`
}

type DNSControllerStatus struct {
    DelayMs int64  `json:"delay_ms"`
    Failing bool   `json:"failing"`
    Mode    string `json:"mode"`
}

var metrics = struct {
    TotalRequests   int64
    SuccessRequests int64
    FailedRequests  int64
    TotalDNSTime    int64
}{}

func getDNSControllerStatus() DNSControllerStatus {
    client := &http.Client{Timeout: 1 * time.Second}
    resp, err := client.Get("http://dns-controller:9000/status")
    if err != nil {
        // If DNS controller is unreachable, assume healthy
        return DNSControllerStatus{DelayMs: 0, Failing: false, Mode: "healthy"}
    }
    defer resp.Body.Close()
    
    var status DNSControllerStatus
    if err := json.NewDecoder(resp.Body).Decode(&status); err != nil {
        return DNSControllerStatus{DelayMs: 0, Failing: false, Mode: "healthy"}
    }
    return status
}

func callBackend() StatusResponse {
    start := time.Now()
    
    // Check DNS controller status
    dnsStatus := getDNSControllerStatus()
    
    // Start DNS timing (includes delay)
    dnsStart := time.Now()
    
    // Apply DNS delay if configured
    if dnsStatus.DelayMs > 0 {
        time.Sleep(time.Duration(dnsStatus.DelayMs) * time.Millisecond)
    }
    
    // Simulate DNS failure if configured
    if dnsStatus.Failing {
        dnsTime := time.Since(dnsStart).Milliseconds()
        metrics.TotalRequests++
        metrics.FailedRequests++
        metrics.TotalDNSTime += dnsTime
        return StatusResponse{
            Status:    "error",
            DNSTime:   dnsTime,
            TotalTime: time.Since(start).Milliseconds(),
            Error:     "DNS resolution failed (simulated)",
            Timestamp: time.Now(),
        }
    }
    
    // This is fragile - uses default DNS resolution with no caching
    // Do DNS lookup first to measure DNS time
    ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
    defer cancel()
    
    _, err := net.DefaultResolver.LookupHost(ctx, "backend")
    dnsTime := time.Since(dnsStart).Milliseconds()
    
    metrics.TotalRequests++
    metrics.TotalDNSTime += dnsTime
    
    if err != nil {
        metrics.FailedRequests++
        return StatusResponse{
            Status:    "error",
            DNSTime:   dnsTime,
            TotalTime: time.Since(start).Milliseconds(),
            Error:     err.Error(),
            Timestamp: time.Now(),
        }
    }
    
    // Now make HTTP request
    resp, err := http.Get("http://backend:8080/data")
    if err != nil {
        metrics.FailedRequests++
        return StatusResponse{
            Status:    "error",
            DNSTime:   dnsTime,
            TotalTime: time.Since(start).Milliseconds(),
            Error:     err.Error(),
            Timestamp: time.Now(),
        }
    }
    defer resp.Body.Close()
    
    totalTime := time.Since(start).Milliseconds()
    metrics.SuccessRequests++
    
    return StatusResponse{
        Status:    "success",
        Backend:   "backend:8080",
        DNSTime:   dnsTime,
        TotalTime: totalTime,
        Timestamp: time.Now(),
    }
}

func setCORSHeaders(w http.ResponseWriter) {
    w.Header().Set("Access-Control-Allow-Origin", "*")
    w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
    setCORSHeaders(w)
    if r.Method == "OPTIONS" {
        w.WriteHeader(http.StatusOK)
        return
    }
    result := callBackend()
    w.Header().Set("Content-Type", "application/json")
    if result.Status == "error" {
        w.WriteHeader(http.StatusServiceUnavailable)
    }
    json.NewEncoder(w).Encode(result)
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
    setCORSHeaders(w)
    if r.Method == "OPTIONS" {
        w.WriteHeader(http.StatusOK)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "total_requests":   metrics.TotalRequests,
        "success_requests": metrics.SuccessRequests,
        "failed_requests":  metrics.FailedRequests,
        "avg_dns_time_ms":  func() int64 {
            if metrics.TotalRequests == 0 {
                return 0
            }
            return metrics.TotalDNSTime / metrics.TotalRequests
        }(),
        "success_rate": func() float64 {
            if metrics.TotalRequests == 0 {
                return 100.0
            }
            return float64(metrics.SuccessRequests) / float64(metrics.TotalRequests) * 100
        }(),
    })
}

func main() {
    http.HandleFunc("/health", healthHandler)
    http.HandleFunc("/metrics", metricsHandler)
    
    fmt.Println("🔴 Fragile Service starting on :8081")
    fmt.Println("⚠️  No DNS caching, no resilience patterns")
    log.Fatal(http.ListenAndServe(":8081", nil))
}
