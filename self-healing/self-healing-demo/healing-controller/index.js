const express = require('express');
const cors = require('cors');
const axios = require('axios');
const WebSocket = require('ws');
const Docker = require('dockerode');

const app = express();
const PORT = process.env.CONTROLLER_PORT || 3000;
const docker = new Docker();

app.use(cors());
app.use(express.json());

// WebSocket server for real-time updates
const wss = new WebSocket.Server({ port: 8080 });

// Service registry
const services = [
    { name: 'user-service', url: 'http://user-service:3000', container: 'self-healing-demo-user-service-1' },
    { name: 'order-service', url: 'http://order-service:3000', container: 'self-healing-demo-order-service-1' },
    { name: 'payment-service', url: 'http://payment-service:3000', container: 'self-healing-demo-payment-service-1' }
];

// Healing state
const healingState = {
    services: {},
    healingAttempts: {},
    healingHistory: []
};

// Initialize service states
services.forEach(service => {
    healingState.services[service.name] = {
        status: 'unknown',
        lastCheck: null,
        consecutiveFailures: 0,
        healingInProgress: false,
        metrics: {}
    };
    healingState.healingAttempts[service.name] = 0;
});

// Broadcast state to all connected clients
function broadcastState() {
    const message = JSON.stringify({
        type: 'state-update',
        data: healingState
    });
    
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(message);
        }
    });
}

// Health check function
async function checkServiceHealth(service) {
    try {
        const response = await axios.get(`${service.url}/health`, { timeout: 5000 });
        return {
            healthy: response.status === 200,
            data: response.data
        };
    } catch (error) {
        return {
            healthy: false,
            error: error.message
        };
    }
}

// Healing actions
async function healService(service) {
    const serviceName = service.name;
    const serviceState = healingState.services[serviceName];
    
    if (serviceState.healingInProgress) {
        console.log(`${serviceName}: Healing already in progress`);
        return;
    }
    
    serviceState.healingInProgress = true;
    healingState.healingAttempts[serviceName]++;
    
    const healingEvent = {
        timestamp: new Date().toISOString(),
        service: serviceName,
        action: 'restart',
        attempt: healingState.healingAttempts[serviceName]
    };
    
    console.log(`${serviceName}: Starting healing process (attempt ${healingState.healingAttempts[serviceName]})`);
    
    try {
        // Try gentle recovery first
        try {
            await axios.post(`${service.url}/recover`, {}, { timeout: 3000 });
            console.log(`${serviceName}: Gentle recovery attempted`);
            healingEvent.action = 'gentle-recovery';
        } catch (error) {
            console.log(`${serviceName}: Gentle recovery failed, attempting container restart`);
            
            // Container restart
            const container = docker.getContainer(service.container);
            await container.restart();
            console.log(`${serviceName}: Container restarted`);
            healingEvent.action = 'container-restart';
        }
        
        // Wait for service to come back up
        await new Promise(resolve => setTimeout(resolve, 10000));
        
        // Verify healing success
        const healthCheck = await checkServiceHealth(service);
        if (healthCheck.healthy) {
            serviceState.consecutiveFailures = 0;
            healingEvent.result = 'success';
            console.log(`${serviceName}: Healing successful`);
        } else {
            healingEvent.result = 'failed';
            console.log(`${serviceName}: Healing failed`);
        }
        
    } catch (error) {
        console.error(`${serviceName}: Healing error:`, error.message);
        healingEvent.result = 'error';
        healingEvent.error = error.message;
    }
    
    serviceState.healingInProgress = false;
    healingState.healingHistory.push(healingEvent);
    
    // Keep only last 50 healing events
    if (healingState.healingHistory.length > 50) {
        healingState.healingHistory = healingState.healingHistory.slice(-50);
    }
    
    broadcastState();
}

// Main monitoring loop
async function monitorServices() {
    for (const service of services) {
        const serviceName = service.name;
        const serviceState = healingState.services[serviceName];
        
        try {
            const healthCheck = await checkServiceHealth(service);
            serviceState.lastCheck = new Date().toISOString();
            
            if (healthCheck.healthy) {
                serviceState.status = 'healthy';
                serviceState.consecutiveFailures = 0;
                serviceState.metrics = healthCheck.data?.metrics || {};
            } else {
                serviceState.status = 'unhealthy';
                serviceState.consecutiveFailures++;
                
                // Trigger healing after 2 consecutive failures
                if (serviceState.consecutiveFailures >= 2 && !serviceState.healingInProgress) {
                    console.log(`${serviceName}: Triggering healing after ${serviceState.consecutiveFailures} failures`);
                    healService(service);
                }
            }
        } catch (error) {
            serviceState.status = 'error';
            serviceState.consecutiveFailures++;
            console.error(`${serviceName}: Health check error:`, error.message);
        }
    }
    
    broadcastState();
}

// API endpoints
app.get('/health', (req, res) => {
    res.json({
        controller: 'healthy',
        timestamp: new Date().toISOString()
    });
});

app.get('/services', (req, res) => {
    res.json(healingState);
});

app.post('/heal/:serviceName', async (req, res) => {
    const serviceName = req.params.serviceName;
    const service = services.find(s => s.name === serviceName);
    
    if (!service) {
        return res.status(404).json({ error: 'Service not found' });
    }
    
    healService(service);
    res.json({ message: `Healing triggered for ${serviceName}` });
});

app.post('/simulate/:serviceName/:type', async (req, res) => {
    const { serviceName, type } = req.params;
    const service = services.find(s => s.name === serviceName);
    
    if (!service) {
        return res.status(404).json({ error: 'Service not found' });
    }
    
    try {
        await axios.post(`${service.url}/simulate/${type}`);
        res.json({ message: `${type} simulation triggered for ${serviceName}` });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// WebSocket connection handling
wss.on('connection', (ws) => {
    console.log('Dashboard connected');
    ws.send(JSON.stringify({
        type: 'initial-state',
        data: healingState
    }));
});

// Start monitoring
setInterval(monitorServices, 10000); // Check every 10 seconds

app.listen(PORT, () => {
    console.log(`Healing Controller running on port ${PORT}`);
    console.log('WebSocket server running on port 8080');
    
    // Initial health check
    setTimeout(monitorServices, 5000);
});
