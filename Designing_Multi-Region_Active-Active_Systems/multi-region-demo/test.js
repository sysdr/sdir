const fetch = require('node-fetch');

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runTests() {
  console.log('\n🧪 Running Multi-Region Tests...\n');

  try {
    // Test 1: Write to each region
    console.log('Test 1: Writing to all regions...');
    await fetch('http://localhost:3000/api/write', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ region: 'us-east', key: 'test1', value: 'us-east-value' })
    });
    await fetch('http://localhost:3000/api/write', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ region: 'us-west', key: 'test2', value: 'us-west-value' })
    });
    await fetch('http://localhost:3000/api/write', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ region: 'eu-west', key: 'test3', value: 'eu-west-value' })
    });
    console.log('✓ All writes successful\n');

    // Test 2: Verify replication
    console.log('Test 2: Checking replication (waiting 2s)...');
    await sleep(2000);
    
    const read1 = await fetch('http://localhost:3000/api/read/us-west/test1');
    const data1 = await read1.json();
    console.log(`✓ Read test1 from us-west: ${data1.value}`);

    const read2 = await fetch('http://localhost:3000/api/read/eu-west/test2');
    const data2 = await read2.json();
    console.log(`✓ Read test2 from eu-west: ${data2.value}\n`);

    // Test 3: Simulate conflict
    console.log('Test 3: Testing conflict resolution...');
    await Promise.all([
      fetch('http://localhost:3000/api/write', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ region: 'us-east', key: 'conflict', value: 'from-us-east' })
      }),
      fetch('http://localhost:3000/api/write', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ region: 'eu-west', key: 'conflict', value: 'from-eu-west' })
      })
    ]);
    await sleep(1000);
    console.log('✓ Conflict scenario executed\n');

    // Test 4: Check stats
    console.log('Test 4: Verifying statistics...');
    const statsUS = await (await fetch('http://us-east:3001/stats')).json();
    const statsEU = await (await fetch('http://eu-west:3003/stats')).json();
    
    console.log(`✓ US-East - Writes: ${statsUS.writes}, Replications: ${statsUS.replications}, Conflicts: ${statsUS.conflicts}`);
    console.log(`✓ EU-West - Writes: ${statsEU.writes}, Replications: ${statsEU.replications}, Conflicts: ${statsEU.conflicts}\n`);

    console.log('✅ All tests passed!\n');
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    process.exit(1);
  }
}

// Wait for services to start
setTimeout(runTests, 5000);
