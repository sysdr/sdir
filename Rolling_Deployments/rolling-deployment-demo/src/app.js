const express = require('express');
const app = express();

const VERSION = process.env.APP_VERSION || 'v1.0';
const PORT = process.env.PORT || 3000;
const INSTANCE_ID = process.env.INSTANCE_ID || 'instance-1';

let isHealthy = true;
let startTime = Date.now();
let requestCount = 0;

app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
    if (!isHealthy) {
        return res.status(503).json({ status: 'unhealthy', instance: INSTANCE_ID });
    }
    
    const uptime = Math.floor((Date.now() - startTime) / 1000);
    res.json({ 
        status: 'healthy', 
        instance: INSTANCE_ID,
        version: VERSION,
        uptime: uptime,
        requests: requestCount
    });
});

// Main API endpoint
app.get('/api/data', (req, res) => {
    requestCount++;
    
    // Simulate some processing time
    setTimeout(() => {
        res.json({
            message: `Hello from ${INSTANCE_ID}`,
            version: VERSION,
            timestamp: new Date().toISOString(),
            requestId: Math.random().toString(36).substr(2, 9)
        });
    }, Math.random() * 100);
});

// Admin endpoint to control health
app.post('/admin/health', (req, res) => {
    isHealthy = req.body.healthy;
    res.json({ message: `Health set to ${isHealthy}`, instance: INSTANCE_ID });
});

// Metrics endpoint
app.get('/metrics', (req, res) => {
    const uptime = Math.floor((Date.now() - startTime) / 1000);
    res.json({
        instance: INSTANCE_ID,
        version: VERSION,
        uptime: uptime,
        requests: requestCount,
        healthy: isHealthy,
        memory: process.memoryUsage()
    });
});

app.listen(PORT, () => {
    console.log(`${INSTANCE_ID} (${VERSION}) listening on port ${PORT}`);
});
