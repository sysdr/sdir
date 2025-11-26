const express = require('express');
const cors = require('cors');
const axios = require('axios');
const WebSocket = require('ws');

const app = express();
app.use(cors());
app.use(express.json());

const PORT = 3000;

// Region endpoints
const REGIONS = {
  US: 'http://us-region:3001',
  EU: 'http://eu-region:3002',
  APAC: 'http://apac-region:3003'
};

// WebSocket for real-time updates
const wss = new WebSocket.Server({ noServer: true });
const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);
  ws.on('close', () => clients.delete(ws));
});

function broadcast(data) {
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(JSON.stringify(data));
    }
  });
}

// Geographic routing - route to nearest region
function getRegionForUser(userLocation) {
  const regionMap = {
    'new-york': 'US',
    'california': 'US',
    'london': 'EU',
    'paris': 'EU',
    'tokyo': 'APAC',
    'singapore': 'APAC'
  };
  return regionMap[userLocation] || 'US';
}

// Get all listings from all regions
app.get('/api/listings/all', async (req, res) => {
  try {
    const promises = Object.entries(REGIONS).map(([region, url]) =>
      axios.get(`${url}/listings`).catch(e => ({ data: { region, listings: [], error: e.message } }))
    );
    
    const results = await Promise.all(promises);
    const allListings = results.flatMap(r => r.data.listings || []);
    
    res.json({
      total: allListings.length,
      regions: results.map(r => ({ region: r.data.region, count: (r.data.listings || []).length })),
      listings: allListings
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Route booking request to appropriate region
app.post('/api/book', async (req, res) => {
  const { listingId, userId, userLocation } = req.body;
  const timestamp = Date.now();
  
  // Determine listing region from ID
  const listingRegion = listingId.split('-')[0].toUpperCase();
  const userRegion = getRegionForUser(userLocation);
  
  const targetUrl = REGIONS[listingRegion];
  
  broadcast({
    type: 'booking-attempt',
    listingId,
    userId,
    userRegion,
    listingRegion,
    timestamp,
    crossRegion: userRegion !== listingRegion
  });
  
  try {
    const response = await axios.post(`${targetUrl}/book`, {
      listingId,
      userId,
      timestamp
    });
    
    broadcast({
      type: 'booking-result',
      ...response.data,
      userRegion,
      listingRegion
    });
    
    res.json(response.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Health check for all regions
app.get('/api/health', async (req, res) => {
  const checks = await Promise.all(
    Object.entries(REGIONS).map(async ([region, url]) => {
      try {
        const response = await axios.get(`${url}/health`, { timeout: 2000 });
        return { region, status: response.data.status };
      } catch (error) {
        return { region, status: 'unhealthy' };
      }
    })
  );
  
  res.json({ regions: checks });
});

const server = app.listen(PORT, () => {
  console.log(`Global Router running on port ${PORT}`);
});

server.on('upgrade', (request, socket, head) => {
  wss.handleUpgrade(request, socket, head, (ws) => {
    wss.emit('connection', ws, request);
  });
});
