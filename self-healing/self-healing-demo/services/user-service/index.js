const express = require('express');
const cors = require('cors');

const app = express();
const PORT = process.env.SERVICE_PORT || 3000;
const SERVICE_NAME = process.env.SERVICE_NAME || 'unknown-service';
const INSTANCE_ID = process.env.INSTANCE_ID || 'instance-1';

app.use(cors());
app.use(express.json());

// Service state management
let serviceState = {
    healthy: true,
    memoryUsage: 50,
    cpuUsage: 30,
    errorRate: 0,
    responseTime: 100,
    startTime: Date.now(),
    requestCount: 0,
    errorCount: 0
};

// Simulate gradual memory leak
setInterval(() => {
    if (serviceState.healthy) {
        // Simulate normal fluctuations
        serviceState.memoryUsage += Math.random() * 2 - 1;
        serviceState.cpuUsage += Math.random() * 5 - 2.5;
        serviceState.responseTime += Math.random() * 20 - 10;
        
        // Boundary checks
        serviceState.memoryUsage = Math.max(20, Math.min(95, serviceState.memoryUsage));
        serviceState.cpuUsage = Math.max(10, Math.min(90, serviceState.cpuUsage));
        serviceState.responseTime = Math.max(50, Math.min(500, serviceState.responseTime));
        
        // Calculate error rate
        serviceState.errorRate = serviceState.requestCount > 0 ? 
            (serviceState.errorCount / serviceState.requestCount) * 100 : 0;
    }
}, 5000);

// Health check endpoint
app.get('/health', (req, res) => {
    const isHealthy = serviceState.healthy && 
                     serviceState.memoryUsage < 90 && 
                     serviceState.cpuUsage < 85 &&
                     serviceState.errorRate < 50;
    
    res.status(isHealthy ? 200 : 503).json({
        service: SERVICE_NAME,
        instance: INSTANCE_ID,
        status: isHealthy ? 'healthy' : 'unhealthy',
        timestamp: new Date().toISOString(),
        uptime: Date.now() - serviceState.startTime,
        metrics: serviceState
    });
});

// Detailed metrics endpoint
app.get('/metrics', (req, res) => {
    res.json({
        service: SERVICE_NAME,
        instance: INSTANCE_ID,
        metrics: serviceState,
        timestamp: new Date().toISOString()
    });
});

// Service-specific endpoints
app.get('/', (req, res) => {
    serviceState.requestCount++;
    
    // Simulate occasional errors
    if (Math.random() < serviceState.errorRate / 100) {
        serviceState.errorCount++;
        return res.status(500).json({ error: 'Service temporarily unavailable' });
    }
    
    res.json({
        service: SERVICE_NAME,
        instance: INSTANCE_ID,
        message: `${SERVICE_NAME} is running normally`,
        timestamp: new Date().toISOString()
    });
});

// Failure simulation endpoints
app.post('/simulate/memory-leak', (req, res) => {
    console.log(`${SERVICE_NAME}: Simulating memory leak`);
    const leakInterval = setInterval(() => {
        serviceState.memoryUsage += 5;
        if (serviceState.memoryUsage >= 95) {
            serviceState.healthy = false;
            clearInterval(leakInterval);
        }
    }, 2000);
    
    res.json({ message: 'Memory leak simulation started' });
});

app.post('/simulate/high-cpu', (req, res) => {
    console.log(`${SERVICE_NAME}: Simulating high CPU usage`);
    serviceState.cpuUsage = 95;
    serviceState.healthy = false;
    
    res.json({ message: 'High CPU simulation started' });
});

app.post('/simulate/errors', (req, res) => {
    console.log(`${SERVICE_NAME}: Simulating high error rate`);
    serviceState.errorRate = 75;
    
    res.json({ message: 'Error simulation started' });
});

app.post('/recover', (req, res) => {
    console.log(`${SERVICE_NAME}: Manual recovery triggered`);
    serviceState.healthy = true;
    serviceState.memoryUsage = 50;
    serviceState.cpuUsage = 30;
    serviceState.errorRate = 0;
    serviceState.errorCount = 0;
    serviceState.requestCount = 0;
    
    res.json({ message: 'Service recovered' });
});

app.listen(PORT, () => {
    console.log(`${SERVICE_NAME} (${INSTANCE_ID}) running on port ${PORT}`);
});
