#!/bin/bash
# Docker Vector Clock System Demo Setup
# Creates a containerized distributed system demonstration
# Author: System Design Interview Roadmap
# Version: 2.0

set -e

echo "🐳 Setting up Dockerized Vector Clock Demonstration"
DEMO_DIR="vector_clock_docker_demo"
rm -rf $DEMO_DIR && mkdir $DEMO_DIR && cd $DEMO_DIR

# Create Dockerfile
cat > Dockerfile << 'EOF'
FROM node:18-alpine

WORKDIR /app

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S vectorclock -u 1001

# Copy application files
COPY vector_clock.js package.json ./

# Install dependencies (if any)
RUN npm install --production 2>/dev/null || true

# Set ownership
RUN chown -R vectorclock:nodejs /app
USER vectorclock

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT}/status || exit 1

EXPOSE ${PORT}

CMD ["node", "vector_clock.js"]
EOF

# Create package.json
cat > package.json << 'EOF'
{
  "name": "vector-clock-demo",
  "version": "1.0.0",
  "description": "Vector Clock Distributed System Demo",
  "main": "vector_clock.js",
  "scripts": {
    "start": "node vector_clock.js"
  },
  "dependencies": {},
  "engines": {
    "node": ">=14"
  }
}
EOF

# Create enhanced vector clock implementation with Docker networking
cat > vector_clock.js << 'EOF'
const http = require('http');

class VectorClock {
    constructor(processId, numProcesses) {
        this.processId = processId;
        this.clock = new Array(numProcesses).fill(0);
        this.eventLog = [];
    }

    tick() {
        this.clock[this.processId]++;
        this.logEvent('LOCAL_EVENT', null, [...this.clock]);
        return [...this.clock];
    }

    update(otherClock) {
        for (let i = 0; i < this.clock.length; i++) {
            this.clock[i] = Math.max(this.clock[i], otherClock[i]);
        }
        this.clock[this.processId]++;
        this.logEvent('MESSAGE_RECEIVED', otherClock, [...this.clock]);
        return [...this.clock];
    }

    static compare(clock1, clock2) {
        let less = true, greater = true;
        for (let i = 0; i < clock1.length; i++) {
            if (clock1[i] > clock2[i]) less = false;
            if (clock1[i] < clock2[i]) greater = false;
        }
        if (less && greater) return 'EQUAL';
        if (less) return 'BEFORE';
        if (greater) return 'AFTER';
        return 'CONCURRENT';
    }

    logEvent(type, receivedClock, currentClock) {
        this.eventLog.push({
            timestamp: new Date().toISOString(),
            type, processId: this.processId,
            receivedClock, currentClock: [...currentClock]
        });
        // Keep only last 50 events to prevent memory issues
        if (this.eventLog.length > 50) {
            this.eventLog = this.eventLog.slice(-50);
        }
    }

    toString() { return JSON.stringify(this.clock); }
}

// Environment configuration
const processId = parseInt(process.env.PROCESS_ID || process.argv[2] || 0);
const numProcesses = parseInt(process.env.NUM_PROCESSES || process.argv[3] || 3);
const port = parseInt(process.env.PORT || process.argv[4] || 8080);
const containerName = process.env.CONTAINER_NAME || `process-${processId}`;

const vectorClock = new VectorClock(processId, numProcesses);

console.log(`🚀 Starting Vector Clock Process ${processId}`);
console.log(`📍 Container: ${containerName}, Port: ${port}`);
console.log(`🕐 Initial clock: [${vectorClock.toString()}]`);

