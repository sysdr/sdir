const express = require('express');
const winston = require('winston');

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

let isHealthy = true;
let degradationLevel = 0;

const inventory = {
    1: { stock: 50, reserved: 5 },
    2: { stock: 30, reserved: 2 },
    3: { stock: 100, reserved: 0 },
    4: { stock: 25, reserved: 3 }
};

const cachedInventory = {
    1: { stock: 45, reserved: 0, lastUpdated: Date.now() - 300000 },
    2: { stock: 28, reserved: 0, lastUpdated: Date.now() - 300000 },
    3: { stock: 95, reserved: 0, lastUpdated: Date.now() - 300000 },
    4: { stock: 22, reserved: 0, lastUpdated: Date.now() - 300000 }
};

// Health endpoint
app.get('/health', (req, res) => {
    const health = {
        status: isHealthy ? 'healthy' : 'unhealthy',
        degradationLevel,
        timestamp: Date.now()
    };
    res.json(health);
});

// Control endpoints
app.post('/control/degrade/:level', (req, res) => {
    degradationLevel = parseInt(req.params.level);
    logger.info(`Degradation level set to ${degradationLevel}`);
    res.json({ degradationLevel });
});

// Check inventory
app.get('/inventory/:productId', async (req, res) => {
    const productId = parseInt(req.params.productId);

    if (degradationLevel >= 3) {
        return res.status(503).json({ error: 'Inventory service unavailable' });
    }

    if (degradationLevel >= 2) {
        // Return cached data
        const cached = cachedInventory[productId];
        return res.json({
            productId,
            available: cached ? cached.stock : 0,
            source: 'cache',
            lastUpdated: cached ? cached.lastUpdated : Date.now()
        });
    }

    if (degradationLevel >= 1) {
        await new Promise(resolve => setTimeout(resolve, 1500)); // Slow database
    }

    const item = inventory[productId];
    if (!item) {
        return res.status(404).json({ error: 'Product not found in inventory' });
    }

    res.json({
        productId,
        available: item.stock - item.reserved,
        source: 'live',
        lastUpdated: Date.now()
    });
});

// Reserve inventory
app.post('/inventory/:productId/reserve', async (req, res) => {
    const productId = parseInt(req.params.productId);
    const { quantity = 1 } = req.body;

    if (degradationLevel >= 3) {
        return res.status(503).json({ 
            error: 'Reservation service unavailable',
            fallback: 'allow_overselling'
        });
    }

    if (degradationLevel >= 2 && Math.random() < 0.3) {
        return res.status(500).json({ 
            error: 'Reservation failed',
            fallback: 'optimistic_reserve'
        });
    }

    const item = inventory[productId];
    if (!item || (item.stock - item.reserved) < quantity) {
        return res.status(400).json({ error: 'Insufficient inventory' });
    }

    item.reserved += quantity;
    
    res.json({
        productId,
        quantity,
        reservationId: `res_${Date.now()}`,
        status: 'reserved'
    });
});

const PORT = process.env.PORT || 3003;
app.listen(PORT, () => {
    logger.info(`Inventory service running on port ${PORT}`);
});
