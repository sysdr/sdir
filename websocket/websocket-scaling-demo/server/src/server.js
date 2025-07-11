const WebSocket = require('ws');
const express = require('express');
const http = require('http');
const redis = require('redis');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');
const compression = require('compression');
const helmet = require('helmet');
const cluster = require('cluster');
const os = require('os');

// Configuration
const CONFIG = {
    port: process.env.PORT || 8080,
    redisUrl: process.env.REDIS_URL || 'redis://redis:6379',
    maxConnections: parseInt(process.env.MAX_CONNECTIONS) || 10000,
    heartbeatInterval: 30000,
    messageBufferSize: 1000,
    compressionEnabled: true
};

class ScalableWebSocketServer {
    constructor(config) {
        this.config = config;
        this.connections = new Map();
        this.messageBuffer = [];
        this.metrics = {
            connectionsActive: 0,
            messagesProcessed: 0,
            memoryUsage: 0,
            startTime: Date.now()
        };
        
        this.initializeRedis();
        this.initializeServer();
        this.initializeWebSocket();
        this.startMetricsCollection();
    }
    
    async initializeRedis() {
        try {
            this.redisClient = redis.createClient({ url: this.config.redisUrl });
            this.redisSubscriber = this.redisClient.duplicate();
            
            await this.redisClient.connect();
            await this.redisSubscriber.connect();
            
            // Subscribe to cross-server messages
            await this.redisSubscriber.subscribe('websocket:broadcast', (message) => {
                this.handleCrossServerMessage(JSON.parse(message));
            });
            
            console.log('✅ Redis connection established');
        } catch (error) {
            console.error('❌ Redis connection failed:', error.message);
            process.exit(1);
        }
    }
    
    initializeServer() {
        this.app = express();
        
        // Security and performance middleware
        this.app.use(helmet());
        this.app.use(cors());
        this.app.use(compression());
        this.app.use(express.json());
        
        // Health check endpoint
        this.app.get('/health', (req, res) => {
            res.json({
                status: 'healthy',
                connections: this.metrics.connectionsActive,
                uptime: Date.now() - this.metrics.startTime,
                memory: process.memoryUsage(),
                pid: process.pid
            });
        });
        
        // Metrics endpoint (JSON format)
        this.app.get('/metrics', (req, res) => {
            res.json({
                ...this.metrics,
                memory: process.memoryUsage(),
                connections: this.connections.size,
                pid: process.pid
            });
        });

        // Prometheus metrics endpoint
        this.app.get('/prometheus', (req, res) => {
            const memory = process.memoryUsage();
            const uptime = Date.now() - this.metrics.startTime;
            
            const prometheusMetrics = `# HELP websocket_connections_active Number of active WebSocket connections
# TYPE websocket_connections_active gauge
websocket_connections_active ${this.metrics.connectionsActive}

# HELP websocket_messages_processed_total Total number of messages processed
# TYPE websocket_messages_processed_total counter
websocket_messages_processed_total ${this.metrics.messagesProcessed}

# HELP websocket_memory_usage_bytes Memory usage in bytes
# TYPE websocket_memory_usage_bytes gauge
websocket_memory_usage_bytes{type="rss"} ${memory.rss}
websocket_memory_usage_bytes{type="heapTotal"} ${memory.heapTotal}
websocket_memory_usage_bytes{type="heapUsed"} ${memory.heapUsed}
websocket_memory_usage_bytes{type="external"} ${memory.external}

# HELP websocket_uptime_seconds Server uptime in seconds
# TYPE websocket_uptime_seconds gauge
websocket_uptime_seconds ${uptime / 1000}

# HELP websocket_server_info Server information
# TYPE websocket_server_info gauge
websocket_server_info{pid="${process.pid}",port="${this.config.port}"} 1
`;
            
            res.set('Content-Type', 'text/plain; version=0.0.4; charset=utf-8');
            res.send(prometheusMetrics);
        });
        
        // Connection info endpoint
        this.app.get('/connections', (req, res) => {
            const connectionInfo = Array.from(this.connections.entries()).map(([id, conn]) => ({
                id,
                connected: conn.socket.readyState === WebSocket.OPEN,
                lastPing: conn.lastPing,
                messageCount: conn.messageCount
            }));
            
            res.json({
                total: connectionInfo.length,
                connections: connectionInfo.slice(0, 100) // Limit response size
            });
        });
        
        this.server = http.createServer(this.app);
    }
    
