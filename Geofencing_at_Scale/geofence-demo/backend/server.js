import express from 'express';
import { WebSocketServer } from 'ws';
import http from 'http';
import cors from 'cors';
import { QuadTree, Rectangle, Point } from './quadtree.js';
import { Geohash, GeohashIndex } from './geohash.js';

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

app.use(cors());
app.use(express.json());

// Initialize spatial indexes
const mapBounds = new Rectangle(0, 0, 500, 500); // 1000x1000 map
const quadTree = new QuadTree(mapBounds, 8);
const geohashIndex = new GeohashIndex(5);

// Define geofences (zones)
const geofences = [
  { id: 'downtown', center: { x: 200, y: 200 }, radius: 80, name: 'Downtown Zone' },
  { id: 'airport', center: { x: 700, y: 300 }, radius: 100, name: 'Airport Zone' },
  { id: 'suburbs', center: { x: 400, y: 600 }, radius: 120, name: 'Suburbs Zone' },
  { id: 'industrial', center: { x: 750, y: 700 }, radius: 90, name: 'Industrial Zone' },
];

// Simulated vehicles
const vehicles = [];
const VEHICLE_COUNT = 1000;

// Normalize lat/lon to map coordinates
function latLonToXY(lat, lon) {
  const x = ((lon + 180) / 360) * 1000;
  const y = ((90 - lat) / 180) * 1000;
  return { x, y };
}

function xyToLatLon(x, y) {
  const lon = (x / 1000) * 360 - 180;
  const lat = 90 - (y / 1000) * 180;
  return { lat, lon };
}

// Initialize vehicles
for (let i = 0; i < VEHICLE_COUNT; i++) {
  const x = Math.random() * 1000;
  const y = Math.random() * 1000;
  const { lat, lon } = xyToLatLon(x, y);
  
  vehicles.push({
    id: `vehicle_${i}`,
    x,
    y,
    lat,
    lon,
    vx: (Math.random() - 0.5) * 2,
    vy: (Math.random() - 0.5) * 2,
    currentZones: [],
    geohash: Geohash.encode(lat, lon, 5)
  });
}

// Performance metrics
const metrics = {
  quadtree: { insertTime: 0, queryTime: 0, queriesPerformed: 0 },
  geohash: { insertTime: 0, queryTime: 0, queriesPerformed: 0 },
  boundaryEvents: 0,
  updateCount: 0
};

// Rebuild indexes
function rebuildIndexes() {
  const qtStart = Date.now();
  const newQuadTree = new QuadTree(mapBounds, 8);
  for (const vehicle of vehicles) {
    newQuadTree.insert(new Point(vehicle.x, vehicle.y, vehicle));
  }
  metrics.quadtree.insertTime = Date.now() - qtStart;

  const ghStart = Date.now();
  const newGeohashIndex = new GeohashIndex(5);
  for (const vehicle of vehicles) {
    newGeohashIndex.insert(vehicle.lat, vehicle.lon, vehicle);
  }
  metrics.geohash.insertTime = Date.now() - ghStart;

  return { quadTree: newQuadTree, geohashIndex: newGeohashIndex };
}

// Check geofence containment
function isInGeofence(vehicle, geofence) {
  const dx = vehicle.x - geofence.center.x;
  const dy = vehicle.y - geofence.center.y;
  return Math.sqrt(dx * dx + dy * dy) <= geofence.radius;
}

// Update vehicle positions
function updateVehicles() {
  const { quadTree: newQt, geohashIndex: newGh } = rebuildIndexes();

  for (const vehicle of vehicles) {
    // Update position
    vehicle.x += vehicle.vx;
    vehicle.y += vehicle.vy;

    // Bounce off boundaries
    if (vehicle.x < 0 || vehicle.x > 1000) vehicle.vx *= -1;
    if (vehicle.y < 0 || vehicle.y > 1000) vehicle.vy *= -1;
    
    vehicle.x = Math.max(0, Math.min(1000, vehicle.x));
    vehicle.y = Math.max(0, Math.min(1000, vehicle.y));

    const { lat, lon } = xyToLatLon(vehicle.x, vehicle.y);
    vehicle.lat = lat;
    vehicle.lon = lon;

    const oldGeohash = vehicle.geohash;
    vehicle.geohash = Geohash.encode(lat, lon, 5);

    // Track geohash cell transitions
    if (oldGeohash !== vehicle.geohash) {
      metrics.boundaryEvents++;
    }

    // Check geofence entry/exit
    const newZones = [];
    for (const geofence of geofences) {
      if (isInGeofence(vehicle, geofence)) {
        newZones.push(geofence.id);
      }
    }

    // Detect zone changes
    const entered = newZones.filter(z => !vehicle.currentZones.includes(z));
    const exited = vehicle.currentZones.filter(z => !newZones.includes(z));

    if (entered.length > 0 || exited.length > 0) {
      metrics.boundaryEvents++;
    }

    vehicle.currentZones = newZones;
  }

  metrics.updateCount++;

  // Perform sample queries
  const queryCenter = geofences[0].center;
  const queryRadius = geofences[0].radius;

  const qtQueryStart = Date.now();
  const queryRect = new Rectangle(queryCenter.x, queryCenter.y, queryRadius, queryRadius);
  const qtResults = newQt.query(queryRect);
  metrics.quadtree.queryTime = Date.now() - qtQueryStart;
  metrics.quadtree.queriesPerformed++;

  const { lat: queryLat, lon: queryLon } = xyToLatLon(queryCenter.x, queryCenter.y);
  const ghQueryStart = Date.now();
  const ghResults = newGh.query(queryLat, queryLon, queryRadius / 100); // Rough km conversion
  metrics.geohash.queryTime = Date.now() - ghQueryStart;
  metrics.geohash.queriesPerformed++;

  return { newQt, newGh, qtResults: qtResults.length, ghResults: ghResults.length };
}

// API endpoints
app.get('/api/status', (req, res) => {
  const { quadTree: newQt, geohashIndex: newGh } = rebuildIndexes();
  const qtStats = newQt.getStats();
  const ghStats = newGh.getStats();

  res.json({
    vehicles: vehicles.length,
    geofences: geofences.length,
    metrics,
    quadtree: qtStats,
    geohash: {
      totalCells: ghStats.totalCells,
      avgObjectsPerCell: ghStats.avgObjectsPerCell
    }
  });
});

app.get('/api/geofences', (req, res) => {
  res.json(geofences);
});

app.get('/api/vehicles', (req, res) => {
  // Return sample of vehicles
  res.json(vehicles.slice(0, 100));
});

// Background update loop to keep metrics updating
let updateInterval = setInterval(() => {
  updateVehicles();
}, 1000);

// WebSocket for real-time updates
wss.on('connection', (ws) => {
  console.log('Client connected');

  const wsInterval = setInterval(() => {
    const { qtResults, ghResults } = updateVehicles();

    ws.send(JSON.stringify({
      type: 'update',
      vehicles: vehicles.slice(0, 100), // Send subset for performance
      metrics,
      queryResults: { quadtree: qtResults, geohash: ghResults }
    }));
  }, 1000);

  ws.on('close', () => {
    clearInterval(wsInterval);
    console.log('Client disconnected');
  });
});

const PORT = 3000;
server.listen(PORT, () => {
  console.log(`✅ Geofence server running on port ${PORT}`);
  console.log(`🔄 Background updates started`);
});
