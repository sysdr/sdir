const express = require('express');
const redis = require('redis');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const REDIS_URL = 'redis://redis:6379';
let redisClient;

async function initRedis() {
  redisClient = redis.createClient({ url: REDIS_URL });
  await redisClient.connect();
  console.log('Query Service connected to Redis');
}

// Get account by ID
app.get('/accounts/:accountId', async (req, res) => {
  try {
    const { accountId } = req.params;
    const account = await redisClient.hGetAll(`account:${accountId}`);
    
    if (!account || Object.keys(account).length === 0) {
      return res.status(404).json({ error: 'Account not found' });
    }

    res.json({
      accountId: account.accountId,
      balance: parseFloat(account.balance),
      transactionCount: parseInt(account.transactionCount),
      createdAt: account.createdAt,
      lastUpdated: account.lastUpdated
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get all accounts
app.get('/accounts', async (req, res) => {
  try {
    const keys = await redisClient.keys('account:*');
    const accounts = [];

    for (const key of keys) {
      const account = await redisClient.hGetAll(key);
      accounts.push({
        accountId: account.accountId,
        balance: parseFloat(account.balance),
        transactionCount: parseInt(account.transactionCount),
        createdAt: account.createdAt,
        lastUpdated: account.lastUpdated
      });
    }

    res.json(accounts);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = 3003;

async function start() {
  await initRedis();
  app.listen(PORT, () => {
    console.log(`Query Service running on port ${PORT}`);
  });
}

start().catch(console.error);
