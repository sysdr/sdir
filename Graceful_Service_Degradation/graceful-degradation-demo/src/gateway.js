const express = require('express');
const axios = require('axios');
const winston = require('winston');
const CircuitBreaker = require('./circuit-breaker');
const WebSocket = require('ws');
const http = require('http');
const path = require('path');

const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    transports: [new winston.transports.Console()]
});

const app = express();
app.use(express.json());
app.use(express.static('static'));

// Service URLs
const SERVICES = {
    product: process.env.PRODUCT_SERVICE_URL || 'http://localhost:3001',
    payment: process.env.PAYMENT_SERVICE_URL || 'http://localhost:3002',
    inventory: process.env.INVENTORY_SERVICE_URL || 'http://localhost:3003'
};

// Circuit breakers
const circuitBreakers = {
    product: new CircuitBreaker('product', { failureThreshold: 3, timeout: 5000 }),
    payment: new CircuitBreaker('payment', { failureThreshold: 3, timeout: 8000 }),
    inventory: new CircuitBreaker('inventory', { failureThreshold: 3, timeout: 3000 })
};

// Fallback data
const fallbackProducts = [
    { id: 1, name: 'Laptop', price: 999, category: 'Electronics' },
    { id: 2, name: 'Phone', price: 599, category: 'Electronics' }
];

let systemLoad = 0;
let requestCount = 0;

// Dashboard endpoint
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, '..', 'static', 'index.html'));
});

// Health aggregation
app.get('/health', async (req, res) => {
    const healthChecks = {};
    
    for (const [service, url] of Object.entries(SERVICES)) {
        try {
            const response = await axios.get(`${url}/health`, { timeout: 2000 });
            healthChecks[service] = response.data;
        } catch (error) {
            healthChecks[service] = { status: 'unhealthy', error: error.message };
        }
    }

    const circuitStates = {};
    for (const [service, cb] of Object.entries(circuitBreakers)) {
        circuitStates[service] = cb.getState();
    }

    res.json({
        services: healthChecks,
        circuits: circuitStates,
        systemLoad,
        requestCount
    });
});

// Product endpoints with fallbacks
app.get('/api/products', async (req, res) => {
    requestCount++;
    
    // Load shedding: reject non-essential requests under high load
    if (systemLoad > 80 && Math.random() < 0.3) {
        return res.json({ 
            products: fallbackProducts, 
            source: 'cached',
            message: 'Serving cached data due to high load'
        });
    }

    try {
        const result = await circuitBreakers.product.execute(async () => {
            const response = await axios.get(`${SERVICES.product}/products`);
            return response.data;
        });
        res.json(result);
    } catch (error) {
        logger.warn('Product service failed, using fallback', { error: error.message });
        res.json({ 
            products: fallbackProducts, 
            source: 'fallback',
            reason: 'service_unavailable'
        });
    }
});

app.get('/api/products/:id', async (req, res) => {
    requestCount++;
    const productId = req.params.id;

    try {
        const result = await circuitBreakers.product.execute(async () => {
            const response = await axios.get(`${SERVICES.product}/products/${productId}`);
            return response.data;
        });
        res.json(result);
    } catch (error) {
        const fallback = fallbackProducts.find(p => p.id == productId);
        if (fallback) {
            res.json({ 
                product: fallback, 
                source: 'fallback',
                reason: 'service_unavailable'
            });
        } else {
            res.status(404).json({ error: 'Product not found' });
        }
    }
});

