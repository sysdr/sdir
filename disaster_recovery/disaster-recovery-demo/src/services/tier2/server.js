const express = require('express');
const { Pool } = require('pg');
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
    new winston.transports.File({ filename: '/app/logs/inventory-service.log' }),
    new winston.transports.Console()
  ]
});

// PostgreSQL connection
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  idleTimeoutMillis: 30000
});

// Service state tracking
let serviceState = {
  startTime: Date.now(),
  isHealthy: true,
  disasterMode: false,
  rtoSeconds: parseInt(process.env.RTO_SECONDS) || 300,
  rpoSeconds: parseInt(process.env.RPO_SECONDS) || 60,
  inventoryUpdates: 0,
  lastBackup: null
};

// Health check endpoint
app.get('/health', async (req, res) => {
  const health = {
    service: 'inventory-service',
    tier: 2,
    status: serviceState.isHealthy && !serviceState.disasterMode ? 'healthy' : 'unhealthy',
    uptime: Date.now() - serviceState.startTime,
    rto: serviceState.rtoSeconds,
    rpo: serviceState.rpoSeconds,
    metrics: {
      updates: serviceState.inventoryUpdates,
      lastBackup: serviceState.lastBackup
    },
    timestamp: new Date().toISOString()
  };
  
  res.status(serviceState.isHealthy ? 200 : 503).json(health);
});

// Get inventory
app.get('/inventory', async (req, res) => {
  try {
    if (serviceState.disasterMode) {
      return res.status(503).json({ 
        error: 'Service in disaster mode',
        retryAfter: serviceState.rtoSeconds 
      });
    }
    
    const result = await pool.query('SELECT * FROM inventory ORDER BY id');
    res.json(result.rows);
  } catch (error) {
    logger.error('Inventory fetch failed:', error);
    res.status(500).json({ error: 'Inventory fetch failed' });
  }
});

// Update inventory
app.put('/inventory/:id', async (req, res) => {
  try {
    if (serviceState.disasterMode) {
      return res.status(503).json({ 
        error: 'Service in disaster mode',
        retryAfter: serviceState.rtoSeconds 
      });
    }
    
    const { id } = req.params;
    const { quantity } = req.body;
    
    const result = await pool.query(
      'UPDATE inventory SET quantity = $1, last_updated = CURRENT_TIMESTAMP WHERE id = $2 RETURNING *',
      [quantity, id]
    );
    
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    serviceState.inventoryUpdates++;
    logger.info('Inventory updated', { productId: id, newQuantity: quantity });
    
    res.json(result.rows[0]);
  } catch (error) {
    logger.error('Inventory update failed:', error);
    res.status(500).json({ error: 'Inventory update failed' });
  }
});

// Simulate disaster
app.post('/simulate/disaster', async (req, res) => {
  serviceState.disasterMode = true;
  serviceState.isHealthy = false;
  logger.warn('Disaster mode activated for inventory service');
  
  // Simulate recovery after RTO
  setTimeout(async () => {
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

// Backup endpoint for backup system
app.get('/backup/data', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM inventory');
    serviceState.lastBackup = new Date().toISOString();
    res.json({
      timestamp: serviceState.lastBackup,
      data: result.rows
    });
  } catch (error) {
    logger.error('Backup failed:', error);
    res.status(500).json({ error: 'Backup failed' });
  }
});

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  logger.info(`Inventory service (Tier 2) started on port ${PORT}`);
});
