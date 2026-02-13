package main

import (
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"runtime"
	"runtime/debug"
	"sort"
	"sync"
	"sync/atomic"
	"time"
)

var (
	requestCount  int64
	latencySamples = make([]int64, 0, 1000)
	latencyMu     sync.Mutex
	cache         = make(map[string][]byte)
	cacheMu       sync.RWMutex
)

func addLatency(ms int64) {
	latencyMu.Lock()
	defer latencyMu.Unlock()
	latencySamples = append(latencySamples, ms)
	if len(latencySamples) > 1000 {
		latencySamples = latencySamples[1:]
	}
}

func processHandler(w http.ResponseWriter, r *http.Request) {
	load := r.URL.Query().Get("load")
	if load == "" {
		load = "medium"
	}

	start := time.Now()

	// Allocation-heavy work — mix of stack and heap allocations
	allocCount := 2000
	switch load {
	case "heavy":
		allocCount = 5000
	case "light":
		allocCount = 500
	}

	// These slices escape to heap due to size
	slices := make([][]byte, allocCount)
	for i := range slices {
		slices[i] = make([]byte, 512)
		slices[i][0] = byte(i % 256)
	}

	// Computation to prevent optimizer from eliminating the work
	checksum := int64(0)
	for _, s := range slices {
		checksum += int64(s[0])
	}

	// 5% of requests write to long-lived cache (old-gen analogue in Go)
	count := atomic.AddInt64(&requestCount, 1)
	if count%20 == 0 {
		key := fmt.Sprintf("entry-%d", rand.Intn(500))
		data := make([]byte, 4096)
		cacheMu.Lock()
		cache[key] = data
		if len(cache) > 500 {
			// Evict one
			for k := range cache {
				delete(cache, k)
				break
			}
		}
		cacheMu.Unlock()
	}

	elapsed := time.Since(start).Milliseconds()
	addLatency(elapsed)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"requestId":        count,
		"latencyMs":        elapsed,
		"allocatedObjects": allocCount,
		"checksum":         checksum,
	})
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	var memStats runtime.MemStats
	runtime.ReadMemStats(&memStats)

	var gcStats debug.GCStats
	debug.ReadGCStats(&gcStats)

	// Compute latency percentiles
	latencyMu.Lock()
	samples := make([]int64, len(latencySamples))
	copy(samples, latencySamples)
	latencyMu.Unlock()

	p50, p95, p99, p999 := int64(0), int64(0), int64(0), int64(0)
	if len(samples) > 0 {
		sort.Slice(samples, func(i, j int) bool { return samples[i] < samples[j] })
		sz := len(samples)
		p50  = samples[int(float64(sz)*0.50)]
		p95  = samples[int(float64(sz)*0.95)]
		p99  = samples[min(int(float64(sz)*0.99), sz-1)]
		p999 = samples[min(int(float64(sz)*0.999), sz-1)]
	}

	cacheMu.RLock()
	cacheSize := len(cache)
	cacheMu.RUnlock()

	gogc := os.Getenv("GOGC")
	if gogc == "" {
		gogc = "100 (default)"
	}
	gomemlimit := os.Getenv("GOMEMLIMIT")
	if gomemlimit == "" {
		gomemlimit = "unset"
	}

	// Convert GC pause durations to ms
	pauseList := make([]float64, 0)
	for _, p := range gcStats.Pause {
		pauseList = append(pauseList, float64(p.Nanoseconds())/1e6)
		if len(pauseList) >= 20 {
			break
		}
	}

	result := map[string]interface{}{
		"runtime":         "go",
		"gogc":            gogc,
		"gomemlimit":      gomemlimit,
		"heapAllocMB":     memStats.HeapAlloc / 1024 / 1024,
		"heapSysMB":       memStats.HeapSys / 1024 / 1024,
		"heapInuseMB":     memStats.HeapInuse / 1024 / 1024,
		"heapIdleMB":      memStats.HeapIdle / 1024 / 1024,
		"totalAllocMB":    memStats.TotalAlloc / 1024 / 1024,
		"mallocsTotal":    memStats.Mallocs,
		"freesTotal":      memStats.Frees,
		"gcCycles":        memStats.NumGC,
		"gcPauseLastUs":   memStats.PauseNs[(memStats.NumGC+255)%256] / 1000,
		"gcPauseTotalMs":  memStats.PauseTotalNs / 1e6,
		"nextGCMB":        memStats.NextGC / 1024 / 1024,
		"goroutines":      runtime.NumGoroutine(),
		"totalRequests":   atomic.LoadInt64(&requestCount),
		"cacheSize":       cacheSize,
		"latencyP50":      p50,
		"latencyP95":      p95,
		"latencyP99":      p99,
		"latencyP999":     p999,
		"sampleCount":     len(samples),
		"recentGcPausesMs": pauseList,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func gcHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	runtime.GC()
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok","message":"GC triggered"}`))
}

func main() {
	// Background allocation pressure
	go func() {
		for {
			scratch := make([][]byte, 200)
			for i := range scratch {
				scratch[i] = make([]byte, 1024)
			}
			_ = scratch
			time.Sleep(2 * time.Second)
		}
	}()

	http.HandleFunc("/process", processHandler)
	http.HandleFunc("/metrics", metricsHandler)
	http.HandleFunc("/gc", gcHandler)
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(200)
		w.Write([]byte(`{"status":"ok"}`))
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}
	log.Printf("Go GC demo service on :%s (GOGC=%s, GOMEMLIMIT=%s)",
		port, os.Getenv("GOGC"), os.Getenv("GOMEMLIMIT"))
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
