const express = require('express');
const axios = require('axios');
const WebSocket = require('ws');
const Redis = require('redis');
const cron = require('node-cron');

class RedundancyService {
    constructor(port, region, serviceId) {
        this.port = port;
        this.region = region;
        this.serviceId = serviceId;
        this.app = express();
        this.isHealthy = true;
        this.requestCount = 0;
        this.startTime = Date.now();
        
        this.setupRoutes();
        this.setupHealthChecks();
    }

    setupRoutes() {
        this.app.use(express.json());
        this.app.use(express.static('web'));

        // Health check endpoint
        this.app.get('/health', (req, res) => {
            if (this.isHealthy) {
                res.json({
                    status: 'healthy',
                    serviceId: this.serviceId,
                    region: this.region,
                    uptime: Date.now() - this.startTime,
                    requestCount: this.requestCount
                });
            } else {
                res.status(503).json({
                    status: 'unhealthy',
                    serviceId: this.serviceId,
                    region: this.region
                });
            }
        });

        // Service endpoint
        this.app.get('/api/data', (req, res) => {
            this.requestCount++;
            if (!this.isHealthy) {
                return res.status(503).json({ error: 'Service unavailable' });
            }

            res.json({
                serviceId: this.serviceId,
                region: this.region,
                timestamp: Date.now(),
                data: `Response from ${this.serviceId} in ${this.region}`,
                requestNumber: this.requestCount
            });
        });

        // Simulate failure
        this.app.post('/api/fail', (req, res) => {
            this.isHealthy = false;
            console.log(`💥 Service ${this.serviceId} marked as unhealthy`);
            res.json({ message: `Service ${this.serviceId} failed` });
        });

        // Recover service
        this.app.post('/api/recover', (req, res) => {
            this.isHealthy = true;
            console.log(`✅ Service ${this.serviceId} recovered`);
            res.json({ message: `Service ${this.serviceId} recovered` });
        });
    }

    setupHealthChecks() {
        // Periodic health announcement
        cron.schedule('*/5 * * * * *', () => {
            if (this.isHealthy) {
                console.log(`💚 ${this.serviceId} (${this.region}): Healthy - ${this.requestCount} requests served`);
            }
        });
    }

    start() {
        this.server = this.app.listen(this.port, () => {
            console.log(`🚀 Service ${this.serviceId} started on port ${this.port} (${this.region})`);
        });
    }

    stop() {
        if (this.server) {
            this.server.close();
        }
    }
}

// Load Balancer with Health Checking
class LoadBalancer {
    constructor(port) {
        this.port = port;
        this.app = express();
        this.services = [
            { url: 'http://service1:3001', region: 'us-east-1', healthy: true },
            { url: 'http://service2:3002', region: 'us-east-1', healthy: true },
            { url: 'http://service3:3003', region: 'us-west-2', healthy: true },
            { url: 'http://service4:3004', region: 'eu-west-1', healthy: true }
        ];
        this.currentIndex = 0;
        
        this.setupRoutes();
        this.startHealthChecks();
    }

    setupRoutes() {
        this.app.use(express.json());
        this.app.use(express.static('web'));

        // Proxy requests to healthy services
        this.app.get('/api/data', async (req, res) => {
            const service = this.getHealthyService();
            if (!service) {
                return res.status(503).json({ error: 'No healthy services available' });
            }

            try {
                const response = await axios.get(`${service.url}/api/data`);
                res.json({
                    ...response.data,
                    loadBalancer: 'active',
                    selectedService: service.url
                });
            } catch (error) {
                this.markUnhealthy(service);
                res.status(503).json({ error: 'Service request failed' });
            }
        });

        // Service management
        this.app.post('/api/services/:port/fail', async (req, res) => {
            const port = req.params.port;
            try {
                await axios.post(`http://localhost:${port}/api/fail`);
                res.json({ message: `Service on port ${port} failed` });
            } catch (error) {
                res.status(500).json({ error: 'Failed to fail service' });
            }
        });

        this.app.post('/api/services/:port/recover', async (req, res) => {
            const port = req.params.port;
            try {
                await axios.post(`http://localhost:${port}/api/recover`);
                res.json({ message: `Service on port ${port} recovered` });
            } catch (error) {
                res.status(500).json({ error: 'Failed to recover service' });
            }
        });

        // Status endpoint
        this.app.get('/api/status', (req, res) => {
            res.json({
                services: this.services,
                healthyCount: this.services.filter(s => s.healthy).length,
                totalCount: this.services.length
            });
        });
    }

    getHealthyService() {
        const healthyServices = this.services.filter(s => s.healthy);
        if (healthyServices.length === 0) return null;

        // Round-robin among healthy services
        const service = healthyServices[this.currentIndex % healthyServices.length];
        this.currentIndex++;
        return service;
    }

    markUnhealthy(service) {
        service.healthy = false;
        console.log(`❌ Marked ${service.url} as unhealthy`);
    }

    startHealthChecks() {
        setInterval(async () => {
            for (const service of this.services) {
                try {
                    const response = await axios.get(`${service.url}/health`, { timeout: 2000 });
                    if (!service.healthy && response.status === 200) {
                        service.healthy = true;
                        console.log(`✅ Service ${service.url} recovered`);
                    }
                } catch (error) {
                    if (service.healthy) {
                        service.healthy = false;
                        console.log(`❌ Service ${service.url} failed health check`);
                    }
                }
            }
        }, 3000);
    }

    start() {
        this.server = this.app.listen(this.port, () => {
            console.log(`🔄 Load Balancer started on port ${this.port}`);
        });
    }
}

// Start services based on environment
const SERVICE_PORT = process.env.SERVICE_PORT;
const SERVICE_ID = process.env.SERVICE_ID;
const SERVICE_REGION = process.env.SERVICE_REGION;
const LOAD_BALANCER = process.env.LOAD_BALANCER;

if (LOAD_BALANCER === 'true') {
    const lb = new LoadBalancer(3000);
    lb.start();
} else if (SERVICE_PORT && SERVICE_ID && SERVICE_REGION) {
    const service = new RedundancyService(parseInt(SERVICE_PORT), SERVICE_REGION, SERVICE_ID);
    service.start();
} else {
    console.log('Starting all services...');
    
    // Start individual services
    const services = [
        new RedundancyService(3001, 'us-east-1', 'service-1'),
        new RedundancyService(3002, 'us-east-1', 'service-2'),
        new RedundancyService(3003, 'us-west-2', 'service-3'),
        new RedundancyService(3004, 'eu-west-1', 'service-4')
    ];

    services.forEach(service => service.start());

    // Start load balancer
    setTimeout(() => {
        const lb = new LoadBalancer(3000);
        lb.start();
    }, 2000);
}
