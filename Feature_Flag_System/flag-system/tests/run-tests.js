const fetch = require('node-fetch');

const colors = {
  green: '\x1b[32m',
  red: '\x1b[31m',
  reset: '\x1b[0m'
};

async function test(name, fn) {
  try {
    await fn();
    console.log(`${colors.green}✓${colors.reset} ${name}`);
    return true;
  } catch (error) {
    console.log(`${colors.red}✗${colors.reset} ${name}`);
    console.log(`  Error: ${error.message}`);
    return false;
  }
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runTests() {
  console.log('\n=== Feature Flag System Tests ===\n');
  
  const results = [];
  
  // Wait for services
  console.log('Waiting for services to be ready...');
  await sleep(5000);
  
  // Test flag service health
  results.push(await test('Flag service is healthy', async () => {
    const res = await fetch('http://flag-service:3000/health');
    const data = await res.json();
    if (data.status !== 'healthy') throw new Error('Service unhealthy');
  }));
  
  // Test retrieve all flags
  results.push(await test('Retrieve all flags', async () => {
    const res = await fetch('http://flag-service:3000/flags');
    const flags = await res.json();
    if (!Array.isArray(flags)) throw new Error('Expected array');
    if (flags.length === 0) throw new Error('No flags found');
  }));
  
  // Test flag evaluation
  results.push(await test('Evaluate flag for user', async () => {
    const res = await fetch('http://flag-service:3000/evaluate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        flagId: 'fast-checkout',
        userId: 'test-user-123',
        context: {}
      })
    });
    const data = await res.json();
    if (typeof data.enabled !== 'boolean') throw new Error('Invalid response');
  }));
  
  // Test consistent hashing
  results.push(await test('Consistent user assignment', async () => {
    const userId = 'consistency-test-user';
    const results = [];
    
    for (let i = 0; i < 5; i++) {
      const res = await fetch('http://flag-service:3000/evaluate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          flagId: 'new-payment-flow',
          userId,
          context: {}
        })
      });
      const data = await res.json();
      results.push(data.enabled);
    }
    
    const allSame = results.every(r => r === results[0]);
    if (!allSame) throw new Error('Inconsistent assignment');
  }));
  
  // Test toggle flag
  results.push(await test('Toggle flag', async () => {
    const res = await fetch('http://flag-service:3000/flags/dark-mode/toggle', {
      method: 'POST'
    });
    const flag = await res.json();
    if (!flag.id) throw new Error('Toggle failed');
  }));
  
  // Test rollout percentage
  results.push(await test('Update rollout percentage', async () => {
    const res = await fetch('http://flag-service:3000/flags/new-payment-flow/rollout', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ percentage: 75 })
    });
    const flag = await res.json();
    if (flag.rollout_percentage !== 75) throw new Error('Rollout update failed');
  }));
  
  // Test checkout service
  results.push(await test('Checkout service responds correctly', async () => {
    const res = await fetch('http://checkout-service:3001/checkout/test-user');
    const data = await res.json();
    if (!data.flow) throw new Error('Invalid checkout response');
  }));
  
  // Test payment service
  results.push(await test('Payment service responds correctly', async () => {
    const res = await fetch('http://payment-service:3002/process/test-user');
    const data = await res.json();
    if (!data.version) throw new Error('Invalid payment response');
  }));
  
  // Test recommendations service
  results.push(await test('Recommendations service responds correctly', async () => {
    const res = await fetch('http://recommendations-service:3003/recommendations/test-user');
    const data = await res.json();
    if (!data.items) throw new Error('Invalid recommendations response');
  }));
  
  // Test statistics endpoint
  results.push(await test('Statistics endpoint works', async () => {
    const res = await fetch('http://flag-service:3000/stats');
    const stats = await res.json();
    if (typeof stats.total_flags !== 'number') throw new Error('Invalid stats');
  }));
  
  const passed = results.filter(r => r).length;
  const total = results.length;
  
  console.log(`\n=== Results: ${passed}/${total} tests passed ===\n`);
  
  if (passed !== total) {
    process.exit(1);
  }
}

runTests().catch(console.error);
