#!/bin/bash

# Serverless Architecture Patterns Demo Setup
# Demonstrates: API Gateway, Workflows, Containers, Events, Serverless DB

set -e

echo "🚀 Setting up Serverless Architecture Demo..."

# 1. Create directory structure
mkdir -p serverless-demo/{api,orchestrator,worker,dashboard/src,database}
cd serverless-demo

# 2. Create API Gateway Service (Node.js + Express)
cat > api/server.js << 'EOF'
const express = require('express');
const Redis = require('ioredis');
const { v4: uuidv4 } = require('uuid');

const app = express();
const redis = new Redis({ host: 'redis', port: 6379 });
const pub = new Redis({ host: 'redis', port: 6379 });

app.use(express.json());
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', '*');
  if (req.method === 'OPTIONS') return res.sendStatus(200);
  next();
});

// API Gateway endpoint - receives requests and triggers workflows
app.post('/api/process', async (req, res) => {
  const requestId = uuidv4();
  const { type, data, priority = 'normal' } = req.body;
  
  const request = {
    requestId,
    type: type || 'video-transcode',
    data: data || { filename: 'sample.mp4', duration: Math.floor(Math.random() * 300) + 30 },
    priority,
    timestamp: new Date().toISOString(),
    status: 'received'
  };

  // Store request
  await redis.set(`request:${requestId}`, JSON.stringify(request));
  
  // Publish to workflow orchestrator
  await pub.publish('workflow:start', JSON.stringify(request));
  
  console.log(`[API] Request ${requestId} received - ${type}`);
  
  res.json({
    requestId,
    status: 'accepted',
    message: 'Workflow initiated',
    estimatedTime: `${Math.floor(request.data.duration / 60)} minutes`
  });
});

// Get request status
app.get('/api/status/:requestId', async (req, res) => {
  const data = await redis.get(`request:${req.params.requestId}`);
  if (!data) return res.status(404).json({ error: 'Request not found' });
  res.json(JSON.parse(data));
});

// Get metrics
app.get('/api/metrics', async (req, res) => {
  const [received, processing, completed, failed] = await Promise.all([
    redis.get('metrics:received') || '0',
    redis.get('metrics:processing') || '0',
    redis.get('metrics:completed') || '0',
    redis.get('metrics:failed') || '0'
  ]);
  
  res.json({
    received: parseInt(received),
    processing: parseInt(processing),
    completed: parseInt(completed),
    failed: parseInt(failed),
    timestamp: new Date().toISOString()
  });
});

app.listen(3001, () => console.log('[API] Gateway listening on :3001'));
EOF

cat > api/package.json << 'EOF'
{
  "name": "serverless-api",
  "dependencies": {
    "express": "^4.18.2",
    "ioredis": "^5.3.2",
    "uuid": "^9.0.1"
  }
}
EOF

cat > api/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY server.js .
CMD ["node", "server.js"]
EOF

# 3. Create Workflow Orchestrator (Step Functions simulation)
cat > orchestrator/orchestrator.js << 'EOF'
const Redis = require('ioredis');
const { Pool } = require('pg');

const redis = new Redis({ host: 'redis', port: 6379 });
const sub = new Redis({ host: 'redis', port: 6379 });
const pub = new Redis({ host: 'redis', port: 6379 });

const pool = new Pool({
  host: 'postgres',
  database: 'serverless',
  user: 'postgres',
  password: 'postgres',
  port: 5432
});

// State machine definition
const stateMachine = {
  'Start': { next: 'Validate', action: validateRequest },
  'Validate': { next: 'Process', action: logValidation },
  'Process': { next: 'Complete', action: triggerWorker, isAsync: true },
  'Complete': { next: null, action: finalizeRequest }
};

async function validateRequest(request) {
  console.log(`[Orchestrator] Validating request ${request.requestId}`);
  await new Promise(resolve => setTimeout(resolve, 500));
  if (!request.data || !request.type) throw new Error('Invalid request');
  return { ...request, validated: true };
}

async function logValidation(request) {
  console.log(`[Orchestrator] Request ${request.requestId} validated`);
  await pool.query(
    'INSERT INTO workflow_logs (request_id, state, timestamp) VALUES ($1, $2, NOW())',
    [request.requestId, 'Validated']
  );
  return request;
}

