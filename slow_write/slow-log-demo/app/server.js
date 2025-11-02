const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 3000;

// Configuration
let config = {
  loggingMode: 'sync', // 'sync' or 'async'
  logDelay: 0, // artificial delay in ms
  maxQueueSize: 10000
};

// Metrics
let metrics = {
  totalRequests: 0,
  successfulRequests: 0,
  failedRequests: 0,
  avgResponseTime: 0,
  currentThreadsBlocked: 0,
  queueSize: 0,
  droppedLogs: 0,
  responseTimes: []
};

// Async logging queue
let logQueue = [];
let isProcessingQueue = false;

// Synchronous logging (blocking)
function logSync(message) {
  const start = Date.now();
  const timestamp = new Date().toISOString();
  const logEntry = `[${timestamp}] ${message}\n`;
  
  // Artificial delay to simulate slow log service
  if (config.logDelay > 0) {
    const until = Date.now() + config.logDelay;
    while (Date.now() < until) {
      // Busy wait - simulates blocking I/O
    }
  }
  
  // Write to file (synchronous)
  try {
    fs.appendFileSync('/tmp/app.log', logEntry);
  } catch (err) {
    console.error('Log write failed:', err.message);
  }
  
  return Date.now() - start;
}

// Asynchronous logging (non-blocking)
function logAsync(message) {
  const timestamp = new Date().toISOString();
  const logEntry = `[${timestamp}] ${message}\n`;
  
  // Add to queue
  if (logQueue.length < config.maxQueueSize) {
    logQueue.push(logEntry);
    metrics.queueSize = logQueue.length;
  } else {
    metrics.droppedLogs++;
  }
  
  // Start processing if not already running
  if (!isProcessingQueue) {
    processLogQueue();
  }
  
  return 0; // Non-blocking, returns immediately
}

// Process log queue asynchronously
async function processLogQueue() {
  if (isProcessingQueue) return;
  isProcessingQueue = true;
  
  while (logQueue.length > 0) {
    const entry = logQueue.shift();
    metrics.queueSize = logQueue.length;
    
    // Artificial delay
    if (config.logDelay > 0) {
      await new Promise(resolve => setTimeout(resolve, config.logDelay));
    }
    
    // Write to file
    try {
      fs.appendFileSync('/tmp/app.log', entry);
    } catch (err) {
      console.error('Log write failed:', err.message);
    }
  }
  
  isProcessingQueue = false;
}

// Middleware to track metrics
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    metrics.totalRequests++;
    metrics.responseTimes.push(duration);
    
    // Keep only last 100 response times
    if (metrics.responseTimes.length > 100) {
      metrics.responseTimes.shift();
    }
    
    // Calculate average
    const sum = metrics.responseTimes.reduce((a, b) => a + b, 0);
    metrics.avgResponseTime = Math.round(sum / metrics.responseTimes.length);
    
    if (res.statusCode >= 200 && res.statusCode < 300) {
      metrics.successfulRequests++;
    } else {
      metrics.failedRequests++;
    }
  });
  
  next();
});

app.use(express.json());
app.use(express.static('dashboard'));

// API endpoint - simulates business logic
app.get('/api/process', (req, res) => {
  const requestId = Math.random().toString(36).substring(7);
  
  try {
    // Simulate some processing
    let result = 0;
    for (let i = 0; i < 1000; i++) {
      result += Math.sqrt(i);
    }
    
    // Log the request
    const logTime = config.loggingMode === 'sync' 
      ? logSync(`Processing request ${requestId}`)
      : logAsync(`Processing request ${requestId}`);
    
    if (config.loggingMode === 'sync' && logTime > 100) {
      metrics.currentThreadsBlocked++;
    }
    
    res.json({
      success: true,
      requestId,
      result: Math.round(result),
      logMode: config.loggingMode
    });
    
    if (config.loggingMode === 'sync' && logTime > 100) {
      metrics.currentThreadsBlocked = Math.max(0, metrics.currentThreadsBlocked - 1);
    }
  } catch (error) {
    res.status(500).json({
      success: false,
      error: error.message
    });
  }
});

// Get current metrics
app.get('/api/metrics', (req, res) => {
  res.json(metrics);
});

// Get current configuration
app.get('/api/config', (req, res) => {
  res.json(config);
});

// Update configuration
app.post('/api/config', (req, res) => {
  const { loggingMode, logDelay } = req.body;
  
  if (loggingMode) {
    config.loggingMode = loggingMode;
  }
  
  if (logDelay !== undefined) {
    config.logDelay = parseInt(logDelay);
  }
  
  // Reset metrics when changing config
  metrics.totalRequests = 0;
  metrics.successfulRequests = 0;
  metrics.failedRequests = 0;
  metrics.avgResponseTime = 0;
  metrics.currentThreadsBlocked = 0;
  metrics.droppedLogs = 0;
  metrics.responseTimes = [];
  
  res.json({ success: true, config });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on http://localhost:${PORT}`);
  console.log(`📊 Dashboard: http://localhost:${PORT}`);
  console.log(`📝 Logging mode: ${config.loggingMode}`);
});
