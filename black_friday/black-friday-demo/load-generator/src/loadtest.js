const autocannon = require('autocannon');
const axios = require('axios');

const TARGET_URL = process.env.TARGET_URL || 'http://localhost:3001';

console.log('🔥 Black Friday Load Generator Starting...');
console.log(`Target: ${TARGET_URL}`);

// Simulate Black Friday traffic pattern
const trafficPatterns = [
  { duration: 30, connections: 10, name: 'Normal Traffic' },
  { duration: 60, connections: 100, name: 'Pre-Sale Buildup' },
  { duration: 120, connections: 500, name: 'Flash Sale Start' },
  { duration: 180, connections: 1000, name: 'Peak Black Friday' },
  { duration: 120, connections: 300, name: 'Post-Peak Stabilization' },
  { duration: 60, connections: 50, name: 'Return to Normal' }
];

async function runTrafficPattern(pattern) {
  console.log(`\n🚀 Starting: ${pattern.name}`);
  console.log(`📊 Connections: ${pattern.connections}, Duration: ${pattern.duration}s`);
  
  return new Promise((resolve) => {
    const instance = autocannon({
      url: `${TARGET_URL}/api/products`,
      connections: pattern.connections,
      duration: pattern.duration,
      headers: {
        'User-Agent': 'BlackFriday-LoadTest/1.0'
      }
    });

    let lastUpdate = 0;
    instance.on('tick', (counter) => {
      const now = Date.now();
      if (now - lastUpdate > 5000) { // Update every 5 seconds
        console.log(`📈 Current RPS: ${Math.round(counter.requests / (counter.duration / 1000))}`);
        lastUpdate = now;
      }
    });

    instance.on('done', (result) => {
      console.log(`✅ ${pattern.name} completed`);
      console.log(`📊 Average RPS: ${Math.round(result.requests / (result.duration / 1000))}`);
      console.log(`⏱️  Average Latency: ${result.latency.mean}ms`);
      console.log(`❌ Error Rate: ${((result.non2xx / result.requests) * 100).toFixed(2)}%`);
      resolve(result);
    });
  });
}

async function simulateBlackFridayTraffic() {
  console.log('🛍️  Simulating Black Friday Traffic Patterns');
  console.log('===============================================');
  
  for (const pattern of trafficPatterns) {
    await runTrafficPattern(pattern);
    await new Promise(resolve => setTimeout(resolve, 5000)); // 5s break between patterns
  }
  
  console.log('\n🎉 Black Friday simulation completed!');
  console.log('Check your dashboard for metrics and scaling events.');
}

// Wait for backend to be ready
async function waitForBackend() {
  let attempts = 0;
  while (attempts < 30) {
    try {
      await axios.get(`${TARGET_URL}/health`);
      console.log('✅ Backend is ready');
      return;
    } catch (error) {
      attempts++;
      console.log(`⏳ Waiting for backend... (${attempts}/30)`);
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  }
  throw new Error('Backend not ready after 60 seconds');
}

// Main execution
waitForBackend()
  .then(() => simulateBlackFridayTraffic())
  .catch(console.error);