async function triggerWorker(request) {
  console.log(`[Orchestrator] Triggering worker for ${request.requestId}`);
  request.status = 'processing';
  request.workflowState = 'Process';
  await redis.set(`request:${request.requestId}`, JSON.stringify(request));
  await redis.incr('metrics:processing');
  
  // Publish to worker queue with priority
  const queue = request.priority === 'high' ? 'work:high' : 'work:normal';
  await pub.lpush(queue, JSON.stringify(request));
  
  return request;
}

async function finalizeRequest(request) {
  console.log(`[Orchestrator] Finalizing request ${request.requestId}`);
  request.status = 'completed';
  request.completedAt = new Date().toISOString();
  await redis.set(`request:${request.requestId}`, JSON.stringify(request));
  await redis.incr('metrics:completed');
  await redis.decr('metrics:processing');
  
  await pool.query(
    'INSERT INTO workflow_logs (request_id, state, timestamp) VALUES ($1, $2, NOW())',
    [request.requestId, 'Completed']
  );
  
  // Publish completion event
  await pub.publish('workflow:complete', JSON.stringify(request));
  
  return request;
}

async function executeWorkflow(request) {
  let currentState = 'Start';
  let context = request;
  
  try {
    while (currentState) {
      const state = stateMachine[currentState];
      console.log(`[Orchestrator] Executing state: ${currentState}`);
      
      context = await state.action(context);
      
      if (state.isAsync) {
        // Async state - wait for callback
        console.log(`[Orchestrator] Workflow ${request.requestId} suspended at ${currentState}`);
        return; // Resume will be triggered by worker completion
      }
      
      currentState = state.next;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  } catch (error) {
    console.error(`[Orchestrator] Workflow failed:`, error.message);
    context.status = 'failed';
    context.error = error.message;
    await redis.set(`request:${request.requestId}`, JSON.stringify(context));
    await redis.incr('metrics:failed');
    await redis.decr('metrics:processing');
  }
}

// Subscribe to workflow events
sub.subscribe('workflow:start', 'worker:complete', (err) => {
  if (err) console.error('[Orchestrator] Subscribe error:', err);
  else console.log('[Orchestrator] Subscribed to workflow events');
});

sub.on('message', async (channel, message) => {
  const request = JSON.parse(message);
  
  if (channel === 'workflow:start') {
    await redis.incr('metrics:received');
    await executeWorkflow(request);
  } else if (channel === 'worker:complete') {
    // Resume workflow from async state
    const data = await redis.get(`request:${request.requestId}`);
    if (data) {
      const context = JSON.parse(data);
      currentState = 'Complete';
      await finalizeRequest(context);
    }
  }
});

// Initialize database
async function initDB() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS workflow_logs (
      id SERIAL PRIMARY KEY,
      request_id TEXT,
      state TEXT,
      timestamp TIMESTAMP
    )
  `);
  console.log('[Orchestrator] Database initialized');
}

initDB().catch(console.error);
console.log('[Orchestrator] Workflow engine started');
EOF

cat > orchestrator/package.json << 'EOF'
{
  "name": "serverless-orchestrator",
  "dependencies": {
    "ioredis": "^5.3.2",
    "pg": "^8.11.3"
  }
}
EOF

cat > orchestrator/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY orchestrator.js .
CMD ["node", "orchestrator.js"]
EOF

# 4. Create Serverless Worker (Container-based processing)
cat > worker/worker.js << 'EOF'
const Redis = require('ioredis');

const redis = new Redis({ host: 'redis', port: 6379 });
const pub = new Redis({ host: 'redis', port: 6379 });

// Simulate cold start delay
const COLD_START_MS = Math.random() * 2000 + 1000;
let isWarm = false;

async function processJob(job) {
  if (!isWarm) {
    console.log(`[Worker] Cold start - initializing container (${Math.round(COLD_START_MS)}ms)`);
    await new Promise(resolve => setTimeout(resolve, COLD_START_MS));
    isWarm = true;
  }
  
  console.log(`[Worker] Processing job ${job.requestId} - ${job.type}`);
  
  const processingTime = job.data.duration * 1000; // Simulate work
  const steps = 10;
  const stepTime = processingTime / steps;
  
  for (let i = 1; i <= steps; i++) {
    await new Promise(resolve => setTimeout(resolve, stepTime));
    job.progress = Math.round((i / steps) * 100);
    await redis.set(`request:${job.requestId}`, JSON.stringify(job));
    
    if (i % 3 === 0) {
      console.log(`[Worker] Job ${job.requestId} - ${job.progress}% complete`);
    }
  }
  
  job.status = 'worker-complete';
  job.processingTime = processingTime;
  await redis.set(`request:${job.requestId}`, JSON.stringify(job));
  
  // Notify orchestrator
  await pub.publish('worker:complete', JSON.stringify(job));
  
  console.log(`[Worker] Job ${job.requestId} completed in ${processingTime}ms`);
}

async function pollQueue() {
  while (true) {
    try {
      // Check high priority first, then normal
      let job = await redis.rpop('work:high');
      if (!job) job = await redis.rpop('work:normal');
      
      if (job) {
        const jobData = JSON.parse(job);
        await processJob(jobData);
      } else {
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    } catch (error) {
      console.error('[Worker] Error:', error.message);
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
  }
}

console.log('[Worker] Container started - waiting for jobs');
pollQueue();
EOF

cat > worker/package.json << 'EOF'
{
  "name": "serverless-worker",
  "dependencies": {
    "ioredis": "^5.3.2"
  }
}
EOF

cat > worker/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install --production
COPY worker.js .
CMD ["node", "worker.js"]
EOF

# 5. Create Dashboard
cat > dashboard/src/App.jsx << 'EOF'
import React, { useState, useEffect } from 'react';

function App() {
  const [metrics, setMetrics] = useState({ received: 0, processing: 0, completed: 0, failed: 0 });
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const fetchMetrics = async () => {
      try {
        const res = await fetch('http://localhost:3001/api/metrics');
        const data = await res.json();
        setMetrics(data);
      } catch (err) {
        console.error('Failed to fetch metrics:', err);
      }
    };

    fetchMetrics();
    const interval = setInterval(fetchMetrics, 2000);
    return () => clearInterval(interval);
  }, []);

  const submitRequest = async (priority = 'normal') => {
    setLoading(true);
    try {
      const res = await fetch('http://localhost:3001/api/process', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: 'video-transcode',
          data: { filename: `video-${Date.now()}.mp4`, duration: Math.floor(Math.random() * 60) + 10 },
          priority
        })
      });
      const data = await res.json();
      setRequests(prev => [data, ...prev].slice(0, 10));
    } catch (err) {
      console.error('Failed to submit:', err);
    }
    setLoading(false);
  };

  return (
    <div style={{ 
      minHeight: '100vh', 
      background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
      padding: '40px 20px',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif'
    }}>
      <div style={{ maxWidth: '1200px', margin: '0 auto' }}>
        <h1 style={{ 
          color: 'white', 
          fontSize: '36px', 
          marginBottom: '30px', 
          textAlign: 'center',
          textShadow: '2px 2px 4px rgba(0,0,0,0.2)'
        }}>
          Serverless Architecture Patterns
        </h1>

        {/* Metrics Grid */}
        <div style={{ 
          display: 'grid', 
          gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', 
          gap: '20px', 
          marginBottom: '30px' 
        }}>
          {[
            { label: 'Received', value: metrics.received, color: '#3b82f6' },
            { label: 'Processing', value: metrics.processing, color: '#f59e0b' },
            { label: 'Completed', value: metrics.completed, color: '#10b981' },
            { label: 'Failed', value: metrics.failed, color: '#ef4444' }
          ].map(metric => (
            <div key={metric.label} style={{
              background: 'white',
              borderRadius: '12px',
              padding: '24px',
              boxShadow: '0 4px 6px rgba(0,0,0,0.1)',
              transform: 'translateY(0)',
              transition: 'transform 0.2s'
            }}>
              <div style={{ fontSize: '14px', color: '#6b7280', marginBottom: '8px', fontWeight: '500' }}>
                {metric.label}
              </div>
              <div style={{ fontSize: '32px', fontWeight: 'bold', color: metric.color }}>
                {metric.value}
              </div>
            </div>
          ))}
        </div>

        {/* Control Panel */}
        <div style={{
          background: 'white',
          borderRadius: '12px',
          padding: '30px',
          marginBottom: '30px',
          boxShadow: '0 4px 6px rgba(0,0,0,0.1)'
        }}>
          <h2 style={{ marginBottom: '20px', color: '#1f2937', fontSize: '20px' }}>Trigger Serverless Workflows</h2>
          <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
            <button
              onClick={() => submitRequest('normal')}
              disabled={loading}
              style={{
                padding: '12px 24px',
                background: '#3b82f6',
                color: 'white',
                border: 'none',
                borderRadius: '8px',
                fontSize: '16px',
                cursor: loading ? 'not-allowed' : 'pointer',
                opacity: loading ? 0.6 : 1,
                boxShadow: '0 2px 4px rgba(59, 130, 246, 0.4)',
                transition: 'all 0.2s'
              }}
            >
              Process Normal Priority
            </button>
            <button
              onClick={() => submitRequest('high')}
              disabled={loading}
              style={{
                padding: '12px 24px',
                background: '#ef4444',
                color: 'white',
                border: 'none',
                borderRadius: '8px',
                fontSize: '16px',
                cursor: loading ? 'not-allowed' : 'pointer',
                opacity: loading ? 0.6 : 1,
                boxShadow: '0 2px 4px rgba(239, 68, 68, 0.4)',
                transition: 'all 0.2s'
              }}
            >
              Process High Priority
            </button>
          </div>
        </div>

        {/* Recent Requests */}
        <div style={{
          background: 'white',
          borderRadius: '12px',
          padding: '30px',
          boxShadow: '0 4px 6px rgba(0,0,0,0.1)'
        }}>
          <h2 style={{ marginBottom: '20px', color: '#1f2937', fontSize: '20px' }}>Recent Requests</h2>
          {requests.length === 0 ? (
            <p style={{ color: '#6b7280', textAlign: 'center', padding: '20px' }}>
              No requests yet. Submit a workflow to see it here.
            </p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
              {requests.map(req => (
                <div key={req.requestId} style={{
                  padding: '16px',
                  background: '#f9fafb',
                  borderRadius: '8px',
                  border: '1px solid #e5e7eb'
                }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                    <span style={{ fontWeight: '600', color: '#1f2937', fontSize: '14px' }}>
                      {req.requestId.substring(0, 8)}...
                    </span>
                    <span style={{
                      padding: '4px 12px',
                      background: req.status === 'accepted' ? '#dbeafe' : '#d1fae5',
                      color: req.status === 'accepted' ? '#1e40af' : '#065f46',
                      borderRadius: '12px',
                      fontSize: '12px',
                      fontWeight: '500'
                    }}>
                      {req.status}
                    </span>
                  </div>
                  <div style={{ color: '#6b7280', fontSize: '13px' }}>
                    Estimated time: {req.estimatedTime}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Pattern Info */}
        <div style={{
          background: 'rgba(255,255,255,0.1)',
          borderRadius: '12px',
          padding: '20px',
          marginTop: '30px',
          backdropFilter: 'blur(10px)'
        }}>
          <h3 style={{ color: 'white', marginBottom: '12px', fontSize: '16px' }}>Patterns Demonstrated:</h3>
          <div style={{ color: 'rgba(255,255,255,0.9)', fontSize: '14px', lineHeight: '1.6' }}>
            • <strong>API Gateway:</strong> HTTP endpoint receiving requests<br/>
            • <strong>Workflow Orchestration:</strong> Step Functions managing state<br/>
            • <strong>Serverless Containers:</strong> Workers processing jobs<br/>
            • <strong>Event-Driven:</strong> Redis pub/sub for async communication<br/>
            • <strong>Managed Database:</strong> PostgreSQL for workflow logs
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
EOF

cat > dashboard/package.json << 'EOF'
{
  "name": "serverless-dashboard",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0",
    "build": "vite build"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.1",
    "vite": "^5.0.11"
  }
}
EOF

cat > dashboard/vite.config.js << 'EOF'
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: { port: 3000 }
});
EOF

cat > dashboard/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Serverless Architecture Demo</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
EOF

cat > dashboard/src/main.jsx << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF

cat > dashboard/Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["npm", "run", "dev"]
EOF

# 6. Create Docker Compose
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: serverless
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 5

  api:
    build: ./api
    ports:
      - "3001:3001"
    depends_on:
      redis:
        condition: service_healthy
    restart: unless-stopped

  orchestrator:
    build: ./orchestrator
    depends_on:
      redis:
        condition: service_healthy
      postgres:
        condition: service_healthy
    restart: unless-stopped

  worker:
    build: ./worker
    depends_on:
      - redis
    deploy:
      replicas: 2
    restart: unless-stopped

  dashboard:
    build: ./dashboard
    ports:
      - "3000:3000"
    depends_on:
      - api
    restart: unless-stopped
EOF

# 7. Create test script
cat > test.sh << 'EOF'
#!/bin/bash

echo "🧪 Running Serverless Architecture Tests..."

# Test 1: API Health
echo "Test 1: API Gateway endpoint..."
response=$(curl -s -X POST http://localhost:3001/api/process \
  -H "Content-Type: application/json" \
  -d '{"type":"test","data":{"duration":5},"priority":"normal"}')
request_id=$(echo $response | grep -o '"requestId":"[^"]*"' | cut -d'"' -f4)

if [ -n "$request_id" ]; then
  echo "✅ API Gateway test passed - Request ID: $request_id"
else
  echo "❌ API Gateway test failed"
  exit 1
fi

# Test 2: Wait and check status
echo "Test 2: Workflow execution..."
sleep 8

status_response=$(curl -s http://localhost:3001/api/status/$request_id)
status=$(echo $status_response | grep -o '"status":"[^"]*"' | cut -d'"' -f4)

if [ "$status" = "completed" ] || [ "$status" = "processing" ]; then
  echo "✅ Workflow test passed - Status: $status"
else
  echo "❌ Workflow test failed - Status: $status"
  exit 1
fi

# Test 3: Metrics
echo "Test 3: Metrics collection..."
metrics=$(curl -s http://localhost:3001/api/metrics)
received=$(echo $metrics | grep -o '"received":[0-9]*' | cut -d':' -f2)

if [ "$received" -gt 0 ]; then
  echo "✅ Metrics test passed - Received: $received requests"
else
  echo "❌ Metrics test failed"
  exit 1
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "Dashboard: http://localhost:3000"
echo "API Endpoint: http://localhost:3001/api/process"
EOF

chmod +x test.sh

# 8. Create cleanup script
cat > cleanup.sh << 'EOF'
#!/bin/bash
echo "🧹 Cleaning up Serverless Architecture Demo..."
docker-compose down -v
docker system prune -f
echo "✅ Cleanup complete"
EOF

chmod +x cleanup.sh

# 9. Create demo script
cat > demo.sh << 'EOF'
#!/bin/bash

echo "🎬 Running Serverless Architecture Demo..."
echo ""

# Submit multiple requests
for i in {1..5}; do
  priority=$([ $((i % 2)) -eq 0 ] && echo "high" || echo "normal")
  curl -s -X POST http://localhost:3001/api/process \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"demo-$i\",\"data\":{\"duration\":$((10 + i * 5))},\"priority\":\"$priority\"}" \
    | jq -r '"Request \(.requestId | .[0:8])... submitted - Priority: '$priority'"'
  sleep 1
done

echo ""
echo "📊 Current Metrics:"
curl -s http://localhost:3001/api/metrics | jq '.'

echo ""
echo "💡 Watch the dashboard at http://localhost:3000 to see workflows executing"
echo "💡 Check Docker logs: docker-compose logs -f orchestrator worker"
EOF

chmod +x demo.sh

# 10. Build and run
echo "📦 Building Docker images..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 10

echo "🧪 Running tests..."
./test.sh

echo ""
echo "✅ Setup complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Serverless Architecture Demo Ready!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📱 Dashboard:    http://localhost:3000"
echo "🔌 API Gateway:  http://localhost:3001"
echo ""
echo "Commands:"
echo "  ./demo.sh     - Submit sample requests"
echo "  ./test.sh     - Run test suite"
echo "  ./cleanup.sh  - Stop and remove all containers"
echo ""
echo "View logs:"
echo "  docker-compose logs -f"
echo "  docker-compose logs -f orchestrator"
echo "  docker-compose logs -f worker"
echo ""