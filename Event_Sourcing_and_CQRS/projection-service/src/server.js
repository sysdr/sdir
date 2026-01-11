const axios = require('axios');
const redis = require('redis');
const WebSocket = require('ws');
const { EventTypes } = require('../shared/events');

const EVENT_STORE_URL = 'http://event-store:3001';
const REDIS_URL = 'redis://redis:6379';

let redisClient;
let lastProcessedSequence = 0;
let processingStats = {
  totalProcessed: 0,
  errors: 0,
  lagMs: 0
};

async function initRedis() {
  redisClient = redis.createClient({ url: REDIS_URL });
  await redisClient.connect();
  console.log('Connected to Redis');

  // Load last processed sequence
  const saved = await redisClient.get('projection:last_sequence');
  if (saved) {
    lastProcessedSequence = parseInt(saved);
    console.log(`Resuming from sequence ${lastProcessedSequence}`);
  }
}

// Process single event and update projection
async function processEvent(event) {
  try {
    // Normalize event format (handle both camelCase from WebSocket and snake_case from database)
    const sequence_number = event.sequence_number || event.sequenceNumber;
    const aggregate_id = event.aggregate_id || event.aggregateId;
    const event_type = event.event_type || event.type;
    let event_data = event.event_data || event.data;
    const timestamp = event.timestamp;
    
    // Parse event_data if it's a string (from database JSONB)
    if (typeof event_data === 'string') {
      try {
        event_data = JSON.parse(event_data);
      } catch (e) {
        throw new Error(`Failed to parse event_data: ${e.message}`);
      }
    }
    
    // Validate required fields
    if (!sequence_number || !aggregate_id || !event_type || !event_data || !timestamp) {
      throw new Error(`Invalid event format: missing required fields. Event: ${JSON.stringify(event)}`);
    }
    
    // Simulate processing delay (demonstrating eventual consistency)
    await new Promise(resolve => setTimeout(resolve, 100));

    switch (event_type) {
      case EventTypes.ACCOUNT_CREATED:
        if (!event_data || typeof event_data.initialBalance === 'undefined') {
          throw new Error(`ACCOUNT_CREATED event missing initialBalance: ${JSON.stringify(event_data)}`);
        }
        await redisClient.hSet(`account:${aggregate_id}`, {
          accountId: aggregate_id,
          balance: (parseFloat(event_data.initialBalance) || 0).toString(),
          transactionCount: '0',
          createdAt: timestamp,
          lastUpdated: timestamp
        });
        break;

      case EventTypes.MONEY_DEPOSITED:
        if (!event_data || typeof event_data.amount === 'undefined') {
          throw new Error(`MONEY_DEPOSITED event missing amount: ${JSON.stringify(event_data)}`);
        }
        const depositBalance = await redisClient.hGet(`account:${aggregate_id}`, 'balance');
        const depositCount = await redisClient.hGet(`account:${aggregate_id}`, 'transactionCount');
        await redisClient.hSet(`account:${aggregate_id}`, {
          balance: (parseFloat(depositBalance || 0) + parseFloat(event_data.amount || 0)).toString(),
          transactionCount: (parseInt(depositCount || 0) + 1).toString(),
          lastUpdated: timestamp
        });
        break;

      case EventTypes.MONEY_WITHDRAWN:
        if (!event_data || typeof event_data.amount === 'undefined') {
          throw new Error(`MONEY_WITHDRAWN event missing amount: ${JSON.stringify(event_data)}`);
        }
        const withdrawBalance = await redisClient.hGet(`account:${aggregate_id}`, 'balance');
        const withdrawCount = await redisClient.hGet(`account:${aggregate_id}`, 'transactionCount');
        await redisClient.hSet(`account:${aggregate_id}`, {
          balance: (parseFloat(withdrawBalance || 0) - parseFloat(event_data.amount || 0)).toString(),
          transactionCount: (parseInt(withdrawCount || 0) + 1).toString(),
          lastUpdated: timestamp
        });
        break;

      case EventTypes.MONEY_TRANSFERRED:
        if (!event_data || typeof event_data.fromAccountId === 'undefined' || 
            typeof event_data.toAccountId === 'undefined' || typeof event_data.amount === 'undefined') {
          throw new Error(`MONEY_TRANSFERRED event missing required fields: ${JSON.stringify(event_data)}`);
        }
        // Update both accounts
        const fromBalance = await redisClient.hGet(`account:${event_data.fromAccountId}`, 'balance');
        const fromCount = await redisClient.hGet(`account:${event_data.fromAccountId}`, 'transactionCount');
        await redisClient.hSet(`account:${event_data.fromAccountId}`, {
          balance: (parseFloat(fromBalance || 0) - parseFloat(event_data.amount || 0)).toString(),
          transactionCount: (parseInt(fromCount || 0) + 1).toString(),
          lastUpdated: timestamp
        });

        const toBalance = await redisClient.hGet(`account:${event_data.toAccountId}`, 'balance');
        const toCount = await redisClient.hGet(`account:${event_data.toAccountId}`, 'transactionCount');
        await redisClient.hSet(`account:${event_data.toAccountId}`, {
          balance: (parseFloat(toBalance || 0) + parseFloat(event_data.amount || 0)).toString(),
          transactionCount: (parseInt(toCount || 0) + 1).toString(),
          lastUpdated: timestamp
        });
        break;
    }

    // Update sequence tracking
    lastProcessedSequence = sequence_number;
    await redisClient.set('projection:last_sequence', lastProcessedSequence.toString());
    
    processingStats.totalProcessed++;
    
    // Calculate lag
    const eventTime = new Date(timestamp);
    processingStats.lagMs = Date.now() - eventTime.getTime();

    console.log(`Processed event ${sequence_number}: ${event_type}`);
  } catch (error) {
    processingStats.errors++;
    console.error('Error processing event:', error.message);
    console.error('Event details:', JSON.stringify(event, null, 2));
    // Don't throw - allow processing to continue for other events
    // throw error;
  }
}

