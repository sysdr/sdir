const express = require('express');
const { createClient } = require('redis');
const { Client } = require('pg');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

let redisClient, pgClient;

// CQRS: Separate read and write models
class InventoryWriteModel {
  async reserveItems(orderId, items) {
    for (const item of items) {
      const event = {
        type: 'ItemReserved',
        data: { orderId, productId: item.productId, quantity: item.quantity }
      };
      
      await pgClient.query(
        'INSERT INTO inventory_events (id, event_type, data, timestamp) VALUES ($1, $2, $3, $4)',
        [require('uuid').v4(), event.type, JSON.stringify(event.data), new Date()]
      );
      
      await redisClient.xAdd('inventory-events', '*', {
        eventType: event.type,
        data: JSON.stringify(event.data)
      });
    }
  }
}

class InventoryReadModel {
  async getStock(productId) {
    const result = await redisClient.hGet('inventory:stock', productId);
    return parseInt(result || '0');
  }
  
  async updateStock(productId, quantity) {
    await redisClient.hSet('inventory:stock', productId, quantity.toString());
  }
}

const writeModel = new InventoryWriteModel();
const readModel = new InventoryReadModel();

// Event consumer
async function processEvents() {
  try {
    const events = await redisClient.xRead(
      { key: 'order-events', id: '$' },
      { BLOCK: 1000 }
    );
    
    if (events) {
      for (const event of events[0].messages) {
        const data = JSON.parse(event.message.data);
        if (event.message.eventType === 'OrderCreated') {
          await writeModel.reserveItems(data.orderId, data.items);
          console.log(`Reserved items for order ${data.orderId}`);
        }
      }
    }
  } catch (error) {
    console.error('Event processing error:', error);
  }
  setTimeout(processEvents, 100);
}

// Routes
app.get('/inventory/:productId', async (req, res) => {
  try {
    const stock = await readModel.getStock(req.params.productId);
    res.json({ productId: req.params.productId, stock });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/inventory/:productId/stock', async (req, res) => {
  try {
    const { quantity } = req.body;
    await readModel.updateStock(req.params.productId, quantity);
    res.json({ productId: req.params.productId, stock: quantity });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'inventory' }));

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
    
    await pgClient.query(`
      CREATE TABLE IF NOT EXISTS inventory_events (
        id UUID PRIMARY KEY,
        event_type VARCHAR(100) NOT NULL,
        data JSONB NOT NULL,
        timestamp TIMESTAMP NOT NULL
      )
    `);
    
    // Initialize stock
    await readModel.updateStock('product-1', 100);
    await readModel.updateStock('product-2', 50);
    await readModel.updateStock('product-3', 25);
    
    processEvents();
    console.log('Inventory Service started on port 3002');
  } catch (error) {
    console.error('Failed to initialize Inventory Service:', error);
    process.exit(1);
  }
}

app.listen(3002, init);
