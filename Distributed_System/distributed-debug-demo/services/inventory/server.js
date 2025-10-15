const express = require('express');
const redis = require('redis');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

const client = redis.createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
client.connect();

// Simulate inventory data
const inventory = {
  'item1': { stock: 100, reserved: 0 },
  'item2': { stock: 50, reserved: 0 },
  'item3': { stock: 25, reserved: 0 }
};

async function logEvent(correlationId, event, data) {
  const logEntry = {
    timestamp: new Date().toISOString(),
    service: 'inventory-service',
    correlationId,
    event,
    data: JSON.stringify(data)
  };
  
  await client.lPush(`debug:${correlationId}`, JSON.stringify(logEntry));
  console.log(`[${correlationId}] ${event}:`, data);
}

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'inventory-service' });
});

app.post('/check', async (req, res) => {
  const correlationId = req.headers['x-correlation-id'];
  
  try {
    await logEvent(correlationId, 'INVENTORY_CHECK_START', {
      items: req.body.items
    });

    // Simulate processing time
    await new Promise(resolve => setTimeout(resolve, Math.random() * 100 + 50));

    let available = true;
    const itemDetails = [];

    for (const item of req.body.items) {
      const stock = inventory[item.id] || { stock: 0, reserved: 0 };
      const availableStock = stock.stock - stock.reserved;
      
      itemDetails.push({
        id: item.id,
        requested: item.quantity,
        available: availableStock,
        sufficient: availableStock >= item.quantity
      });

      if (availableStock < item.quantity) {
        available = false;
      }
    }

    // Simulate occasional stock issues
    if (Math.random() < 0.1) { // 10% chance
      available = false;
      itemDetails[0].sufficient = false;
    }

    await logEvent(correlationId, 'INVENTORY_CHECK_COMPLETE', {
      available,
      itemDetails
    });

    res.json({ 
      available, 
      items: itemDetails,
      correlationId
    });

  } catch (error) {
    await logEvent(correlationId, 'INVENTORY_ERROR', { error: error.message });
    res.status(500).json({ error: error.message, correlationId });
  }
});

app.listen(3003, () => {
  console.log('Inventory service running on port 3003');
});
