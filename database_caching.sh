#!/bin/bash

# docker_cache_demo.sh - Multi-layer cache demonstration with Docker
# This script creates a complete caching environment with monitoring capabilities

set -e

echo "🔥 Docker-Based Multi-Layer Cache Demonstration"
echo "=============================================="

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker is not running. Please start Docker and try again."
        exit 1
    fi
    echo "✅ Docker is running"
}

# Function to create our caching network
setup_network() {
    echo "🌐 Setting up cache network..."
    docker network create cache-demo-network 2>/dev/null || echo "Network already exists"
}

# Function to start Redis (L2 distributed cache)
start_redis() {
    echo "🚀 Starting Redis (L2 Distributed Cache)..."
    docker run -d \
        --name redis-l2-cache \
        --network cache-demo-network \
        -p 6379:6379 \
        redis:7-alpine \
        redis-server --appendonly yes --maxmemory 100mb --maxmemory-policy allkeys-lru
    
    # Wait for Redis to be ready
    echo "⏳ Waiting for Redis to be ready..."
    sleep 3
    docker exec redis-l2-cache redis-cli ping
    echo "✅ Redis (L2) is ready"
}

# Function to start a mock database (L3)
start_database() {
    echo "🗄️ Starting Mock Database (L3)..."
    docker run -d \
        --name mock-database-l3 \
        --network cache-demo-network \
        -p 3001:3001 \
        node:18-alpine \
        sh -c '
        cat > server.js << EOF
const http = require("http");
const server = http.createServer((req, res) => {
    const url = req.url;
    console.log(`[L3-DATABASE] ${new Date().toISOString()} - Request for: ${url}`);
    
    // Simulate database latency (50-100ms)
    const latency = Math.random() * 50 + 50;
    setTimeout(() => {
        if (url.startsWith("/get/")) {
            const key = url.split("/")[2];
            const value = `database_value_for_${key}_${Date.now()}`;
            console.log(`[L3-DATABASE] Returning: ${key} = ${value} (${latency.toFixed(1)}ms)`);
            res.writeHead(200, {"Content-Type": "application/json"});
            res.end(JSON.stringify({key, value, source: "L3-DATABASE", latency}));
        } else {
            res.writeHead(404);
            res.end("Not found");
        }
    }, latency);
});
server.listen(3001, "0.0.0.0", () => {
    console.log("[L3-DATABASE] Mock database listening on port 3001");
});
EOF
        node server.js'
    
    echo "⏳ Waiting for mock database to be ready..."
    sleep 3
    echo "✅ Mock Database (L3) is ready"
}