    initializeWebSocket() {
        this.wss = new WebSocket.Server({ 
            server: this.server,
            perMessageDeflate: this.config.compressionEnabled,
            maxPayload: 16 * 1024 // 16KB max message size
        });
        
        this.wss.on('connection', (socket, request) => {
            this.handleNewConnection(socket, request);
        });
        
        console.log('✅ WebSocket server initialized');
    }
    
    handleNewConnection(socket, request) {
        // Check connection limits
        if (this.connections.size >= this.config.maxConnections) {
            socket.close(1013, 'Server at capacity');
            return;
        }
        
        const connectionId = uuidv4();
        const clientIP = request.headers['x-forwarded-for'] || request.connection.remoteAddress;
        
        const connectionData = {
            id: connectionId,
            socket,
            lastPing: Date.now(),
            messageCount: 0,
            clientIP,
            connectedAt: Date.now()
        };
        
        this.connections.set(connectionId, connectionData);
        this.metrics.connectionsActive++;
        
        console.log(`🔗 New connection: ${connectionId} from ${clientIP} (Total: ${this.connections.size})`);
        
        // Send welcome message
        this.sendMessage(socket, {
            type: 'welcome',
            connectionId,
            serverInfo: {
                pid: process.pid,
                totalConnections: this.connections.size
            }
        });
        
        // Set up event handlers
        socket.on('message', (data) => {
            this.handleMessage(connectionId, data);
        });
        
        socket.on('close', () => {
            this.handleDisconnection(connectionId);
        });
        
        socket.on('pong', () => {
            if (this.connections.has(connectionId)) {
                this.connections.get(connectionId).lastPing = Date.now();
            }
        });
        
        // Start heartbeat for this connection
        this.startHeartbeat(connectionId);
    }
    
    handleMessage(connectionId, data) {
        try {
            const connection = this.connections.get(connectionId);
            if (!connection) return;
            
            const message = JSON.parse(data.toString());
            connection.messageCount++;
            this.metrics.messagesProcessed++;
            
            console.log(`📨 Message from ${connectionId}: ${message.type}`);
            
            switch (message.type) {
                case 'ping':
                    this.sendMessage(connection.socket, { type: 'pong', timestamp: Date.now() });
                    break;
                    
                case 'broadcast':
                    this.handleBroadcast(connectionId, message);
                    break;
                    
                case 'join_room':
                    this.handleJoinRoom(connectionId, message.room);
                    break;
                    
                case 'leave_room':
                    this.handleLeaveRoom(connectionId, message.room);
                    break;
                    
                case 'room_message':
                    this.handleRoomMessage(connectionId, message);
                    break;
                    
                default:
                    console.log(`❓ Unknown message type: ${message.type}`);
            }
        } catch (error) {
            console.error(`❌ Error handling message from ${connectionId}:`, error.message);
        }
    }
    
    async handleBroadcast(senderId, message) {
        const broadcastData = {
            type: 'broadcast',
            from: senderId,
            message: message.content,
            timestamp: Date.now(),
            serverId: process.pid
        };
        
        // Broadcast to local connections
        this.broadcastToLocal(broadcastData);
        
        // Broadcast to other servers via Redis
        await this.redisClient.publish('websocket:broadcast', JSON.stringify(broadcastData));
    }
    
    async handleJoinRoom(connectionId, room) {
        const connection = this.connections.get(connectionId);
        if (!connection) return;
        
        // Store room membership in Redis
        await this.redisClient.sAdd(`room:${room}`, connectionId);
        await this.redisClient.hSet(`connection:${connectionId}`, 'room', room);
        
        this.sendMessage(connection.socket, {
            type: 'room_joined',
            room,
            timestamp: Date.now()
        });
        
        console.log(`🏠 ${connectionId} joined room: ${room}`);
    }
    
