import { QuadTree, Rectangle, Point } from '../backend/quadtree.js';
import { Geohash, GeohashIndex } from '../backend/geohash.js';

console.log('🧪 Running Geofencing Tests...\n');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`✅ ${name}`);
    passed++;
  } catch (error) {
    console.log(`❌ ${name}: ${error.message}`);
    failed++;
  }
}

// QuadTree tests
test('QuadTree: Insert and Query', () => {
  const boundary = new Rectangle(0, 0, 100, 100);
  const qt = new QuadTree(boundary, 4);
  
  qt.insert(new Point(50, 50, { id: 1 }));
  qt.insert(new Point(55, 55, { id: 2 }));
  
  const range = new Rectangle(50, 50, 10, 10);
  const found = qt.query(range);
  
  if (found.length !== 2) throw new Error(`Expected 2 points, got ${found.length}`);
});

test('QuadTree: Subdivision', () => {
  const boundary = new Rectangle(0, 0, 100, 100);
  const qt = new QuadTree(boundary, 2);
  
  // Insert enough points to force subdivision
  qt.insert(new Point(50, 50, { id: 1 }));
  qt.insert(new Point(51, 51, { id: 2 }));
  qt.insert(new Point(52, 52, { id: 3 }));
  
  if (!qt.divided) throw new Error('QuadTree should have subdivided');
  
  const stats = qt.getStats();
  if (stats.maxDepth < 1) throw new Error('Max depth should be at least 1');
});

test('QuadTree: Boundary Checks', () => {
  const boundary = new Rectangle(0, 0, 100, 100);
  const qt = new QuadTree(boundary, 4);
  
  const inserted = qt.insert(new Point(200, 200, { id: 1 }));
  if (inserted) throw new Error('Should not insert point outside boundary');
});

// Geohash tests
test('Geohash: Encode/Decode', () => {
  const lat = 37.7749;
  const lon = -122.4194;
  
  const hash = Geohash.encode(lat, lon, 8);
  const decoded = Geohash.decode(hash);
  
  const latDiff = Math.abs(decoded.lat - lat);
  const lonDiff = Math.abs(decoded.lon - lon);
  
  if (latDiff > 0.001 || lonDiff > 0.001) {
    throw new Error(`Decode error too large: lat=${latDiff}, lon=${lonDiff}`);
  }
});

test('Geohash: Neighbors', () => {
  const hash = '9q5';
  const neighbors = Geohash.neighbors(hash);
  
  if (neighbors.length !== 8) {
    throw new Error(`Expected 8 neighbors, got ${neighbors.length}`);
  }
  
  // All neighbors should have same precision
  for (const neighbor of neighbors) {
    if (neighbor.length !== hash.length) {
      throw new Error(`Neighbor precision mismatch: ${neighbor}`);
    }
  }
});

test('GeohashIndex: Insert and Query', () => {
  const index = new GeohashIndex(5);
  
  index.insert(37.7749, -122.4194, { id: 'sf' });
  index.insert(37.7849, -122.4094, { id: 'nearby' });
  index.insert(40.7128, -74.0060, { id: 'nyc' });
  
  const results = index.query(37.7749, -122.4194, 5);
  
  if (results.length < 2) {
    throw new Error(`Expected at least 2 nearby results, got ${results.length}`);
  }
});

test('GeohashIndex: Distance Calculation', () => {
  const index = new GeohashIndex(5);
  
  // San Francisco to Los Angeles (about 559 km)
  const distance = index.haversineDistance(37.7749, -122.4194, 34.0522, -118.2437);
  
  if (Math.abs(distance - 559) > 50) {
    throw new Error(`Distance calculation off: ${distance}km (expected ~559km)`);
  }
});

test('Performance: Large Dataset', () => {
  const boundary = new Rectangle(0, 0, 500, 500);
  const qt = new QuadTree(boundary, 8);
  const gh = new GeohashIndex(6);
  
  const start = Date.now();
  
  // Insert 1000 points
  for (let i = 0; i < 1000; i++) {
    const x = Math.random() * 1000;
    const y = Math.random() * 1000;
    const lat = (y / 1000) * 180 - 90;
    const lon = (x / 1000) * 360 - 180;
    
    qt.insert(new Point(x, y, { id: i }));
    gh.insert(lat, lon, { id: i });
  }
  
  const insertTime = Date.now() - start;
  if (insertTime > 1000) {
    throw new Error(`Insert took too long: ${insertTime}ms`);
  }
  
  // Query performance
  const queryStart = Date.now();
  const range = new Rectangle(500, 500, 50, 50);
  qt.query(range);
  gh.query(0, 0, 100);
  const queryTime = Date.now() - queryStart;
  
  if (queryTime > 100) {
    throw new Error(`Query took too long: ${queryTime}ms`);
  }
});

console.log(`\n📊 Test Results: ${passed} passed, ${failed} failed`);

if (failed > 0) {
  process.exit(1);
}
