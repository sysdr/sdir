#!/bin/bash

set -e

echo "🚀 DNS Resilience Demo Setup"
echo "=============================="
echo ""

# Check for Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose is required but not installed. Please install docker-compose first."
    exit 1
fi

# Create project structure
echo "📁 Creating project structure..."
mkdir -p dns-demo/{services/{fragile,resilient,backend,dns-server},dashboard,config}

# Create Go service - Fragile version
cat > dns-demo/services/fragile/main.go <<'EOF'
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
EOF

# Create Go service - Resilient version
cat > dns-demo/services/resilient/main.go <<'EOF'
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
    dnsStart := time.Now()
    ips, cacheHit, err := dnsCache.resolve("backend")
    dnsTime := time.Since(dnsStart).Milliseconds()
    
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
EOF

# Create backend service
cat > dns-demo/services/backend/main.go <<'EOF'
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "time"
)

func dataHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "data":      "Backend response",
        "timestamp": time.Now(),
    })
}

func main() {
    http.HandleFunc("/data", dataHandler)
    fmt.Println("🔵 Backend Service starting on :8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

# Create DNS chaos controller
cat > dns-demo/services/dns-server/main.go <<'EOF'
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "sync/atomic"
)

var (
    dnsDelayMs int64 = 0 // Delay in milliseconds
    dnsFailing int64 = 0 // 0 = working, 1 = failing
)

type DNSStatus struct {
    DelayMs int64  `json:"delay_ms"`
    Failing bool   `json:"failing"`
    Mode    string `json:"mode"`
}

func setCORSHeaders(w http.ResponseWriter) {
    w.Header().Set("Access-Control-Allow-Origin", "*")
    w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
    setCORSHeaders(w)
    if r.Method == "OPTIONS" {
        w.WriteHeader(http.StatusOK)
        return
    }
    delay := atomic.LoadInt64(&dnsDelayMs)
    failing := atomic.LoadInt64(&dnsFailing) == 1
    
    mode := "healthy"
    if failing {
        mode = "failing"
    } else if delay > 5000 {
        mode = "slow"
    } else if delay > 0 {
        mode = "degraded"
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(DNSStatus{
        DelayMs: delay,
        Failing: failing,
        Mode:    mode,
    })
}

func setDelayHandler(w http.ResponseWriter, r *http.Request) {
    setCORSHeaders(w)
    if r.Method == "OPTIONS" {
        w.WriteHeader(http.StatusOK)
        return
    }
    if r.Method != "POST" {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    
    var req struct {
        DelayMs int64 `json:"delay_ms"`
    }
    
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    
    atomic.StoreInt64(&dnsDelayMs, req.DelayMs)
    log.Printf("DNS delay set to %dms", req.DelayMs)
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "delay_ms": req.DelayMs,
        "message":  fmt.Sprintf("DNS delay set to %dms", req.DelayMs),
    })
}

func setFailingHandler(w http.ResponseWriter, r *http.Request) {
    setCORSHeaders(w)
    if r.Method == "OPTIONS" {
        w.WriteHeader(http.StatusOK)
        return
    }
    if r.Method != "POST" {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    
    var req struct {
        Failing bool `json:"failing"`
    }
    
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    
    if req.Failing {
        atomic.StoreInt64(&dnsFailing, 1)
        log.Println("DNS set to failing mode")
    } else {
        atomic.StoreInt64(&dnsFailing, 0)
        log.Println("DNS set to working mode")
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "failing": req.Failing,
        "message": fmt.Sprintf("DNS failing mode: %v", req.Failing),
    })
}

func main() {
    http.HandleFunc("/status", statusHandler)
    http.HandleFunc("/delay", setDelayHandler)
    http.HandleFunc("/failing", setFailingHandler)
    
    fmt.Println("🌐 DNS Chaos Controller starting on :9000")
    fmt.Println("   Use /delay and /failing endpoints to simulate issues")
    log.Fatal(http.ListenAndServe(":9000", nil))
}
EOF

# Create dashboard
cat > dns-demo/dashboard/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNS Resilience Demo</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        header {
            text-align: center;
            color: white;
            margin-bottom: 30px;
        }
        
        h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .subtitle {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .controls {
            background: white;
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 20px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        
        .control-group {
            margin-bottom: 20px;
        }
        
        .control-group label {
            display: block;
            font-weight: 600;
            margin-bottom: 8px;
            color: #333;
        }
        
        .slider-container {
            display: flex;
            align-items: center;
            gap: 15px;
        }
        
        input[type="range"] {
            flex: 1;
            height: 8px;
            border-radius: 5px;
            background: #ddd;
            outline: none;
            -webkit-appearance: none;
        }
        
        input[type="range"]::-webkit-slider-thumb {
            -webkit-appearance: none;
            appearance: none;
            width: 20px;
            height: 20px;
            border-radius: 50%;
            background: #667eea;
            cursor: pointer;
        }
        
        .value-display {
            min-width: 100px;
            padding: 8px 15px;
            background: #f0f0f0;
            border-radius: 8px;
            text-align: center;
            font-weight: 600;
        }
        
        .button-group {
            display: flex;
            gap: 10px;
        }
        
        button {
            flex: 1;
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            font-size: 1em;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
        }
        
        .btn-healthy {
            background: #10b981;
            color: white;
        }
        
        .btn-slow {
            background: #f59e0b;
            color: white;
        }
        
        .btn-fail {
            background: #ef4444;
            color: white;
        }
        
        button:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
        }
        
        .metrics-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .metric-card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        
        .metric-card h3 {
            font-size: 1.2em;
            margin-bottom: 15px;
            color: #333;
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .status-indicator {
            width: 12px;
            height: 12px;
            border-radius: 50%;
            display: inline-block;
        }
        
        .status-healthy {
            background: #10b981;
        }
        
        .status-degraded {
            background: #f59e0b;
        }
        
        .status-error {
            background: #ef4444;
        }
        
        .metric-value {
            font-size: 2.5em;
            font-weight: 700;
            color: #667eea;
            margin: 10px 0;
        }
        
        .metric-label {
            color: #666;
            font-size: 0.9em;
        }
        
        .chart-container {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
            margin-bottom: 20px;
        }
        
        .comparison-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 20px;
        }
        
        @media (max-width: 768px) {
            .comparison-grid {
                grid-template-columns: 1fr;
            }
        }
        
        .service-card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        
        .service-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin-bottom: 20px;
        }
        
        .service-title {
            font-size: 1.3em;
            font-weight: 700;
        }
        
        .badge {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: 600;
        }
        
        .badge-fragile {
            background: #fee2e2;
            color: #dc2626;
        }
        
        .badge-resilient {
            background: #dcfce7;
            color: #16a34a;
        }
        
        .stat-row {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            border-bottom: 1px solid #eee;
        }
        
        .stat-label {
            color: #666;
        }
        
        .stat-value {
            font-weight: 600;
            color: #333;
        }
    </style>
</head>
<body>
    <div class="container">
        <header>
            <h1>🌐 DNS Resilience Demo</h1>
            <p class="subtitle">See how DNS failures cascade through your system</p>
        </header>
        
        <div class="controls">
            <h3 style="margin-bottom: 20px;">DNS Chaos Controls</h3>
            
            <div class="control-group">
                <label>DNS Response Delay</label>
                <div class="slider-container">
                    <input type="range" id="delaySlider" min="0" max="15000" value="0" step="500">
                    <div class="value-display" id="delayValue">0ms</div>
                </div>
            </div>
            
            <div class="control-group">
                <label>Quick Scenarios</label>
                <div class="button-group">
                    <button class="btn-healthy" onclick="setHealthy()">🟢 Healthy</button>
                    <button class="btn-slow" onclick="setSlow()">🟡 Slow DNS (5s)</button>
                    <button class="btn-fail" onclick="setFailing()">🔴 DNS Timeout (10s)</button>
                </div>
            </div>
        </div>
        
        <div class="metrics-grid">
            <div class="metric-card">
                <h3><span class="status-indicator" id="dnsStatus"></span> DNS Status</h3>
                <div class="metric-value" id="dnsMode">HEALTHY</div>
                <div class="metric-label">Current response time: <span id="dnsDelay">0ms</span></div>
            </div>
            
            <div class="metric-card">
                <h3>Request Volume</h3>
                <div class="metric-value" id="totalRequests">0</div>
                <div class="metric-label">Total requests processed</div>
            </div>
        </div>
        
        <div class="comparison-grid">
            <div class="service-card">
                <div class="service-header">
                    <div class="service-title">🔴 Fragile Service</div>
                    <span class="badge badge-fragile">NO RESILIENCE</span>
                </div>
                
                <div class="stat-row">
                    <span class="stat-label">Success Rate</span>
                    <span class="stat-value" id="fragileSuccess">100%</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Total Requests</span>
                    <span class="stat-value" id="fragileTotal">0</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Failed Requests</span>
                    <span class="stat-value" id="fragileFailed">0</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Avg DNS Time</span>
                    <span class="stat-value" id="fragileDNS">0ms</span>
                </div>
            </div>
            
            <div class="service-card">
                <div class="service-header">
                    <div class="service-title">🟢 Resilient Service</div>
                    <span class="badge badge-resilient">WITH CACHING</span>
                </div>
                
                <div class="stat-row">
                    <span class="stat-label">Success Rate</span>
                    <span class="stat-value" id="resilientSuccess">100%</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Total Requests</span>
                    <span class="stat-value" id="resilientTotal">0</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Failed Requests</span>
                    <span class="stat-value" id="resilientFailed">0</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Avg DNS Time</span>
                    <span class="stat-value" id="resilientDNS">0ms</span>
                </div>
                <div class="stat-row">
                    <span class="stat-label">Cache Hit Rate</span>
                    <span class="stat-value" id="resilientCacheHit">0%</span>
                </div>
            </div>
        </div>
        
        <div class="chart-container">
            <h3 style="margin-bottom: 20px;">Success Rate Comparison</h3>
            <canvas id="successChart"></canvas>
        </div>
    </div>
    
    <script>
        const ctx = document.getElementById('successChart').getContext('2d');
        const chart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'Fragile Service',
                        data: [],
                        borderColor: '#ef4444',
                        backgroundColor: 'rgba(239, 68, 68, 0.1)',
                        tension: 0.4
                    },
                    {
                        label: 'Resilient Service',
                        data: [],
                        borderColor: '#10b981',
                        backgroundColor: 'rgba(16, 185, 129, 0.1)',
                        tension: 0.4
                    }
                ]
            },
            options: {
                responsive: true,
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 100,
                        ticks: {
                            callback: function(value) {
                                return value + '%';
                            }
                        }
                    }
                },
                plugins: {
                    legend: {
                        display: true,
                        position: 'top'
                    }
                }
            }
        });
        
        const delaySlider = document.getElementById('delaySlider');
        const delayValue = document.getElementById('delayValue');
        
        delaySlider.addEventListener('input', (e) => {
            const value = e.target.value;
            delayValue.textContent = value + 'ms';
            setDNSDelay(parseInt(value));
        });
        
        function setHealthy() {
            delaySlider.value = 0;
            delayValue.textContent = '0ms';
            setDNSDelay(0);
        }
        
        function setSlow() {
            delaySlider.value = 5000;
            delayValue.textContent = '5000ms';
            setDNSDelay(5000);
        }
        
        function setFailing() {
            delaySlider.value = 10000;
            delayValue.textContent = '10000ms';
            setDNSDelay(10000);
        }
        
        async function setDNSDelay(ms) {
            try {
                await fetch('http://localhost:9000/delay', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({delay_ms: ms})
                });
            } catch (e) {
                console.error('Failed to set DNS delay:', e);
            }
        }
        
        async function fetchMetrics() {
            try {
                const [dnsStatus, fragile, resilient] = await Promise.all([
                    fetch('http://localhost:9000/status').then(r => r.json()),
                    fetch('http://localhost:8081/metrics').then(r => r.json()),
                    fetch('http://localhost:8082/metrics').then(r => r.json())
                ]);
                
                // Update DNS status
                document.getElementById('dnsDelay').textContent = dnsStatus.delay_ms + 'ms';
                document.getElementById('dnsMode').textContent = dnsStatus.mode.toUpperCase();
                
                const statusEl = document.getElementById('dnsStatus');
                if (dnsStatus.mode === 'healthy') {
                    statusEl.className = 'status-indicator status-healthy';
                } else if (dnsStatus.mode === 'slow' || dnsStatus.mode === 'degraded') {
                    statusEl.className = 'status-indicator status-degraded';
                } else {
                    statusEl.className = 'status-indicator status-error';
                }
                
                // Update fragile service
                document.getElementById('fragileSuccess').textContent = fragile.success_rate.toFixed(1) + '%';
                document.getElementById('fragileTotal').textContent = fragile.total_requests;
                document.getElementById('fragileFailed').textContent = fragile.failed_requests;
                document.getElementById('fragileDNS').textContent = fragile.avg_dns_time_ms + 'ms';
                
                // Update resilient service
                document.getElementById('resilientSuccess').textContent = resilient.success_rate.toFixed(1) + '%';
                document.getElementById('resilientTotal').textContent = resilient.total_requests;
                document.getElementById('resilientFailed').textContent = resilient.failed_requests;
                document.getElementById('resilientDNS').textContent = resilient.avg_dns_time_ms + 'ms';
                document.getElementById('resilientCacheHit').textContent = resilient.cache_hit_rate.toFixed(1) + '%';
                
                // Update chart
                const now = new Date().toLocaleTimeString();
                if (chart.data.labels.length > 20) {
                    chart.data.labels.shift();
                    chart.data.datasets[0].data.shift();
                    chart.data.datasets[1].data.shift();
                }
                chart.data.labels.push(now);
                chart.data.datasets[0].data.push(fragile.success_rate);
                chart.data.datasets[1].data.push(resilient.success_rate);
                chart.update('none');
                
                document.getElementById('totalRequests').textContent = 
                    fragile.total_requests + resilient.total_requests;
                
            } catch (e) {
                console.error('Failed to fetch metrics:', e);
            }
        }
        
        // Update every second
        setInterval(fetchMetrics, 1000);
        fetchMetrics();
        
        // Make requests to both services
        async function makeRequests() {
            try {
                await Promise.all([
                    fetch('http://localhost:8081/health'),
                    fetch('http://localhost:8082/health')
                ]);
            } catch (e) {
                // Ignore errors
            }
        }
        
        setInterval(makeRequests, 2000);
    </script>