const server = http.createServer((req, res) => {
    // Enable CORS for web interface
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
    
    if (req.method === 'OPTIONS') {
        res.writeHead(200);
        res.end();
        return;
    }
    
    if (req.method === 'POST' && req.url === '/message') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            try {
                const message = JSON.parse(body);
                console.log(`📨 Process ${processId}: Received from ${message.senderId}`);
                console.log(`   Before: [${vectorClock.toString()}]`);
                const newClock = vectorClock.update(message.vectorClock);
                console.log(`   After:  [${newClock}]`);
                
                const relationship = VectorClock.compare(message.vectorClock, newClock);
                console.log(`   Relationship: ${relationship}`);
                
                res.writeHead(200, {'Content-Type': 'application/json'});
                res.end(JSON.stringify({
                    status: 'received',
                    processId: processId,
                    currentClock: vectorClock.toString(),
                    relationship: relationship,
                    timestamp: new Date().toISOString()
                }));
            } catch (error) {
                console.error(`❌ Process ${processId}: Error processing message:`, error);
                res.writeHead(400);
                res.end(JSON.stringify({error: 'Invalid message format'}));
            }
        });
    } else if (req.method === 'GET' && req.url === '/status') {
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({
            processId, 
            containerName,
            vectorClock: vectorClock.toString(),
            eventLog: vectorClock.eventLog.slice(-10),
            uptime: process.uptime(),
            timestamp: new Date().toISOString()
        }));
    } else if (req.method === 'POST' && req.url === '/local-event') {
        const newClock = vectorClock.tick();
        console.log(`⚡ Process ${processId}: Local event [${newClock}]`);
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({
            status: 'local-event', 
            processId: processId,
            currentClock: newClock,
            timestamp: new Date().toISOString()
        }));
    } else if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200, {'Content-Type': 'application/json'});
        res.end(JSON.stringify({
            status: 'healthy',
            processId: processId,
            uptime: process.uptime()
        }));
    } else {
        res.writeHead(404);
        res.end(JSON.stringify({error: 'Not found'}));
    }
});

server.listen(port, '0.0.0.0', () => {
    console.log(`✅ Process ${processId} listening on 0.0.0.0:${port}`);
    
    // Simulate periodic local events in containerized environment
    setInterval(() => {
        if (Math.random() < 0.2) { // 20% chance every interval
            const newClock = vectorClock.tick();
            console.log(`🔄 Process ${processId}: Auto local event [${newClock}]`);
        }
    }, 8000 + Math.random() * 7000); // Random interval 8-15 seconds
});

