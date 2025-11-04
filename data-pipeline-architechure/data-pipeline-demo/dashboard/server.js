const express = require('express');
const WebSocket = require('ws');
const { createClient } = require('redis');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const server = require('http').createServer(app);
const wss = new WebSocket.Server({ server });

const redis = createClient({ url: process.env.REDIS_URL });
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

app.use(express.static(path.join(__dirname, 'public')));

// API endpoints
app.get('/api/realtime-metrics', async (req, res) => {
  try {
    const metrics = await redis.hGetAll('realtime:metrics');
    res.json(metrics);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/batch-metrics', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT date, hour, event_type, user_segment, event_count, total_revenue, unique_users
      FROM batch_metrics 
      WHERE date >= CURRENT_DATE - INTERVAL '7 days'
      ORDER BY date DESC, hour DESC
      LIMIT 100
    `);
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/lambda-view', async (req, res) => {
  try {
    const mergedView = await redis.get('lambda:merged_view');
    res.json(JSON.parse(mergedView || '{}'));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/api/recent-events', async (req, res) => {
  try {
    const events = await redis.lRange('recent:events', 0, 19);
    res.json(events.map(event => JSON.parse(event)));
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// WebSocket for real-time updates
wss.on('connection', (ws) => {
  console.log('📱 Dashboard client connected');
  
  const interval = setInterval(async () => {
    try {
      const metrics = await redis.hGetAll('realtime:metrics');
      const lambdaView = await redis.get('lambda:merged_view');
      
      ws.send(JSON.stringify({
        type: 'metrics_update',
        data: {
          realtime: metrics,
          lambda: JSON.parse(lambdaView || '{}')
        }
      }));
    } catch (error) {
      console.error('WebSocket error:', error);
    }
  }, 5000);
  
  ws.on('close', () => {
    clearInterval(interval);
    console.log('📱 Dashboard client disconnected');
  });
});

// Create public directory and index.html
const fs = require('fs').promises;
async function createPublicFiles() {
  await fs.mkdir(path.join(__dirname, 'public'), { recursive: true });
  
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Data Pipeline Architecture Dashboard</title>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #2c3e50 0%, #34495e 100%);
            color: #333; min-height: 100vh; padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        .header { 
            background: rgba(255,255,255,0.95); padding: 30px; border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1); margin-bottom: 30px; text-align: center;
        }
        .header h1 { color: #2c3e50; font-size: 2.5rem; margin-bottom: 10px; }
        .header p { color: #7f8c8d; font-size: 1.1rem; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(350px, 1fr)); gap: 30px; }
        .card { 
            background: rgba(255,255,255,0.95); padding: 30px; border-radius: 20px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1); transition: transform 0.3s ease;
        }
        .card:hover { transform: translateY(-5px); }
        .card h3 { color: #2c3e50; margin-bottom: 20px; font-size: 1.4rem; }
        .metric-value { font-size: 2.5rem; font-weight: bold; margin: 10px 0; }
        .metric-label { color: #7f8c8d; font-size: 0.9rem; text-transform: uppercase; letter-spacing: 1px; }
        .realtime { color: #27ae60; }
        .batch { color: #16a085; }
        .lambda { color: #e67e22; }
        .events-list { max-height: 300px; overflow-y: auto; }
        .event-item { 
            padding: 10px; margin: 8px 0; background: #f8f9fa; border-radius: 8px;
            border-left: 4px solid #16a085; font-size: 0.9rem;
        }
        .status-indicator { 
            display: inline-block; width: 10px; height: 10px; border-radius: 50%;
            margin-right: 8px; animation: pulse 2s infinite;
        }
        .active { background-color: #27ae60; }
        @keyframes pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.5; } }
        .chart-container { position: relative; height: 300px; margin-top: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏗️ Data Pipeline Architecture Dashboard</h1>
            <p>Real-time monitoring of Batch, Stream, and Lambda pipeline patterns</p>
        </div>

        <div class="grid">
            <div class="card">
                <h3><span class="status-indicator active"></span>Stream Processing (Kappa)</h3>
                <div class="realtime metric-value" id="stream-events">0</div>
                <div class="metric-label">Events Processed</div>
                <div class="realtime metric-value" id="active-users">0</div>
                <div class="metric-label">Active Users</div>
                <div class="chart-container">
                    <canvas id="streamChart"></canvas>
                </div>
            </div>

            <div class="card">
                <h3><span class="status-indicator active"></span>Batch Processing</h3>
                <div class="batch metric-value" id="batch-events">0</div>
                <div class="metric-label">Historical Events</div>
                <div class="batch metric-value" id="batch-revenue">$0</div>
                <div class="metric-label">Total Revenue</div>
                <div class="chart-container">
                    <canvas id="batchChart"></canvas>
                </div>
            </div>

            <div class="card">
                <h3><span class="status-indicator active"></span>Lambda Architecture</h3>
                <div class="lambda metric-value" id="combined-events">0</div>
                <div class="metric-label">Combined Events</div>
                <div class="lambda metric-value" id="data-freshness">0s</div>
                <div class="metric-label">Data Freshness</div>
                <div class="chart-container">
                    <canvas id="lambdaChart"></canvas>
                </div>
            </div>

            <div class="card">
                <h3>🔄 Recent Events Stream</h3>
                <div class="events-list" id="events-list">
                    <div class="event-item">Waiting for events...</div>
                </div>
            </div>

            <div class="card">
                <h3>📊 Event Type Distribution</h3>
                <div class="chart-container">
                    <canvas id="eventTypeChart"></canvas>
                </div>
            </div>

            <div class="card">
                <h3>💰 Revenue by Segment</h3>
                <div class="chart-container">
                    <canvas id="revenueChart"></canvas>
                </div>
            </div>
        </div>
    </div>

    <script>
        const ws = new WebSocket(\`ws://\${window.location.host}\`);
        
        // Initialize charts
        const streamChart = new Chart(document.getElementById('streamChart'), {
            type: 'line',
            data: { labels: [], datasets: [{ label: 'Events/min', data: [], borderColor: '#27ae60', tension: 0.4 }] },
            options: { responsive: true, maintainAspectRatio: false, scales: { y: { beginAtZero: true } } }
        });

        const batchChart = new Chart(document.getElementById('batchChart'), {
            type: 'bar',
            data: { labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'], datasets: [{ label: 'Daily Events', data: [1200, 1900, 3000, 5000, 2300, 3200, 4100], backgroundColor: '#16a085' }] },
            options: { responsive: true, maintainAspectRatio: false }
        });

        const lambdaChart = new Chart(document.getElementById('lambdaChart'), {
            type: 'doughnut',
            data: { labels: ['Speed Layer', 'Batch Layer'], datasets: [{ data: [60, 40], backgroundColor: ['#27ae60', '#16a085'] }] },
            options: { responsive: true, maintainAspectRatio: false }
        });

        const eventTypeChart = new Chart(document.getElementById('eventTypeChart'), {
            type: 'pie',
            data: { labels: [], datasets: [{ data: [], backgroundColor: ['#e74c3c', '#f39c12', '#27ae60', '#16a085', '#e67e22'] }] },
            options: { responsive: true, maintainAspectRatio: false }
        });

        const revenueChart = new Chart(document.getElementById('revenueChart'), {
            type: 'bar',
            data: { labels: [], datasets: [{ label: 'Revenue ($)', data: [], backgroundColor: '#e67e22' }] },
            options: { responsive: true, maintainAspectRatio: false }
        });

        ws.onmessage = (event) => {
            const message = JSON.parse(event.data);
            
            if (message.type === 'metrics_update') {
                const { realtime, lambda } = message.data;
                
                // Update realtime metrics
                document.getElementById('stream-events').textContent = realtime.totalEvents || 0;
                document.getElementById('active-users').textContent = realtime.activeUsers || 0;
                
                // Update stream chart with events per minute
                if (realtime.eventsPerMinute) {
                    try {
                        const eventsPerMin = JSON.parse(realtime.eventsPerMinute);
                        streamChart.data.labels = eventsPerMin.map(m => m.time);
                        streamChart.data.datasets[0].data = eventsPerMin.map(m => m.count);
                        streamChart.update();
                    } catch (e) {
                        console.error('Error parsing eventsPerMinute:', e);
                    }
                }
                
                // Update lambda metrics
                if (lambda.serving_layer) {
                    document.getElementById('combined-events').textContent = lambda.serving_layer.combined_events || 0;
                    document.getElementById('data-freshness').textContent = (lambda.serving_layer.data_freshness_seconds || 0) + 's';
                }
                
                // Update batch metrics
                if (lambda.batch_layer) {
                    document.getElementById('batch-events').textContent = lambda.batch_layer.total_events || 0;
                    document.getElementById('batch-revenue').textContent = '$' + (lambda.batch_layer.total_revenue || 0).toFixed(2);
                }
                
                // Update event type chart
                if (realtime.eventsByType) {
                    const eventTypes = JSON.parse(realtime.eventsByType);
                    eventTypeChart.data.labels = Object.keys(eventTypes);
                    eventTypeChart.data.datasets[0].data = Object.values(eventTypes);
                    eventTypeChart.update();
                }
                
                // Update revenue chart
                if (realtime.revenueBySegment) {
                    const revenue = JSON.parse(realtime.revenueBySegment);
                    revenueChart.data.labels = Object.keys(revenue);
                    revenueChart.data.datasets[0].data = Object.values(revenue).map(v => parseFloat(v).toFixed(2));
                    revenueChart.update();
                }
            }
        };

        // Load recent events
        async function loadRecentEvents() {
            try {
                const response = await fetch('/api/recent-events');
                const events = await response.json();
                
                const eventsList = document.getElementById('events-list');
                eventsList.innerHTML = events.map(event => \`
                    <div class="event-item">
                        <strong>\${event.eventType}</strong> by User \${event.userId} 
                        <br><small>\${new Date(event.timestamp).toLocaleTimeString()} - \${event.userSegment} - \${event.metadata.device}</small>
                    </div>
                \`).join('');
            } catch (error) {
                console.error('Error loading events:', error);
            }
        }

        setInterval(loadRecentEvents, 5000);
        loadRecentEvents();
    </script>
</body>
</html>`;
  
  await fs.writeFile(path.join(__dirname, 'public', 'index.html'), html);
}

async function startServer() {
  await redis.connect();
  await createPublicFiles();
  
  server.listen(3000, () => {
    console.log('🌐 Dashboard server running on port 3000');
  });
}

startServer().catch(console.error);
