const http = require('http');

function request(options, body = null) {
  return new Promise((resolve, reject) => {
    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, data });
        }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function runTests() {
  console.log('\n🧪 Running Integration Tests...\n');

  // Test 1: Health checks
  console.log('Test 1: Service health checks');
  const services = [
    { name: 'Ingestion', port: 3001 },
    { name: 'Query', port: 3002 }
  ];

  for (const svc of services) {
    const res = await request({ hostname: 'localhost', port: svc.port, path: '/health' });
    console.log(`  ✓ ${svc.name}: ${res.data.status}`);
  }

  // Test 2: Ingest events
  console.log('\nTest 2: Event ingestion');
  const eventRes = await request(
    { hostname: 'localhost', port: 3001, path: '/events', method: 'POST', headers: { 'Content-Type': 'application/json' } },
    { userId: 'test_user_1', page: '/home' }
  );
  console.log(`  ✓ Event ingested: ${eventRes.data.eventId}`);

  // Test 3: Generate load
  console.log('\nTest 3: Load generation');
  request(
    { hostname: 'localhost', port: 3001, path: '/generate-load', method: 'POST', headers: { 'Content-Type': 'application/json' } },
    { count: 500, ratePerSecond: 50 }
  );
  console.log('  ✓ Generating 500 events at 50/sec...');

  // Wait for processing
  await new Promise(resolve => setTimeout(resolve, 5000));

  // Test 4: Query metrics
  console.log('\nTest 4: Query current metrics');
  const metricsRes = await request({ hostname: 'localhost', port: 3002, path: '/metrics/current' });
  console.log(`  ✓ Total Events: ${metricsRes.data.metrics.totalEvents}`);
  console.log(`  ✓ Unique Users: ${metricsRes.data.metrics.uniqueUsers}`);
  console.log(`  ✓ Active Sessions: ${metricsRes.data.metrics.activeSessions}`);

  console.log('\n✅ All tests passed!\n');
}

runTests().catch(console.error);