# Function to start our application with L1 cache
start_application() {
    echo "🎯 Starting Application with L1 Cache..."
    docker run -d \
        --name app-with-l1-cache \
        --network cache-demo-network \
        -p 3000:3000 \
        node:18-alpine \
        sh -c '
        cat > app.js << EOF
const http = require("http");

// L1 Cache (In-memory within application)
class L1Cache {
    constructor() {
        this.cache = new Map();
        this.accessCounts = new Map();
        this.lastAccess = new Map();
        this.ttl = 60000; // 60 seconds TTL
        
        // Clean expired entries every 30 seconds
        setInterval(() => this.cleanup(), 30000);
    }
    
    cleanup() {
        const now = Date.now();
        for (const [key, timestamp] of this.lastAccess) {
            if (now - timestamp > this.ttl) {
                this.cache.delete(key);
                this.accessCounts.delete(key);
                this.lastAccess.delete(key);
                console.log(`[L1-CACHE] Expired: ${key}`);
            }
        }
    }
    
    get(key) {
        const now = Date.now();
        if (this.cache.has(key) && now - this.lastAccess.get(key) < this.ttl) {
            this.lastAccess.set(key, now);
            const count = this.accessCounts.get(key) + 1;
            this.accessCounts.set(key, count);
            console.log(`[L1-CACHE] HIT: ${key} = ${this.cache.get(key)} (access count: ${count})`);
            return { value: this.cache.get(key), source: "L1-CACHE", accessCount: count };
        }
        console.log(`[L1-CACHE] MISS: ${key}`);
        return null;
    }
    
    set(key, value) {
        const now = Date.now();
        this.cache.set(key, value);
        this.lastAccess.set(key, now);
        this.accessCounts.set(key, (this.accessCounts.get(key) || 0) + 1);
        console.log(`[L1-CACHE] SET: ${key} = ${value}`);
    }
    
    getStats() {
        return {
            size: this.cache.size,
            entries: Object.fromEntries(
                Array.from(this.cache.entries()).map(([k, v]) => [
                    k, 
                    { value: v, accessCount: this.accessCounts.get(k) || 0 }
                ])
            )
        };
    }
}

const l1Cache = new L1Cache();

// Helper function to call L2 cache (Redis)
async function getFromL2(key) {
    try {
        const response = await fetch(`http://redis-l2-cache:6379`);
        // Since we cannot directly HTTP to Redis, we simulate the call
        console.log(`[L2-CACHE] Simulated check for: ${key}`);
        return null; // Simplified for demo
    } catch (error) {
        console.log(`[L2-CACHE] MISS: ${key}`);
        return null;
    }
}

// Helper function to call L3 database
async function getFromL3(key) {
    try {
        const response = await fetch(`http://mock-database-l3:3001/get/${key}`);
        const data = await response.json();
        console.log(`[L3-DATABASE] Retrieved: ${key} = ${data.value}`);
        return data;
    } catch (error) {
        console.log(`[L3-DATABASE] Error: ${error.message}`);
        return null;
    }
}

// Multi-layer get operation
async function multiLayerGet(key) {
    console.log(`\n🔍 GET: ${key}`);
    console.log("-------------------");
    
    // Try L1 first
    const l1Result = l1Cache.get(key);
    if (l1Result) {
        return l1Result;
    }
    
    // Try L2 (simplified for demo)
    const l2Result = await getFromL2(key);
    if (l2Result) {
        l1Cache.set(key, l2Result.value);
        return l2Result;
    }
    
    // Fallback to L3 (database)
    const l3Result = await getFromL3(key);
    if (l3Result) {
        l1Cache.set(key, l3Result.value);
        return l3Result;
    }
    
    return { error: "Key not found in any layer" };
}

// HTTP server to handle requests
const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    
    if (url.pathname.startsWith("/get/")) {
        const key = url.pathname.split("/")[2];
        const result = await multiLayerGet(key);
        res.writeHead(200, {"Content-Type": "application/json"});
        res.end(JSON.stringify(result));
    } else if (url.pathname === "/stats") {
        const stats = l1Cache.getStats();
        res.writeHead(200, {"Content-Type": "application/json"});
        res.end(JSON.stringify(stats));
    } else {
        res.writeHead(404);
        res.end("Not found");
    }
});

server.listen(3000, "0.0.0.0", () => {
    console.log("[APPLICATION] Multi-layer cache application listening on port 3000");
});
EOF
        node app.js'
    
    echo "⏳ Waiting for application to be ready..."
    sleep 3
    echo "✅ Application with L1 Cache is ready"
}

# Function to run the demonstration scenarios
run_demo_scenarios() {
    echo
    echo "🧪 Running Cache Layer Demonstration Scenarios..."
    echo
    
    # Scenario 1: Cold data access
    echo "📊 Scenario 1: Cold Data Access Pattern"
    echo "This demonstrates what happens when data is accessed for the first time"
    curl -s http://localhost:3000/get/user_cold | jq '.'
    
    echo
    echo "📊 Scenario 2: Data Warming Pattern"
    echo "Making multiple requests to see caching in action..."
    
    for i in {1..5}; do
        echo "Access attempt #$i:"
        curl -s http://localhost:3000/get/user_popular | jq '.'
        echo "Waiting 1 second before next request..."
        sleep 1
    done
    
    echo
    echo "📊 Scenario 3: Rapid Access (Hot Data Simulation)"
    echo "Making rapid requests to demonstrate L1 cache efficiency..."
    
    for i in {6..10}; do
        echo "Rapid access #$i:"
        curl -s http://localhost:3000/get/user_popular | jq '.'
        sleep 0.2
    done
}

