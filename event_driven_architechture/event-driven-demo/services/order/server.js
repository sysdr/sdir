const express = require('express');
const { createClient } = require('redis');
const { Client } = require('pg');
const { v4: uuidv4 } = require('uuid');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

let redisClient, pgClient;

// Event Sourcing: Store events as facts
class EventStore {
  async saveEvent(streamId, event) {
    const eventData = {
      id: uuidv4(),
      streamId,
      eventType: event.type,
      data: JSON.stringify(event.data),
      timestamp: new Date().toISOString()
    };
    
    await pgClient.query(
      'INSERT INTO events (id, stream_id, event_type, data, timestamp) VALUES ($1, $2, $3, $4, $5)',
      [eventData.id, eventData.streamId, eventData.eventType, eventData.data, eventData.timestamp]
    );
    
    // Publish to Redis Stream
    await redisClient.xAdd('order-events', '*', {
      eventId: eventData.id,
      eventType: eventData.eventType,
      streamId: eventData.streamId,
      data: eventData.data
    });
    
    return eventData;
  }
  
  async getEvents(streamId) {
    const result = await pgClient.query(
      'SELECT * FROM events WHERE stream_id = $1 ORDER BY timestamp ASC',
      [streamId]
    );
    return result.rows.map(row => ({
      ...row,
      data: JSON.parse(row.data)
    }));
  }
}

const eventStore = new EventStore();

// Order Aggregate
class Order {
  constructor() {
    this.id = null;
    this.customerId = null;
    this.items = [];
    this.status = 'pending';
    this.totalAmount = 0;
  }
  
  static fromEvents(events) {
    const order = new Order();
    events.forEach(event => order.apply(event));
    return order;
  }
  
  apply(event) {
    switch (event.event_type || event.eventType) {
      case 'OrderCreated':
        this.id = event.data.orderId;
        this.customerId = event.data.customerId;
        this.items = event.data.items;
        this.totalAmount = event.data.totalAmount;
        this.status = 'created';
        break;
      case 'OrderConfirmed':
        this.status = 'confirmed';
        break;
      case 'OrderCancelled':
        this.status = 'cancelled';
        break;
    }
  }
}

// Routes
app.post('/orders', async (req, res) => {
  try {
    const { customerId, items } = req.body;
    const orderId = uuidv4();
    const totalAmount = items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    
    const event = {
      type: 'OrderCreated',
      data: { orderId, customerId, items, totalAmount }
    };
    
    await eventStore.saveEvent(orderId, event);
    
    res.json({ orderId, status: 'created' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/orders/:id', async (req, res) => {
  try {
    const events = await eventStore.getEvents(req.params.id);
    const order = Order.fromEvents(events);
    res.json(order);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/orders/:id/confirm', async (req, res) => {
  try {
    const event = {
      type: 'OrderConfirmed',
      data: { orderId: req.params.id }
    };
    await eventStore.saveEvent(req.params.id, event);
    res.json({ status: 'confirmed' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'order' }));

async function connectWithRetry(client, maxRetries = 10, delay = 2000) {
  for (let i = 0; i < maxRetries; i++) {
    try {
      await client.connect();
      console.log('Database connection successful');
      return;
    } catch (error) {
      console.log(`Connection attempt ${i + 1} failed:`, error.message);
      if (i === maxRetries - 1) {
        throw error;
      }
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
}

async function init() {
  try {
    redisClient = createClient({ url: process.env.REDIS_URL });
    await redisClient.connect();
    console.log('Redis connection successful');
    
    pgClient = new Client({ connectionString: process.env.DB_URL });
    await connectWithRetry(pgClient);
    
    // Create events table
    await pgClient.query(`
      CREATE TABLE IF NOT EXISTS events (
        id UUID PRIMARY KEY,
        stream_id UUID NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        data JSONB NOT NULL,
        timestamp TIMESTAMP NOT NULL
      )
    `);
    
    console.log('Order Service started on port 3001');
  } catch (error) {
    console.error('Failed to initialize Order Service:', error);
    process.exit(1);
  }
}

app.listen(3001, init);
