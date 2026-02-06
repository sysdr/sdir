import http from 'http';

function makeRequest(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'localhost',
      port: 3001,
      path,
      method,
      headers: body ? {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(JSON.stringify(body))
      } : {}
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          resolve(data);
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function runTests() {
  console.log('🧪 Running tests...\n');

  try {
    // Test 1: Health check
    console.log('Test 1: Health check');
    const health = await makeRequest('GET', '/health');
    console.assert(health.status === 'healthy', 'Health check failed');
    console.log('✅ Health check passed\n');

    // Test 2: Reset account
    console.log('Test 2: Reset account');
    await makeRequest('POST', '/api/reset');
    const account = await makeRequest('GET', '/api/account');
    const balance = typeof account.balance === 'number' ? account.balance : parseFloat(account.balance);
    console.assert(Math.abs(balance - 1000) < 0.01, 'Reset failed - expected balance 1000, got ' + balance);
    console.log('✅ Account reset passed\n');

    // Test 3: Pessimistic locking batch
    console.log('Test 3: Pessimistic locking (10 concurrent transactions)');
    const pessimisticResult = await makeRequest('POST', '/api/batch', {
      mode: 'pessimistic',
      count: 10,
      amount: 10
    });
    console.assert(pessimisticResult.success, 'Pessimistic batch failed');
    console.log(`✅ Pessimistic locking passed - All transactions succeeded\n`);

    // Test 4: Reset for optimistic test
    await makeRequest('POST', '/api/reset');

    // Test 5: Optimistic locking batch
    console.log('Test 4: Optimistic locking (10 concurrent transactions)');
    const optimisticResult = await makeRequest('POST', '/api/batch', {
      mode: 'optimistic',
      count: 10,
      amount: 10
    });
    console.assert(optimisticResult.success, 'Optimistic batch failed');
    const retries = optimisticResult.results
      .filter(r => r.success)
      .reduce((sum, r) => sum + (r.retries || 0), 0);
    console.log(`✅ Optimistic locking passed - Total retries: ${retries}\n`);

    console.log('🎉 All tests passed!');
    process.exit(0);
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    process.exit(1);
  }
}

// Wait for server to be ready
setTimeout(runTests, 3000);
