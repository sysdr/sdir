const WebSocket = require('ws');
const io = require('socket.io-client');

console.log('🧪 Running WebRTC Demo Tests...');

// Test 1: Backend Health Check
async function testBackendHealth() {
  try {
    const response = await fetch('http://localhost:3001/health');
    const data = await response.json();
    console.log('✅ Backend health check passed:', data.status);
    return true;
  } catch (error) {
    console.log('❌ Backend health check failed:', error.message);
    return false;
  }
}

// Test 2: WebSocket Connection
function testWebSocketConnection() {
  return new Promise((resolve) => {
    const socket = io('http://localhost:3001');
    
    socket.on('connect', () => {
      console.log('✅ WebSocket connection successful');
      socket.disconnect();
      resolve(true);
    });
    
    socket.on('connect_error', (error) => {
      console.log('❌ WebSocket connection failed:', error.message);
      resolve(false);
    });
    
    setTimeout(() => {
      console.log('❌ WebSocket connection timeout');
      resolve(false);
    }, 5000);
  });
}

// Test 3: Room Functionality
function testRoomFunctionality() {
  return new Promise((resolve) => {
    const socket1 = io('http://localhost:3001');
    const socket2 = io('http://localhost:3001');
    
    let socket1Connected = false;
    let socket2Connected = false;
    let userJoinedReceived = false;
    
    socket1.on('connect', () => {
      socket1Connected = true;
      socket1.emit('join-room', { roomId: 'test-room', userName: 'User1' });
    });
    
    socket2.on('connect', () => {
      socket2Connected = true;
      socket2.emit('join-room', { roomId: 'test-room', userName: 'User2' });
    });
    
    socket1.on('user-joined', (data) => {
      if (data.userName === 'User2') {
        userJoinedReceived = true;
        console.log('✅ Room functionality test passed');
        socket1.disconnect();
        socket2.disconnect();
        resolve(true);
      }
    });
    
    setTimeout(() => {
      if (!userJoinedReceived) {
        console.log('❌ Room functionality test failed');
        socket1.disconnect();
        socket2.disconnect();
        resolve(false);
      }
    }, 5000);
  });
}

// Run all tests
async function runTests() {
  console.log('\n🧪 Testing WebRTC Demo System...\n');
  
  const test1 = await testBackendHealth();
  const test2 = await testWebSocketConnection();
  const test3 = await testRoomFunctionality();
  
  const passed = [test1, test2, test3].filter(Boolean).length;
  const total = 3;
  
  console.log(`\n📊 Test Results: ${passed}/${total} tests passed`);
  
  if (passed === total) {
    console.log('🎉 All tests passed! WebRTC demo is working correctly.');
  } else {
    console.log('⚠️  Some tests failed. Check the logs above for details.');
  }
  
  process.exit(passed === total ? 0 : 1);
}

runTests();
