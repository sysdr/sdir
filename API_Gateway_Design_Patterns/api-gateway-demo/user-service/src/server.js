const express = require('express');
const app = express();

app.use(express.json());

app.get('/api/user/:userId', async (req, res) => {
  // Simulate realistic latency
  await new Promise(resolve => setTimeout(resolve, 50 + Math.random() * 50));
  
  res.json({
    id: req.params.userId,
    name: 'John Doe',
    email: 'john@example.com',
    avatar: 'https://ui-avatars.com/api/?name=John+Doe',
    memberSince: '2020-01-15',
    preferences: {
      language: 'en',
      timezone: 'UTC',
      notifications: true
    }
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => console.log(`User Service on port ${PORT}`));
