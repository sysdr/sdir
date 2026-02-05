import express from 'express';
import { createServer } from 'http';
import { WebSocketServer } from 'ws';
import Redis from 'ioredis';
import { DistributedScheduler } from '../scheduler/scheduler.js';
import { Worker } from '../worker/worker.js';

const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

const REDIS_URL = process.env.REDIS_URL || 'redis://redis:6379';
const NODE_ID = process.env.NODE_ID || 'dashboard-node';

// Create scheduler and workers
const scheduler = new DistributedScheduler(NODE_ID, REDIS_URL);
const workers = [];

// Create 3 workers
for (let i = 0; i < 3; i++) {
  workers.push(new Worker(`worker-${i}`, REDIS_URL));
}

// Redis subscriber for events
const subscriber = new Redis(REDIS_URL);

// WebSocket clients
const clients = new Set();

// Broadcast to all connected clients
function broadcast(data) {
  const message = JSON.stringify(data);
  clients.forEach(client => {
    if (client.readyState === 1) { // OPEN
      client.send(message);
    }
  });
}

// Push stats to all clients for real-time dashboard updates
function pushStats() {
  broadcast({ type: 'stats', stats: scheduler.getStats() });
}

// Schedule demo tasks - burst of tasks so PENDING and RUNNING stay visible
async function scheduleDemoTasks() {
  const names = ['Send Email', 'Process Payment', 'Generate Report', 'Sync Data', 'Send Notification',
    'Validate Order', 'Update Cache', 'Export Report', 'Send Invoice', 'Process Refund'];
  // Burst of 10 tasks at same time - creates PENDING backlog (7 waiting) + RUNNING (3 workers)
  const burstDelay = 2000;
  for (let i = 0; i < 10; i++) {
    await scheduler.scheduleTask({
      name: names[i],
      payload: { id: i },
      delayMs: burstDelay // All fire together - 7 PENDING, 3 RUNNING
    });
  }
  // Recurring tasks
  await scheduler.scheduleTask({
    name: 'Health Check',
    payload: { service: 'api-server' },
    delayMs: 2000,
    recurring: true,
    intervalMs: 15000
  });
  await scheduler.scheduleTask({
    name: 'Metrics Collection',
    payload: { namespace: 'application' },
    delayMs: 2500,
    recurring: true,
    intervalMs: 20000
  });
}

// Listen for scheduler events - push stats on state changes for real-time dashboard
scheduler.on('task-scheduled', (task) => { broadcast({ type: 'task-scheduled', task }); pushStats(); });
scheduler.on('task-pending', (task) => { broadcast({ type: 'task-pending', task }); pushStats(); });
scheduler.on('task-running', (task) => { broadcast({ type: 'task-running', task }); pushStats(); });
scheduler.on('task-completed', (task) => { broadcast({ type: 'task-completed', task }); pushStats(); });
scheduler.on('task-failed', (task) => { broadcast({ type: 'task-failed', task }); pushStats(); });
scheduler.on('task-reassigned', (task) => { broadcast({ type: 'task-reassigned', task }); pushStats(); });
scheduler.on('leader-elected', (nodeId) => { broadcast({ type: 'leader-elected', nodeId }); pushStats(); });
scheduler.on('leader-lost', (nodeId) => { broadcast({ type: 'leader-lost', nodeId }); pushStats(); });
scheduler.on('task-rescheduled', (task) => { broadcast({ type: 'task-rescheduled', task }); pushStats(); });

// Subscribe to task completion events from workers
subscriber.subscribe('scheduler:events');
subscriber.on('message', (channel, message) => {
  try {
    const event = JSON.parse(message);
    
    if (event.type === 'task-completed') {
      scheduler.markTaskCompleted(event.taskId, event.success, event.result);
      pushStats(); // Real-time update when task completes
    } else if (event.type === 'task-started') {
      scheduler.markTaskRunning(event.taskId, event.workerId);
      pushStats(); // Real-time update when task starts
    }
    
    broadcast(event);
  } catch (error) {
    console.error('Event processing error:', error);
  }
});

// API endpoint for stats validation
app.get('/api/stats', (req, res) => {
  res.json(scheduler.getStats());
});

