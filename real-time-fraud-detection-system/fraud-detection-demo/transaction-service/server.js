const express = require('express');
const { Kafka } = require('kafkajs');
const { createClient } = require('redis');
const { Pool } = require('pg');
const cors = require('cors');
const WebSocket = require('ws');

const app = express();
app.use(cors());
app.use(express.json());

const kafka = new Kafka({
  clientId: 'transaction-service',
  brokers: [process.env.KAFKA_BROKER || 'localhost:9092']
});

const producer = kafka.producer();
const consumer = kafka.consumer({ groupId: 'transaction-results' });

const redis = createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
const pool = new Pool({
  host: process.env.PG_HOST || 'localhost',
  user: process.env.PG_USER || 'fraud',
  password: process.env.PG_PASSWORD || 'fraud123',
  database: process.env.PG_DATABASE || 'frauddb',
  port: 5432
});

let wsClients = [];

async function init() {
  await redis.connect();
  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topics: ['fraud-decisions'], fromBeginning: false });
  
  await consumer.run({
    eachMessage: async ({ message }) => {
      const decision = JSON.parse(message.value.toString());
      
      // Save to database
      await pool.query(
        `UPDATE transactions 
         SET risk_score = $1, decision = $2, features = $3 
         WHERE transaction_id = $4`,
        [decision.riskScore, decision.decision, JSON.stringify(decision.features), decision.transactionId]
      );
      
      // Broadcast to WebSocket clients
      wsClients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify({ type: 'decision', data: decision }));
        }
      });
      
      console.log(`✅ Decision recorded: ${decision.transactionId} - ${decision.decision} (Score: ${decision.riskScore})`);
    }
  });
}

// Submit transaction
app.post('/api/transactions', async (req, res) => {
  const transaction = {
    transactionId: `TXN-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
    ...req.body,
    timestamp: new Date().toISOString()
  };
  
  // Save to database
  await pool.query(
    `INSERT INTO transactions (transaction_id, user_id, amount, merchant, device_id, ip_address, latitude, longitude, timestamp)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
    [transaction.transactionId, transaction.userId, transaction.amount, transaction.merchant,
     transaction.deviceId, transaction.ipAddress, transaction.latitude, transaction.longitude, transaction.timestamp]
  );
  
  // Send to Kafka
  await producer.send({
    topic: 'transactions',
    messages: [{ value: JSON.stringify(transaction) }]
  });
  
  console.log(`📝 Transaction submitted: ${transaction.transactionId}`);
  res.json({ success: true, transactionId: transaction.transactionId });
});

// Get transactions
app.get('/api/transactions', async (req, res) => {
  const result = await pool.query(
    'SELECT * FROM transactions ORDER BY timestamp DESC LIMIT 50'
  );
  res.json(result.rows);
});

// Get stats
app.get('/api/stats', async (req, res) => {
  const total = await pool.query('SELECT COUNT(*) FROM transactions WHERE timestamp > NOW() - INTERVAL \'1 hour\'');
  const approved = await pool.query('SELECT COUNT(*) FROM transactions WHERE decision = \'APPROVE\' AND timestamp > NOW() - INTERVAL \'1 hour\'');
  const challenged = await pool.query('SELECT COUNT(*) FROM transactions WHERE decision = \'CHALLENGE\' AND timestamp > NOW() - INTERVAL \'1 hour\'');
  const blocked = await pool.query('SELECT COUNT(*) FROM transactions WHERE decision = \'BLOCK\' AND timestamp > NOW() - INTERVAL \'1 hour\'');
  
  res.json({
    total: parseInt(total.rows[0].count),
    approved: parseInt(approved.rows[0].count),
    challenged: parseInt(challenged.rows[0].count),
    blocked: parseInt(blocked.rows[0].count)
  });
});

const server = app.listen(3001, () => {
  console.log('🚀 Transaction Service running on port 3001');
  init().catch(console.error);
});

// WebSocket server
const wss = new WebSocket.Server({ server });
wss.on('connection', (ws) => {
  wsClients.push(ws);
  ws.on('close', () => {
    wsClients = wsClients.filter(client => client !== ws);
  });
});
