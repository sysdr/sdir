const express = require('express');
const WebSocket = require('ws');
const fetch = require('node-fetch');

const app = express();
const port = 3000;
const path = require('path');

app.use(express.static(__dirname));
app.use(express.json());

// Proxy endpoints
const regions = [
  { id: 'us-east', url: 'http://us-east:3001' },
  { id: 'us-west', url: 'http://us-west:3002' },
  { id: 'eu-west', url: 'http://eu-west:3003' }
];

// Write to nearest region
app.post('/api/write', async (req, res) => {
  const { region, key, value } = req.body;
  const targetRegion = regions.find(r => r.id === region);
  
  try {
    const response = await fetch(`${targetRegion.url}/write`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ key, value })
    });
    const data = await response.json();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Read from any region
app.get('/api/read/:region/:key', async (req, res) => {
  const { region, key } = req.params;
  const targetRegion = regions.find(r => r.id === region);
  
  try {
    const response = await fetch(`${targetRegion.url}/read/${key}`);
    const data = await response.json();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Fail region
app.post('/api/fail/:region', async (req, res) => {
  const { region } = req.params;
  const targetRegion = regions.find(r => r.id === region);
  
  try {
    const response = await fetch(`${targetRegion.url}/fail`, {
      method: 'POST'
    });
    const data = await response.json();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Recover region
app.post('/api/recover/:region', async (req, res) => {
  const { region } = req.params;
  const targetRegion = regions.find(r => r.id === region);
  
  try {
    const response = await fetch(`${targetRegion.url}/recover`, {
      method: 'POST'
    });
    const data = await response.json();
    res.json(data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(port, () => {
  console.log(`Dashboard running on port ${port}`);
});

// WebSocket for real-time updates
const wss = new WebSocket.Server({ port: 3100 });

async function broadcastStats() {
  const stats = await Promise.all(
    regions.map(async r => {
      try {
        const response = await fetch(`${r.url}/stats`);
        return await response.json();
      } catch (error) {
        return { region: r.id, error: true };
      }
    })
  );

  wss.clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(stats));
    }
  });
}

setInterval(broadcastStats, 1000);
