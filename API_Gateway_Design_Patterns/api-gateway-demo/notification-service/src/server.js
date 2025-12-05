const express = require('express');
const app = express();

app.use(express.json());

app.get('/api/notifications/:userId', async (req, res) => {
  // Simulate occasional timeouts (30% chance)
  if (process.env.SIMULATE_TIMEOUT === 'true' && Math.random() < 0.3) {
    await new Promise(resolve => setTimeout(resolve, 5000));
  } else {
    await new Promise(resolve => setTimeout(resolve, 70 + Math.random() * 50));
  }
  
  res.json({
    count: 7,
    unread: 3,
    notifications: [
      { id: 1, type: 'order', message: 'Order shipped', read: false },
      { id: 2, type: 'promo', message: 'New sale alert', read: false },
      { id: 3, type: 'system', message: 'Profile updated', read: true }
    ]
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = process.env.PORT || 3004;
app.listen(PORT, () => console.log(`Notification Service on port ${PORT}`));
