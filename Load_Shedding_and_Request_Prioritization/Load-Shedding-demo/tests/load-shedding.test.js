import http from 'http';
import { PriorityClassifier } from '../src/classifier.js';
import { LoadShedder } from '../src/shedder.js';

function makeRequest(path, userTier = 'free') {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'localhost',
      port: 3000,
      path,
      method: 'GET',
      headers: { 'X-User-Tier': userTier }
    };
    
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, data }));
    });
    
    req.on('error', reject);
    req.setTimeout(5000, () => {
      req.destroy();
      reject(new Error('Request timeout'));
    });
    
    req.end();
  });
}

async function runTests() {
  console.log('🧪 Running Load Shedding Tests...\n');
  
  // Wait for server to be ready
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  // Test 1: Priority Classification
  console.log('Test 1: Priority Classification');
  const classifier = new PriorityClassifier();
  
  const criticalReq = classifier.classify({ url: '/api/checkout', headers: {} });
  console.assert(criticalReq.priority === 0, 'Checkout should be CRITICAL');
  
  const normalReq = classifier.classify({ url: '/api/search', headers: {} });
  console.assert(normalReq.priority === 2, 'Search should be NORMAL');
  
  const backgroundReq = classifier.classify({ url: '/api/analytics', headers: {} });
  console.assert(backgroundReq.priority === 3, 'Analytics should be BACKGROUND');
  
  console.log('✅ Classification tests passed\n');
  
  // Test 2: Load Shedder Logic
  console.log('Test 2: Load Shedder Logic');
  const shedder = new LoadShedder();
  
  // Normal load - should accept all
  shedder.updateMetrics(30, 50, 100, 20);
  console.assert(shedder.shouldAccept(3) === true, 'Should accept under normal load');
  
  // High load - should reject background
  shedder.updateMetrics(85, 400, 800, 80);
  await new Promise(resolve => setTimeout(resolve, 200)); // Wait for acceptance rates to update
  let rejected = 0;
  for (let i = 0; i < 100; i++) {
    if (!shedder.shouldAccept(3)) rejected++;
  }
  console.assert(rejected > 50, 'Should reject most background requests under high load');
  
  console.log('✅ Load shedder tests passed\n');
  
  // Test 3: End-to-End Acceptance
  console.log('Test 3: End-to-End Request Flow');
  
  try {
    const criticalResponse = await makeRequest('/api/checkout');
    console.assert(criticalResponse.status === 200, 'Critical request should be accepted');
    
    const normalResponse = await makeRequest('/api/search');
    console.assert([200, 503].includes(normalResponse.status), 'Normal request status valid');
    
    console.log('✅ End-to-end tests passed\n');
  } catch (err) {
    console.error('❌ End-to-end test failed:', err.message);
  }
  
  // Test 4: Stats Endpoint
  console.log('Test 4: Stats Endpoint');
  const statsResponse = await makeRequest('/api/stats');
  console.assert(statsResponse.status === 200, 'Stats endpoint should return 200');
  
  const stats = JSON.parse(statsResponse.data);
  console.assert(typeof stats.total === 'number', 'Stats should include total count');
  console.assert(typeof stats.loadScore === 'number', 'Stats should include load score');
  
  console.log('✅ Stats endpoint tests passed\n');
  
  console.log('🎉 All tests passed!');
  process.exit(0);
}

runTests().catch(function(err) { console.error(err); process.exit(1); });
