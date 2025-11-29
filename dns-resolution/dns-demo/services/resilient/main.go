package main

import (
    "context"
    "encoding/json"
    "fmt"
    "log"
    "net"
    "net/http"
    "sync"
    "time"
)

type StatusResponse struct {
    Status      string    `json:"status"`
    Backend     string    `json:"backend"`
    DNSTime     int64     `json:"dns_time_ms"`
    TotalTime   int64     `json:"total_time_ms"`
    CacheHit    bool      `json:"cache_hit"`
    Error       string    `json:"error,omitempty"`
    Timestamp   time.Time `json:"timestamp"`
}

var metrics = struct {
    sync.RWMutex
    TotalRequests   int64
    SuccessRequests int64
    FailedRequests  int64
    TotalDNSTime    int64
    CacheHits       int64
}{}

// DNS cache with stale-serve capability
type DNSCache struct {
    mu    sync.RWMutex
    cache map[string]cacheEntry
}

type cacheEntry struct {
    ips       []string
    timestamp time.Time
    ttl       time.Duration
}

type DNSControllerStatus struct {
    DelayMs int64  `json:"delay_ms"`
    Failing bool   `json:"failing"`
    Mode    string `json:"mode"`
}

var dnsCache = &DNSCache{
    cache: make(map[string]cacheEntry),
}

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

func (c *DNSCache) resolve(host string) ([]string, bool, error) {
    c.mu.RLock()
    entry, exists := c.cache[host]
    c.mu.RUnlock()
    
    // Check DNS controller status
    dnsStatus := getDNSControllerStatus()
    
    // Check if cached and still valid
    if exists && time.Since(entry.timestamp) < entry.ttl {
        // Even with cache hit, apply delay if configured (simulates DNS delay affecting all lookups)
        if dnsStatus.DelayMs > 0 {
            time.Sleep(time.Duration(dnsStatus.DelayMs) * time.Millisecond)
        }
        return entry.ips, true, nil
    }
    
    // Apply DNS delay before lookup
    if dnsStatus.DelayMs > 0 {
        time.Sleep(time.Duration(dnsStatus.DelayMs) * time.Millisecond)
    }
    
    // Simulate DNS failure if configured
    if dnsStatus.Failing {
        // DNS failed - serve stale if available
        if exists {
            log.Printf("⚠️  DNS failed (simulated), serving stale cache for %s (age: %v)", host, time.Since(entry.timestamp))
            return entry.ips, true, nil
        }
        return nil, false, fmt.Errorf("DNS resolution failed (simulated)")
    }
    
    // Try fresh DNS lookup with timeout
    ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
    defer cancel()
    
    ips, err := net.DefaultResolver.LookupHost(ctx, host)
    if err != nil {
        // DNS failed - serve stale if available
        if exists {
            log.Printf("⚠️  DNS failed, serving stale cache for %s (age: %v)", host, time.Since(entry.timestamp))
            return entry.ips, true, nil
        }
        return nil, false, err
    }
    
    // Cache the fresh result
    c.mu.Lock()
    c.cache[host] = cacheEntry{
        ips:       ips,
        timestamp: time.Now(),
        ttl:       5 * time.Minute, // Cache for 5 minutes
    }
    c.mu.Unlock()
    
    return ips, false, nil
}

func callBackend() StatusResponse {
    start := time.Now()
    
    // Resilient DNS resolution with caching
    ips, cacheHit, err := dnsCache.resolve("backend")
    dnsTime := time.Since(start).Milliseconds()
    
    metrics.Lock()
    metrics.TotalRequests++
    metrics.TotalDNSTime += dnsTime
    if cacheHit {
        metrics.CacheHits++
    }
    metrics.Unlock()
    
    if err != nil {
        metrics.Lock()
        metrics.FailedRequests++
        metrics.Unlock()
        return StatusResponse{
            Status:    "error",
            DNSTime:   dnsTime,
            TotalTime: time.Since(start).Milliseconds(),
            CacheHit:  cacheHit,
            Error:     err.Error(),
            Timestamp: time.Now(),
        }
    }
    
    // Use the resolved IP
    client := &http.Client{Timeout: 5 * time.Second}
    resp, err := client.Get(fmt.Sprintf("http://%s:8080/data", ips[0]))
    
    if err != nil {
        metrics.Lock()
        metrics.FailedRequests++
        metrics.Unlock()
        return StatusResponse{
            Status:    "error",
            DNSTime:   dnsTime,
            TotalTime: time.Since(start).Milliseconds(),
            CacheHit:  cacheHit,
            Error:     err.Error(),
            Timestamp: time.Now(),
        }
    }
    defer resp.Body.Close()
    
    totalTime := time.Since(start).Milliseconds()
    metrics.Lock()
    metrics.SuccessRequests++
    metrics.Unlock()
    
    return StatusResponse{
        Status:    "success",
        Backend:   fmt.Sprintf("%s:8080", ips[0]),
        DNSTime:   dnsTime,
        TotalTime: totalTime,
        CacheHit:  cacheHit,
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
    metrics.RLock()
    defer metrics.RUnlock()
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "total_requests":   metrics.TotalRequests,
        "success_requests": metrics.SuccessRequests,
        "failed_requests":  metrics.FailedRequests,
        "cache_hits":       metrics.CacheHits,
        "avg_dns_time_ms":  func() int64 {
            if metrics.TotalRequests == 0 {
                return 0
            }
            return metrics.TotalDNSTime / metrics.TotalRequests
        }(),
        "cache_hit_rate": func() float64 {
            if metrics.TotalRequests == 0 {
                return 0.0
            }
            return float64(metrics.CacheHits) / float64(metrics.TotalRequests) * 100
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
    
    fmt.Println("🟢 Resilient Service starting on :8082")
    fmt.Println("✅ DNS caching enabled, stale-serve on failure")
    log.Fatal(http.ListenAndServe(":8082", nil))
}
