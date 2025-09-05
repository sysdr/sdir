const express = require('express');
const WebSocket = require('ws');
const redis = require('redis');
const cron = require('node-cron');
const axios = require('axios');
const path = require('path');

const app = express();
const server = require('http').createServer(app);
const wss = new WebSocket.Server({ server });

// Redis client setup
let redisClient;
(async () => {
  redisClient = redis.createClient({ url: 'redis://redis:6379' });
  await redisClient.connect();
  console.log('Connected to Redis');
})();

app.use(express.json());
app.use(express.static('web'));

// SLA Configuration
const SLA_TIERS = {
  premium: { availability: 99.99, latency_p95: 100, error_budget: 0.01 },
  standard: { availability: 99.9, latency_p95: 500, error_budget: 0.1 },
  basic: { availability: 99.0, latency_p95: 2000, error_budget: 1.0 }
};

const SERVICES = ['auth-service', 'payment-service', 'order-service', 'notification-service'];

// Service simulation with different reliability patterns
class ServiceSimulator {
  constructor(name, baseReliability = 0.99) {
    this.name = name;
    this.baseReliability = baseReliability;
    this.currentLoad = 0;
    this.incidents = [];
  }

  async processRequest(tier = 'standard') {
    const startTime = Date.now();
    
    // Simulate different reliability patterns
    let success = Math.random() < this.getEffectiveReliability(tier);
    let latency = this.calculateLatency(tier, success);
    
    // Add some chaos - occasional incidents
    if (Math.random() < 0.001) { // 0.1% chance of incident
      this.createIncident();
    }

    const responseTime = Date.now() - startTime + latency;
    
    // Record metrics
    await this.recordMetrics(tier, success, responseTime);
    
    return { success, responseTime, service: this.name };
  }

  getEffectiveReliability(tier) {
    const tierMultiplier = tier === 'premium' ? 1.001 : tier === 'standard' ? 1.0 : 0.998;
    const loadPenalty = this.currentLoad > 80 ? 0.95 : 1.0;
    const incidentPenalty = this.incidents.filter(i => Date.now() - i.startTime < 300000).length > 0 ? 0.8 : 1.0;
    
    return Math.min(0.9999, this.baseReliability * tierMultiplier * loadPenalty * incidentPenalty);
  }

  calculateLatency(tier, success) {
    const baseLatency = success ? 50 : 5000; // Failed requests are slower
    const tierMultiplier = tier === 'premium' ? 0.5 : tier === 'standard' ? 1.0 : 2.0;
    const jitter = Math.random() * 50;
    
    return Math.floor(baseLatency * tierMultiplier + jitter);
  }

  createIncident() {
    const incident = {
      id: `incident-${Date.now()}`,
      startTime: Date.now(),
      severity: Math.random() > 0.7 ? 'major' : 'minor',
      service: this.name
    };
    this.incidents.push(incident);
    console.log(`🚨 Incident created: ${incident.id} on ${this.name}`);
  }

  async recordMetrics(tier, success, responseTime) {
    const timestamp = Date.now();
    const key = `metrics:${this.name}:${tier}`;
    
    const metric = {
      timestamp,
      success: success ? 1 : 0,
      responseTime,
      service: this.name,
      tier
    };
    
    await redisClient.lPush(key, JSON.stringify(metric));
    await redisClient.lTrim(key, 0, 999); // Keep last 1000 metrics
  }
}

// Initialize service simulators
const services = {};
SERVICES.forEach(name => {
  const reliability = 0.995 + (Math.random() * 0.004); // 99.5% to 99.9%
  services[name] = new ServiceSimulator(name, reliability);
});

// API Endpoints
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '../web/index.html'));
});

