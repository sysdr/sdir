const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const Redis = require('redis');
const winston = require('winston');
const cron = require('node-cron');
const path = require('path');

const app = express();
const server = http.createServer(app);
const io = socketIo(server);

// Configuration
const PORT = process.env.PORT || 3000;
const REGION = process.env.REGION || 'us-east-1';
const REDIS_URL = process.env.REDIS_URL || 'redis://redis:6379';

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.printf(({ timestamp, level, message, region = REGION }) => {
      return `${timestamp} [${region}] ${level.toUpperCase()}: ${message}`;
    })
  ),
  transports: [
    new winston.transports.Console(),
    new winston.transports.File({ filename: 'logs/app.log' })
  ]
});

// Redis client
let redisClient;

// Region configuration
const REGIONS = {
  'us-east-1': { name: 'US East 1', primary: true, healthy: true },
  'us-west-2': { name: 'US West 2', primary: false, healthy: true },
  'eu-west-1': { name: 'EU West 1', primary: false, healthy: true }
};

class RegionManager {
  constructor() {
    this.currentRegion = REGION;
    this.healthStatus = new Map();
    this.failoverHistory = [];
    this.requestCount = 0;
    
    // Initialize health status
    Object.keys(REGIONS).forEach(region => {
      this.healthStatus.set(region, {
        healthy: true,
        lastCheck: Date.now(),
        responseTime: Math.random() * 50 + 10, // 10-60ms
        errorRate: 0,
        connections: 0
      });
    });
  }

  async checkRegionHealth(region) {
    const status = this.healthStatus.get(region);
    if (!status) return false;

    // Simulate health check with some variability
    const isHealthy = Math.random() > 0.05; // 95% uptime
    const responseTime = Math.random() * 100 + status.responseTime;
    
    status.healthy = isHealthy;
    status.lastCheck = Date.now();
    status.responseTime = responseTime;
    status.errorRate = isHealthy ? 0 : Math.random() * 0.1;
    
    this.healthStatus.set(region, status);
    
    logger.info(`Health check for ${region}: ${isHealthy ? 'HEALTHY' : 'UNHEALTHY'} (${responseTime.toFixed(1)}ms)`);
    
    return isHealthy;
  }

  async performFailover(fromRegion, toRegion) {
    logger.info(`Initiating failover from ${fromRegion} to ${toRegion}`);
    
    const failoverEvent = {
      timestamp: Date.now(),
      from: fromRegion,
      to: toRegion,
      reason: 'automated_health_check',
      duration: 0
    };
    
    // Simulate failover process
    const steps = [
      'Detecting failure in primary region',
      'Checking secondary region health',
      'Updating DNS records',
      'Redirecting traffic',
      'Verifying failover success'
    ];
    
    for (let i = 0; i < steps.length; i++) {
      logger.info(`Failover step ${i + 1}/5: ${steps[i]}`);
      io.emit('failover_step', { step: i + 1, description: steps[i] });
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
    
    // Update region status
    REGIONS[fromRegion].primary = false;
    REGIONS[toRegion].primary = true;
    
    failoverEvent.duration = Date.now() - failoverEvent.timestamp;
    this.failoverHistory.push(failoverEvent);
    
    logger.info(`Failover completed in ${failoverEvent.duration}ms`);
    io.emit('failover_complete', failoverEvent);
    
    return failoverEvent;
  }

  getPrimaryRegion() {
    return Object.keys(REGIONS).find(region => REGIONS[region].primary);
  }

  getRegionStatus() {
    const regions = Object.keys(REGIONS).map(region => ({
      id: region,
      name: REGIONS[region].name,
      primary: REGIONS[region].primary,
      health: this.healthStatus.get(region),
      status: REGIONS[region]
    }));
    
    return {
      regions,
      currentPrimary: this.getPrimaryRegion(),
      totalRequests: this.requestCount,
      failoverHistory: this.failoverHistory.slice(-10) // Last 10 events
    };
  }

  async simulateRegionFailure(region) {
    logger.info(`Simulating failure in region: ${region}`);
    const status = this.healthStatus.get(region);
    status.healthy = false;
    status.errorRate = 1.0;
    this.healthStatus.set(region, status);
    
    // If primary region failed, trigger failover
    if (REGIONS[region].primary) {
      const healthyRegions = Object.keys(REGIONS).filter(r => {
        const health = this.healthStatus.get(r);
        return r !== region && health.healthy;
      });
      
      if (healthyRegions.length > 0) {
        await this.performFailover(region, healthyRegions[0]);
      }
    }
    
    io.emit('region_failure', { region, timestamp: Date.now() });
  }

  async recoverRegion(region) {
    logger.info(`Recovering region: ${region}`);
    const status = this.healthStatus.get(region);
    status.healthy = true;
    status.errorRate = 0;
    this.healthStatus.set(region, status);
    
    io.emit('region_recovery', { region, timestamp: Date.now() });
  }
}

// Initialize components
const regionManager = new RegionManager();

// Middleware
app.use(express.json());
app.use(express.static(path.join(__dirname, '../web')));

// API Routes
app.get('/api/health', (req, res) => {
  regionManager.requestCount++;
  res.json({
    region: REGION,
    status: 'healthy',
    timestamp: Date.now(),
    uptime: process.uptime()
  });
});

app.get('/api/status', (req, res) => {
  res.json(regionManager.getRegionStatus());
});

app.post('/api/simulate-failure/:region', async (req, res) => {
  const { region } = req.params;
  await regionManager.simulateRegionFailure(region);
  res.json({ message: `Simulated failure in ${region}` });
});

app.post('/api/recover/:region', async (req, res) => {
  const { region } = req.params;
  await regionManager.recoverRegion(region);
  res.json({ message: `Recovering ${region}` });
});

app.get('/api/metrics', (req, res) => {
  const metrics = {
    totalRequests: regionManager.requestCount,
    regions: regionManager.getRegionStatus().regions,
    uptime: process.uptime(),
    timestamp: Date.now()
  };
  res.json(metrics);
});

// Socket.IO connection handling
io.on('connection', (socket) => {
  logger.info('Client connected to dashboard');
  
  // Send initial status
  socket.emit('status_update', regionManager.getRegionStatus());
  
  socket.on('disconnect', () => {
    logger.info('Client disconnected from dashboard');
  });
});

// Background health monitoring
cron.schedule('*/10 * * * * *', async () => {
  const regions = Object.keys(REGIONS);
  
  for (const region of regions) {
    await regionManager.checkRegionHealth(region);
  }
  
  // Emit status update
  io.emit('status_update', regionManager.getRegionStatus());
});

// Periodic metrics broadcast
cron.schedule('*/5 * * * * *', () => {
  io.emit('metrics_update', {
    totalRequests: regionManager.requestCount,
    timestamp: Date.now(),
    regions: regionManager.getRegionStatus().regions
  });
});

// Initialize Redis connection
async function initRedis() {
  try {
    redisClient = Redis.createClient({ url: REDIS_URL });
    await redisClient.connect();
    logger.info('Connected to Redis');
  } catch (error) {
    logger.error('Redis connection failed:', error.message);
  }
}

// Start server
server.listen(PORT, async () => {
  logger.info(`Multi-Region Failover Demo running on port ${PORT}`);
  logger.info(`Region: ${REGION}`);
  await initRedis();
});

module.exports = { app, regionManager };