// Enhanced checkout with multiple fallback levels
app.post('/api/checkout', async (req, res) => {
    requestCount++;
    const { productId, quantity = 1, userId, paymentInfo } = req.body;
    const checkoutResult = { steps: [], warnings: [], fallbacks: [] };

    // Step 1: Check inventory with fallback
    try {
        const inventoryResult = await circuitBreakers.inventory.execute(async () => {
            const response = await axios.get(`${SERVICES.inventory}/inventory/${productId}`);
            return response.data;
        });
        
        checkoutResult.steps.push({ step: 'inventory', status: 'success', data: inventoryResult });
        
        if (inventoryResult.available < quantity) {
            return res.status(400).json({ 
                error: 'Insufficient inventory',
                available: inventoryResult.available,
                requested: quantity
            });
        }
    } catch (error) {
        checkoutResult.steps.push({ step: 'inventory', status: 'fallback', error: error.message });
        checkoutResult.fallbacks.push('Allowing checkout without real-time inventory check');
        checkoutResult.warnings.push('Inventory verification temporarily unavailable');
    }

    // Step 2: Reserve inventory (optional during degradation)
    if (circuitBreakers.inventory.state !== 'OPEN') {
        try {
            const reserveResult = await circuitBreakers.inventory.execute(async () => {
                const response = await axios.post(`${SERVICES.inventory}/${productId}/reserve`, { quantity });
                return response.data;
            });
            checkoutResult.steps.push({ step: 'reserve', status: 'success', data: reserveResult });
        } catch (error) {
            checkoutResult.steps.push({ step: 'reserve', status: 'fallback', error: error.message });
            checkoutResult.fallbacks.push('Proceeding with optimistic inventory reservation');
        }
    } else {
        checkoutResult.steps.push({ step: 'reserve', status: 'skipped', reason: 'circuit_open' });
        checkoutResult.fallbacks.push('Inventory reservation skipped due to service issues');
    }

    // Step 3: Process payment with multiple fallback strategies
    try {
        const paymentResult = await circuitBreakers.payment.execute(async () => {
            const response = await axios.post(`${SERVICES.payment}/payments`, {
                amount: paymentInfo.amount,
                cardType: paymentInfo.cardType,
                userId
            });
            return response.data;
        });
        checkoutResult.steps.push({ step: 'payment', status: 'success', data: paymentResult });
    } catch (error) {
        checkoutResult.steps.push({ step: 'payment', status: 'fallback', error: error.message });
        
        // Multiple payment fallback strategies
        if (systemLoad < 50) {
            checkoutResult.fallbacks.push('Order placed with cash-on-delivery option');
            checkoutResult.paymentMethod = 'cash_on_delivery';
        } else {
            checkoutResult.fallbacks.push('Order queued for later payment processing');
            checkoutResult.paymentMethod = 'deferred';
        }
    }

    // Success response with degradation information
    const response = {
        orderId: `order_${Date.now()}`,
        status: 'confirmed',
        degradationMode: checkoutResult.fallbacks.length > 0,
        ...checkoutResult
    };

    res.json(response);
});

// Control endpoints for testing
app.post('/control/load/:level', (req, res) => {
    systemLoad = parseInt(req.params.level);
    logger.info(`System load set to ${systemLoad}%`);
    res.json({ systemLoad });
});

app.post('/control/degrade/:service/:level', async (req, res) => {
    const { service, level } = req.params;
    
    if (SERVICES[service]) {
        try {
            await axios.post(`${SERVICES[service]}/control/degrade/${level}`);
            res.json({ service, degradationLevel: level });
        } catch (error) {
            res.status(500).json({ error: error.message });
        }
    } else {
        res.status(404).json({ error: 'Service not found' });
    }
});

// WebSocket for real-time updates
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws) => {
    logger.info('Dashboard connected');
    
    const sendMetrics = () => {
        if (ws.readyState === WebSocket.OPEN) {
            const metrics = {
                timestamp: Date.now(),
                systemLoad,
                requestCount,
                circuits: Object.fromEntries(
                    Object.entries(circuitBreakers).map(([name, cb]) => [name, cb.getState()])
                )
            };
            ws.send(JSON.stringify(metrics));
        }
    };

    const interval = setInterval(sendMetrics, 1000);
    
    ws.on('close', () => {
        clearInterval(interval);
        logger.info('Dashboard disconnected');
    });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    logger.info(`API Gateway running on port ${PORT}`);
    logger.info(`Dashboard available at http://localhost:${PORT}`);
});
