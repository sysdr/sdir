const axios = require('axios');

async function runLoadTest() {
  console.log('🚀 Starting load test...');
  
  const baseURL = 'http://localhost:3000';
  const duration = 60000; // 1 minute
  const startTime = Date.now();
  
  let requests = 0;
  let successes = 0;
  let failures = 0;
  
  while (Date.now() - startTime < duration) {
    const promises = [];
    
    // Generate load
    for (let i = 0; i < 10; i++) {
      promises.push(
        axios.get(`${baseURL}/api/recommendations/user${i}`)
          .then(() => { requests++; successes++; })
          .catch(() => { requests++; failures++; })
      );
      
      promises.push(
        axios.post(`${baseURL}/api/payment`, {
          amount: Math.floor(Math.random() * 1000),
          currency: 'USD',
          cardToken: 'tok_test'
        })
          .then(() => { requests++; successes++; })
          .catch(() => { requests++; failures++; })
      );
    }
    
    await Promise.all(promises);
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  
  console.log(`📊 Load test completed:`);
  console.log(`   Total requests: ${requests}`);
  console.log(`   Successes: ${successes}`);
  console.log(`   Failures: ${failures}`);
  console.log(`   Success rate: ${((successes / requests) * 100).toFixed(2)}%`);
}

if (require.main === module) {
  runLoadTest().catch(console.error);
}

module.exports = { runLoadTest };
