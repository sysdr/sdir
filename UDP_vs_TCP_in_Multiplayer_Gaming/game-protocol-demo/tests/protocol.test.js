const dgram = require('dgram');
const net = require('net');
const assert = require('assert');

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function testUDPConnection() {
  console.log('Testing UDP connection...');
  
  const client = dgram.createSocket('udp4');
  let received = false;

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      client.close();
      reject(new Error('UDP test timeout'));
    }, 5000);

    client.on('message', (msg) => {
      try {
        const data = JSON.parse(msg.toString());
        assert(data.tick !== undefined, 'UDP response should contain tick number');
        assert(Array.isArray(data.players), 'UDP response should contain players array');
        received = true;
        clearTimeout(timeout);
        client.close();
        console.log('✅ UDP connection test passed');
        resolve();
      } catch (err) {
        clearTimeout(timeout);
        client.close();
        reject(err);
      }
    });

    client.bind(() => {
      const joinMsg = JSON.stringify({ type: 'join', clientId: 'test-udp' });
      client.send(joinMsg, 9001, 'localhost', (err) => {
        if (err) {
          clearTimeout(timeout);
          client.close();
          reject(err);
        }
      });
    });
  });
}

async function testTCPConnection() {
  console.log('Testing TCP connection...');
  
  return new Promise((resolve, reject) => {
    const client = net.createConnection({ port: 9002, host: 'localhost' });
    let buffer = '';

    const timeout = setTimeout(() => {
      client.end();
      reject(new Error('TCP test timeout'));
    }, 5000);

    client.on('connect', () => {
      const inputMsg = JSON.stringify({ type: 'input', vx: 5, vy: 3 });
      client.write(inputMsg + '\n');
    });

    client.on('data', (data) => {
      buffer += data.toString();
      
      const newlineIndex = buffer.indexOf('\n');
      if (newlineIndex !== -1) {
        const message = buffer.slice(0, newlineIndex);
        try {
          const parsed = JSON.parse(message);
          assert(parsed.tick !== undefined, 'TCP response should contain tick number');
          assert(Array.isArray(parsed.players), 'TCP response should contain players array');
          clearTimeout(timeout);
          client.end();
          console.log('✅ TCP connection test passed');
          resolve();
        } catch (err) {
          clearTimeout(timeout);
          client.end();
          reject(err);
        }
      }
    });

    client.on('error', (err) => {
      clearTimeout(timeout);
      reject(err);
    });
  });
}

async function testMetricsEndpoint() {
  console.log('Testing metrics endpoint...');
  
  const http = require('http');
  
  return new Promise((resolve, reject) => {
    const req = http.get('http://localhost:3000/metrics', (res) => {
      let data = '';
      
      res.on('data', (chunk) => {
        data += chunk;
      });
      
      res.on('end', () => {
        try {
          const metrics = JSON.parse(data);
          assert(metrics.metrics !== undefined, 'Response should contain metrics');
          assert(metrics.tickNumber !== undefined, 'Response should contain tick number');
          assert(metrics.playerCount !== undefined, 'Response should contain player count');
          console.log('✅ Metrics endpoint test passed');
          resolve();
        } catch (err) {
          reject(err);
        }
      });
    });

    req.on('error', reject);
    req.setTimeout(5000);
  });
}

async function testStateSync() {
  console.log('Testing state synchronization...');
  
  const udpClient = dgram.createSocket('udp4');
  let stateUpdates = 0;

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      udpClient.close();
      reject(new Error('State sync test timeout'));
    }, 5000);

    udpClient.on('message', (msg) => {
      stateUpdates++;
      if (stateUpdates >= 3) {
        clearTimeout(timeout);
        udpClient.close();
        console.log(`✅ State synchronization test passed (${stateUpdates} updates received)`);
        resolve();
      }
    });

    udpClient.bind(() => {
      const joinMsg = JSON.stringify({ type: 'join', clientId: 'test-sync' });
      udpClient.send(joinMsg, 9001, 'localhost');
    });
  });
}

async function runTests() {
  console.log('🧪 Running test suite...\n');

  try {
    await sleep(2000); // Wait for server to be ready
    
    await testMetricsEndpoint();
    await testUDPConnection();
    await testTCPConnection();
    await testStateSync();
    
    console.log('\n✅ All tests passed!');
    process.exit(0);
  } catch (err) {
    console.error('\n❌ Test failed:', err.message);
    process.exit(1);
  }
}

runTests();
