const express = require('express');
const path = require('path');
const axios = require('axios');

const app = express();
const PORT = 3000;

app.use(express.json());
app.use(express.static('public'));

// Proxy endpoint to get status from all services
app.get('/api/status', async (req, res) => {
  try {
    const [serviceA, serviceB, serviceC] = await Promise.allSettled([
      axios.get('http://service-a:3001/status', { timeout: 1000 }),
      axios.get('http://service-b:3002/status', { timeout: 1000 }),
      axios.get('http://service-c:3003/status', { timeout: 1000 })
    ]);

    res.json({
      serviceA: serviceA.status === 'fulfilled' ? serviceA.value.data : { error: 'Timeout' },
      serviceB: serviceB.status === 'fulfilled' ? serviceB.value.data : { error: 'Timeout' },
      serviceC: serviceC.status === 'fulfilled' ? serviceC.value.data : { error: 'Timeout' },
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Control endpoint
app.post('/api/control', async (req, res) => {
  try {
    const { delay } = req.body;
    await axios.post('http://service-a:3001/control/slow', { delay });
    res.json({ success: true, delay });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(PORT, () => {
  console.log(`✅ Dashboard running on http://localhost:${PORT}`);
});
