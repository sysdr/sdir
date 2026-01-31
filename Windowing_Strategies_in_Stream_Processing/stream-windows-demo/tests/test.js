import http from 'http';

function testEndpoint(path, expectedStatus = 200) {
  return new Promise((resolve, reject) => {
    http.get(`http://localhost:3001${path}`, (res) => {
      if (res.statusCode === expectedStatus) {
        console.log(`✅ ${path} - Status ${res.statusCode}`);
        resolve();
      } else {
        console.log(`❌ ${path} - Expected ${expectedStatus}, got ${res.statusCode}`);
        reject();
      }
    }).on('error', reject);
  });
}

async function runTests() {
  console.log('\n🧪 Running API Tests...\n');
  
  try {
    await testEndpoint('/health');
    await testEndpoint('/stats');
    
    console.log('\n✅ All tests passed!\n');
    process.exit(0);
  } catch (error) {
    console.log('\n❌ Tests failed\n');
    process.exit(1);
  }
}

// Wait for server to be ready
setTimeout(runTests, 5000);