app.post('/api/request', async (req, res) => {
  const { service, tier = 'standard' } = req.body;
  
  if (!services[service]) {
    return res.status(404).json({ error: 'Service not found' });
  }
  
  try {
    const result = await services[service].processRequest(tier);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/sla-status', async (req, res) => {
  const slaStatus = {};
  
  for (const tier of Object.keys(SLA_TIERS)) {
    slaStatus[tier] = {};
    
    for (const serviceName of SERVICES) {
      const metrics = await getSLAMetrics(serviceName, tier);
      slaStatus[tier][serviceName] = metrics;
    }
  }
  
  res.json(slaStatus);
});

app.get('/api/error-budget', async (req, res) => {
  const { service, tier = 'standard' } = req.query;
  const budget = await calculateErrorBudget(service, tier);
  res.json(budget);
});

async function getSLAMetrics(service, tier) {
  const key = `metrics:${service}:${tier}`;
  const metricsData = await redisClient.lRange(key, 0, 99);
  
  if (metricsData.length === 0) {
    return { availability: 100, avgLatency: 0, p95Latency: 0, errorBudgetUsed: 0 };
  }
  
  const metrics = metricsData.map(m => JSON.parse(m));
  const successCount = metrics.filter(m => m.success).length;
  const availability = (successCount / metrics.length) * 100;
  
  const responseTimes = metrics.map(m => m.responseTime).sort((a, b) => a - b);
  const avgLatency = responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length;
  const p95Index = Math.floor(responseTimes.length * 0.95);
  const p95Latency = responseTimes[p95Index] || 0;
  
  const targetAvailability = SLA_TIERS[tier].availability;
  const errorBudgetUsed = Math.max(0, (targetAvailability - availability) / (100 - targetAvailability) * 100);
  
  return {
    availability: Math.round(availability * 100) / 100,
    avgLatency: Math.round(avgLatency),
    p95Latency: Math.round(p95Latency),
    errorBudgetUsed: Math.round(errorBudgetUsed * 100) / 100,
    slaTarget: targetAvailability
  };
}

async function calculateErrorBudget(service, tier) {
  const windowHours = 24; // 24-hour window
  const key = `metrics:${service}:${tier}`;
  const metricsData = await redisClient.lRange(key, 0, -1);
  
  const cutoffTime = Date.now() - (windowHours * 60 * 60 * 1000);
  const recentMetrics = metricsData
    .map(m => JSON.parse(m))
    .filter(m => m.timestamp > cutoffTime);
    
  if (recentMetrics.length === 0) {
    return { budgetRemaining: 100, burnRate: 0, timeToExhaustion: null };
  }
  
  const failureCount = recentMetrics.filter(m => !m.success).length;
  const totalRequests = recentMetrics.length;
  const failureRate = failureCount / totalRequests;
  
  const slaTarget = SLA_TIERS[tier].availability / 100;
  const errorBudget = 1 - slaTarget;
  const budgetUsed = failureRate / errorBudget;
  const budgetRemaining = Math.max(0, 100 - (budgetUsed * 100));
  
  // Calculate burn rate (failures per hour)
  const timeSpanHours = (Date.now() - Math.min(...recentMetrics.map(m => m.timestamp))) / (1000 * 60 * 60);
  const burnRate = failureCount / Math.max(timeSpanHours, 1);
  
  const timeToExhaustion = burnRate > 0 ? (errorBudget * totalRequests - failureCount) / burnRate : null;
  
  return {
    budgetRemaining: Math.round(budgetRemaining * 100) / 100,
    burnRate: Math.round(burnRate * 100) / 100,
    timeToExhaustion: timeToExhaustion ? Math.round(timeToExhaustion * 10) / 10 : null
  };
}

// WebSocket for real-time updates
wss.on('connection', (ws) => {
  console.log('Client connected to WebSocket');
  
  const interval = setInterval(async () => {
    try {
      const slaStatus = await getSLAStatusForWebSocket();
      ws.send(JSON.stringify({ type: 'sla-update', data: slaStatus }));
    } catch (error) {
      console.error('WebSocket update error:', error);
    }
  }, 2000);
  
  ws.on('close', () => {
    clearInterval(interval);
    console.log('Client disconnected from WebSocket');
  });
});

async function getSLAStatusForWebSocket() {
  const status = {};
  for (const tier of Object.keys(SLA_TIERS)) {
    status[tier] = {};
    for (const serviceName of SERVICES) {
      status[tier][serviceName] = await getSLAMetrics(serviceName, tier);
    }
  }
  return status;
}

// Background load generator
cron.schedule('*/5 * * * * *', () => {
  // Generate realistic traffic patterns
  SERVICES.forEach(serviceName => {
    const service = services[serviceName];
    const requestCount = Math.floor(Math.random() * 10) + 1;
    
    for (let i = 0; i < requestCount; i++) {
      const tier = Math.random() > 0.7 ? 'premium' : Math.random() > 0.5 ? 'standard' : 'basic';
      service.processRequest(tier).catch(console.error);
    }
  });
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log(`🚀 SLA Design Demo running on port ${PORT}`);
  console.log(`📊 Dashboard: http://localhost:${PORT}`);
});
