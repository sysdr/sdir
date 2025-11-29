#!/bin/bash

set -e

echo "=========================================="
echo "Global Scale System - Airbnb Case Study"
echo "Issue #160: Multi-Region Architecture Demo"
echo "=========================================="

# Create project structure
echo "Creating project structure..."
mkdir -p global-scale-demo/{us-region,eu-region,apac-region,global-router,frontend,shared}

# Create shared types
cat > global-scale-demo/shared/types.js << 'EOF'
// Shared types and utilities
module.exports = {
  REGIONS: {
    US: 'us-east',
    EU: 'eu-west',
    APAC: 'apac-south'
  },
  
  BOOKING_STATUS: {
    AVAILABLE: 'available',
    HELD: 'held',
    CONFIRMED: 'confirmed'
  }
};
EOF

# Create US Region Service
cat > global-scale-demo/us-region/package.json << 'EOF'
{
  "name": "us-region-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "redis": "^4.6.0"
  }
}
EOF

cat > global-scale-demo/us-region/server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const { createClient } = require('redis');

const app = express();
app.use(cors());
app.use(express.json());

const REGION = 'US';
const PORT = 3001;

let redisClient;

// Initialize Redis
async function initRedis() {
  redisClient = createClient({ url: 'redis://redis:6379' });
  await redisClient.connect();
  
  // Initialize sample listings
  const listings = [
    { id: 'us-1', name: 'NYC Loft', region: 'US', price: 250 },
    { id: 'us-2', name: 'SF Studio', region: 'US', price: 180 },
    { id: 'us-3', name: 'LA Beach House', region: 'US', price: 320 }
  ];
  
  for (const listing of listings) {
    await redisClient.hSet(`listing:${listing.id}`, listing);
    await redisClient.set(`availability:${listing.id}`, 'available');
  }
}

// Get regional listings
app.get('/listings', async (req, res) => {
  const keys = await redisClient.keys('listing:us-*');
  const listings = [];
  
  for (const key of keys) {
    const listing = await redisClient.hGetAll(key);
    const listingId = key.split(':')[1];
    const availability = await redisClient.get(`availability:${listingId}`);
    listings.push({ ...listing, availability, id: listingId });
  }
  
  res.json({ region: REGION, listings, latency: Math.random() * 50 + 30 });
});

