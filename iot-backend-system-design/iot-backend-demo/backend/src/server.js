import express from 'express';
import { WebSocketServer } from 'ws';
import mqtt from 'mqtt';
import pg from 'pg';
import cors from 'cors';
import { createServer } from 'http';

const { Pool } = pg;

const app = express();
app.use(cors());
app.use(express.json());

const server = createServer(app);
const wss = new WebSocketServer({ server });

// Database connection
const pool = new Pool({
  host: process.env.DB_HOST || 'timescaledb',
  port: 5432,
  database: 'iotdb',
  user: 'postgres',
  password: 'postgres'
});

// MQTT connection
const mqttClient = mqtt.connect(process.env.MQTT_URL || 'mqtt://mqtt-broker:1883');

// WebSocket clients
const wsClients = new Set();

wss.on('connection', (ws) => {
  wsClients.add(ws);
  console.log('Dashboard connected');
  
  ws.on('close', () => {
    wsClients.delete(ws);
  });
});

function broadcast(data) {
  const message = JSON.stringify(data);
  wsClients.forEach(client => {
    if (client.readyState === 1) {
      client.send(message);
    }
  });
}

// MQTT message handler
mqttClient.on('connect', () => {
  console.log('Connected to MQTT broker');
  mqttClient.subscribe('devices/+/telemetry');
  mqttClient.subscribe('devices/+/status');
});

mqttClient.on('message', async (topic, message) => {
  try {
    const parts = topic.split('/');
    const deviceId = parts[1];
    const messageType = parts[2];
    const payload = JSON.parse(message.toString());

    if (messageType === 'telemetry') {
      // Store telemetry in TimescaleDB
      for (const [metric, value] of Object.entries(payload.metrics || {})) {
        await pool.query(
          `INSERT INTO device_telemetry (time, device_id, metric_name, metric_value, metadata)
           VALUES (NOW(), $1, $2, $3, $4)`,
          [deviceId, metric, value, JSON.stringify(payload.metadata || {})]
        );
      }

      // Update device registry
      await pool.query(
        `INSERT INTO device_registry (device_id, device_type, reported_state, last_seen)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (device_id) DO UPDATE SET
           reported_state = $3,
           last_seen = NOW(),
           updated_at = NOW()`,
        [deviceId, payload.device_type || 'sensor', JSON.stringify(payload.metrics)]
      );

      // Broadcast to dashboard
      broadcast({
        type: 'telemetry',
        deviceId,
        metrics: payload.metrics,
        timestamp: new Date().toISOString()
      });
    }

    if (messageType === 'status') {
      broadcast({
        type: 'status',
        deviceId,
        status: payload.status,
        timestamp: new Date().toISOString()
      });
    }
  } catch (error) {
    console.error('Error processing message:', error);
  }
});

// API Routes

// Get all devices
app.get('/api/devices', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT device_id, device_type, desired_state, reported_state, last_seen
       FROM device_registry
       ORDER BY last_seen DESC NULLS LAST`
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get device twin
app.get('/api/devices/:deviceId/twin', async (req, res) => {
  try {
    const { deviceId } = req.params;
    const result = await pool.query(
      `SELECT * FROM device_registry WHERE device_id = $1`,
      [deviceId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Device not found' });
    }
    res.json(result.rows[0]);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Update desired state (send command)
app.post('/api/devices/:deviceId/command', async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { command, payload } = req.body;

    // Store command
    await pool.query(
      `INSERT INTO device_commands (device_id, command_type, payload)
       VALUES ($1, $2, $3)`,
      [deviceId, command, JSON.stringify(payload)]
    );

    // Update desired state
    await pool.query(
      `UPDATE device_registry
       SET desired_state = desired_state || $2::jsonb,
           updated_at = NOW()
       WHERE device_id = $1`,
      [deviceId, JSON.stringify(payload)]
    );

    // Publish command to MQTT
    mqttClient.publish(`devices/${deviceId}/command`, JSON.stringify({
      command,
      payload,
      timestamp: new Date().toISOString()
    }));

    broadcast({
      type: 'command',
      deviceId,
      command,
      payload,
      timestamp: new Date().toISOString()
    });

    res.json({ success: true, message: 'Command sent' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get telemetry history
app.get('/api/devices/:deviceId/telemetry', async (req, res) => {
  try {
    const { deviceId } = req.params;
    const { hours = 1 } = req.query;

    const result = await pool.query(
      `SELECT time, metric_name, metric_value
       FROM device_telemetry
       WHERE device_id = $1 AND time > NOW() - INTERVAL '${parseInt(hours)} hours'
       ORDER BY time DESC
       LIMIT 500`,
      [deviceId]
    );
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Get aggregated stats
app.get('/api/stats', async (req, res) => {
  try {
    const deviceCount = await pool.query(
      `SELECT COUNT(DISTINCT device_id) as count FROM device_registry`
    );
    
    const messageCount = await pool.query(
      `SELECT COUNT(*) as count FROM device_telemetry
       WHERE time > NOW() - INTERVAL '1 hour'`
    );

    const activeDevices = await pool.query(
      `SELECT COUNT(*) as count FROM device_registry
       WHERE last_seen > NOW() - INTERVAL '5 minutes'`
    );

    res.json({
      totalDevices: parseInt(deviceCount.rows[0].count),
      messagesLastHour: parseInt(messageCount.rows[0].count),
      activeDevices: parseInt(activeDevices.rows[0].count)
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', mqtt: mqttClient.connected });
});

const PORT = process.env.PORT || 3001;
server.listen(PORT, () => {
  console.log(`IoT Backend running on port ${PORT}`);
});
