import { v4 as uuidv4 } from 'uuid';

const GATEWAY_URL = 'http://localhost:3000';
const PROCESSOR_URL = 'http://localhost:3001';

async function testIdempotency() {
  console.log('\n🧪 Testing Idempotency...');
  
  const idempotencyKey = uuidv4();
  const payment = {
    idempotencyKey,
    amount: 1000,
    sourceCurrency: 'USD',
    targetCurrency: 'EUR'
  };
  
  // Send same payment twice
  const res1 = await fetch(`${GATEWAY_URL}/api/payment`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payment)
  });
  const data1 = await res1.json();
  
  const res2 = await fetch(`${GATEWAY_URL}/api/payment`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payment)
  });
  const data2 = await res2.json();
  
  if (data1.id === data2.id) {
    console.log('✅ Idempotency working: Same payment ID returned');
  } else {
    console.log('❌ Idempotency failed: Different payment IDs');
  }
}

async function testCurrencyConversion() {
  console.log('\n🧪 Testing Currency Conversion...');
  
  const payment = {
    idempotencyKey: uuidv4(),
    amount: 1000,
    sourceCurrency: 'USD',
    targetCurrency: 'JPY'
  };
  
  const res = await fetch(`${GATEWAY_URL}/api/payment`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payment)
  });
  const data = await res.json();
  
  if (data.lockedRate && data.convertedAmount) {
    console.log(`✅ Currency conversion: ${payment.amount} ${payment.sourceCurrency} = ${data.convertedAmount} ${payment.targetCurrency}`);
    console.log(`   Locked rate: ${data.lockedRate}`);
  } else {
    console.log('❌ Currency conversion failed');
  }
}

async function testFraudDetection() {
  console.log('\n🧪 Testing Fraud Detection...');
  
  const payment = {
    idempotencyKey: uuidv4(),
    amount: 15000, // High amount
    sourceCurrency: 'USD',
    targetCurrency: 'EUR'
  };
  
  const res = await fetch(`${GATEWAY_URL}/api/payment`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payment)
  });
  const data = await res.json();
  
  if (data.fraudScore !== undefined) {
    console.log(`✅ Fraud score calculated: ${data.fraudScore}`);
    if (data.state === 'rejected' && data.fraudScore > 0.85) {
      console.log('✅ High-risk payment correctly rejected');
    }
  } else {
    console.log('❌ Fraud detection failed');
  }
}

async function testStateMachine() {
  console.log('\n🧪 Testing Payment State Machine...');
  
  const payment = {
    idempotencyKey: uuidv4(),
    amount: 500,
    sourceCurrency: 'EUR',
    targetCurrency: 'USD'
  };
  
  const res = await fetch(`${GATEWAY_URL}/api/payment`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payment)
  });
  const data = await res.json();
  
  const validStates = ['pending', 'validated', 'authorized', 'captured', 'rejected'];
  if (validStates.includes(data.state)) {
    console.log(`✅ Payment in valid state: ${data.state}`);
  } else {
    console.log(`❌ Invalid state: ${data.state}`);
  }
}

async function testMetrics() {
  console.log('\n🧪 Testing Metrics Endpoint...');
  
  const res = await fetch(`${GATEWAY_URL}/api/metrics`);
  const data = await res.json();
  
  if (data.totalPayments !== undefined && data.authorizationRate !== undefined) {
    console.log(`✅ Metrics working: ${data.totalPayments} total, ${data.authorizationRate}% auth rate`);
  } else {
    console.log('❌ Metrics failed');
  }
}

async function runTests() {
  console.log('🚀 Starting Global Payment System Tests\n');
  
  // Wait for services to be ready
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  try {
    await testIdempotency();
    await testCurrencyConversion();
    await testFraudDetection();
    await testStateMachine();
    await testMetrics();
    
    console.log('\n✅ All tests completed!');
  } catch (error) {
    console.error('\n❌ Test failed:', error.message);
    process.exit(1);
  }
}

runTests();
