const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const axios = require('axios');
const path = require('path');

const app = express();
const server = http.createServer(app);
const io = socketIo(server);

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Store active alerts
let activeAlerts = [];
let alertHistory = [];

// Webhook endpoints for AlertManager
app.post('/webhook/alerts', (req, res) => {
    console.log('Received alerts:', req.body);
    res.status(200).send('OK');
});

app.post('/webhook/critical', (req, res) => {
    const alert = {
        id: Date.now(),
        severity: 'critical',
        timestamp: new Date(),
        message: req.body.title || 'Critical Alert',
        tier: 1
    };
    
    activeAlerts.push(alert);
    alertHistory.push(alert);
    
    // Broadcast to all connected clients
    io.emit('newAlert', alert);
    
    console.log('Critical alert:', alert);
    res.status(200).send('OK');
});

app.post('/webhook/warning', (req, res) => {
    const alert = {
        id: Date.now(),
        severity: 'warning', 
        timestamp: new Date(),
        message: req.body.title || 'Warning Alert',
        tier: 2
    };
    
    activeAlerts.push(alert);
    alertHistory.push(alert);
    
    io.emit('newAlert', alert);
    
    console.log('Warning alert:', alert);
    res.status(200).send('OK');
});

// API endpoints
app.get('/api/alerts/active', (req, res) => {
    res.json(activeAlerts);
});

app.get('/api/alerts/history', (req, res) => {
    res.json(alertHistory.slice(-50)); // Last 50 alerts
});

app.get('/api/metrics/summary', async (req, res) => {
    try {
        // Fetch metrics from Prometheus
        const response = await axios.get('http://prometheus:9090/api/v1/query_range', {
            params: {
                query: 'up',
                start: Math.floor(Date.now() / 1000) - 3600,
                end: Math.floor(Date.now() / 1000),
                step: 60
            }
        });
        
        res.json(response.data);
    } catch (error) {
        console.error('Error fetching metrics:', error.message);
        res.status(500).json({ error: 'Failed to fetch metrics' });
    }
});

// Socket.io connection handling
io.on('connection', (socket) => {
    console.log('Client connected');
    
    // Send current active alerts to new client
    socket.emit('activeAlerts', activeAlerts);
    
    socket.on('disconnect', () => {
        console.log('Client disconnected');
    });
});

const PORT = process.env.PORT || 8080;
server.listen(PORT, '0.0.0.0', () => {
    console.log(`Dashboard server running on port ${PORT}`);
});