</body>
</html>
EOF

# Create Dockerfiles
cat > dns-demo/services/fragile/Dockerfile <<'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go build -o fragile main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/fragile .
EXPOSE 8081
CMD ["./fragile"]
EOF

cat > dns-demo/services/resilient/Dockerfile <<'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go build -o resilient main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/resilient .
EXPOSE 8082
CMD ["./resilient"]
EOF

cat > dns-demo/services/backend/Dockerfile <<'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go build -o backend main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/backend .
EXPOSE 8080
CMD ["./backend"]
EOF

cat > dns-demo/services/dns-server/Dockerfile <<'EOF'
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY main.go .
RUN go build -o dns-server main.go

FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/dns-server .
EXPOSE 9000
CMD ["./dns-server"]
EOF

# Create docker-compose.yml
cat > dns-demo/docker-compose.yml <<'EOF'
version: '3.8'

services:
  backend:
    build: ./services/backend
    container_name: dns-demo-backend
    networks:
      - demo-network
    ports:
      - "8080:8080"
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/data"]
      interval: 5s
      timeout: 3s
      retries: 3

  fragile:
    build: ./services/fragile
    container_name: dns-demo-fragile
    networks:
      - demo-network
    ports:
      - "8081:8081"
    depends_on:
      - backend
    dns:
      - 127.0.0.11

  resilient:
    build: ./services/resilient
    container_name: dns-demo-resilient
    networks:
      - demo-network
    ports:
      - "8082:8082"
    depends_on:
      - backend
    dns:
      - 127.0.0.11

  dns-controller:
    build: ./services/dns-server
    container_name: dns-demo-controller
    networks:
      - demo-network
    ports:
      - "9000:9000"

  dashboard:
    image: nginx:alpine
    container_name: dns-demo-dashboard
    volumes:
      - ./dashboard:/usr/share/nginx/html:ro
    ports:
      - "3000:80"
    networks:
      - demo-network

networks:
  demo-network:
    driver: bridge
EOF

echo "🔨 Building Docker images..."
cd dns-demo
docker-compose build --parallel

echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "✅ Demo is running!"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔴 Fragile Service: http://localhost:8081"
echo "🟢 Resilient Service: http://localhost:8082"
echo "🌐 DNS Controller: http://localhost:9000"
echo ""
echo "Try these scenarios:"
echo "1. Click 'Healthy' - Both services work perfectly"
echo "2. Click 'Slow DNS (5s)' - Watch the fragile service fail while resilient survives"
echo "3. Click 'DNS Timeout (10s)' - Complete DNS failure simulation"
echo ""
echo "To stop: ./cleanup.sh"