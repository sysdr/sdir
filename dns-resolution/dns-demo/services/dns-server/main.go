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
