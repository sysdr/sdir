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
