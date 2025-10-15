const express = require('express');
const cors = require('cors');
const axios = require('axios');
const path = require('path');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Serve dashboard
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// API proxy endpoints to demonstrate cross-context communication
app.get('/api/health', async (req, res) => {
  try {
    const services = [
      { name: 'user-service', url: 'http://user-service:3001/health' },
      { name: 'product-service', url: 'http://product-service:3002/health' },
      { name: 'order-service', url: 'http://order-service:3003/health' },
      { name: 'payment-service', url: 'http://payment-service:3004/health' }
    ];

    const healthChecks = await Promise.allSettled(
      services.map(service => 
        axios.get(service.url, { timeout: 5000 })
          .then(response => ({ ...service, status: 'healthy', data: response.data }))
          .catch(error => ({ ...service, status: 'unhealthy', error: error.message }))
      )
    );

    res.json(healthChecks.map(result => result.value || result.reason));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/users', async (req, res) => {
  try {
    const response = await axios.get('http://user-service:3001/users');
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/products', async (req, res) => {
  try {
    const response = await axios.get('http://product-service:3002/products');
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/orders', async (req, res) => {
  try {
    const response = await axios.get('http://order-service:3003/orders');
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/payments', async (req, res) => {
  try {
    const response = await axios.get('http://payment-service:3004/payments');
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create new user
app.post('/api/users', async (req, res) => {
  try {
    const response = await axios.post('http://user-service:3001/users', req.body);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Create new order (demonstrates cross-context communication)
app.post('/api/orders', async (req, res) => {
  try {
    const response = await axios.post('http://order-service:3003/orders', req.body);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Process payment
app.post('/api/payments', async (req, res) => {
  try {
    const response = await axios.post('http://payment-service:3004/payments', req.body);
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update product price (demonstrates context isolation)
app.put('/api/products/:productId/price', async (req, res) => {
  try {
    const response = await axios.put(
      `http://product-service:3002/products/${req.params.productId}/price`,
      req.body
    );
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Metrics endpoint for dashboard
app.get('/api/metrics', async (req, res) => {
  try {
    const [users, products, orders, payments] = await Promise.allSettled([
      axios.get('http://user-service:3001/users'),
      axios.get('http://product-service:3002/products'),
      axios.get('http://order-service:3003/orders'),
      axios.get('http://payment-service:3004/payments')
    ]);

    const metrics = {
      users: {
        total: users.status === 'fulfilled' ? users.value.data.total : 0,
        context: 'User Management'
      },
      products: {
        total: products.status === 'fulfilled' ? products.value.data.total : 0,
        context: 'Product Catalog'
      },
      orders: {
        total: orders.status === 'fulfilled' ? orders.value.data.total : 0,
        context: 'Order Processing'
      },
      payments: {
        total: payments.status === 'fulfilled' ? payments.value.data.total : 0,
        context: 'Payment Processing'
      }
    };

    res.json(metrics);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🖥️ Dashboard running on port ${PORT}`);
  console.log(`📊 Visit http://localhost:${PORT} to view the Bounded Contexts Demo`);
});
