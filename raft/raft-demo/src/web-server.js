const express = require('express');
const WebSocket = require('ws');
const path = require('path');
const RaftCluster = require('./cluster');

const app = express();
const port = process.env.PORT || 3000;

// Serve static files
app.use(express.static(path.join(__dirname, '../public')));
app.use(express.json());

// Create Raft cluster
const cluster = new RaftCluster(5);

// WebSocket server
const server = require('http').createServer(app);
const wss = new WebSocket.Server({ server });

// Broadcast to all connected clients
function broadcast(data) {
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify(data));
        }
    });
}

// Forward cluster events to web clients
cluster.on('stateChange', (data) => {
    broadcast({ type: 'stateChange', data });
});

cluster.on('log', (data) => {
    broadcast({ type: 'log', data });
});

cluster.on('logEntry', (data) => {
    broadcast({ type: 'logEntry', data });
});

cluster.on('partition', (data) => {
    broadcast({ type: 'partition', data });
});

cluster.on('reconnect', (data) => {
    broadcast({ type: 'reconnect', data });
});

// API endpoints
app.get('/api/status', (req, res) => {
    res.json(cluster.getStatus());
});

app.post('/api/entry', (req, res) => {
    const { data } = req.body;
    const success = cluster.addEntry(data);
    res.json({ success });
});

app.post('/api/partition/:nodeId', (req, res) => {
    const nodeId = parseInt(req.params.nodeId);
    cluster.partitionNode(nodeId);
    res.json({ success: true });
});

app.post('/api/reconnect/:nodeId', (req, res) => {
    const nodeId = parseInt(req.params.nodeId);
    cluster.reconnectNode(nodeId);
    res.json({ success: true });
});

// WebSocket connection handling
wss.on('connection', (ws) => {
    console.log('Client connected');
    
    // Send initial status
    ws.send(JSON.stringify({
        type: 'status',
        data: cluster.getStatus()
    }));
    
    ws.on('close', () => {
        console.log('Client disconnected');
    });
});

// Graceful shutdown
process.on('SIGINT', () => {
    console.log('\nShutting down Raft cluster...');
    cluster.stop();
    process.exit(0);
});

server.listen(port, () => {
    console.log(`Raft demo server running at http://localhost:${port}`);
});
