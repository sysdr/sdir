const express = require('express');
const cors = require('cors');
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
    new winston.transports.Console()
  ]
});

const INSTANCE_ID = process.env.INSTANCE_ID || 'user-1';
const PORT = process.env.PORT || 3002;

// Instance state
let instanceState = {
  id: INSTANCE_ID,
  status: 'healthy',
  requestCount: 0,
  startTime: Date.now(),
  failureInjected: false
};

// Simulate user data
const users = {
  'user-1': { id: 'user-1', name: 'Alice Johnson', email: 'alice@example.com' },
  'user-2': { id: 'user-2', name: 'Bob Smith', email: 'bob@example.com' },
  'user-3': { id: 'user-3', name: 'Charlie Brown', email: 'charlie@example.com' }
};

// Health check endpoint
app.get('/health', (req, res) => {
  if (instanceState.failureInjected) {
    return res.status(503).json({
      status: 'failed',
      instance: INSTANCE_ID,
      message: 'Service temporarily unavailable'
    });
  }
  
  res.json({
    status: 'healthy',
    instance: INSTANCE_ID,
    uptime: Date.now() - instanceState.startTime,
    requestCount: instanceState.requestCount
  });
});

// Get user data
app.get('/users/:userId', async (req, res) => {
  instanceState.requestCount++;
  
  if (instanceState.failureInjected) {
    return res.status(503).json({
      error: 'Service temporarily unavailable',
      instance: INSTANCE_ID
    });
  }
  
  // Simulate variable response time
  const responseTime = 100 + Math.random() * 200;
  await new Promise(resolve => setTimeout(resolve, responseTime));
  
  const user = users[req.params.userId];
  if (!user) {
    return res.status(404).json({ error: 'User not found' });
  }
  
  res.json({
    user,
    servedBy: INSTANCE_ID,
    responseTime: Math.round(responseTime)
  });
});

// List all users
app.get('/users', async (req, res) => {
  instanceState.requestCount++;
  
  if (instanceState.failureInjected) {
    return res.status(503).json({
      error: 'Service temporarily unavailable',
      instance: INSTANCE_ID
    });
  }
  
  const responseTime = 50 + Math.random() * 100;
  await new Promise(resolve => setTimeout(resolve, responseTime));
  
  res.json({
    users: Object.values(users),
    servedBy: INSTANCE_ID,
    responseTime: Math.round(responseTime)
  });
});

// Inject failure for testing
app.post('/inject-failure', (req, res) => {
  instanceState.failureInjected = true;
  instanceState.status = 'failed';
  setTimeout(() => {
    instanceState.failureInjected = false;
    instanceState.status = 'healthy';
  }, 20000);
  res.json({ message: `Failure injected on ${INSTANCE_ID} for 20 seconds` });
});

// Reset instance
app.post('/reset', (req, res) => {
  instanceState.failureInjected = false;
  instanceState.status = 'healthy';
  instanceState.requestCount = 0;
  res.json({ message: `Instance ${INSTANCE_ID} reset` });
});

app.listen(PORT, () => {
  logger.info(`User service ${INSTANCE_ID} running on port ${PORT}`);
});
