const http = require('http');
const https = require('https');

async function testServer(url, protocol) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith('https') ? https : http;
    
    client.get(url, { rejectUnauthorized: false }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          console.log(`✅ ${protocol} Server: ${json.protocol || protocol} - Active Streams: ${json.activeStreams || 0}`);
          resolve(true);
        } catch (err) {
          console.log(`❌ ${protocol} Server: Invalid response`);
          resolve(false);
        }
      });
    }).on('error', (err) => {
      console.log(`❌ ${protocol} Server: ${err.message}`);
      resolve(false);
    });
  });
}

async function runTests() {
  console.log('🧪 Running tests...\n');
  
  // Wait for servers to start
  await new Promise(resolve => setTimeout(resolve, 3000));
  
  const results = await Promise.all([
    testServer('http://127.0.0.1:8443/stats', 'HTTP/2'),
    testServer('http://127.0.0.1:8444/stats', 'HTTP/3')
  ]);
  
  const allPassed = results.every(r => r);
  
  console.log('\n' + (allPassed ? '✅ All tests passed!' : '❌ Some tests failed'));
  process.exit(allPassed ? 0 : 1);
}

runTests();
