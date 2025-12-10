const express = require('express');
const app = express();

app.use(express.json());

app.get('/api/analytics/:userId', async (req, res) => {
  // Simulate realistic latency
  await new Promise(resolve => setTimeout(resolve, 60 + Math.random() * 60));
  
  res.json({
    pageViews: 1247,
    sessionDuration: 1832,
    bounceRate: 0.32,
    topPages: [
      { path: '/dashboard', views: 523 },
      { path: '/products', views: 412 },
      { path: '/orders', views: 312 }
    ],
    deviceBreakdown: {
      mobile: 0.45,
      desktop: 0.42,
      tablet: 0.13
    }
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = process.env.PORT || 3003;
app.listen(PORT, () => console.log(`Analytics Service on port ${PORT}`));
