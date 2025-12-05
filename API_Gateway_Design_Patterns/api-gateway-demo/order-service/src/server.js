const express = require('express');
const app = express();

app.use(express.json());

app.get('/api/orders/:userId', async (req, res) => {
  // Simulate realistic latency
  await new Promise(resolve => setTimeout(resolve, 80 + Math.random() * 80));
  
  res.json({
    orders: [
      {
        id: 'ORD-001',
        date: '2024-11-20',
        amount: 149.99,
        status: 'delivered',
        items: 3
      },
      {
        id: 'ORD-002',
        date: '2024-11-25',
        amount: 89.50,
        status: 'shipped',
        items: 2
      },
      {
        id: 'ORD-003',
        date: '2024-11-27',
        amount: 299.99,
        status: 'processing',
        items: 5
      }
    ],
    totalOrders: 3,
    totalSpent: 539.48
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log(`Order Service on port ${PORT}`));