    async handleLeaveRoom(connectionId, room) {
        const connection = this.connections.get(connectionId);
        if (!connection) return;
        
        // Remove room membership from Redis
        await this.redisClient.sRem(`room:${room}`, connectionId);
        await this.redisClient.hDel(`connection:${connectionId}`, 'room');
        
        this.sendMessage(connection.socket, {
            type: 'room_left',
            room,
            timestamp: Date.now()
        });
        
        console.log(`🚪 ${connectionId} left room: ${room}`);
    }
    
    async handleRoomMessage(senderId, message) {
        const { room, content } = message;
        
        // Get all members of the room
        const roomMembers = await this.redisClient.sMembers(`room:${room}`);
        
        const roomMessage = {
            type: 'room_message',
            room,
            from: senderId,
            content,
            timestamp: Date.now()
        };
        
        // Send to local connections in the room
        roomMembers.forEach(memberId => {
            const connection = this.connections.get(memberId);
            if (connection) {
                this.sendMessage(connection.socket, roomMessage);
            }
        });
        
        // Broadcast to other servers for cross-server room messaging
        await this.redisClient.publish('websocket:room_message', JSON.stringify({
            ...roomMessage,
            roomMembers
        }));
    }
    
    handleCrossServerMessage(message) {
        if (message.serverId === process.pid) return; // Ignore our own messages
        
        console.log(`📡 Cross-server message: ${message.type}`);
        this.broadcastToLocal(message);
    }
    
    broadcastToLocal(message) {
        let sentCount = 0;
        this.connections.forEach((connection) => {
            if (connection.socket.readyState === WebSocket.OPEN) {
                this.sendMessage(connection.socket, message);
                sentCount++;
            }
        });
        console.log(`📢 Broadcasted to ${sentCount} local connections`);
    }
    
    sendMessage(socket, message) {
        if (socket.readyState === WebSocket.OPEN) {
            socket.send(JSON.stringify(message));
        }
    }
    
    startHeartbeat(connectionId) {
        const interval = setInterval(() => {
            const connection = this.connections.get(connectionId);
            if (!connection) {
                clearInterval(interval);
                return;
            }
            
            const now = Date.now();
            if (now - connection.lastPing > this.config.heartbeatInterval * 2) {
                console.log(`💔 Connection ${connectionId} timed out`);
                connection.socket.terminate();
                this.handleDisconnection(connectionId);
                clearInterval(interval);
                return;
            }
            
            if (connection.socket.readyState === WebSocket.OPEN) {
                connection.socket.ping();
            }
        }, this.config.heartbeatInterval);
    }
    
    async handleDisconnection(connectionId) {
        const connection = this.connections.get(connectionId);
        if (!connection) return;
        
        // Clean up Redis data
        const room = await this.redisClient.hGet(`connection:${connectionId}`, 'room');
        if (room) {
            await this.redisClient.sRem(`room:${room}`, connectionId);
        }
        await this.redisClient.del(`connection:${connectionId}`);
        
        this.connections.delete(connectionId);
        this.metrics.connectionsActive--;
        
        console.log(`🔌 Disconnected: ${connectionId} (Total: ${this.connections.size})`);
    }
    
    startMetricsCollection() {
        setInterval(() => {
            this.metrics.memoryUsage = process.memoryUsage().heapUsed;
            
            // Clean up dead connections
            this.connections.forEach((connection, id) => {
                if (connection.socket.readyState !== WebSocket.OPEN) {
                    this.handleDisconnection(id);
                }
            });
        }, 10000); // Every 10 seconds
    }
    
    start() {
        this.server.listen(this.config.port, () => {
            console.log(`🚀 WebSocket server running on port ${this.config.port}`);
            console.log(`📊 Max connections: ${this.config.maxConnections}`);
            console.log(`💓 Heartbeat interval: ${this.config.heartbeatInterval}ms`);
        });
    }
}

// Cluster setup for better performance
if (cluster.isMaster && process.env.NODE_ENV === 'production') {
    const numWorkers = os.cpus().length;
    
    console.log(`🎯 Master process ${process.pid} starting ${numWorkers} workers`);
    
    for (let i = 0; i < numWorkers; i++) {
        cluster.fork();
    }
    
    cluster.on('exit', (worker, code, signal) => {
        console.log(`💀 Worker ${worker.process.pid} died. Starting new worker...`);
        cluster.fork();
    });
} else {
    // Start the server
    const server = new ScalableWebSocketServer(CONFIG);
    server.start();
}
