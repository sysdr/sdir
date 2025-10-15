const express = require('express');
const { Pool } = require('pg');
const redis = require('redis');
const cors = require('cors');

const app = express();
const port = process.env.APP_PORT || 3001;
const serviceName = process.env.SERVICE_NAME || 'app-service';

app.use(cors());
app.use(express.json());

// Database connection
const dbPool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5432,
  database: 'ecommerce',
  user: 'admin',
  password: 'password123',
  max: 10,
  idleTimeoutMillis: 30000,
});

// Redis connection
const redisClient = redis.createClient({
  socket: {
    host: process.env.REDIS_HOST || 'localhost',
    port: 6379
  },
  password: 'redis123'
});

redisClient.connect().catch(console.error);

// Health check endpoint
app.get('/health', async (req, res) => {
  try {
    // Check database
    await dbPool.query('SELECT 1');
    
    // Check redis
    await redisClient.ping();
    
    res.json({ 
      status: 'healthy',
      service: serviceName,
      timestamp: new Date().toISOString(),
      checks: {
        database: 'healthy',
        redis: 'healthy'
      }
    });
  } catch (error) {
    res.status(500).json({ 
      status: 'unhealthy',
      service: serviceName,
      error: error.message 
    });
  }
});

// Deep health check
app.get('/health/deep', async (req, res) => {
  try {
    // Test database functionality
    const dbResult = await dbPool.query('SELECT COUNT(*) FROM products');
    
    // Test redis functionality
    await redisClient.set('health_check', Date.now(), { EX: 10 });
    const redisResult = await redisClient.get('health_check');
    
    res.json({
      status: 'healthy',
      service: serviceName,
      timestamp: new Date().toISOString(),
      checks: {
        database: { status: 'healthy', productCount: dbResult.rows[0].count },
        redis: { status: 'healthy', testValue: redisResult }
      }
    });
  } catch (error) {
    res.status(500).json({
      status: 'unhealthy',
      service: serviceName,
      error: error.message
    });
  }
});

// Get products
app.get('/api/products', async (req, res) => {
  try {
    const result = await dbPool.query('SELECT * FROM products ORDER BY id');
    res.json({
      products: result.rows,
      service: serviceName
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create order
app.post('/api/orders', async (req, res) => {
  const { userId, productId, quantity } = req.body;
  
  try {
    // Begin transaction
    const client = await dbPool.connect();
    
    try {
      await client.query('BEGIN');
      
      // Check stock
      const productResult = await client.query('SELECT * FROM products WHERE id = $1', [productId]);
      const product = productResult.rows[0];
      
      if (!product || product.stock < quantity) {
        throw new Error('Insufficient stock');
      }
      
      // Update stock
      await client.query('UPDATE products SET stock = stock - $1 WHERE id = $2', [quantity, productId]);
      
      // Create order
      const total = product.price * quantity;
      const orderResult = await client.query(
        'INSERT INTO orders (user_id, product_id, quantity, total_amount) VALUES ($1, $2, $3, $4) RETURNING *',
        [userId, productId, quantity, total]
      );
      
      // Cache order in Redis
      await redisClient.setEx(`order:${orderResult.rows[0].id}`, 3600, JSON.stringify(orderResult.rows[0]));
      
      await client.query('COMMIT');
      
      res.json({
        order: orderResult.rows[0],
        service: serviceName
      });
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Simulate service failure
app.post('/api/simulate-failure', (req, res) => {
  console.log(`${serviceName} simulating failure...`);
  setTimeout(() => {
    process.exit(1);
  }, 1000);
  res.json({ message: `${serviceName} will fail in 1 second` });
});

app.listen(port, () => {
  console.log(`${serviceName} running on port ${port}`);
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('Received SIGTERM, shutting down gracefully');
  await dbPool.end();
  await redisClient.quit();
  process.exit(0);
});
