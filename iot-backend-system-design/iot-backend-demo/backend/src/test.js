import mqtt from 'mqtt';

console.log('🧪 Running IoT Backend Tests...\n');

const API_URL = process.env.API_URL || 'http://localhost:3001';

async function runTests() {
  let passed = 0;
  let failed = 0;

  // Test 1: Health check
  try {
    const res = await fetch(`${API_URL}/health`);
    const data = await res.json();
    if (data.status === 'healthy') {
      console.log('✅ Health check passed');
      passed++;
    } else {
      throw new Error('Unhealthy status');
    }
  } catch (e) {
    console.log('❌ Health check failed:', e.message);
    failed++;
  }

  // Test 2: Get devices
  try {
    const res = await fetch(`${API_URL}/api/devices`);
    const data = await res.json();
    if (Array.isArray(data)) {
      console.log(`✅ Get devices passed (${data.length} devices)`);
      passed++;
    } else {
      throw new Error('Invalid response');
    }
  } catch (e) {
    console.log('❌ Get devices failed:', e.message);
    failed++;
  }

  // Test 3: Get stats
  try {
    const res = await fetch(`${API_URL}/api/stats`);
    const data = await res.json();
    if ('totalDevices' in data && 'messagesLastHour' in data) {
      console.log(`✅ Get stats passed (${data.messagesLastHour} messages/hour)`);
      passed++;
    } else {
      throw new Error('Invalid response');
    }
  } catch (e) {
    console.log('❌ Get stats failed:', e.message);
    failed++;
  }

  // Test 4: Send command
  try {
    const res = await fetch(`${API_URL}/api/devices/sensor-001/command`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        command: 'set_power',
        payload: { power: 'on' }
      })
    });
    const data = await res.json();
    if (data.success) {
      console.log('✅ Send command passed');
      passed++;
    } else {
      throw new Error('Command failed');
    }
  } catch (e) {
    console.log('❌ Send command failed:', e.message);
    failed++;
  }

  console.log(`\n📊 Test Results: ${passed} passed, ${failed} failed`);
  process.exit(failed > 0 ? 1 : 0);
}

// Wait for services to be ready
setTimeout(runTests, 2000);
