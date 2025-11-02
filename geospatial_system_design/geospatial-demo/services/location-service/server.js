const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const redis = require('redis');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const { v4: uuidv4 } = require('uuid');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Redis client setup
const redisClient = redis.createClient({
  url: process.env.REDIS_URL || 'redis://localhost:6379'
});

redisClient.connect().catch(console.error);

// Middleware
app.use(helmet());
app.use(compression());
app.use(cors());
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'location-service' });
});

// Geospatial operations using Redis
class LocationManager {
  constructor(client) {
    this.redis = client;
    this.DRIVERS_KEY = 'drivers:locations';
    this.METRICS_KEY = 'location:metrics';
  }

  async updateDriverLocation(driverId, lat, lon, metadata = {}) {
    try {
      // Add to geospatial index
      await this.redis.geoAdd(this.DRIVERS_KEY, {
        longitude: parseFloat(lon),
        latitude: parseFloat(lat),
        member: driverId
      });

      // Store additional metadata
      const locationData = {
        lat: parseFloat(lat),
        lon: parseFloat(lon),
        timestamp: Date.now(),
        ...metadata
      };

      await this.redis.hSet(`driver:${driverId}`, locationData);
      
      // Update metrics
      await this.redis.incr(`${this.METRICS_KEY}:updates`);
      
      return true;
    } catch (error) {
      console.error('Error updating location:', error);
      return false;
    }
  }

  async findNearbyDrivers(lat, lon, radius = 5000, unit = 'm') {
    try {
      const drivers = await this.redis.geoRadius(
        this.DRIVERS_KEY,
        { longitude: parseFloat(lon), latitude: parseFloat(lat) },
        radius,
        unit,
        { WITHCOORD: true, WITHDIST: true }
      );

      const enrichedDrivers = await Promise.all(
        drivers.map(async (driver) => {
          const metadata = await this.redis.hGetAll(`driver:${driver.member}`);
          return {
            id: driver.member,
            distance: parseFloat(driver.distance),
            coordinates: driver.coordinates,
            ...metadata
          };
        })
      );

      return enrichedDrivers;
    } catch (error) {
      console.error('Error finding nearby drivers:', error);
      return [];
    }
  }

  async getDriversInArea(minLat, minLon, maxLat, maxLon) {
    try {
      // Use geosearch for bounding box queries
      const drivers = await this.redis.geoSearchWith(
        this.DRIVERS_KEY,
        { longitude: (minLon + maxLon) / 2, latitude: (minLat + maxLat) / 2 },
        { width: Math.abs(maxLon - minLon) * 111000, height: Math.abs(maxLat - minLat) * 111000, unit: 'm' },
        { WITHCOORD: true }
      );

      return drivers.map(driver => ({
        id: driver.member,
        coordinates: driver.coordinates
      }));
    } catch (error) {
      console.error('Error getting drivers in area:', error);
      return [];
    }
  }

  async getMetrics() {
    try {
      const totalDrivers = await this.redis.zCard(this.DRIVERS_KEY);
      const totalUpdates = await this.redis.get(`${this.METRICS_KEY}:updates`) || 0;
      
      return {
        totalDrivers: parseInt(totalDrivers),
        totalUpdates: parseInt(totalUpdates),
        timestamp: Date.now()
      };
    } catch (error) {
      console.error('Error getting metrics:', error);
      return { totalDrivers: 0, totalUpdates: 0, timestamp: Date.now() };
    }
  }
}

const locationManager = new LocationManager(redisClient);

// REST API endpoints
app.post('/api/location/update', async (req, res) => {
  const { driverId, lat, lon, ...metadata } = req.body;
  
  if (!driverId || !lat || !lon) {
    return res.status(400).json({ error: 'Missing required fields: driverId, lat, lon' });
  }

  const success = await locationManager.updateDriverLocation(driverId, lat, lon, metadata);
  
  if (success) {
    // Broadcast to connected clients
    io.emit('locationUpdate', { driverId, lat, lon, ...metadata });
    res.json({ success: true });
  } else {
    res.status(500).json({ error: 'Failed to update location' });
  }
});

app.get('/api/location/nearby', async (req, res) => {
  const { lat, lon, radius = 5000 } = req.query;
  
  if (!lat || !lon) {
    return res.status(400).json({ error: 'Missing required parameters: lat, lon' });
  }

  const drivers = await locationManager.findNearbyDrivers(lat, lon, radius);
  res.json({ drivers, total: drivers.length });
});

app.get('/api/location/area', async (req, res) => {
  const { minLat, minLon, maxLat, maxLon } = req.query;
  
  if (!minLat || !minLon || !maxLat || !maxLon) {
    return res.status(400).json({ error: 'Missing bounding box parameters' });
  }

  const drivers = await locationManager.getDriversInArea(minLat, minLon, maxLat, maxLon);
  res.json({ drivers, total: drivers.length });
});

app.get('/api/metrics', async (req, res) => {
  const metrics = await locationManager.getMetrics();
  res.json(metrics);
});

// WebSocket connection handling
io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);

  socket.on('joinTracking', (data) => {
    socket.join('locationTracking');
    console.log(`Socket ${socket.id} joined location tracking`);
  });

  socket.on('updateLocation', async (data) => {
    const { driverId, lat, lon, ...metadata } = data;
    const success = await locationManager.updateDriverLocation(driverId, lat, lon, metadata);
    
    if (success) {
      socket.to('locationTracking').emit('locationUpdate', data);
    }
  });

  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
  });
});

// Simulate driver movements for demo
async function simulateDriverMovements() {
  const driverIds = ['driver_001', 'driver_002', 'driver_003', 'driver_004', 'driver_005'];
  
  // NYC bounding box
  const nycBounds = {
    minLat: 40.6892, maxLat: 40.8820,
    minLon: -74.0445, maxLon: -73.9006
  };

  const drivers = driverIds.map(id => ({
    id,
    lat: nycBounds.minLat + Math.random() * (nycBounds.maxLat - nycBounds.minLat),
    lon: nycBounds.minLon + Math.random() * (nycBounds.maxLon - nycBounds.minLon),
    status: Math.random() > 0.3 ? 'available' : 'busy',
    speed: Math.random() * 60 + 10 // 10-70 km/h
  }));

  setInterval(async () => {
    for (const driver of drivers) {
      // Simulate realistic movement
      const maxMove = 0.001; // ~100m
      driver.lat += (Math.random() - 0.5) * maxMove;
      driver.lon += (Math.random() - 0.5) * maxMove;
      
      // Keep within NYC bounds
      driver.lat = Math.max(nycBounds.minLat, Math.min(nycBounds.maxLat, driver.lat));
      driver.lon = Math.max(nycBounds.minLon, Math.min(nycBounds.maxLon, driver.lon));

      await locationManager.updateDriverLocation(driver.id, driver.lat, driver.lon, {
        status: driver.status,
        speed: driver.speed
      });

      // Broadcast to WebSocket clients
      io.to('locationTracking').emit('locationUpdate', {
        driverId: driver.id,
        lat: driver.lat,
        lon: driver.lon,
        status: driver.status,
        speed: driver.speed
      });
    }
  }, 3000); // Update every 3 seconds
}

const PORT = process.env.PORT || 8000;
server.listen(PORT, () => {
  console.log(`Location service running on port ${PORT}`);
  simulateDriverMovements();
});
