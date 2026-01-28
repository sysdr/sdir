import { WebSocket } from 'ws';

const API_URL = 'http://localhost:3001';
const WS_URL = 'ws://localhost:3001';

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function runTests() {
  console.log('🧪 Starting Chat System Tests...\n');
  
  try {
    // Test 1: Health check
    console.log('Test 1: API Health Check');
    const healthRes = await fetch(`${API_URL}/health`);
    const health = await healthRes.json();
    console.log('✅ Health check passed:', health.status);
    console.log('');
    
    // Test 2: WebSocket connection and presence
    console.log('Test 2: WebSocket Connection & Presence');
    const ws1 = new WebSocket(WS_URL);
    
    await new Promise((resolve) => {
      ws1.on('open', () => {
        console.log('✅ WebSocket connected');
        ws1.send(JSON.stringify({
          type: 'join',
          userId: 'test_user_1',
          username: 'TestUser1'
        }));
        resolve();
      });
    });
    
    await sleep(1000);
    
    // Test 3: Presence verification
    console.log('\nTest 3: Presence Verification');
    const presenceRes = await fetch(`${API_URL}/api/presence`);
    const presence = await presenceRes.json();
    const user1Present = presence.some(p => p.username === 'TestUser1' && p.status === 'online');
    
    if (user1Present) {
      console.log('✅ User presence correctly tracked');
    } else {
      throw new Error('User presence not found');
    }
    
    // Test 4: Message sending and write-through persistence
    console.log('\nTest 4: Message Sending & Persistence');
    const messagePromise = new Promise((resolve) => {
      ws1.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'message' && msg.content === 'Test message') {
          console.log(`✅ Message received (persisted in ${msg.persistLatency}ms)`);
          resolve(msg);
        }
      });
    });
    
    ws1.send(JSON.stringify({
      type: 'message',
      channelId: 'test-channel',
      content: 'Test message'
    }));
    
    const receivedMsg = await messagePromise;
    
    // Verify persistence
    await sleep(500);
    const messagesRes = await fetch(`${API_URL}/api/messages/test-channel`);
    const messages = await messagesRes.json();
    const persistedMsg = messages.find(m => m.id === receivedMsg.id);
    
    if (persistedMsg) {
      console.log('✅ Message persisted to PostgreSQL');
    } else {
      throw new Error('Message not persisted');
    }
    
    // Test 5: Read receipts
    console.log('\nTest 5: Read Receipts');
    const readPromise = new Promise((resolve) => {
      ws1.on('message', (data) => {
        const msg = JSON.parse(data.toString());
        if (msg.type === 'read_receipt') {
          console.log(`✅ Read receipt received (read count: ${msg.readCount})`);
          resolve(msg);
        }
      });
    });
    
    ws1.send(JSON.stringify({
      type: 'read',
      channelId: 'test-channel',
      messageId: receivedMsg.id
    }));
    
    await readPromise;
    
    // Test 6: Multiple users
    console.log('\nTest 6: Multiple Users & Presence Updates');
    const ws2 = new WebSocket(WS_URL);
    
    await new Promise((resolve) => {
      ws2.on('open', () => {
        ws2.send(JSON.stringify({
          type: 'join',
          userId: 'test_user_2',
          username: 'TestUser2'
        }));
        resolve();
      });
    });
    
    await sleep(1000);
    
    const presenceRes2 = await fetch(`${API_URL}/api/presence`);
    const presence2 = await presenceRes2.json();
    
    if (presence2.length >= 2) {
      console.log(`✅ Multiple users tracked (${presence2.length} online)`);
    } else {
      throw new Error('Multiple users not tracked correctly');
    }
    
    // Test 7: System stats
    console.log('\nTest 7: System Statistics');
    const statsRes = await fetch(`${API_URL}/api/stats`);
    const stats = await statsRes.json();
    
    console.log('✅ Stats retrieved:');
    console.log(`   - Total messages: ${stats.totalMessages}`);
    console.log(`   - Read receipts: ${stats.totalReadReceipts}`);
    console.log(`   - Online users: ${stats.onlineUsers}`);
    console.log(`   - Connected clients: ${stats.connectedClients}`);
    
    // Cleanup
    ws1.close();
    ws2.close();
    
    console.log('\n✅ All tests passed!\n');
    process.exit(0);
    
  } catch (error) {
    console.error('\n❌ Test failed:', error.message);
    process.exit(1);
  }
}

// Wait for services to be ready
async function waitForServices() {
  console.log('⏳ Waiting for services to be ready...');
  let attempts = 0;
  const maxAttempts = 30;
  
  while (attempts < maxAttempts) {
    try {
      const res = await fetch(`${API_URL}/health`);
      if (res.ok) {
        console.log('✅ Services ready\n');
        return;
      }
    } catch (error) {
      // Service not ready yet
    }
    
    attempts++;
    await sleep(1000);
  }
  
  throw new Error('Services failed to start');
}

waitForServices().then(runTests);
