const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const axios = require('axios');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

const CONSUL_HOST = process.env.CONSUL_HOST || 'localhost';
const CONSUL_URL = `http://${CONSUL_HOST}:8500`;

// Serve static files
app.use(express.static(path.join(__dirname, 'public')));

// API endpoint to get service discovery data
app.get('/api/services', async (req, res) => {
    try {
        const response = await axios.get(`${CONSUL_URL}/v1/agent/services`);
        const services = response.data;
        
        // Get health status for each service
        const servicesWithHealth = await Promise.all(
            Object.entries(services).map(async ([id, service]) => {
                try {
                    const healthResponse = await axios.get(
                        `${CONSUL_URL}/v1/health/service/${service.Service}?passing=true`
                    );
                    return {
                        id: service.ID,
                        name: service.Service,
                        address: service.Address,
                        port: service.Port,
                        tags: service.Tags,
                        health: healthResponse.data.length > 0 ? 'healthy' : 'unhealthy'
                    };
                } catch (error) {
                    return {
                        id: service.ID,
                        name: service.Service,
                        address: service.Address,
                        port: service.Port,
                        tags: service.Tags,
                        health: 'unknown'
                    };
                }
            })
        );
        
        res.json(servicesWithHealth);
    } catch (error) {
        console.error('Error fetching services:', error.message);
        res.status(500).json({ error: 'Failed to fetch services' });
    }
});

// WebSocket for real-time updates
wss.on('connection', (ws) => {
    console.log('Client connected to dashboard');
    
    // Send initial data
    const sendServicesUpdate = async () => {
        try {
            const response = await axios.get('http://localhost:3000/api/services');
            ws.send(JSON.stringify({
                type: 'services_update',
                data: response.data
            }));
        } catch (error) {
            console.error('Error sending update:', error.message);
        }
    };
    
    // Send updates every 5 seconds
    const interval = setInterval(sendServicesUpdate, 5000);
    sendServicesUpdate(); // Send initial update
    
    ws.on('close', () => {
        console.log('Client disconnected');
        clearInterval(interval);
    });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`Dashboard server running on port ${PORT}`);
});
