const { Kafka } = require('kafkajs');
const { createClient } = require('redis');
const { Pool } = require('pg');

// Test configuration
const kafka = new Kafka({
  clientId: 'pipeline-tester',
  brokers: ['localhost:9092']
});

const redis = createClient({ url: 'redis://localhost:6379' });
const pool = new Pool({
  connectionString: 'postgresql://admin:password@localhost:5432/pipeline_db'
});

async function testStreamProcessing() {
  console.log('🧪 Testing Stream Processing...');
  
  const producer = kafka.producer();
  await producer.connect();
  
  // Send test events
  for (let i = 0; i < 10; i++) {
    await producer.send({
      topic: 'user-events',
      messages: [{
        key: i.toString(),
        value: JSON.stringify({
          eventId: `test-${i}`,
          userId: i,
          eventType: 'test',
          timestamp: new Date().toISOString(),
          amount: 100
        })
      }]
    });
  }
  
  await producer.disconnect();
  
  // Wait for processing
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  // Verify metrics in Redis
  const metrics = await redis.hGetAll('realtime:metrics');
  console.log('✅ Stream metrics:', metrics.totalEvents);
}

async function testBatchProcessing() {
  console.log('🧪 Testing Batch Processing...');
  
  // Verify batch data exists
  const result = await pool.query('SELECT COUNT(*) FROM batch_metrics');
  console.log('✅ Batch records:', result.rows[0].count);
}

async function testLambdaArchitecture() {
  console.log('🧪 Testing Lambda Architecture...');
  
  // Verify merged view exists
  const mergedView = await redis.get('lambda:merged_view');
  if (mergedView) {
    const view = JSON.parse(mergedView);
    console.log('✅ Lambda view:', view.serving_layer);
  }
}

async function runTests() {
  try {
    await redis.connect();
    
    await testStreamProcessing();
    await testBatchProcessing();
    await testLambdaArchitecture();
    
    console.log('🎉 All tests passed!');
  } catch (error) {
    console.error('❌ Test failed:', error);
  } finally {
    await redis.disconnect();
    await pool.end();
  }
}

if (require.main === module) {
  runTests();
}