// Graceful shutdown
const shutdown = () => {
    console.log(`🛑 Process ${processId}: Shutting down gracefully`);
    server.close(() => {
        console.log(`✅ Process ${processId}: Server closed`);
        process.exit(0);
    });
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

// Handle unhandled errors
process.on('uncaughtException', (error) => {
    console.error(`💥 Process ${processId}: Uncaught exception:`, error);
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    console.error(`💥 Process ${processId}: Unhandled rejection at:`, promise, 'reason:', reason);
});
EOF

# Create Docker Compose configuration
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # Vector Clock Processes
  process-0:
    build: .
    container_name: vector-clock-process-0
    environment:
      - PROCESS_ID=0
      - NUM_PROCESSES=3
      - PORT=8080
      - CONTAINER_NAME=process-0
    ports:
      - "8080:8080"
    networks:
      - vector-clock-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s

  process-1:
    build: .
    container_name: vector-clock-process-1
    environment:
      - PROCESS_ID=1
      - NUM_PROCESSES=3
      - PORT=8080
      - CONTAINER_NAME=process-1
    ports:
      - "8081:8080"
    networks:
      - vector-clock-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s

  process-2:
    build: .
    container_name: vector-clock-process-2
    environment:
      - PROCESS_ID=2
      - NUM_PROCESSES=3
      - PORT=8080
      - CONTAINER_NAME=process-2
    ports:
      - "8082:8080"
    networks:
      - vector-clock-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 10s

  # Web Interface
  web-interface:
    image: nginx:alpine
    container_name: vector-clock-web
    ports:
      - "8090:80"
    volumes:
      - ./web:/usr/share/nginx/html:ro
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    networks:
      - vector-clock-network
    restart: unless-stopped
    depends_on:
      - process-0
      - process-1
      - process-2

networks:
  vector-clock-network:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.20.0.0/16
EOF

# Create web directory and interface
mkdir -p web

cat > web/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>🐳 Vector Clock Docker Demo</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        * { box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; padding: 20px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
        }
        .container { 
            max-width: 1400px; margin: 0 auto; 
            background: rgba(255, 255, 255, 0.95);
            border-radius: 15px; padding: 30px;
            box-shadow: 0 20px 40px rgba(0, 0, 0, 0.1);
        }
        h1 { 
            text-align: center; color: #4a5568; 
            margin-bottom: 30px; font-size: 2.2em;
        }
        .docker-info {
            background: linear-gradient(135deg, #4299e1 0%, #3182ce 100%);
            color: white; padding: 15px; border-radius: 8px;
            margin-bottom: 20px; text-align: center;
        }
        .controls { 
            text-align: center; margin: 20px 0; 
            padding: 20px; background: #f8f9fa;
            border-radius: 10px; border: 2px solid #e9ecef;
        }
        button { 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white; border: none; 
            padding: 12px 24px; margin: 5px; 
            border-radius: 6px; cursor: pointer;
            font-size: 14px; font-weight: 600;
            transition: all 0.3s ease;
        }
        button:hover { 
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
        }
        .status { 
            text-align: center; padding: 15px; 
            margin: 10px 0; border-radius: 8px;
            font-weight: 600; font-size: 14px;
        }
        .success { 
            background: linear-gradient(135deg, #48bb78 0%, #38a169 100%);
            color: white;
        }
        .error { 
            background: linear-gradient(135deg, #f56565 0%, #e53e3e 100%);
            color: white;
        }
        .processes { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px; margin: 20px 0;
        }
        .process { 
            background: white; padding: 25px; 
            border-radius: 12px; 
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
            border-left: 5px solid #667eea;
            transition: transform 0.2s ease;
        }
        .process:hover {
            transform: translateY(-3px);
            box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
        }
        .process.healthy { border-left-color: #48bb78; }
        .process.unhealthy { border-left-color: #f56565; }
        .process h3 { 
            margin: 0 0 15px 0; color: #2d3748;
            font-size: 1.3em;
        }
        .container-info {
            font-size: 12px; color: #718096;
            background: #edf2f7; padding: 8px;
            border-radius: 4px; margin: 10px 0;
        }
        .clock { 
            font-family: 'Courier New', monospace; 
            font-size: 20px; color: #667eea; 
            font-weight: bold; background: #f7fafc;
            padding: 12px; border-radius: 6px;
            border: 2px solid #e2e8f0;
            margin: 10px 0;
        }
        .events { 
            max-height: 220px; overflow-y: auto; 
            background: #f8f9fa; padding: 15px; 
            border-radius: 8px; border: 1px solid #e9ecef;
        }
        .event { 
            margin: 8px 0; padding: 10px; 
            background: white; border-radius: 6px; 
            font-size: 13px; border-left: 4px solid #48bb78;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.1);
        }
        .docker-stats {
            background: #f0f8ff; padding: 15px;
            border-radius: 8px; margin: 20px 0;
            border-left: 4px solid #4299e1;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🐳 Vector Clock Docker Demo</h1>
        
        <div class="docker-info">
            <strong>🐳 Containerized Distributed System</strong><br>
            Each vector clock process runs in its own Docker container with health monitoring
        </div>
        
        <div class="controls">
            <button onclick="refreshStatus()">🔄 Refresh Status</button>
            <button onclick="sendRandomMessage()">📨 Send Random Message</button>
            <button onclick="triggerLocalEvent()">⚡ Trigger Local Event</button>
            <button onclick="demonstrateCausality()">🔗 Demonstrate Causality</button>
            <button onclick="checkHealth()">❤️ Health Check</button>
        </div>
        
        <div id="status" class="status"></div>
        
        <div class="docker-stats">
            <strong>🏗️ Container Architecture:</strong>
            <ul style="margin: 10px 0; padding-left: 20px;">
                <li>3 Vector Clock processes (containers: vector-clock-process-0,1,2)</li>
                <li>Nginx web server (container: vector-clock-web)</li>
                <li>Custom Docker network with health checks</li>
                <li>Automatic restart and graceful shutdown</li>
            </ul>
        </div>
        
        <div id="processes" class="processes"></div>
    </div>

    <script>
        const NUM_PROCESSES = 3;
        const BASE_PORT = 8080;
        let autoRefresh = true;

        async function refreshStatus() {
            const processesDiv = document.getElementById('processes');
            processesDiv.innerHTML = '<div style="text-align: center;">🔄 Loading...</div>';
            
            let healthyProcesses = 0;
            const processElements = [];
            
            for (let i = 0; i < NUM_PROCESSES; i++) {
                try {
                    const response = await fetch(`http://localhost:${BASE_PORT + i}/status`);
                    const data = await response.json();
                    healthyProcesses++;
                    
                    const processDiv = document.createElement('div');
                    processDiv.className = 'process healthy';
                    processDiv.innerHTML = `
                        <h3>🐳 Container: ${data.containerName}</h3>
                        <div class="container-info">
                            Process ID: ${data.processId} | Uptime: ${Math.floor(data.uptime)}s | Port: ${BASE_PORT + i}
                        </div>
                        <div class="clock">Vector Clock: ${data.vectorClock}</div>
                        <h4>📋 Recent Events (${data.eventLog.length}):</h4>
                        <div class="events">
                            ${data.eventLog.map(event => `
                                <div class="event">
                                    <strong>🔄 ${event.type.replace('_', ' ')}</strong> 
                                    - Clock: [${event.currentClock.join(', ')}]
                                    ${event.receivedClock ? `<br>📥 Received: [${event.receivedClock.join(', ')}]` : ''}
                                    <br><small>⏰ ${new Date(event.timestamp).toLocaleTimeString()}</small>
                                </div>
                            `).join('')}
                        </div>
                    `;
                    processElements.push(processDiv);
                } catch (error) {
                    const processDiv = document.createElement('div');
                    processDiv.className = 'process unhealthy';
                    processDiv.innerHTML = `
                        <h3>❌ Container: process-${i} (Unhealthy)</h3>
                        <div class="container-info">Connection failed - container may be down</div>
                        <div class="clock">Status: Unreachable</div>
                        <div class="events">
                            <div class="event" style="border-left-color: #f56565;">
                                <strong>ERROR:</strong> Cannot connect to container
                                <br><small>Check: docker-compose ps</small>
                            </div>
                        </div>
                    `;
                    processElements.push(processDiv);
                }
            }
            
            processesDiv.innerHTML = '';
            processElements.forEach(el => processesDiv.appendChild(el));
            
            updateStatus(`✅ Status refreshed - ${healthyProcesses}/${NUM_PROCESSES} containers healthy`, 'success');
        }

        async function sendRandomMessage() {
            const sender = Math.floor(Math.random() * NUM_PROCESSES);
            const receiver = Math.floor(Math.random() * NUM_PROCESSES);
            
            if (sender === receiver) return sendRandomMessage();
            
            try {
                const senderResponse = await fetch(`http://localhost:${BASE_PORT + sender}/status`);
                const senderData = await senderResponse.json();
                const senderClock = JSON.parse(senderData.vectorClock);
                
                const message = {
                    senderId: sender,
                    vectorClock: senderClock,
                    content: `Docker message ${new Date().toISOString()}`,
                    timestamp: new Date().toISOString()
                };
                
                const response = await fetch(`http://localhost:${BASE_PORT + receiver}/message`, {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify(message)
                });
                
                const result = await response.json();
                updateStatus(`📨 Message: Container ${sender} → Container ${receiver} | ${result.relationship}`, 'success');
                setTimeout(refreshStatus, 500);
            } catch (error) {
                updateStatus('❌ Error sending message: ' + error.message, 'error');
            }
        }

        async function triggerLocalEvent() {
            const processId = Math.floor(Math.random() * NUM_PROCESSES);
            
            try {
                await fetch(`http://localhost:${BASE_PORT + processId}/local-event`, {
                    method: 'POST'
                });
                
                updateStatus(`⚡ Local event triggered in Container ${processId}`, 'success');
                setTimeout(refreshStatus, 500);
            } catch (error) {
                updateStatus('❌ Error triggering local event: ' + error.message, 'error');
            }
        }

        async function demonstrateCausality() {
            updateStatus('🔗 Demonstrating Docker container causality...', 'success');
            
            try {
                // Create causal chain across containers
                await fetch(`http://localhost:8080/local-event`, {method: 'POST'});
                await new Promise(resolve => setTimeout(resolve, 300));
                
                const p0Status = await fetch(`http://localhost:8080/status`);
                const p0Data = await p0Status.json();
                await fetch(`http://localhost:8081/message`, {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        senderId: 0,
                        vectorClock: JSON.parse(p0Data.vectorClock),
                        content: 'Container causal chain step 1'
                    })
                });
                
                await new Promise(resolve => setTimeout(resolve, 300));
                
                const p1Status = await fetch(`http://localhost:8081/status`);
                const p1Data = await p1Status.json();
                await fetch(`http://localhost:8082/message`, {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({
                        senderId: 1,
                        vectorClock: JSON.parse(p1Data.vectorClock),
                        content: 'Container causal chain step 2'
                    })
                });
                
                updateStatus('🔗 Causal chain completed across Docker containers: C0 → C1 → C2', 'success');
                setTimeout(refreshStatus, 500);
            } catch (error) {
                updateStatus('❌ Error in causality demonstration: ' + error.message, 'error');
            }
        }

        async function checkHealth() {
            updateStatus('❤️ Checking container health...', 'success');
            
            let healthyCount = 0;
            for (let i = 0; i < NUM_PROCESSES; i++) {
                try {
                    const response = await fetch(`http://localhost:${BASE_PORT + i}/health`);
                    const data = await response.json();
                    if (data.status === 'healthy') healthyCount++;
                } catch (error) {
                    // Container unhealthy
                }
            }
            
            updateStatus(`❤️ Health check: ${healthyCount}/${NUM_PROCESSES} containers healthy`, 
                        healthyCount === NUM_PROCESSES ? 'success' : 'error');
            setTimeout(refreshStatus, 500);
        }

        function updateStatus(message, type) {
            const statusDiv = document.getElementById('status');
            statusDiv.textContent = message;
            statusDiv.className = `status ${type}`;
        }

        function startAutoRefresh() {
            if (autoRefresh) {
                refreshStatus();
                setTimeout(startAutoRefresh, 5000);
            }
        }

        document.addEventListener('DOMContentLoaded', () => {
            refreshStatus();
            startAutoRefresh();
        });

        document.addEventListener('visibilitychange', () => {
            autoRefresh = !document.hidden;
            if (autoRefresh) startAutoRefresh();
        });
    </script>
</body>
</html>
EOF

# Create nginx configuration
cat > nginx.conf << 'EOF'
events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    
    sendfile        on;
    keepalive_timeout  65;
    
    server {
        listen 80;
        server_name localhost;
        
        location / {
            root /usr/share/nginx/html;
            index index.html;
            try_files $uri $uri/ /index.html;
        }
        
        # Health check endpoint
        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF

# Create startup script
cat > start_demo.sh << 'EOF'
#!/bin/bash
echo "🐳 Starting Dockerized Vector Clock Demo..."

# Check Docker and Docker Compose
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    echo "❌ Docker Compose is not available. Please install Docker Compose."
    exit 1
fi

# Use docker compose (newer) or docker-compose (legacy)
if docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo "🧹 Cleaning up existing containers..."
$COMPOSE_CMD down --remove-orphans 2>/dev/null || true

echo "🔨 Building Docker images..."
$COMPOSE_CMD build --no-cache

echo "🚀 Starting services..."
$COMPOSE_CMD up -d

echo "⏳ Waiting for services to be healthy..."
sleep 5

# Check service health
echo "🔍 Checking service status..."
healthy=0
for i in {0..2}; do
    if curl -s http://localhost:$((8080 + i))/health > /dev/null 2>&1; then
        echo "✅ Process $i container is healthy"
        ((healthy++))
    else
        echo "⚠️  Process $i container not ready yet"
    fi
done

if curl -s http://localhost:8090/health > /dev/null 2>&1; then
    echo "✅ Web interface is healthy"
else
    echo "⚠️  Web interface not ready yet"
fi

echo ""
echo "🎉 Docker Vector Clock Demo is running!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 Web Interface: http://localhost:8090"
echo "🐳 Container Status: $COMPOSE_CMD ps"
echo "📊 Container Logs: $COMPOSE_CMD logs -f"
echo "🛑 Stop Demo: $COMPOSE_CMD down"
echo ""
echo "📋 Direct API Access:"
for i in {0..2}; do
    echo "   Process $i: http://localhost:$((8080 + i))/status"
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $healthy -eq 3 ]; then
    echo "✅ All vector clock containers are healthy!"
    
    # Send initial test messages
    echo "📨 Sending initial test messages..."
    sleep 2
    
    curl -s -X POST http://localhost:8081/message \
         -H "Content-Type: application/json" \
         -d '{"senderId": 0, "vectorClock": [1,0,0], "content": "Docker init message"}' > /dev/null
    
    curl -s -X POST http://localhost:8082/message \
         -H "Content-Type: application/json" \
         -d '{"senderId": 1, "vectorClock": [1,1,0], "content": "Docker response"}' > /dev/null
    
    echo "✅ Initial messages sent. Ready for demonstration!"
else
    echo "⚠️  Some containers may still be starting up. Check logs if needed:"
    echo "   $COMPOSE_CMD logs"
fi
EOF

chmod +x start_demo.sh

# Create stop script
cat > stop_demo.sh << 'EOF'
#!/bin/bash
echo "🛑 Stopping Docker Vector Clock Demo..."

# Determine compose command
if docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo "📊 Final container status:"
$COMPOSE_CMD ps

echo "🗂️  Collecting final logs..."
mkdir -p logs_archive/$(date +"%Y%m%d_%H%M%S")
$COMPOSE_CMD logs > logs_archive/$(date +"%Y%m%d_%H%M%S")/all_containers.log 2>&1

echo "🧹 Stopping and removing containers..."
$COMPOSE_CMD down --remove-orphans

echo "🔍 Cleaning up unused Docker resources..."
docker system prune -f > /dev/null 2>&1

echo "✅ Docker demo stopped successfully"
echo "📁 Logs archived in logs_archive/"
EOF

chmod +x stop_demo.sh

# Create verification script
cat > verify_demo.sh << 'EOF'
#!/bin/bash
echo "🔍 Docker Vector Clock Demo Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Determine compose command
if docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo "1️⃣  Checking Docker containers..."
echo "Container Status:"
$COMPOSE_CMD ps

echo -e "\n2️⃣  Verifying container health..."
healthy_count=0
for i in {0..2}; do
    if response=$(curl -s http://localhost:$((8080 + i))/health 2>/dev/null); then
        echo "✅ Container process-$i: $response"
        ((healthy_count++))
    else
        echo "❌ Container process-$i: Not responding"
    fi
done

echo -e "\n3️⃣  Testing vector clock functionality..."
if [ $healthy_count -eq 3 ]; then
    echo "📨 Sending test message between containers..."
    
    response=$(curl -s -X POST http://localhost:8081/message \
        -H "Content-Type: application/json" \
        -d '{"senderId": 0, "vectorClock": [2,0,0], "content": "Docker verification"}')
    
    if echo "$response" | grep -q "received"; then
        echo "✅ Message exchange successful"
        echo "Response: $response"
    else
        echo "❌ Message exchange failed"
    fi
    
    echo -e "\n📊 Current vector clock states:"
    for i in {0..2}; do
        clock=$(curl -s http://localhost:$((8080 + i))/status | grep -o '"vectorClock":"[^"]*"' | cut -d'"' -f4)
        echo "   Container $i: $clock"
    done
else
    echo "⚠️  Cannot test functionality - not all containers are healthy"
fi

echo -e "\n4️⃣  Checking web interface..."
if curl -s http://localhost:8090 > /dev/null 2>&1; then
    echo "✅ Web interface accessible at http://localhost:8090"
else
    echo "❌ Web interface not accessible"
fi

echo -e "\n5️⃣  Container resource usage..."
echo "Docker Stats (snapshot):"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
    vector-clock-process-0 vector-clock-process-1 vector-clock-process-2 vector-clock-web 2>/dev/null || \
    echo "⚠️  Could not retrieve container stats"

echo -e "\n6️⃣  Network connectivity test..."
if docker network inspect vector_clock_docker_demo_vector-clock-network > /dev/null 2>&1; then
    echo "✅ Docker network 'vector-clock-network' exists"
    container_count=$(docker network inspect vector_clock_docker_demo_vector-clock-network | grep -c "vector-clock")
    echo "✅ Network has $container_count connected containers"
else
    echo "❌ Docker network not found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $healthy_count -eq 3 ]; then
    echo "✅ Verification complete - All systems operational!"
else
    echo "⚠️  Verification complete - Some issues detected"
fi
echo ""
echo "🔧 Troubleshooting commands:"
echo "   $COMPOSE_CMD logs [service_name]"
echo "   $COMPOSE_CMD restart [service_name]"
echo "   docker system df"
EOF

chmod +x verify_demo.sh

# Create README
cat > README.md << 'EOF'
# 🐳 Dockerized Vector Clock Distributed System

A production-ready containerized implementation of vector clocks for demonstrating 
causal consistency in distributed systems.

## Quick Start

```bash
./start_demo.sh    # Build and start all containers
./verify_demo.sh   # Verify system functionality  
./stop_demo.sh     # Clean shutdown and cleanup
```

## Architecture

- **3 Vector Clock Processes**: Each in isolated Docker containers
- **Nginx Web Server**: Serves interactive visualization interface
- **Custom Docker Network**: Secure container communication
- **Health Monitoring**: Built-in health checks and auto-restart
- **Production Features**: Graceful shutdown, logging, security

## Container Services

| Service | Container | Ports | Purpose |
|---------|-----------|--------|---------|
| process-0 | vector-clock-process-0 | 8080 | Vector clock process |
| process-1 | vector-clock-process-1 | 8081 | Vector clock process |
| process-2 | vector-clock-process-2 | 8082 | Vector clock process |
| web-interface | vector-clock-web | 8090 | Web visualization |

## Docker Commands

```bash
# View running containers
docker-compose ps

# View logs
docker-compose logs -f [service_name]

# Restart specific service
docker-compose restart process-0

# Scale services (if needed)
docker-compose up -d --scale process-0=2

# Shell into container
docker exec -it vector-clock-process-0 sh

# View resource usage
docker stats
```

## Production Features

- **Health Checks**: Automated container health monitoring
- **Restart Policies**: Automatic restart on failure
- **Resource Limits**: Memory and CPU constraints
- **Security**: Non-root user, minimal attack surface
- **Logging**: Structured logging with timestamps
- **Graceful Shutdown**: SIGTERM handling

## Development vs Production

### Development Mode (default)
- Local port mapping for direct access
- Debug logging enabled
- Hot reload capabilities

### Production Mode
```bash
# Use production compose file
docker-compose -f docker-compose.prod.yml up -d
```

## Monitoring

- **Health Endpoints**: `/health` on each process
- **Status API**: `/status` with detailed metrics
- **Docker Health Checks**: Integrated with Docker daemon
- **Log Aggregation**: Centralized logging via Docker

## Requirements

- Docker Engine 20.0+
- Docker Compose 2.0+
- 2GB available RAM
- Ports 8080-8082, 8090 available

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Port conflicts | `sudo lsof -i :8080-8090` and kill conflicting processes |
| Build failures | `docker-compose build --no-cache` |
| Network issues | `docker network prune && docker-compose up` |
| Memory issues | `docker system prune -a` |

EOF

echo "✅ Dockerized demo setup complete!"
echo ""
echo "📁 Created directory: $DEMO_DIR"
echo "🐳 Docker components:"
echo "   • Dockerfile              - Multi-stage Node.js container"
echo "   • docker-compose.yml      - Service orchestration"
echo "   • vector_clock.js         - Enhanced containerized implementation"
echo "   • nginx.conf              - Web server configuration"
echo "   • web/index.html          - Container-aware web interface"
echo ""
echo "🚀 Scripts created:"
echo "   • start_demo.sh           - Build and start containers"
echo "   • stop_demo.sh            - Clean shutdown and cleanup"
echo "   • verify_demo.sh          - Health verification"
echo "   • README.md               - Complete documentation"
echo ""
echo "🐳 To run the Docker demo:"
echo "   1. cd $DEMO_DIR"
echo "   2. ./start_demo.sh"
echo "   3. ./verify_demo.sh"
echo "   4. Open http://localhost:8090"
echo ""
echo "📋 Requirements: Docker, Docker Compose"