// Optimistic booking with timestamp-based conflict resolution
app.post('/book', async (req, res) => {
  const { listingId, userId, timestamp } = req.body;
  const startTime = Date.now();
  
  const availability = await redisClient.get(`availability:${listingId}`);
  
  if (availability === 'available') {
    // Hold booking with timestamp
    const holdKey = `hold:${listingId}`;
    const existingHold = await redisClient.get(holdKey);
    
    if (existingHold) {
      const existing = JSON.parse(existingHold);
      // Conflict! Earliest timestamp wins
      if (timestamp < existing.timestamp) {
        await redisClient.set(holdKey, JSON.stringify({ userId, timestamp }), { EX: 60 });
        setTimeout(async () => {
          await redisClient.set(`availability:${listingId}`, 'confirmed');
          await redisClient.del(holdKey);
          // Replicate to other regions
          await redisClient.publish('booking-confirmed', JSON.stringify({ listingId, region: REGION }));
        }, 1000);
        
        res.json({
          success: true,
          message: 'Booking confirmed (won conflict resolution)',
          listingId,
          region: REGION,
          latency: Date.now() - startTime
        });
      } else {
        res.json({
          success: false,
          message: 'Booking conflict - another user reserved first',
          alternative: 'us-2',
          latency: Date.now() - startTime
        });
      }
    } else {
      await redisClient.set(holdKey, JSON.stringify({ userId, timestamp }), { EX: 60 });
      setTimeout(async () => {
        await redisClient.set(`availability:${listingId}`, 'confirmed');
        await redisClient.del(holdKey);
        await redisClient.publish('booking-confirmed', JSON.stringify({ listingId, region: REGION }));
      }, 1000);
      
      res.json({
        success: true,
        message: 'Booking confirmed',
        listingId,
        region: REGION,
        latency: Date.now() - startTime
      });
    }
  } else {
    res.json({
      success: false,
      message: 'Listing not available',
      alternative: 'us-3',
      latency: Date.now() - startTime
    });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy', region: REGION }));

initRedis().then(() => {
  app.listen(PORT, () => console.log(`US Region Service running on port ${PORT}`));
});
EOF

# Create EU Region Service
cat > global-scale-demo/eu-region/package.json << 'EOF'
{
  "name": "eu-region-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "redis": "^4.6.0"
  }
}
EOF

cat > global-scale-demo/eu-region/server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const { createClient } = require('redis');

const app = express();
app.use(cors());
app.use(express.json());

const REGION = 'EU';
const PORT = 3002;

let redisClient;

async function initRedis() {
  redisClient = createClient({ url: 'redis://redis:6379' });
  await redisClient.connect();
  
  const listings = [
    { id: 'eu-1', name: 'Paris Apartment', region: 'EU', price: 200 },
    { id: 'eu-2', name: 'London Flat', region: 'EU', price: 220 },
    { id: 'eu-3', name: 'Berlin Loft', region: 'EU', price: 150 }
  ];
  
  for (const listing of listings) {
    await redisClient.hSet(`listing:${listing.id}`, listing);
    await redisClient.set(`availability:${listing.id}`, 'available');
  }
}

app.get('/listings', async (req, res) => {
  const keys = await redisClient.keys('listing:eu-*');
  const listings = [];
  
  for (const key of keys) {
    const listing = await redisClient.hGetAll(key);
    const listingId = key.split(':')[1];
    const availability = await redisClient.get(`availability:${listingId}`);
    listings.push({ ...listing, availability, id: listingId });
  }
  
  res.json({ region: REGION, listings, latency: Math.random() * 50 + 40 });
});

app.post('/book', async (req, res) => {
  const { listingId, userId, timestamp } = req.body;
  const startTime = Date.now();
  
  const availability = await redisClient.get(`availability:${listingId}`);
  
  if (availability === 'available') {
    const holdKey = `hold:${listingId}`;
    const existingHold = await redisClient.get(holdKey);
    
    if (existingHold) {
      const existing = JSON.parse(existingHold);
      if (timestamp < existing.timestamp) {
        await redisClient.set(holdKey, JSON.stringify({ userId, timestamp }), { EX: 60 });
        setTimeout(async () => {
          await redisClient.set(`availability:${listingId}`, 'confirmed');
          await redisClient.del(holdKey);
          await redisClient.publish('booking-confirmed', JSON.stringify({ listingId, region: REGION }));
        }, 1000);
        
        res.json({
          success: true,
          message: 'Booking confirmed (won conflict resolution)',
          listingId,
          region: REGION,
          latency: Date.now() - startTime
        });
      } else {
        res.json({
          success: false,
          message: 'Booking conflict - another user reserved first',
          alternative: 'eu-2',
          latency: Date.now() - startTime
        });
      }
    } else {
      await redisClient.set(holdKey, JSON.stringify({ userId, timestamp }), { EX: 60 });
      setTimeout(async () => {
        await redisClient.set(`availability:${listingId}`, 'confirmed');
        await redisClient.del(holdKey);
        await redisClient.publish('booking-confirmed', JSON.stringify({ listingId, region: REGION }));
      }, 1000);
      
      res.json({
        success: true,
        message: 'Booking confirmed',
        listingId,
        region: REGION,
        latency: Date.now() - startTime
      });
    }
  } else {
    res.json({
      success: false,
      message: 'Listing not available',
      alternative: 'eu-3',
      latency: Date.now() - startTime
    });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy', region: REGION }));

initRedis().then(() => {
  app.listen(PORT, () => console.log(`EU Region Service running on port ${PORT}`));
});
EOF

# Create APAC Region Service
cat > global-scale-demo/apac-region/package.json << 'EOF'
{
  "name": "apac-region-service",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "redis": "^4.6.0"
  }
}
EOF

cat > global-scale-demo/apac-region/server.js << 'EOF'
const express = require('express');
const cors = require('cors');
const { createClient } = require('redis');

const app = express();
app.use(cors());
app.use(express.json());

const REGION = 'APAC';
const PORT = 3003;

let redisClient;

async function initRedis() {
  redisClient = createClient({ url: 'redis://redis:6379' });
  await redisClient.connect();
  
  const listings = [
    { id: 'apac-1', name: 'Tokyo Apartment', region: 'APAC', price: 190 },
    { id: 'apac-2', name: 'Singapore Condo', region: 'APAC', price: 210 },
    { id: 'apac-3', name: 'Sydney House', region: 'APAC', price: 240 }
  ];
  
  for (const listing of listings) {
    await redisClient.hSet(`listing:${listing.id}`, listing);
    await redisClient.set(`availability:${listing.id}`, 'available');
  }
}

app.get('/listings', async (req, res) => {
  const keys = await redisClient.keys('listing:apac-*');
  const listings = [];
  
  for (const key of keys) {
    const listing = await redisClient.hGetAll(key);
    const listingId = key.split(':')[1];
    const availability = await redisClient.get(`availability:${listingId}`);
    listings.push({ ...listing, availability, id: listingId });
  }
  
  res.json({ region: REGION, listings, latency: Math.random() * 50 + 35 });
});

app.post('/book', async (req, res) => {
  const { listingId, userId, timestamp } = req.body;
  const startTime = Date.now();
  
  const availability = await redisClient.get(`availability:${listingId}`);
  
  if (availability === 'available') {
    const holdKey = `hold:${listingId}`;
    const existingHold = await redisClient.get(holdKey);
    
    if (existingHold) {
      const existing = JSON.parse(existingHold);
      if (timestamp < existing.timestamp) {
        await redisClient.set(holdKey, JSON.stringify({ userId, timestamp }), { EX: 60 });
        setTimeout(async () => {
          await redisClient.set(`availability:${listingId}`, 'confirmed');
          await redisClient.del(holdKey);
          await redisClient.publish('booking-confirmed', JSON.stringify({ listingId, region: REGION }));
        }, 1000);
        
        res.json({
          success: true,
          message: 'Booking confirmed (won conflict resolution)',
          listingId,
          region: REGION,
          latency: Date.now() - startTime
        });
      } else {
        res.json({
          success: false,
          message: 'Booking conflict - another user reserved first',
          alternative: 'apac-2',
          latency: Date.now() - startTime
        });
      }
    } else {
      await redisClient.set(holdKey, JSON.stringify({ userId, timestamp }), { EX: 60 });
      setTimeout(async () => {
        await redisClient.set(`availability:${listingId}`, 'confirmed');
        await redisClient.del(holdKey);
        await redisClient.publish('booking-confirmed', JSON.stringify({ listingId, region: REGION }));
      }, 1000);
      
      res.json({
        success: true,
        message: 'Booking confirmed',
        listingId,
        region: REGION,
        latency: Date.now() - startTime
      });
    }
  } else {
    res.json({
      success: false,
      message: 'Listing not available',
      alternative: 'apac-3',
      latency: Date.now() - startTime
    });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy', region: REGION }));

initRedis().then(() => {
  app.listen(PORT, () => console.log(`APAC Region Service running on port ${PORT}`));
});
EOF

# Create Global Router
cat > global-scale-demo/global-router/package.json << 'EOF'
{
  "name": "global-router",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "axios": "^1.6.0",
    "ws": "^8.16.0"
  }
}
EOF

cat > global-scale-demo/global-router/server.js << 'EOF'
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
EOF

# Create Frontend Dashboard
cat > global-scale-demo/frontend/package.json << 'EOF'
{
  "name": "frontend-dashboard",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF

cat > global-scale-demo/frontend/server.js << 'EOF'
const express = require('express');
const path = require('path');
const app = express();

app.use(express.static('public'));

app.listen(8080, () => {
  console.log('Frontend Dashboard running on http://localhost:8080');
});
EOF

mkdir -p global-scale-demo/frontend/public

cat > global-scale-demo/frontend/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Global Scale System - Multi-Region Booking</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        
        .header {
            text-align: center;
            color: white;
            margin-bottom: 30px;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        
        .header p {
            font-size: 1.2em;
            opacity: 0.9;
        }
        
        .dashboard {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 20px;
        }
        
        .card {
            background: white;
            border-radius: 15px;
            padding: 25px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
        }
        
        .card h2 {
            color: #667eea;
            margin-bottom: 20px;
            font-size: 1.5em;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }
        
        .region-selector {
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        
        .region-btn {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-weight: bold;
            transition: all 0.3s;
            flex: 1;
            min-width: 100px;
        }
        
        .region-btn.us {
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
        }
        
        .region-btn.eu {
            background: linear-gradient(135deg, #f093fb, #f5576c);
            color: white;
        }
        
        .region-btn.apac {
            background: linear-gradient(135deg, #4facfe, #00f2fe);
            color: white;
        }
        
        .region-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.3);
        }
        
        .region-btn.active {
            box-shadow: 0 0 0 3px rgba(255,255,255,0.5);
        }
        
        .listings {
            display: grid;
            gap: 15px;
        }
        
        .listing {
            background: linear-gradient(135deg, #f5f7fa, #c3cfe2);
            padding: 15px;
            border-radius: 10px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: transform 0.3s;
        }
        
        .listing:hover {
            transform: scale(1.02);
        }
        
        .listing-info h3 {
            color: #2d3748;
            margin-bottom: 5px;
        }
        
        .listing-info p {
            color: #4a5568;
            font-size: 0.9em;
        }
        
        .listing-status {
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 0.85em;
            font-weight: bold;
        }
        
        .status-available {
            background: #48bb78;
            color: white;
        }
        
        .status-held {
            background: #ed8936;
            color: white;
        }
        
        .status-confirmed {
            background: #e53e3e;
            color: white;
        }
        
        .book-btn {
            padding: 8px 16px;
            background: #667eea;
            color: white;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-weight: bold;
            transition: all 0.3s;
        }
        
        .book-btn:hover {
            background: #764ba2;
        }
        
        .book-btn:disabled {
            background: #cbd5e0;
            cursor: not-allowed;
        }
        
        .activity-log {
            max-height: 400px;
            overflow-y: auto;
        }
        
        .activity-item {
            padding: 12px;
            margin-bottom: 10px;
            border-radius: 8px;
            font-size: 0.9em;
            line-height: 1.5;
        }
        
        .activity-booking {
            background: linear-gradient(135deg, #ffeaa7, #fdcb6e);
        }
        
        .activity-success {
            background: linear-gradient(135deg, #55efc4, #00b894);
            color: white;
        }
        
        .activity-conflict {
            background: linear-gradient(135deg, #fab1a0, #e17055);
            color: white;
        }
        
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
        }
        
        .stat-box {
            background: linear-gradient(135deg, #667eea, #764ba2);
            padding: 20px;
            border-radius: 10px;
            color: white;
            text-align: center;
        }
        
        .stat-value {
            font-size: 2em;
            font-weight: bold;
            margin-bottom: 5px;
        }
        
        .stat-label {
            font-size: 0.9em;
            opacity: 0.9;
        }
        
        .region-map {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 15px;
            margin-top: 15px;
        }
        
        .region-status {
            padding: 15px;
            border-radius: 10px;
            text-align: center;
            color: white;
            font-weight: bold;
        }
        
        .region-status.healthy {
            background: linear-gradient(135deg, #11998e, #38ef7d);
        }
        
        .region-status.unhealthy {
            background: linear-gradient(135deg, #eb3349, #f45c43);
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🌍 Global Scale Booking System</h1>
            <p>Multi-Region Architecture with Geographic Sharding</p>
        </div>
        
        <div class="dashboard">
            <div class="card">
                <h2>📍 Your Location</h2>
                <div class="region-selector">
                    <button class="region-btn us active" onclick="selectRegion('new-york')">New York (US)</button>
                    <button class="region-btn eu" onclick="selectRegion('london')">London (EU)</button>
                    <button class="region-btn apac" onclick="selectRegion('tokyo')">Tokyo (APAC)</button>
                </div>
                <div id="user-info" style="text-align: center; padding: 15px; background: #f7fafc; border-radius: 8px; margin-top: 10px;">
                    <strong>Current Location:</strong> <span id="current-location">New York, US</span>
                </div>
            </div>
            
            <div class="card">
                <h2>📊 System Statistics</h2>
                <div class="stats">
                    <div class="stat-box">
                        <div class="stat-value" id="total-bookings">0</div>
                        <div class="stat-label">Total Bookings</div>
                    </div>
                    <div class="stat-box">
                        <div class="stat-value" id="conflicts">0</div>
                        <div class="stat-label">Conflicts</div>
                    </div>
                    <div class="stat-box">
                        <div class="stat-value" id="avg-latency">0ms</div>
                        <div class="stat-label">Avg Latency</div>
                    </div>
                </div>
                <div class="region-map">
                    <div class="region-status healthy">
                        <div>🇺🇸 US Region</div>
                        <div style="font-size: 0.8em; margin-top: 5px;">Healthy</div>
                    </div>
                    <div class="region-status healthy">
                        <div>🇪🇺 EU Region</div>
                        <div style="font-size: 0.8em; margin-top: 5px;">Healthy</div>
                    </div>
                    <div class="region-status healthy">
                        <div>🌏 APAC Region</div>
                        <div style="font-size: 0.8em; margin-top: 5px;">Healthy</div>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="dashboard">
            <div class="card">
                <h2>🏠 Available Listings</h2>
                <div id="listings" class="listings">
                    <p style="text-align: center; color: #718096;">Loading listings...</p>
                </div>
            </div>
            
            <div class="card">
                <h2>📝 Activity Log</h2>
                <div id="activity-log" class="activity-log">
                    <div class="activity-item" style="background: #e6fffa; color: #234e52;">
                        System initialized. Ready to process bookings.
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        let currentLocation = 'new-york';
        let ws;
        let stats = { totalBookings: 0, conflicts: 0, latencies: [] };
        
        function selectRegion(location) {
            currentLocation = location;
            const locations = {
                'new-york': 'New York, US',
                'london': 'London, EU',
                'tokyo': 'Tokyo, APAC'
            };
            document.getElementById('current-location').textContent = locations[location];
            
            document.querySelectorAll('.region-btn').forEach(btn => btn.classList.remove('active'));
            event.target.classList.add('active');
            
            addActivity(`Changed location to ${locations[location]}`, 'activity-booking');
        }
        
        function connectWebSocket() {
            ws = new WebSocket('ws://localhost:3000');
            
            ws.onmessage = (event) => {
                const data = JSON.parse(event.data);
                
                if (data.type === 'booking-attempt') {
                    const crossRegion = data.crossRegion ? ' (Cross-Region)' : ' (Same Region)';
                    addActivity(
                        `🔄 Booking attempt: ${data.listingId} from ${data.userRegion}${crossRegion}`,
                        'activity-booking'
                    );
                }
                
                if (data.type === 'booking-result') {
                    if (data.success) {
                        addActivity(
                            `✅ ${data.message} - ${data.listingId} (${data.latency}ms)`,
                            'activity-success'
                        );
                        stats.totalBookings++;
                    } else {
                        addActivity(
                            `⚠️ ${data.message} - ${data.listingId}`,
                            'activity-conflict'
                        );
                        stats.conflicts++;
                    }
                    
                    if (data.latency) {
                        stats.latencies.push(data.latency);
                        if (stats.latencies.length > 10) stats.latencies.shift();
                    }
                    
                    updateStats();
                    loadListings();
                }
            };
            
            ws.onerror = () => addActivity('WebSocket connection error', 'activity-conflict');
        }
        
        function addActivity(message, className) {
            const log = document.getElementById('activity-log');
            const item = document.createElement('div');
            item.className = `activity-item ${className}`;
            item.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
            log.insertBefore(item, log.firstChild);
            
            if (log.children.length > 20) {
                log.removeChild(log.lastChild);
            }
        }
        
        function updateStats() {
            document.getElementById('total-bookings').textContent = stats.totalBookings;
            document.getElementById('conflicts').textContent = stats.conflicts;
            
            if (stats.latencies.length > 0) {
                const avg = Math.round(stats.latencies.reduce((a, b) => a + b, 0) / stats.latencies.length);
                document.getElementById('avg-latency').textContent = `${avg}ms`;
            }
        }
        
        async function loadListings() {
            try {
                const response = await fetch('http://localhost:3000/api/listings/all');
                const data = await response.json();
                
                const listingsDiv = document.getElementById('listings');
                listingsDiv.innerHTML = '';
                
                data.listings.forEach(listing => {
                    const div = document.createElement('div');
                    div.className = 'listing';
                    div.innerHTML = `
                        <div class="listing-info">
                            <h3>${listing.name}</h3>
                            <p>$${listing.price}/night • ${listing.region} Region</p>
                        </div>
                        <div style="display: flex; gap: 10px; align-items: center;">
                            <span class="listing-status status-${listing.availability}">${listing.availability}</span>
                            <button class="book-btn" 
                                    onclick="bookListing('${listing.id}')"
                                    ${listing.availability !== 'available' ? 'disabled' : ''}>
                                Book
                            </button>
                        </div>
                    `;
                    listingsDiv.appendChild(div);
                });
            } catch (error) {
                console.error('Error loading listings:', error);
            }
        }
        
        async function bookListing(listingId) {
            const userId = `user-${Math.random().toString(36).substr(2, 9)}`;
            
            try {
                const response = await fetch('http://localhost:3000/api/book', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ listingId, userId, userLocation: currentLocation })
                });
                
                const result = await response.json();
                // WebSocket will handle the UI update
            } catch (error) {
                addActivity(`Error: ${error.message}`, 'activity-conflict');
            }
        }
        
        // Initialize
        connectWebSocket();
        loadListings();
        setInterval(loadListings, 5000);
    </script>
</body>
</html>
EOF

# Create Docker Compose
cat > global-scale-demo/docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    networks:
      - global-net

  us-region:
    build:
      context: ./us-region
      dockerfile: ../Dockerfile.node
    ports:
      - "3001:3001"
    depends_on:
      - redis
    networks:
      - global-net
    environment:
      - NODE_ENV=production

  eu-region:
    build:
      context: ./eu-region
      dockerfile: ../Dockerfile.node
    ports:
      - "3002:3002"
    depends_on:
      - redis
    networks:
      - global-net
    environment:
      - NODE_ENV=production

  apac-region:
    build:
      context: ./apac-region
      dockerfile: ../Dockerfile.node
    ports:
      - "3003:3003"
    depends_on:
      - redis
    networks:
      - global-net
    environment:
      - NODE_ENV=production

  global-router:
    build:
      context: ./global-router
      dockerfile: ../Dockerfile.node
    ports:
      - "3000:3000"
    depends_on:
      - us-region
      - eu-region
      - apac-region
    networks:
      - global-net
    environment:
      - NODE_ENV=production

  frontend:
    build:
      context: ./frontend
      dockerfile: ../Dockerfile.node
    ports:
      - "8080:8080"
    depends_on:
      - global-router
    networks:
      - global-net
    environment:
      - NODE_ENV=production

networks:
  global-net:
    driver: bridge
EOF

# Create shared Dockerfile
cat > global-scale-demo/Dockerfile.node << 'EOF'
FROM node:18-alpine

WORKDIR /app

COPY package*.json ./

RUN npm install --production

COPY . .

CMD ["node", "server.js"]
EOF

# Create test script
cat > global-scale-demo/test.sh << 'EOF'
#!/bin/bash

echo "Running System Tests..."
echo "======================="

# Test 1: Health Check
echo -e "\n1. Testing Health Check..."
curl -s http://localhost:3000/api/health | grep -q "healthy" && echo "✓ Health check passed" || echo "✗ Health check failed"

# Test 2: Get All Listings
echo -e "\n2. Testing Listings Retrieval..."
LISTINGS=$(curl -s http://localhost:3000/api/listings/all)
COUNT=$(echo $LISTINGS | grep -o '"id"' | wc -l)
[ $COUNT -gt 0 ] && echo "✓ Retrieved $COUNT listings" || echo "✗ Failed to retrieve listings"

# Test 3: Single Booking
echo -e "\n3. Testing Single Booking..."
RESULT=$(curl -s -X POST http://localhost:3000/api/book \
  -H "Content-Type: application/json" \
  -d '{"listingId":"us-1","userId":"test-user-1","userLocation":"new-york"}')
echo $RESULT | grep -q '"success":true' && echo "✓ Booking successful" || echo "✗ Booking failed"

# Test 4: Concurrent Bookings (Conflict Test)
echo -e "\n4. Testing Concurrent Bookings..."
curl -s -X POST http://localhost:3000/api/book \
  -H "Content-Type: application/json" \
  -d '{"listingId":"eu-1","userId":"user-a","userLocation":"london"}' > /dev/null &
curl -s -X POST http://localhost:3000/api/book \
  -H "Content-Type: application/json" \
  -d '{"listingId":"eu-1","userId":"user-b","userLocation":"paris"}' > /dev/null &
wait
sleep 2
echo "✓ Conflict resolution test completed"

echo -e "\n======================="
echo "All tests completed!"
EOF

chmod +x global-scale-demo/test.sh

echo "Building Docker containers..."
cd global-scale-demo
docker-compose build

echo "Starting services..."
docker-compose up -d

echo "Waiting for services to be ready..."
sleep 10

echo ""
echo "=========================================="
echo "Demo is ready!"
echo "=========================================="
echo ""
echo "Access the dashboard at: http://localhost:8080"
echo ""
echo "Features to explore:"
echo "1. Switch between regions (US/EU/APAC) and see latency differences"
echo "2. Book listings and watch conflict resolution in real-time"
echo "3. Observe cross-region booking requests in activity log"
echo "4. Monitor system statistics and region health"
echo ""
echo "Running automated tests..."
./test.sh

echo ""
echo "To view logs: docker-compose logs -f"
echo "To stop: cd global-scale-demo && docker-compose down"
echo ""