const express = require('express');
const redis = require('redis');
const WebSocket = require('ws');
const cors = require('cors');
const path = require('path');

class AvailabilityServer {
    constructor(port, mode, nodeId) {
        this.app = express();
        this.port = port;
        this.mode = mode; // 'active-passive' or 'active-active'
        this.nodeId = nodeId;
        this.isActive = true;
        this.startTime = Date.now();
        this.requestCount = 0;
        this.lastHealthCheck = Date.now();
        
        this.setupMiddleware();
        this.setupRoutes();
        this.setupRedis();
        this.setupWebSocket();
    }
    
    setupMiddleware() {
        this.app.use(cors());
        this.app.use(express.json());
        this.app.use(express.static(path.join(__dirname, '../dashboard')));
    }
    
    setupRoutes() {
        // Health check endpoint
        this.app.get('/health', (req, res) => {
            this.lastHealthCheck = Date.now();
            const health = {
                status: this.isActive ? 'healthy' : 'unhealthy',
                nodeId: this.nodeId,
                mode: this.mode,
                uptime: Date.now() - this.startTime,
                requestCount: this.requestCount,
                timestamp: new Date().toISOString()
            };
            res.json(health);
        });
        
        // Main service endpoint
        this.app.get('/api/service', async (req, res) => {
            this.requestCount++;
            
            if (!this.isActive) {
                return res.status(503).json({ 
                    error: 'Service unavailable',
                    nodeId: this.nodeId 
                });
            }
            
            // Simulate processing time
            await new Promise(resolve => setTimeout(resolve, 10));
            
            const response = {
                message: 'Service response',
                nodeId: this.nodeId,
                mode: this.mode,
                timestamp: new Date().toISOString(),
                requestNumber: this.requestCount
            };
            
            // Store request in Redis for demonstration
            if (this.redisClient) {
                try {
                    await this.redisClient.incr(`requests:${this.nodeId}`);
                    await this.redisClient.set(`lastRequest:${this.nodeId}`, JSON.stringify(response));
                } catch (err) {
                    console.error('Redis error:', err.message);
                }
            }
            
            res.json(response);
        });
        
        // Failure simulation endpoint
        this.app.post('/api/simulate-failure', (req, res) => {
            this.isActive = false;
            console.log(`🔴 Node ${this.nodeId} simulating failure`);
            res.json({ 
                message: 'Failure simulated',
                nodeId: this.nodeId,
                timestamp: new Date().toISOString()
            });
            
            // Auto-recover after 30 seconds
            setTimeout(() => {
                this.isActive = true;
                console.log(`🟢 Node ${this.nodeId} recovered`);
            }, 30000);
        });
        
        // Recovery endpoint
        this.app.post('/api/recover', (req, res) => {
            this.isActive = true;
            console.log(`🟢 Node ${this.nodeId} manually recovered`);
            res.json({ 
                message: 'Node recovered',
                nodeId: this.nodeId,
                timestamp: new Date().toISOString()
            });
        });
        
        // Metrics endpoint
        this.app.get('/api/metrics', async (req, res) => {
            const metrics = {
                nodeId: this.nodeId,
                mode: this.mode,
                isActive: this.isActive,
                uptime: Date.now() - this.startTime,
                requestCount: this.requestCount,
                lastHealthCheck: this.lastHealthCheck,
                timestamp: new Date().toISOString()
            };
            
            if (this.redisClient) {
                try {
                    const redisRequests = await this.redisClient.get(`requests:${this.nodeId}`);
                    metrics.redisRequestCount = parseInt(redisRequests) || 0;
                } catch (err) {
                    metrics.redisError = err.message;
                }
            }
            
            res.json(metrics);
        });
    }
    
    async setupRedis() {
        try {
            this.redisClient = redis.createClient({
                url: 'redis://redis:6379'
            });
            
            await this.redisClient.connect();
            console.log(`📊 Node ${this.nodeId} connected to Redis`);
        } catch (err) {
            console.error(`❌ Redis connection failed for node ${this.nodeId}:`, err.message);
        }
    }
    
    setupWebSocket() {
        this.wss = new WebSocket.Server({ port: parseInt(this.port) + 1000 });
        
        this.wss.on('connection', (ws) => {
            console.log(`🔌 WebSocket client connected to node ${this.nodeId}`);
            
            // Send periodic status updates
            const interval = setInterval(() => {
                if (ws.readyState === WebSocket.OPEN) {
                    ws.send(JSON.stringify({
                        type: 'status',
                        nodeId: this.nodeId,
                        isActive: this.isActive,
                        requestCount: this.requestCount,
                        timestamp: new Date().toISOString()
                    }));
                }
            }, 1000);
            
            ws.on('close', () => {
                clearInterval(interval);
            });
        });
    }
    
    start() {
        this.app.listen(this.port, () => {
            console.log(`🚀 ${this.mode} node ${this.nodeId} running on port ${this.port}`);
            console.log(`   Health: http://localhost:${this.port}/health`);
            console.log(`   Service: http://localhost:${this.port}/api/service`);
            console.log(`   WebSocket: ws://localhost:${parseInt(this.port) + 1000}`);
        });
    }
}

// Start server based on environment variables
const PORT = process.env.PORT || 3000;
const MODE = process.env.MODE || 'active-passive';
const NODE_ID = process.env.NODE_ID || 'node-1';

const server = new AvailabilityServer(PORT, MODE, NODE_ID);
server.start();
