const http = require('http');
const assert = require('assert');

const BACKEND_URL = 'localhost:4000';
const FRONTEND_URL = 'localhost:3000';

function makeRequest(url, options = {}) {
  return new Promise((resolve, reject) => {
    const urlObj = new URL(url);
    const reqOptions = {
      hostname: urlObj.hostname,
      port: urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
      path: urlObj.pathname + urlObj.search,
      method: options.method || 'GET',
      headers: options.headers || {}
    };
    const req = http.request(reqOptions, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve({ status: res.statusCode, data, headers: res.headers }));
    });
    req.on('error', reject);
    if (options.body) {
      req.write(options.body);
    }
    req.end();
  });
}

async function runTests() {
  console.log('🧪 Running ABR Streaming Tests...\n');
  let passed = 0;
  let failed = 0;

  // Test 1: Backend Health Check
  try {
    const res = await makeRequest(`http://${BACKEND_URL}/health`);
    assert.strictEqual(res.status, 200);
    const health = JSON.parse(res.data);
    assert.strictEqual(health.status, 'healthy');
    console.log('✅ Test 1: Backend health check passed');
    passed++;
  } catch (error) {
    console.log('❌ Test 1: Backend health check failed:', error.message);
    failed++;
  }

  // Test 2: DASH Manifest
  try {
    const res = await makeRequest(`http://${BACKEND_URL}/manifest.mpd`);
    assert.strictEqual(res.status, 200);
    assert(res.data.includes('MPD'));
    assert(res.data.includes('240p') && res.data.includes('1080p'));
    console.log('✅ Test 2: DASH manifest generation passed');
    passed++;
  } catch (error) {
    console.log('❌ Test 2: DASH manifest failed:', error.message);
    failed++;
  }

  // Test 3: HLS Master Playlist
  try {
    const res = await makeRequest(`http://${BACKEND_URL}/playlist.m3u8`);
    assert.strictEqual(res.status, 200);
    assert(res.data.includes('#EXTM3U'));
    assert(res.data.includes('BANDWIDTH'));
    console.log('✅ Test 3: HLS master playlist passed');
    passed++;
  } catch (error) {
    console.log('❌ Test 3: HLS master playlist failed:', error.message);
    failed++;
  }

  // Test 4: Segment Download
  try {
    const res = await makeRequest(`http://${BACKEND_URL}/segments/480p/segment_0.m4s`);
    assert.strictEqual(res.status, 200);
    assert(res.headers['content-type'].includes('video/mp4'));
    console.log('✅ Test 4: Segment download passed');
    passed++;
  } catch (error) {
    console.log('❌ Test 4: Segment download failed:', error.message);
    failed++;
  }

  // Test 5: Network Throttling
  try {
    const body = JSON.stringify({ enabled: true, bandwidthKbps: 1000 });
    const res = await makeRequest(`http://${BACKEND_URL}/network/throttle`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: body
    });
    assert.strictEqual(res.status, 200);
    const result = JSON.parse(res.data);
    assert.strictEqual(result.status, 'ok');
    console.log('✅ Test 5: Network throttling passed');
    passed++;
  } catch (error) {
    console.log('❌ Test 5: Network throttling failed:', error.message);
    failed++;
  }

  // Test 6: Metrics Endpoint
  try {
    const res = await makeRequest(`http://${BACKEND_URL}/metrics`);
    assert.strictEqual(res.status, 200);
    const metrics = JSON.parse(res.data);
    assert(metrics.totalSegmentsServed !== undefined);
    assert(metrics.segmentsByQuality !== undefined);
    console.log('✅ Test 6: Metrics endpoint passed');
    passed++;
  } catch (error) {
    console.log('❌ Test 6: Metrics endpoint failed:', error.message);
    failed++;
  }

  // Test 7: Frontend Accessibility
  try {
    const res = await makeRequest(`http://${FRONTEND_URL}`);
    assert.strictEqual(res.status, 200);
    console.log('✅ Test 7: Frontend accessible passed');
    passed++;
  } catch (error) {
    console.log('❌ Test 7: Frontend accessibility failed:', error.message);
    failed++;
  }

  console.log(`\n📊 Test Results: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

setTimeout(runTests, 3000);
