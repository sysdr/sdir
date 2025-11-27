const express = require('express');
const { Pool } = require('pg');
const WebSocket = require('ws');
const cors = require('cors');
const app = express();
app.use(cors());
app.use(express.json());

const PORT = 3003;

const pool = new Pool({
  host: 'postgres',
  user: 'edge_user',
  password: 'edge_pass',
  database: 'edge_db',
  port: 5432
});

let metrics = {
  stored: 0,
  analyzed: 0,
  avgLatency: 0
};

// Initialize database
async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS sensor_data (
      id SERIAL PRIMARY KEY,
      device_id VARCHAR(50),
      temperature FLOAT,
      humidity FLOAT,
      action VARCHAR(50),
      processed_at VARCHAR(50),
      region VARCHAR(50),
      timestamp TIMESTAMP DEFAULT NOW()
    )
  `);
  
  await pool.query(`
    CREATE TABLE IF NOT EXISTS analytics (
      id SERIAL PRIMARY KEY,
      metric_type VARCHAR(50),
      value FLOAT,
      calculated_at TIMESTAMP DEFAULT NOW()
    )
  `);
}

initDB().catch(console.error);

// Long-term storage and analytics
async function storeAndAnalyze(data) {
  const start = Date.now();
  
  // Store in database
  await pool.query(
    'INSERT INTO sensor_data (device_id, temperature, humidity, action, processed_at, region) VALUES ($1, $2, $3, $4, $5, $6)',
    [data.deviceId, data.temperature, data.humidity, data.action, data.processedAt, data.region || 'unknown']
  );
  
  // Perform analytics
  const avgResult = await pool.query(
    'SELECT AVG(temperature) as avg_temp, AVG(humidity) as avg_humidity, COUNT(*) as total FROM sensor_data WHERE timestamp > NOW() - INTERVAL \'1 hour\''
  );
  
  const analytics = avgResult.rows[0];
  
  await pool.query(
    'INSERT INTO analytics (metric_type, value) VALUES ($1, $2), ($3, $4)',
    ['avg_temperature', analytics.avg_temp, 'avg_humidity', analytics.avg_humidity]
  );
  
  const latency = Date.now() - start;
  metrics.stored++;
  metrics.analyzed++;
  metrics.avgLatency = (metrics.avgLatency + latency) / 2;
  
  return {
    ...data,
    analytics: {
      globalAvgTemp: parseFloat(analytics.avg_temp || 0).toFixed(1),
      globalAvgHumidity: parseFloat(analytics.avg_humidity || 0).toFixed(1),
      totalRecords: parseInt(analytics.total || 0)
    },
    processedAt: 'central-cloud',
    latency
  };
}

app.post('/store', async (req, res) => {
  try {
    const result = await storeAndAnalyze(req.body);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/metrics', async (req, res) => {
  res.json({
    tier: 'central-cloud',
    ...metrics,
    latencyTarget: '100-200ms'
  });
});

app.get('/analytics', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM analytics ORDER BY calculated_at DESC LIMIT 10'
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', tier: 'central-cloud' });
});

app.listen(PORT, () => {
  console.log(`Central Cloud running on port ${PORT}`);
  console.log('Storing and analyzing with <200ms latency');
});
