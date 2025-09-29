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

// Process payment
app.post('/payments', async (req, res) => {
    const { amount, cardType = 'credit', userId } = req.body;

    if (degradationLevel >= 3) {
        return res.status(503).json({ 
            error: 'Payment service unavailable',
            fallback: 'cash_on_delivery'
        });
    }

    if (degradationLevel >= 2 && Math.random() < 0.4) {
        return res.status(500).json({ 
            error: 'Payment processing failed',
            fallback: 'retry_later'
        });
    }

    if (degradationLevel >= 1) {
        await new Promise(resolve => setTimeout(resolve, 5000)); // Slow processing
    }

    // Simulate payment processing
    const paymentId = `pay_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    const response = {
        paymentId,
        amount,
        status: 'completed',
        method: degradationLevel >= 1 ? 'simplified' : 'full',
        processingTime: degradationLevel >= 1 ? '5s' : '1s'
    };

    res.json(response);
});

// Payment status
app.get('/payments/:id', (req, res) => {
    res.json({
        paymentId: req.params.id,
        status: 'completed',
        timestamp: Date.now()
    });
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => {
    logger.info(`Payment service running on port ${PORT}`);
});