// Catch-up: process any missed events
async function catchUp() {
  try {
    const response = await axios.get(`${EVENT_STORE_URL}/events`, {
      params: { fromSequence: lastProcessedSequence, limit: 100 }
    });

    for (const event of response.data) {
      await processEvent(event);
    }

    if (response.data.length > 0) {
      console.log(`Caught up: processed ${response.data.length} events`);
    }
  } catch (error) {
    console.error('Catch-up error:', error.message);
  }
}

// Listen for real-time events via WebSocket
function subscribeToEvents() {
  const ws = new WebSocket('ws://event-store:3001');
  
  ws.on('open', () => {
    console.log('Connected to event stream');
  });

  ws.on('message', async (data) => {
    try {
      const message = JSON.parse(data);
      if (message.type === 'NEW_EVENT') {
        try {
          await processEvent(message.event);
        } catch (error) {
          // Log error but don't crash - continue processing other events
          console.error('Error processing WebSocket event:', error.message);
          console.error('Event data:', JSON.stringify(message.event, null, 2));
        }
      }
    } catch (error) {
      console.error('WebSocket message parse error:', error.message);
    }
  });

  ws.on('close', () => {
    console.log('Event stream connection closed, reconnecting...');
    setTimeout(subscribeToEvents, 5000);
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error.message);
  });
}

// Projection replay (rebuild from scratch)
async function replayProjection() {
  console.log('Starting projection replay...');
  
  // Clear existing projections
  const keys = await redisClient.keys('account:*');
  if (keys.length > 0) {
    await redisClient.del(keys);
  }
  await redisClient.set('projection:last_sequence', '0');
  lastProcessedSequence = 0;
  processingStats = { totalProcessed: 0, errors: 0, lagMs: 0 };

  // Replay all events
  const response = await axios.get(`${EVENT_STORE_URL}/events/all/stream`);
  console.log(`Replaying ${response.data.length} events...`);
  
  for (const event of response.data) {
    await processEvent(event);
  }
  
  console.log('Replay complete');
}

async function start() {
  await initRedis();
  
  // Initial catch-up
  await catchUp();
  
  // Subscribe to real-time events
  subscribeToEvents();
  
  // Periodic catch-up (in case WebSocket misses something)
  setInterval(catchUp, 5000);

  // Expose stats endpoint
  const express = require('express');
  const cors = require('cors');
  const app = express();
  
  app.use(cors());
  app.use(express.json());
  
  app.get('/stats', (req, res) => {
    res.json({
      lastProcessedSequence,
      ...processingStats
    });
  });

  app.post('/replay', async (req, res) => {
    try {
      await replayProjection();
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  app.get('/health', (req, res) => res.json({ status: 'healthy' }));

  app.listen(3004, () => {
    console.log('Projection Service stats available on port 3004');
  });
}

start().catch(console.error);
