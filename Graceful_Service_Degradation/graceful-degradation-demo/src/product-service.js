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
let degradationLevel = 0; // 0: normal, 1: slow, 2: error-prone, 3: down

const products = [
    { id: 1, name: 'Laptop', price: 999, category: 'Electronics' },
    { id: 2, name: 'Phone', price: 599, category: 'Electronics' },
    { id: 3, name: 'Book', price: 29, category: 'Books' },
    { id: 4, name: 'Headphones', price: 199, category: 'Electronics' }
];

const mlRecommendations = {
    1: [2, 4], // Laptop -> Phone, Headphones
    2: [1, 4], // Phone -> Laptop, Headphones
    3: [3],    // Book -> Book
    4: [1, 2]  // Headphones -> Laptop, Phone
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

// Control endpoints for testing
app.post('/control/degrade/:level', (req, res) => {
    degradationLevel = parseInt(req.params.level);
    logger.info(`Degradation level set to ${degradationLevel}`);
    res.json({ degradationLevel });
});

app.post('/control/health/:status', (req, res) => {
    isHealthy = req.params.status === 'true';
    logger.info(`Health status set to ${isHealthy}`);
    res.json({ isHealthy });
});

// Get all products
app.get('/products', async (req, res) => {
    if (degradationLevel >= 3) {
        return res.status(503).json({ error: 'Service unavailable' });
    }

    if (degradationLevel >= 1) {
        await new Promise(resolve => setTimeout(resolve, 2000)); // Simulate slowness
    }

    if (degradationLevel >= 2 && Math.random() < 0.3) {
        return res.status(500).json({ error: 'Internal server error' });
    }

    res.json({ products, source: 'live' });
});

// Get product by ID
app.get('/products/:id', async (req, res) => {
    const id = parseInt(req.params.id);
    
    if (degradationLevel >= 3) {
        return res.status(503).json({ error: 'Service unavailable' });
    }

    if (degradationLevel >= 1) {
        await new Promise(resolve => setTimeout(resolve, 1000));
    }

    const product = products.find(p => p.id === id);
    if (!product) {
        return res.status(404).json({ error: 'Product not found' });
    }

    res.json({ product, source: 'live' });
});

// ML-powered recommendations
app.get('/products/:id/recommendations', async (req, res) => {
    const id = parseInt(req.params.id);
    
    if (degradationLevel >= 2) {
        // Fallback to simple recommendations
        const simpleRecs = products.filter(p => p.id !== id).slice(0, 2);
        return res.json({ 
            recommendations: simpleRecs, 
            source: 'fallback',
            type: 'popular'
        });
    }

    if (degradationLevel >= 1) {
        await new Promise(resolve => setTimeout(resolve, 3000)); // ML is slow
    }

    const recIds = mlRecommendations[id] || [];
    const recommendations = products.filter(p => recIds.includes(p.id));
    
    res.json({ 
        recommendations, 
        source: 'ml',
        type: 'personalized'
    });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
    logger.info(`Product service running on port ${PORT}`);
});
