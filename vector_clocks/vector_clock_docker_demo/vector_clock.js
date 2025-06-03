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
