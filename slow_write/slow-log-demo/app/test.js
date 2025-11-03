const http = require('http');

async function testEndpoint() {
  return new Promise((resolve, reject) => {
    const req = http.get('http://127.0.0.1:3000/api/process', (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        if (res.statusCode === 200) {
          resolve(JSON.parse(data));
        } else {
          reject(new Error(`Status: ${res.statusCode}`));
        }
      });
    });
    req.on('error', reject);
  });
}

async function runTests() {
  console.log('🧪 Running tests...\n');
  
  try {
    // Test 1: Basic endpoint
    console.log('Test 1: Basic API endpoint');
    const result1 = await testEndpoint();
    console.log('✅ PASS - Endpoint responds correctly');
    console.log(`   Response: ${JSON.stringify(result1)}\n`);
    
    // Test 2: Multiple concurrent requests
    console.log('Test 2: Concurrent requests');
    const promises = Array(10).fill(null).map(() => testEndpoint());
    const results = await Promise.all(promises);
    console.log(`✅ PASS - Handled ${results.length} concurrent requests\n`);
    
    // Test 3: Metrics endpoint
    console.log('Test 3: Metrics endpoint');
    const metricsReq = await new Promise((resolve, reject) => {
      http.get('http://127.0.0.1:3000/api/metrics', (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => resolve(JSON.parse(data)));
      }).on('error', reject);
    });
    console.log('✅ PASS - Metrics endpoint working');
    console.log(`   Total requests: ${metricsReq.totalRequests}\n`);
    
    console.log('✅ All tests passed!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    process.exit(1);
  }
}

setTimeout(runTests, 5000); // Wait for server to start
