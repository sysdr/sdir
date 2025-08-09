const axios = require('axios');
const { createClient } = require('redis');
const { Pool } = require('pg');
const { CronJob } = require('cron');
const winston = require('winston');
const fs = require('fs-extra');
const path = require('path');

// Logger setup
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  transports: [
    new winston.transports.File({ filename: '/app/logs/backup-system.log' }),
    new winston.transports.Console()
  ]
});

// Database connections
let redisClient;
let pgPool;

const connectDatabases = async () => {
  try {
    // Redis connection
    redisClient = createClient({ url: process.env.REDIS_URL });
    await redisClient.connect();
    
    // PostgreSQL connection
    pgPool = new Pool({
      connectionString: process.env.DATABASE_URL,
      max: 5
    });
    
    logger.info('Connected to all databases');
  } catch (error) {
    logger.error('Database connection failed:', error);
    process.exit(1);
  }
};

// Backup functions
const backupTier1Data = async () => {
  try {
    const timestamp = new Date().toISOString();
    const backupDir = `/app/backups/tier1/${timestamp}`;
    await fs.ensureDir(backupDir);
    
    // Backup Redis data
    const keys = await redisClient.keys('*');
    const data = {};
    
    for (const key of keys) {
      data[key] = await redisClient.get(key);
    }
    
    await fs.writeJson(path.join(backupDir, 'redis-backup.json'), data);
    
    const backupSize = JSON.stringify(data).length;
    logger.info('Tier 1 backup completed', { 
      timestamp, 
      keyCount: keys.length, 
      backupSize 
    });
    
    return { timestamp, backupSize, keyCount: keys.length };
  } catch (error) {
    logger.error('Tier 1 backup failed:', error);
    throw error;
  }
};

const backupTier2Data = async () => {
  try {
    const timestamp = new Date().toISOString();
    const backupDir = `/app/backups/tier2/${timestamp}`;
    await fs.ensureDir(backupDir);
    
    // Backup PostgreSQL data
    const inventoryResult = await pgPool.query('SELECT * FROM inventory');
    const ordersResult = await pgPool.query('SELECT * FROM orders');
    
    const data = {
      inventory: inventoryResult.rows,
      orders: ordersResult.rows
    };
    
    await fs.writeJson(path.join(backupDir, 'postgres-backup.json'), data);
    
    const backupSize = JSON.stringify(data).length;
    logger.info('Tier 2 backup completed', { 
      timestamp, 
      backupSize,
      inventoryCount: inventoryResult.rows.length,
      ordersCount: ordersResult.rows.length
    });
    
    return { timestamp, backupSize, recordCount: inventoryResult.rows.length + ordersResult.rows.length };
  } catch (error) {
    logger.error('Tier 2 backup failed:', error);
    throw error;
  }
};

const backupTier3Data = async () => {
  try {
    const timestamp = new Date().toISOString();
    const backupDir = `/app/backups/tier3/${timestamp}`;
    await fs.ensureDir(backupDir);
    
    // Call analytics service backup endpoint
    const response = await axios.get('http://analytics-service:3000/backup/data');
    
    await fs.writeJson(path.join(backupDir, 'analytics-backup.json'), response.data);
    
    const backupSize = JSON.stringify(response.data).length;
    logger.info('Tier 3 backup completed', { timestamp, backupSize });
    
    return { timestamp, backupSize, eventsCount: response.data.eventsCount };
  } catch (error) {
    logger.error('Tier 3 backup failed:', error);
    throw error;
  }
};

// Recovery functions
const recoverTier1Data = async (backupTimestamp) => {
  try {
    const backupFile = `/app/backups/tier1/${backupTimestamp}/redis-backup.json`;
    const data = await fs.readJson(backupFile);
    
    // Clear existing data
    await redisClient.flushAll();
    
    // Restore data
    for (const [key, value] of Object.entries(data)) {
      await redisClient.set(key, value);
    }
    
    logger.info('Tier 1 recovery completed', { backupTimestamp, keyCount: Object.keys(data).length });
    return { success: true, restoredKeys: Object.keys(data).length };
  } catch (error) {
    logger.error('Tier 1 recovery failed:', error);
    throw error;
  }
};

// Scheduled backup jobs
const setupBackupJobs = () => {
  // Tier 1: Every 10 seconds (RPO: 0 seconds)
  new CronJob('*/10 * * * * *', async () => {
    try {
      await backupTier1Data();
    } catch (error) {
      logger.error('Scheduled Tier 1 backup failed:', error);
    }
  }, null, true);
  
  // Tier 2: Every minute (RPO: 1 minute)
  new CronJob('0 * * * * *', async () => {
    try {
      await backupTier2Data();
    } catch (error) {
      logger.error('Scheduled Tier 2 backup failed:', error);
    }
  }, null, true);
  
  // Tier 3: Every hour (RPO: 1 hour)
  new CronJob('0 0 * * * *', async () => {
    try {
      await backupTier3Data();
    } catch (error) {
      logger.error('Scheduled Tier 3 backup failed:', error);
    }
  }, null, true);
  
  logger.info('Backup jobs scheduled');
};

// Start backup system
const startBackupSystem = async () => {
  try {
    await connectDatabases();
    setupBackupJobs();
    
    // Initial backups
    setTimeout(() => backupTier1Data().catch(console.error), 5000);
    setTimeout(() => backupTier2Data().catch(console.error), 10000);
    setTimeout(() => backupTier3Data().catch(console.error), 15000);
    
    logger.info('Backup system started successfully');
  } catch (error) {
    logger.error('Backup system startup failed:', error);
    process.exit(1);
  }
};

startBackupSystem();
