const express = require('express');
const { Pool } = require('pg');
const cors = require('cors');
const WebSocket = require('ws');
const http = require('http');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

app.use(cors());
app.use(express.json());

const pool = new Pool({
  host: 'postgres',
  port: 5432,
  database: 'eventstore',
  user: 'postgres',
  password: 'postgres'
});

// WebSocket connections for real-time event streaming
const clients = new Set();

wss.on('connection', (ws) => {
  clients.add(ws);
  ws.on('close', () => clients.delete(ws));
});

function broadcastEvent(event) {
  const message = JSON.stringify({ type: 'NEW_EVENT', event });
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

// Initialize database
async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS events (
      sequence_number SERIAL PRIMARY KEY,
      event_id VARCHAR(255) UNIQUE NOT NULL,
      aggregate_id VARCHAR(255) NOT NULL,
      event_type VARCHAR(100) NOT NULL,
      event_data JSONB NOT NULL,
      timestamp TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_aggregate ON events(aggregate_id);
    CREATE INDEX IF NOT EXISTS idx_sequence ON events(sequence_number);
  `);
  console.log('Event store initialized');
}

// Append event (write operation)
app.post('/events', async (req, res) => {
  try {
    const { eventId, aggregateId, type, data, timestamp } = req.body;
    
    const result = await pool.query(
      `INSERT INTO events (event_id, aggregate_id, event_type, event_data, timestamp)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING sequence_number`,
      [eventId, aggregateId, type, JSON.stringify(data), timestamp]
    );

    const event = {
      sequenceNumber: result.rows[0].sequence_number,
      eventId,
      aggregateId,
      type,
      data,
      timestamp
    };

    // Broadcast to projection services
    broadcastEvent(event);

    res.json(event);
  } catch (error) {
    console.error('Error appending event:', error);
    res.status(500).json({ error: error.message });
  }
});

// Get events by aggregate (for rebuilding state)
app.get('/events/:aggregateId', async (req, res) => {
  try {
    const { aggregateId } = req.params;
    const result = await pool.query(
      `SELECT * FROM events WHERE aggregate_id = $1 ORDER BY sequence_number`,
      [aggregateId]
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get events from sequence number (for projection catch-up)
app.get('/events', async (req, res) => {
  try {
    const { fromSequence = 0, limit = 100 } = req.query;
    const result = await pool.query(
      `SELECT sequence_number, event_id, aggregate_id, event_type, event_data, timestamp
       FROM events 
       WHERE sequence_number > $1 
       ORDER BY sequence_number 
       LIMIT $2`,
      [fromSequence, limit]
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get all events (for replay)
app.get('/events/all/stream', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT sequence_number, event_id, aggregate_id, event_type, event_data, timestamp
       FROM events 
       ORDER BY sequence_number`
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

const PORT = 3001;

async function start() {
  await initDB();
  server.listen(PORT, () => {
    console.log(`Event Store running on port ${PORT}`);
  });
}

start().catch(console.error);
