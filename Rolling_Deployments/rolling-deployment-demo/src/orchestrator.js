const express = require('express');
const axios = require('axios');
const WebSocket = require('ws');

const app = express();
const PORT = 8080;

app.use(express.json());
app.use(express.static('web'));

// Service instances configuration
let instances = [
    { id: 'app-1', url: 'http://app-1:3000', healthy: true, version: 'v1.0', targetVersion: 'v1.0' },
    { id: 'app-2', url: 'http://app-2:3000', healthy: true, version: 'v1.0', targetVersion: 'v1.0' },
    { id: 'app-3', url: 'http://app-3:3000', healthy: true, version: 'v1.0', targetVersion: 'v1.0' }
];

// WebSocket server for real-time updates
const wss = new WebSocket.Server({ port: 8081 });

function broadcast(data) {
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            client.send(JSON.stringify(data));
        }
    });
}

// Health checking
async function checkHealth() {
    for (let instance of instances) {
        try {
            const response = await axios.get(`${instance.url}/health`, { timeout: 5000 });
            instance.healthy = response.status === 200;
            // Only update version from health check if not in deployment
            if (!instance.updating && instance.targetVersion === instance.version) {
                instance.version = response.data.version;
            }
            instance.uptime = response.data.uptime;
            instance.requests = response.data.requests;
        } catch (error) {
            instance.healthy = false;
            console.log(`Health check failed for ${instance.id}: ${error.message}`);
        }
    }
    
    broadcast({ type: 'health', instances });
}

// Load balancer - round robin among healthy instances
let currentIndex = 0;
app.get('/api/data', async (req, res) => {
    const healthyInstances = instances.filter(i => i.healthy);
    
    if (healthyInstances.length === 0) {
        return res.status(503).json({ error: 'No healthy instances available' });
    }
    
    const instance = healthyInstances[currentIndex % healthyInstances.length];
    currentIndex++;
    
    try {
        const response = await axios.get(`${instance.url}/api/data`, { timeout: 5000 });
        res.json(response.data);
    } catch (error) {
        res.status(503).json({ error: 'Service unavailable', instance: instance.id });
    }
});

// Rolling deployment endpoint
app.post('/admin/deploy', async (req, res) => {
    const { version, strategy = 'rolling' } = req.body;
    
    console.log(`Starting ${strategy} deployment to version ${version}`);
    broadcast({ type: 'deployment', status: 'started', version, strategy });
    
    try {
        if (strategy === 'rolling') {
            await performRollingDeployment(version);
        }
        
        broadcast({ type: 'deployment', status: 'completed', version });
        res.json({ message: 'Deployment completed successfully' });
    } catch (error) {
        broadcast({ type: 'deployment', status: 'failed', error: error.message });
        res.status(500).json({ error: error.message });
    }
});

async function performRollingDeployment(newVersion) {
    const updateBatchSize = 1; // Update one instance at a time
    const healthCheckWait = 5000; // Wait 5 seconds for health checks
    
    // Set target version for all instances
    instances.forEach(instance => {
        instance.targetVersion = newVersion;
    });
    
    for (let i = 0; i < instances.length; i += updateBatchSize) {
        const batch = instances.slice(i, i + updateBatchSize);
        
        console.log(`Updating batch: ${batch.map(b => b.id).join(', ')}`);
        broadcast({ 
            type: 'batchUpdate', 
            batch: batch.map(b => b.id), 
            version: newVersion 
        });
        
        // Mark instances as updating
        batch.forEach(instance => {
            instance.healthy = false;
            instance.updating = true;
        });
        
        // Simulate deployment (in real world, this would restart containers)
        await new Promise(resolve => setTimeout(resolve, 3000));
        
        // Update version and mark as healthy
        batch.forEach(instance => {
            instance.version = newVersion;
            instance.updating = false;
            instance.healthy = true;
            console.log(`Updated ${instance.id} to version ${newVersion}`);
        });
        
        console.log(`Batch updated. Waiting for health checks...`);
        await new Promise(resolve => setTimeout(resolve, healthCheckWait));
        
        // Verify health
        await checkHealth();
        
        const unhealthyInBatch = batch.filter(instance => !instance.healthy);
        if (unhealthyInBatch.length > 0) {
            throw new Error(`Health check failed for: ${unhealthyInBatch.map(i => i.id).join(', ')}`);
        }
    }
}

// Status endpoint
app.get('/admin/status', (req, res) => {
    res.json({ instances });
});

// Start health checking
setInterval(checkHealth, 3000);
checkHealth();

app.listen(PORT, () => {
    console.log(`Orchestrator running on port ${PORT}`);
});