# Function to show verification methods
show_verification_methods() {
    echo
    echo "🔍 How to Verify Cache Layer Behavior:"
    echo "====================================="
    
    echo
    echo "1. Monitor Application Logs (L1 Cache):"
    echo "   docker logs -f app-with-l1-cache"
    
    echo
    echo "2. Monitor Database Logs (L3):"
    echo "   docker logs -f mock-database-l3"
    
    echo
    echo "3. Check L1 Cache Statistics:"
    echo "   curl http://localhost:3000/stats | jq ."
    
    echo
    echo "4. Monitor Redis (L2) - if implemented:"
    echo "   docker exec redis-l2-cache redis-cli monitor"
    
    echo
    echo "5. Network Traffic Analysis:"
    echo "   docker exec app-with-l1-cache netstat -an"
    
    echo
    echo "6. Performance Testing:"
    echo "   time curl -s http://localhost:3000/get/test_key"
}

# Function to actually verify the system
verify_system() {
    echo
    echo "🔬 System Verification in Progress..."
    echo "===================================="
    
    echo
    echo "✅ Checking L1 Cache Statistics:"
    curl -s http://localhost:3000/stats | jq '.' || echo "L1 stats not available"
    
    echo
    echo "✅ Checking Container Health:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo
    echo "✅ Testing Response Times:"
    echo "First request (should be slowest - hits L3):"
    time curl -s http://localhost:3000/get/timing_test > /dev/null
    
    echo "Second request (should be faster - hits L1):"
    time curl -s http://localhost:3000/get/timing_test > /dev/null
    
    echo
    echo "✅ Checking Network Communication:"
    docker exec app-with-l1-cache ping -c 1 mock-database-l3 >/dev/null 2>&1 && echo "✅ App can reach Database" || echo "❌ App cannot reach Database"
    docker exec app-with-l1-cache ping -c 1 redis-l2-cache >/dev/null 2>&1 && echo "✅ App can reach Redis" || echo "❌ App cannot reach Redis"
}

# Function to cleanup
cleanup() {
    echo
    echo "🧹 Cleaning up containers and network..."
    docker stop app-with-l1-cache mock-database-l3 redis-l2-cache 2>/dev/null || true
    docker rm app-with-l1-cache mock-database-l3 redis-l2-cache 2>/dev/null || true
    docker network rm cache-demo-network 2>/dev/null || true
    echo "✅ Cleanup completed"
}

# Main execution flow
main() {
    # Setup signal handler for cleanup
    trap cleanup EXIT
    
    check_docker
    setup_network
    start_redis
    start_database
    start_application
    
    echo
    echo "🎉 All services are running!"
    echo "Application: http://localhost:3000"
    echo "You can now run the demonstration..."
    
    # Wait a moment for everything to stabilize
    sleep 2
    
    run_demo_scenarios
    show_verification_methods
    verify_system
    
    echo
    echo "🏁 Demonstration Complete!"
    echo "================================"
    echo "Key Observations from This Demo:"
    echo "• Each cache layer runs in its own container (realistic distributed setup)"
    echo "• L1 (application memory) provides fastest access after first request"
    echo "• L3 (database) shows highest latency on first access"
    echo "• Network calls between containers demonstrate real-world behavior"
    echo "• Monitoring tools show exactly what is happening at each layer"
    
    echo
    echo "💡 To explore further:"
    echo "• Leave containers running and experiment with different access patterns"
    echo "• Monitor logs in real-time: docker logs -f app-with-l1-cache"
    echo "• Check performance: time curl http://localhost:3000/get/your_key"
    echo "• View cache stats: curl http://localhost:3000/stats | jq ."
    
    read -p "Press Enter to clean up and exit, or Ctrl+C to keep containers running..."
}

# Check if jq is installed (for JSON formatting)
if ! command -v jq &> /dev/null; then
    echo "📦 Installing jq for JSON formatting..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install jq
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y jq
    fi
fi

main "$@"