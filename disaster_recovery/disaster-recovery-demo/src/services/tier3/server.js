const express = require('express');
const { InfluxDB, Point } = require('@influxdata/influxdb-client');
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
    new winston.transports.File({ filename: '/app/logs/analytics-service.log' }),
    new winston.transports.Console()
  ]
});

// InfluxDB setup
const influxDB = new InfluxDB({
  url: process.env.INFLUX_URL || 'http://localhost:8086',
  token: 'my-super-secret-auth-token'
});

const writeApi = influxDB.getWriteApi('disaster-recovery-org', 'metrics');

// Service state tracking
let serviceState = {
  startTime: Date.now(),
  isHealthy: true,
  disasterMode: false,
  rtoSeconds: parseInt(process.env.RTO_SECONDS) || 14400,
  rpoSeconds: parseInt(process.env.RPO_SECONDS) || 3600,
  eventsProcessed: 0,
  lastBackup: null
};

// Health check endpoint
app.get('/health', async (req, res) => {
  const health = {
    service: 'analytics-service',
    tier: 3,
    status: serviceState.isHealthy && !serviceState.disasterMode ? 'healthy' : 'unhealthy',
    uptime: Date.now() - serviceState.startTime,
    rto: serviceState.rtoSeconds,
    rpo: serviceState.rpoSeconds,
    metrics: {
      eventsProcessed: serviceState.eventsProcessed,
      lastBackup: serviceState.lastBackup
    },
    timestamp: new Date().toISOString()
  };
  
  res.status(serviceState.isHealthy ? 200 : 503).json(health);
});

// Process analytics event
app.post('/analytics/event', async (req, res) => {
  try {
    if (serviceState.disasterMode) {
      return res.status(503).json({ 
        error: 'Service in disaster mode',
        retryAfter: serviceState.rtoSeconds 
      });
    }
    
    const { eventType, userId, metadata = {} } = req.body;
    
    const point = new Point('user_events')
      .tag('event_type', eventType)
      .tag('user_id', userId)
      .floatField('value', 1)
      .timestamp(new Date());
    
    // Add metadata as fields
    Object.entries(metadata).forEach(([key, value]) => {
      if (typeof value === 'number') {
        point.floatField(key, value);
      } else {
        point.stringField(key, String(value));
      }
    });
    
    writeApi.writePoint(point);
    await writeApi.flush();
    
    serviceState.eventsProcessed++;
    logger.info('Analytics event processed', { eventType, userId });
    
    res.json({
      success: true,
      message: 'Event processed successfully'
    });
    
  } catch (error) {
    logger.error('Analytics processing failed:', error);
    res.status(500).json({ error: 'Analytics processing failed' });
  }
});

// Get analytics summary
app.get('/analytics/summary', async (req, res) => {
  try {
    if (serviceState.disasterMode) {
      return res.status(503).json({ 
        error: 'Service in disaster mode',
        retryAfter: serviceState.rtoSeconds 
      });
    }
    
    // Simulate analytics query (would normally query InfluxDB)
    const summary = {
      totalEvents: serviceState.eventsProcessed,
      period: '24h',
      topEvents: [
        { type: 'page_view', count: Math.floor(serviceState.eventsProcessed * 0.6) },
        { type: 'click', count: Math.floor(serviceState.eventsProcessed * 0.3) },
        { type: 'purchase', count: Math.floor(serviceState.eventsProcessed * 0.1) }
      ],
      timestamp: new Date().toISOString()
    };
    
    res.json(summary);
  } catch (error) {
    logger.error('Analytics summary failed:', error);
    res.status(500).json({ error: 'Analytics summary failed' });
  }
});

// Simulate disaster
app.post('/simulate/disaster', (req, res) => {
  serviceState.disasterMode = true;
  serviceState.isHealthy = false;
  logger.warn('Disaster mode activated for analytics service');
  
  // Simulate recovery after RTO
  setTimeout(() => {
    serviceState.disasterMode = false;
    serviceState.isHealthy = true;
    logger.info('Service recovered from disaster');
  }, serviceState.rtoSeconds * 1000);
  
  res.json({ 
    message: 'Disaster simulation started',
    estimatedRecoveryTime: serviceState.rtoSeconds,
    dataLossWindow: serviceState.rpoSeconds
  });
});

// Backup endpoint
app.get('/backup/data', async (req, res) => {
  try {
    serviceState.lastBackup = new Date().toISOString();
    res.json({
      timestamp: serviceState.lastBackup,
      eventsCount: serviceState.eventsProcessed,
      message: 'Analytics backup completed'
    });
  } catch (error) {
    logger.error('Backup failed:', error);
    res.status(500).json({ error: 'Backup failed' });
  }
});

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  logger.info(`Analytics service (Tier 3) started on port ${PORT}`);
});
