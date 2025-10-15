const express = require('express');
const fetch = require('node-fetch');
const cors = require('cors');
const path = require('path');
const app = express();
const PORT = 4000;

app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// Serve dashboard HTML
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Aggregate metrics from both versions
app.get('/api/metrics', async (req, res) => {
  try {
    const [stableResponse, canaryResponse] = await Promise.all([
      fetch('http://stable-app:3000/metrics').catch(() => ({ json: () => ({ error: 'stable unreachable' }) })),
      fetch('http://canary-app:3000/metrics').catch(() => ({ json: () => ({ error: 'canary unreachable' }) }))
    ]);
    
    const stableMetrics = await stableResponse.json();
    const canaryMetrics = await canaryResponse.json();
    
    res.json({
      stable: stableMetrics,
      canary: canaryMetrics,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Test endpoint to simulate traffic
app.post('/api/test-traffic', async (req, res) => {
  const { requests = 50 } = req.body;
  const results = { stable: 0, canary: 0, errors: 0 };
  
  for (let i = 0; i < requests; i++) {
    try {
      const response = await fetch('http://nginx/', {
        headers: { 'X-Request-ID': Math.random().toString() }
      });
      const data = await response.json();
      
      if (response.ok) {
        if (data.version.includes('1.0.0')) results.stable++;
        else if (data.version.includes('2.0.0')) results.canary++;
      } else {
        results.errors++;
      }
    } catch (error) {
      results.errors++;
    }
  }
  
  res.json(results);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Dashboard running on port ${PORT}`);
});