// Serve static dashboard
app.get('/', (req, res) => {
  res.send(`
<!DOCTYPE html>
<html>
<head>
  <title>Distributed Job Scheduler Dashboard</title>
  <style>
    * {
      margin: 0;
      padding: 0;
      box-sizing: border-box;
    }
    
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
      background: #1b5e20;
      min-height: 100vh;
      padding: 20px;
    }
    
    .container {
      max-width: 1400px;
      margin: 0 auto;
    }
    
    h1 {
      color: white;
      margin-bottom: 30px;
      font-size: 32px;
      text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
    }
    
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
      gap: 20px;
      margin-bottom: 20px;
    }
    
    .card {
      background: white;
      border-radius: 12px;
      padding: 24px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
    }
    
    .card h2 {
      color: #3B82F6;
      font-size: 18px;
      margin-bottom: 16px;
      border-bottom: 2px solid #E0E7FF;
      padding-bottom: 8px;
    }
    
    .stat {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 0;
      border-bottom: 1px solid #F3F4F6;
    }
    
    .stat:last-child {
      border-bottom: none;
    }
    
    .stat-label {
      color: #6B7280;
      font-size: 14px;
    }
    
    .stat-value {
      color: #1F2937;
      font-size: 24px;
      font-weight: bold;
    }
    
    .leader-badge {
      display: inline-block;
      background: linear-gradient(135deg, #10B981 0%, #059669 100%);
      color: white;
      padding: 4px 12px;
      border-radius: 12px;
      font-size: 12px;
      font-weight: bold;
    }
    
    .follower-badge {
      display: inline-block;
      background: #9CA3AF;
      color: white;
      padding: 4px 12px;
      border-radius: 12px;
      font-size: 12px;
      font-weight: bold;
    }
    
    .task-log {
      background: white;
      border-radius: 12px;
      padding: 24px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.2);
      max-height: 400px;
      overflow-y: auto;
    }
    
    .log-entry {
      padding: 12px;
      margin-bottom: 8px;
      border-radius: 8px;
      font-size: 13px;
      font-family: 'Courier New', monospace;
      box-shadow: 0 2px 4px rgba(0,0,0,0.1);
    }
    
    .log-scheduled { background: #DBEAFE; color: #1E40AF; }
    .log-pending { background: #FEF3C7; color: #92400E; }
    .log-running { background: #DBEAFE; color: #1E3A8A; }
    .log-completed { background: #D1FAE5; color: #065F46; }
    .log-failed { background: #FEE2E2; color: #991B1B; }
    .log-leader { background: #E0E7FF; color: #3730A3; }
    
    .timestamp {
      color: #6B7280;
      font-size: 11px;
      margin-right: 8px;
    }
    
    .timing-wheel {
      display: grid;
      grid-template-columns: repeat(10, 1fr);
      gap: 4px;
      margin-top: 16px;
    }
    
    .wheel-slot {
      aspect-ratio: 1;
      background: #F3F4F6;
      border-radius: 4px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 10px;
      color: #6B7280;
      transition: all 0.3s;
    }
    
    .wheel-slot.active {
      background: linear-gradient(135deg, #3B82F6 0%, #2563EB 100%);
      color: white;
      transform: scale(1.1);
      box-shadow: 0 4px 8px rgba(59, 130, 246, 0.4);
    }
    
    .wheel-slot.has-tasks {
      background: #DBEAFE;
      color: #1E40AF;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>⚙️ Distributed Job Scheduler</h1>
    
    <div class="grid">
      <div class="card">
        <h2>Scheduler Status</h2>
        <div class="stat">
          <span class="stat-label">Node</span>
          <span class="stat-value" id="nodeId">-</span>
        </div>
        <div class="stat">
          <span class="stat-label">Role</span>
          <span id="role">-</span>
        </div>
        <div class="stat">
          <span class="stat-label">Total Tasks</span>
          <span class="stat-value" id="totalTasks">0</span>
        </div>
      </div>
      
      <div class="card">
        <h2>Task States</h2>
        <div class="stat">
          <span class="stat-label">Scheduled</span>
          <span class="stat-value" id="scheduled">0</span>
        </div>
        <div class="stat">
          <span class="stat-label">Pending</span>
          <span class="stat-value" id="pending">0</span>
        </div>
        <div class="stat">
          <span class="stat-label">Running</span>
          <span class="stat-value" id="running">0</span>
        </div>
        <div class="stat">
          <span class="stat-label">Completed</span>
          <span class="stat-value" id="completed">0</span>
        </div>
      </div>
      
      <div class="card">
        <h2>Workers</h2>
        <div class="stat">
          <span class="stat-label">Active Workers</span>
          <span class="stat-value">3</span>
        </div>
        <div class="stat">
          <span class="stat-label">Tasks Processed</span>
          <span class="stat-value" id="processed">0</span>
        </div>
      </div>
    </div>
    
    <div class="card" style="margin-bottom: 20px;">
      <h2>Timing Wheel (60 Slots, 1 Second/Slot)</h2>
      <div class="timing-wheel" id="timingWheel"></div>
    </div>
    
    <div class="task-log">
      <h2 style="color: #3B82F6; margin-bottom: 16px;">Event Log</h2>
      <div id="logs"></div>
    </div>
  </div>

  <script>
    const ws = new WebSocket('ws://' + window.location.host);
    const logs = document.getElementById('logs');
    let processedCount = 0;
    
    // Initialize timing wheel
    const wheelContainer = document.getElementById('timingWheel');
    for (let i = 0; i < 60; i++) {
      const slot = document.createElement('div');
      slot.className = 'wheel-slot';
      slot.textContent = i;
      slot.id = 'slot-' + i;
      wheelContainer.appendChild(slot);
    }
    
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      
      if (data.type === 'stats') {
        updateStats(data.stats);
      } else {
        addLog(data);
      }
    };
    
    function updateStats(stats) {
      const tb = stats.tasksByState || {};
      const set = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
      set('nodeId', stats.nodeId || '-');
      const roleEl = document.getElementById('role');
      if (roleEl) roleEl.innerHTML = stats.isLeader 
        ? '<span class="leader-badge">LEADER</span>'
        : '<span class="follower-badge">FOLLOWER</span>';
      set('totalTasks', stats.totalTasks ?? 0);
      set('scheduled', tb.SCHEDULED ?? 0);
      set('pending', tb.PENDING ?? 0);
      set('running', tb.RUNNING ?? 0);
      set('completed', tb.COMPLETED ?? 0);
      
      // Update timing wheel
      document.querySelectorAll('.wheel-slot').forEach(slot => {
        slot.classList.remove('active', 'has-tasks');
      });
      
      const currentSlot = document.getElementById('slot-' + stats.currentSlot);
      if (currentSlot) {
        currentSlot.classList.add('active');
      }
    }
    
    function addLog(data) {
      const entry = document.createElement('div');
      const timestamp = new Date().toLocaleTimeString();
      
      let className = 'log-entry ';
      let message = '';
      
      switch(data.type) {
        case 'task-scheduled':
          className += 'log-scheduled';
          message = \`📅 Task scheduled: \${data.task.name} (ID: \${data.task.id.substring(0, 8)})\`;
          break;
        case 'task-pending':
          className += 'log-pending';
          message = \`⏳ Task pending: \${data.task.name}\`;
          break;
        case 'task-started':
          className += 'log-running';
          message = \`🔨 Worker \${data.workerId} started task \${data.taskId.substring(0, 8)}\`;
          break;
        case 'task-completed':
          className += 'log-completed';
          message = \`✅ Task completed by \${data.workerId}: \${data.result}\`;
          processedCount++;
          document.getElementById('processed').textContent = processedCount;
          break;
        case 'task-failed':
          className += 'log-failed';
          message = \`❌ Task failed: \${data.task ? data.task.name : data.result}\`;
          break;
        case 'task-reassigned':
          className += 'log-pending';
          message = \`🔄 Task reassigned after timeout: \${data.task.name}\`;
          break;
        case 'leader-elected':
          className += 'log-leader';
          message = \`🎯 Node \${data.nodeId} elected as LEADER\`;
          break;
        case 'leader-lost':
          className += 'log-leader';
          message = \`❌ Leadership changed to \${data.nodeId}\`;
          break;
        default:
          className += 'log-entry';
          message = JSON.stringify(data);
      }
      
      entry.className = className;
      entry.innerHTML = \`<span class="timestamp">\${timestamp}</span>\${message}\`;
      
      logs.insertBefore(entry, logs.firstChild);
      
      // Keep only last 50 entries
      while (logs.children.length > 50) {
        logs.removeChild(logs.lastChild);
      }
    }
  </script>
</body>
</html>
  `);
});

// WebSocket connection handling
wss.on('connection', (ws) => {
  clients.add(ws);
  console.log('Dashboard client connected');
  const stats = scheduler.getStats();
  if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'stats', stats }));
  ws.on('close', () => {
    clients.delete(ws);
    console.log('Dashboard client disconnected');
  });
});

// Send stats every 500ms to catch transient PENDING/RUNNING states
setInterval(pushStats, 500);

// Start everything
async function start() {
  await scheduler.start();
  
  // Wait a bit for scheduler to initialize
  await new Promise(resolve => setTimeout(resolve, 2000));
  
  // Start workers
  for (const worker of workers) {
    await worker.start();
  }
  
  // Schedule demo tasks
  await scheduleDemoTasks();
  
  const PORT = 3000;
  server.listen(PORT, () => {
    console.log(`Dashboard running at http://localhost:${PORT}`);
  });
}

start().catch(console.error);

