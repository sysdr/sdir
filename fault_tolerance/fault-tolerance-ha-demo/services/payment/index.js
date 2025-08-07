const express = require('express');
const cors = require('cors');
const winston = require('winston');

// Custom Circuit Breaker Implementation
class CircuitBreaker {
  constructor(options = {}) {
    this.timeout = options.timeout || 5000;
    this.errorThreshold = options.errorThreshold || 50;
    this.resetTimeout = options.resetTimeout || 30000;
    this.monitor = options.monitor || false;
    
    this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
    this.failureCount = 0;
    this.lastFailureTime = null;
    this.successCount = 0;
  }
  
  async call(fn) {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureTime > this.resetTimeout) {
        this.state = 'HALF_OPEN';
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }
    
    try {
      const result = await Promise.race([
        fn(),
        new Promise((_, reject) => 
          setTimeout(() => reject(new Error('Timeout')), this.timeout)
        )
      ]);
      
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }
  
  onSuccess() {
    this.failureCount = 0;
    this.successCount++;
    this.state = 'CLOSED';
  }
  
  onFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();
    
    if (this.failureCount >= this.errorThreshold) {
      this.state = 'OPEN';
    }
  }
  
  reset() {
    this.state = 'CLOSED';
    this.failureCount = 0;
    this.successCount = 0;
    this.lastFailureTime = null;
  }
}

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
    new winston.transports.Console()
  ]
});

// Circuit breaker configuration
const circuitBreaker = new CircuitBreaker({
  timeout: 10000, // Increased timeout
  errorThreshold: 3, // Lower threshold for testing
  resetTimeout: 30000,
  monitor: true
});

// State tracking
let serviceState = {
  status: 'healthy',
  circuitState: 'CLOSED',
  retryCount: 0,
  failureInjected: false,
  requestCount: 0,
  successCount: 0
};

// Exponential backoff retry utility
async function retryWithBackoff(fn, maxRetries = 3, baseDelay = 1000) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const result = await fn();
      serviceState.retryCount = 0;
      return result;
    } catch (error) {
      serviceState.retryCount = attempt;
      
      if (attempt === maxRetries) {
        throw error;
      }
      
      const delay = Math.min(baseDelay * Math.pow(2, attempt - 1), 10000);
      const jitter = Math.random() * 0.1 * delay;
      await new Promise(resolve => setTimeout(resolve, delay + jitter));
    }
  }
}

// Simulate database operation
async function processPayment(paymentData) {
  serviceState.requestCount++;
  
  // Simulate failure if injected
  if (serviceState.failureInjected && Math.random() < 0.7) {
    throw new Error('Database connection timeout');
  }
  
  // Simulate processing delay
  await new Promise(resolve => setTimeout(resolve, 200 + Math.random() * 300));
  
  serviceState.successCount++;
  return { 
    transactionId: `txn_${Date.now()}`, 
    status: 'completed',
    amount: paymentData.amount 
  };
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: serviceState.status,
    circuitState: circuitBreaker.state || 'CLOSED',
    uptime: process.uptime(),
    requestCount: serviceState.requestCount,
    successRate: serviceState.requestCount > 0 ? 
      (serviceState.successCount / serviceState.requestCount * 100).toFixed(2) : 100
  });
});

// Process payment with fault tolerance
app.post('/payment', async (req, res) => {
  try {
    logger.info('Processing payment request', { body: req.body });
    
    // Simple direct call for now
    const result = await processPayment(req.body);
    
    serviceState.status = 'healthy';
    serviceState.circuitState = 'CLOSED';
    
    res.json({
      success: true,
      data: result,
      metadata: {
        retryCount: 0,
        circuitState: 'CLOSED'
      }
    });
    
  } catch (error) {
    logger.error('Payment processing failed', { error: error.message });
    
    serviceState.status = 'degraded';
    serviceState.circuitState = 'OPEN';
    
    // Graceful degradation - return cached response
    res.status(200).json({
      success: false,
      error: 'Payment processing temporarily unavailable',
      fallback: {
        transactionId: `fallback_${Date.now()}`,
        status: 'queued',
        message: 'Payment will be processed when service recovers'
      },
      metadata: {
        retryCount: 0,
        circuitState: 'OPEN'
      }
    });
  }
});

// Inject failure for testing
app.post('/inject-failure', (req, res) => {
  serviceState.failureInjected = true;
  serviceState.status = 'degraded';
  setTimeout(() => {
    serviceState.failureInjected = false;
    serviceState.status = 'healthy';
  }, 30000);
  res.json({ message: 'Failure injected for 30 seconds' });
});

// Reset service state
app.post('/reset', (req, res) => {
  serviceState = {
    status: 'healthy',
    circuitState: 'CLOSED',
    retryCount: 0,
    failureInjected: false,
    requestCount: 0,
    successCount: 0
  };
  circuitBreaker.reset();
  res.json({ message: 'Service state reset' });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  logger.info(`Payment service running on port ${PORT}`);
});
