const { Pool } = require('pg');
const cron = require('node-cron');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL
});

// Initialize database schema
async function initDatabase() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS batch_metrics (
      id SERIAL PRIMARY KEY,
      date DATE NOT NULL,
      hour INTEGER NOT NULL,
      event_type VARCHAR(50) NOT NULL,
      user_segment VARCHAR(50) NOT NULL,
      event_count INTEGER DEFAULT 0,
      total_revenue DECIMAL(10,2) DEFAULT 0,
      unique_users INTEGER DEFAULT 0,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(date, hour, event_type, user_segment)
    );
    
    CREATE TABLE IF NOT EXISTS daily_summary (
      id SERIAL PRIMARY KEY,
      date DATE NOT NULL UNIQUE,
      total_events INTEGER DEFAULT 0,
      total_revenue DECIMAL(10,2) DEFAULT 0,
      unique_users INTEGER DEFAULT 0,
      top_event_type VARCHAR(50),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);
  
  console.log('📊 Database schema initialized');
}

// Simulate batch processing with comprehensive analytics
async function processBatchData() {
  console.log('🔄 Running batch processing job...');
  
  const currentDate = new Date().toISOString().split('T')[0];
  const currentHour = new Date().getHours();
  
  // Simulate processing historical data
  const eventTypes = ['click', 'view', 'purchase', 'signup', 'login'];
  const userSegments = ['premium', 'standard', 'trial'];
  
  for (const eventType of eventTypes) {
    for (const segment of userSegments) {
      const eventCount = Math.floor(Math.random() * 1000) + 100;
      const revenue = eventType === 'purchase' ? eventCount * (Math.random() * 100 + 50) : 0;
      const uniqueUsers = Math.floor(eventCount * 0.3);
      
      await pool.query(`
        INSERT INTO batch_metrics (date, hour, event_type, user_segment, event_count, total_revenue, unique_users)
        VALUES ($1, $2, $3, $4, $5, $6, $7)
        ON CONFLICT (date, hour, event_type, user_segment)
        DO UPDATE SET
          event_count = EXCLUDED.event_count,
          total_revenue = EXCLUDED.total_revenue,
          unique_users = EXCLUDED.unique_users
      `, [currentDate, currentHour, eventType, segment, eventCount, revenue, uniqueUsers]);
    }
  }
  
  // Create daily summary
  const summaryResult = await pool.query(`
    SELECT 
      SUM(event_count) as total_events,
      SUM(total_revenue) as total_revenue,
      SUM(unique_users) as unique_users,
      event_type as top_event_type
    FROM batch_metrics 
    WHERE date = $1
    GROUP BY event_type
    ORDER BY SUM(event_count) DESC
    LIMIT 1
  `, [currentDate]);
  
  if (summaryResult.rows.length > 0) {
    const summary = summaryResult.rows[0];
    await pool.query(`
      INSERT INTO daily_summary (date, total_events, total_revenue, unique_users, top_event_type)
      VALUES ($1, $2, $3, $4, $5)
      ON CONFLICT (date)
      DO UPDATE SET
        total_events = EXCLUDED.total_events,
        total_revenue = EXCLUDED.total_revenue,
        unique_users = EXCLUDED.unique_users,
        top_event_type = EXCLUDED.top_event_type
    `, [currentDate, summary.total_events, summary.total_revenue, summary.unique_users, summary.top_event_type]);
  }
  
  console.log(`✅ Batch processing completed for ${currentDate} hour ${currentHour}`);
}

async function startBatchProcessor() {
  await initDatabase();
  
  // Run batch processing every 5 minutes (simulating hourly in production)
  cron.schedule('*/5 * * * *', processBatchData);
  
  // Initial run
  await processBatchData();
  
  console.log('📋 Batch processor started...');
}

startBatchProcessor().catch(console.error);
