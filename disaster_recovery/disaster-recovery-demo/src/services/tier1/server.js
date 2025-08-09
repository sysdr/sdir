const express = require('express');
const { createClient } = require('redis');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const winston = require('winston');

const app = express();
app.use(cors());
app.use(express.json());

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: '/app/logs/payment-service.log' }),
    new winston.transports.Console()
  ]
});

// Redis client setup
let redisClient;
const connectRedis = async () => {
  try {
    redisClient = createClient({ url: process.env.REDIS_URL });
    await redisClient.connect();
    logger.info('Connected to Redis');
  } catch (error) {
    logger.error('Redis connection failed:', error);
    process.exit(1);
  }
};

// Service state tracking
let serviceState = {
  startTime: Date.now(),
  isHealthy: true,
  disasterMode: false,
  rtoSeconds: parseInt(process.env.RTO_SECONDS) || 30,
  rpoSeconds: parseInt(process.env.RPO_SECONDS) || 0,
  processedTransactions: 0,
  failedTransactions: 0
};

// Health check endpoint
app.get('/health', async (req, res) => {
  const health = {
    service: 'payment-service',
    tier: 1,
    status: serviceState.isHealthy && !serviceState.disasterMode ? 'healthy' : 'unhealthy',
    uptime: Date.now() - serviceState.startTime,
    rto: serviceState.rtoSeconds,
    rpo: serviceState.rpoSeconds,
    metrics: {
      processed: serviceState.processedTransactions,
      failed: serviceState.failedTransactions
    },
    timestamp: new Date().toISOString()
  };
  
  res.status(serviceState.isHealthy ? 200 : 503).json(health);
});

// Process payment endpoint
app.post('/payment/process', async (req, res) => {
  try {
    const { customerId, amount, currency = 'USD' } = req.body;
    
    if (serviceState.disasterMode) {
      serviceState.failedTransactions++;
      return res.status(503).json({ 
        error: 'Service in disaster mode',
        retryAfter: serviceState.rtoSeconds 
      });
    }
    
    const transactionId = uuidv4();
    const transaction = {
      id: transactionId,
      customerId,
      amount,
      currency,
      status: 'completed',
      timestamp: new Date().toISOString()
    };
    
    // Store in Redis with immediate persistence (RPO: 0)
    await redisClient.setEx(`transaction:${transactionId}`, 3600, JSON.stringify(transaction));
    
    serviceState.processedTransactions++;
    
    logger.info('Payment processed', { transactionId, customerId, amount });
    
    res.json({
      success: true,
      transactionId,
      message: 'Payment processed successfully'
    });
    
  } catch (error) {
    serviceState.failedTransactions++;
    logger.error('Payment processing failed:', error);
    res.status(500).json({ error: 'Payment processing failed' });
  }
});

// Get transaction status
app.get('/payment/:transactionId', async (req, res) => {
  try {
    const { transactionId } = req.params;
    const transaction = await redisClient.get(`transaction:${transactionId}`);
    
    if (!transaction) {
      return res.status(404).json({ error: 'Transaction not found' });
    }
    
    res.json(JSON.parse(transaction));
  } catch (error) {
    logger.error('Transaction lookup failed:', error);
    res.status(500).json({ error: 'Transaction lookup failed' });
  }
});

// Disaster simulation endpoint
app.post('/simulate/disaster', (req, res) => {
  serviceState.disasterMode = true;
  serviceState.isHealthy = false;
  logger.warn('Disaster mode activated for payment service');
  
  // Simulate recovery after RTO
  setTimeout(() => {
    serviceState.disasterMode = false;
    serviceState.isHealthy = true;
    logger.info('Service recovered from disaster');
  }, serviceState.rtoSeconds * 1000);
  
  res.json({ 
    message: 'Disaster simulation started',
    estimatedRecoveryTime: serviceState.rtoSeconds 
  });
});

// Start server
const PORT = process.env.PORT || 3000;
connectRedis().then(() => {
  app.listen(PORT, () => {
    logger.info(`Payment service (Tier 1) started on port ${PORT}`);
  });
});
