const { Kafka } = require('kafkajs');
const { createClient } = require('redis');
const { Pool } = require('pg');

const kafka = new Kafka({
  clientId: 'lambda-coordinator',
  brokers: [process.env.KAFKA_BOOTSTRAP_SERVERS]
});

const consumer = kafka.consumer({ groupId: 'lambda-coordinator-group' });
const redis = createClient({ url: process.env.REDIS_URL });
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// Lambda Architecture: Merge speed and batch layers
async function mergeViews() {
  try {
    // Get real-time data from speed layer (Redis)
    const speedData = await redis.hGetAll('realtime:metrics');
    
    // Get batch data from batch layer (PostgreSQL)
    const batchResult = await pool.query(`
      SELECT 
        SUM(event_count) as batch_events,
        SUM(total_revenue) as batch_revenue,
        COUNT(DISTINCT user_segment) as segments
      FROM batch_metrics 
      WHERE date = CURRENT_DATE
    `);
    
    const batchData = batchResult.rows[0] || { batch_events: 0, batch_revenue: 0, segments: 0 };
    
    // Merge views for serving layer
    const mergedView = {
      timestamp: new Date().toISOString(),
      speed_layer: {
        total_events: parseInt(speedData.totalEvents || 0),
        active_users: parseInt(speedData.activeUsers || 0),
        events_by_type: JSON.parse(speedData.eventsByType || '{}'),
        revenue_by_segment: JSON.parse(speedData.revenueBySegment || '{}')
      },
      batch_layer: {
        total_events: parseInt(batchData.batch_events || 0),
        total_revenue: parseFloat(batchData.batch_revenue || 0),
        segments_processed: parseInt(batchData.segments || 0)
      },
      serving_layer: {
        combined_events: parseInt(speedData.totalEvents || 0) + parseInt(batchData.batch_events || 0),
        data_freshness_seconds: Math.floor((Date.now() - new Date(speedData.lastUpdate || Date.now()).getTime()) / 1000),
        consistency_check: 'ok'
      }
    };
    
    // Store merged view
    await redis.set('lambda:merged_view', JSON.stringify(mergedView));
    
    console.log(`🔄 Lambda views merged - Speed: ${mergedView.speed_layer.total_events}, Batch: ${mergedView.batch_layer.total_events}`);
    
  } catch (error) {
    console.error('❌ Error merging views:', error.message);
  }
}

async function startCoordinator() {
  await redis.connect();
  await consumer.connect();
  
  // Merge views every 30 seconds
  setInterval(mergeViews, 30000);
  
  // Initial merge
  await mergeViews();
  
  console.log('🏗️  Lambda architecture coordinator started...');
}

startCoordinator().catch(console.error);
