const express = require('express');
const axios = require('axios');
const cors = require('cors');
const { EventTypes, createEvent } = require('../shared/events');

const app = express();
app.use(cors());
app.use(express.json());

const EVENT_STORE_URL = 'http://event-store:3001';
const QUERY_SERVICE_URL = 'http://query-service:3003';

// In-memory command log for demo
const commandLog = [];

// Create account command
app.post('/commands/create-account', async (req, res) => {
  try {
    const { accountId, initialBalance = 0 } = req.body;
    
    // Validate command
    if (!accountId) {
      return res.status(400).json({ error: 'accountId required' });
    }

    // Check if account exists (via query service)
    try {
      const existing = await axios.get(`${QUERY_SERVICE_URL}/accounts/${accountId}`);
      if (existing.data) {
        return res.status(409).json({ error: 'Account already exists' });
      }
    } catch (err) {
      // Account doesn't exist, continue
    }

    // Generate event
    const event = createEvent(accountId, EventTypes.ACCOUNT_CREATED, {
      accountId,
      initialBalance
    });

    // Persist to event store
    await axios.post(`${EVENT_STORE_URL}/events`, event);

    commandLog.push({ command: 'CREATE_ACCOUNT', accountId, timestamp: new Date() });
    
    res.json({ success: true, event });
  } catch (error) {
    console.error('Command error:', error.message);
    res.status(500).json({ error: error.message });
  }
});

// Deposit command
app.post('/commands/deposit', async (req, res) => {
  try {
    const { accountId, amount } = req.body;
    
    if (!accountId || !amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid parameters' });
    }

    const event = createEvent(accountId, EventTypes.MONEY_DEPOSITED, {
      accountId,
      amount
    });

    await axios.post(`${EVENT_STORE_URL}/events`, event);

    commandLog.push({ command: 'DEPOSIT', accountId, amount, timestamp: new Date() });
    
    res.json({ success: true, event });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Withdraw command
app.post('/commands/withdraw', async (req, res) => {
  try {
    const { accountId, amount } = req.body;
    
    if (!accountId || !amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid parameters' });
    }

    // Check balance (eventual consistency - might be stale)
    const accountRes = await axios.get(`${QUERY_SERVICE_URL}/accounts/${accountId}`);
    const account = accountRes.data;
    
    if (account.balance < amount) {
      return res.status(400).json({ error: 'Insufficient funds' });
    }

    const event = createEvent(accountId, EventTypes.MONEY_WITHDRAWN, {
      accountId,
      amount
    });

    await axios.post(`${EVENT_STORE_URL}/events`, event);

    commandLog.push({ command: 'WITHDRAW', accountId, amount, timestamp: new Date() });
    
    res.json({ success: true, event });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Transfer command
app.post('/commands/transfer', async (req, res) => {
  try {
    const { fromAccountId, toAccountId, amount } = req.body;
    
    if (!fromAccountId || !toAccountId || !amount || amount <= 0) {
      return res.status(400).json({ error: 'Invalid parameters' });
    }

    // Check source balance
    const accountRes = await axios.get(`${QUERY_SERVICE_URL}/accounts/${fromAccountId}`);
    const account = accountRes.data;
    
    if (account.balance < amount) {
      return res.status(400).json({ error: 'Insufficient funds' });
    }

    const event = createEvent(fromAccountId, EventTypes.MONEY_TRANSFERRED, {
      fromAccountId,
      toAccountId,
      amount
    });

    await axios.post(`${EVENT_STORE_URL}/events`, event);

    commandLog.push({ 
      command: 'TRANSFER', 
      fromAccountId, 
      toAccountId, 
      amount, 
      timestamp: new Date() 
    });
    
    res.json({ success: true, event });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/commands/log', (req, res) => {
  res.json(commandLog.slice(-20));
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = 3002;
app.listen(PORT, () => {
  console.log(`Command Service running on port ${PORT}`);
});
