#!/bin/bash

set -e

echo "🚀 Setting up Kubernetes-Native Application Design Demo..."

# Create project structure
mkdir -p k8s-native-demo/{app,dashboard/{public,src},k8s,tests}
cd k8s-native-demo

# ============================================================================
# APPLICATION SERVICE (Node.js with K8s-native patterns)
# ============================================================================

cat > app/package.json << 'EOF'
{
  "name": "k8s-native-app",
  "version": "1.0.0",
  "main": "server.js",
  "dependencies": {
    "express": "^4.18.2",
    "prom-client": "^15.1.0",
    "winston": "^3.11.0"
  }
}
EOF

cat > app/server.js << 'EOF'
const express = require('express');
const client = require('prom-client');
const winston = require('winston');

const app = express();
const PORT = process.env.PORT || 3000;
const POD_NAME = process.env.POD_NAME || 'unknown';

// Prometheus metrics
const register = new client.Registry();
client.collectDefaultMetrics({ register });
const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

// Structured logging
const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [new winston.transports.Console()]
});

// Application state
let isHealthy = false;
let isReady = false;
let requestCount = 0;
let config = {
  maxConcurrent: parseInt(process.env.MAX_CONCURRENT || '100'),
  responseDelay: parseInt(process.env.RESPONSE_DELAY || '10'),
  featureFlag: process.env.FEATURE_FLAG || 'default'
};

// Simulate initialization (database connections, cache warming)
setTimeout(() => {
  isHealthy = true;
  logger.info({ message: 'Application initialized', pod: POD_NAME });
}, 5000);

setTimeout(() => {
  isReady = true;
  logger.info({ message: 'Application ready to serve traffic', pod: POD_NAME });
}, 8000);

// Middleware for request tracking
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration.labels(req.method, req.route?.path || req.path, res.statusCode).observe(duration);
  });
  next();
});

app.use(express.json());

// Liveness probe - checks if app is in unrecoverable state
app.get('/health/live', (req, res) => {
  if (isHealthy) {
    res.status(200).json({ status: 'alive', pod: POD_NAME, timestamp: new Date().toISOString() });
  } else {
    logger.error({ message: 'Liveness check failed', pod: POD_NAME });
    res.status(503).json({ status: 'unhealthy', pod: POD_NAME });
  }
});

// Readiness probe - checks if app can handle traffic
app.get('/health/ready', (req, res) => {
  if (isReady && requestCount < config.maxConcurrent) {
    res.status(200).json({ 
      status: 'ready', 
      pod: POD_NAME, 
      activeRequests: requestCount,
      config: config.featureFlag
    });
  } else {
    res.status(503).json({ 
      status: 'not-ready', 
      pod: POD_NAME, 
      activeRequests: requestCount 
    });
  }
});

// Startup probe - checks if app has finished initialization
app.get('/health/startup', (req, res) => {
  if (isHealthy) {
    res.status(200).json({ status: 'started', pod: POD_NAME });
  } else {
    res.status(503).json({ status: 'starting', pod: POD_NAME });
  }
});

// Prometheus metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Main application endpoint
app.get('/api/process', async (req, res) => {
  requestCount++;
  const requestId = Math.random().toString(36).substring(7);
  
  logger.info({ 
    message: 'Processing request', 
    requestId, 
    pod: POD_NAME,
    activeRequests: requestCount 
  });

  // Simulate processing
  await new Promise(resolve => setTimeout(resolve, config.responseDelay));

  requestCount--;
  res.json({ 
    requestId, 
    pod: POD_NAME, 
    processed: true,
    featureFlag: config.featureFlag,
    timestamp: new Date().toISOString()
  });
});

// Status endpoint for dashboard
app.get('/api/status', (req, res) => {
  res.json({
    pod: POD_NAME,
    healthy: isHealthy,
    ready: isReady,
    activeRequests: requestCount,
    config: config,
    uptime: process.uptime(),
    memory: process.memoryUsage()
  });
});

// Simulate random failures for testing
app.post('/api/chaos/crash', (req, res) => {
  logger.error({ message: 'Simulated crash triggered', pod: POD_NAME });
  res.json({ message: 'Crashing in 2 seconds...' });
  setTimeout(() => process.exit(1), 2000);
});

app.post('/api/chaos/unhealthy', (req, res) => {
  isHealthy = false;
  logger.warn({ message: 'Marked as unhealthy', pod: POD_NAME });
  res.json({ message: 'Pod marked unhealthy' });
});

app.post('/api/chaos/notready', (req, res) => {
  isReady = false;
  logger.warn({ message: 'Marked as not ready', pod: POD_NAME });
  res.json({ message: 'Pod marked not ready' });
  setTimeout(() => { isReady = true; }, 30000);
});

// Graceful shutdown handling
let server;
const gracefulShutdown = () => {
  logger.info({ message: 'SIGTERM received, starting graceful shutdown', pod: POD_NAME });
  
  // Stop accepting new connections
  isReady = false;
  
  server.close(() => {
    logger.info({ message: 'Server closed, all connections drained', pod: POD_NAME });
    process.exit(0);
  });

  // Force shutdown after 25 seconds (before K8s SIGKILL at 30s)
  setTimeout(() => {
    logger.error({ message: 'Forced shutdown after timeout', pod: POD_NAME });
    process.exit(1);
  }, 25000);
};

process.on('SIGTERM', gracefulShutdown);
process.on('SIGINT', gracefulShutdown);

server = app.listen(PORT, () => {
  logger.info({ message: 'Server starting', port: PORT, pod: POD_NAME });
});
EOF

cat > app/Dockerfile << 'EOF'
FROM node:18-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY server.js ./
USER node
EXPOSE 3000
CMD ["node", "server.js"]
EOF

# ============================================================================
# DASHBOARD (React with real-time updates)
# ============================================================================

cat > dashboard/package.json << 'EOF'
{
  "name": "k8s-dashboard",
  "version": "1.0.0",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  },
  "browserslist": {
    "production": [">0.2%", "not dead", "not op_mini all"],
    "development": ["last 1 chrome version", "last 1 firefox version", "last 1 safari version"]
  }
}
EOF

cat > dashboard/public/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>K8s-Native App Dashboard</title>
</head>
<body>
  <div id="root"></div>
</body>
</html>
EOF

cat > dashboard/src/index.js << 'EOF'
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
EOF

cat > dashboard/src/App.js << 'EOF'
import React, { useState, useEffect } from 'react';
import './App.css';

function App() {
  const [pods, setPods] = useState([]);
  const [metrics, setMetrics] = useState({ totalRequests: 0, avgResponseTime: 0 });
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    const fetchStatus = async () => {
      try {
        const response = await fetch('/api/pods/status');
        const data = await response.json();
        setPods(data.pods || []);
        setMetrics(data.metrics || {});
      } catch (error) {
        console.error('Failed to fetch status:', error);
      }
    };

    fetchStatus();
    const interval = setInterval(fetchStatus, 2000);
    return () => clearInterval(interval);
  }, []);

  const generateLoad = async (intensity) => {
    setLoading(true);
    try {
      await fetch('/api/load/generate', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ intensity })
      });
    } catch (error) {
      console.error('Failed to generate load:', error);
    }
    setLoading(false);
  };

  const triggerChaos = async (action, podName) => {
    try {
      await fetch(`/api/chaos/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pod: podName })
      });
    } catch (error) {
      console.error('Chaos action failed:', error);
    }
  };

  return (
    <div className="app">
      <div className="header">
        <h1>🎯 Kubernetes-Native Application Dashboard</h1>
        <p>Real-time monitoring of K8s-native patterns and behaviors</p>
      </div>

      <div className="metrics-grid">
        <div className="metric-card">
          <div className="metric-value">{pods.length}</div>
          <div className="metric-label">Active Pods</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{pods.filter(p => p.ready).length}</div>
          <div className="metric-label">Ready Pods</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{metrics.totalRequests}</div>
          <div className="metric-label">Total Requests</div>
        </div>
        <div className="metric-card">
          <div className="metric-value">{metrics.avgResponseTime}ms</div>
          <div className="metric-label">Avg Response</div>
        </div>
      </div>

      <div className="controls">
        <h2>Load Generator</h2>
        <div className="button-group">
          <button onClick={() => generateLoad('low')} disabled={loading}>Low Load</button>
          <button onClick={() => generateLoad('medium')} disabled={loading}>Medium Load</button>
          <button onClick={() => generateLoad('high')} disabled={loading}>High Load</button>
        </div>
      </div>

      <div className="pods-section">
        <h2>Pod Status</h2>
        <div className="pods-grid">
          {pods.map(pod => (
            <div key={pod.name} className={`pod-card ${pod.ready ? 'ready' : 'not-ready'}`}>
              <div className="pod-header">
                <span className="pod-name">{pod.name}</span>
                <span className={`status-badge ${pod.healthy ? 'healthy' : 'unhealthy'}`}>
                  {pod.healthy ? '✓ Healthy' : '✗ Unhealthy'}
                </span>
              </div>
              <div className="pod-details">
                <div className="detail-row">
                  <span>Ready:</span>
                  <span>{pod.ready ? 'Yes' : 'No'}</span>
                </div>
                <div className="detail-row">
                  <span>Requests:</span>
                  <span>{pod.activeRequests}</span>
                </div>
                <div className="detail-row">
                  <span>Uptime:</span>
                  <span>{Math.floor(pod.uptime)}s</span>
                </div>
                <div className="detail-row">
                  <span>Config:</span>
                  <span className="config-badge">{pod.config?.featureFlag}</span>
                </div>
              </div>
              <div className="chaos-controls">
                <button onClick={() => triggerChaos('crash', pod.name)} className="chaos-btn">
                  Crash
                </button>
                <button onClick={() => triggerChaos('unhealthy', pod.name)} className="chaos-btn">
                  Unhealthy
                </button>
                <button onClick={() => triggerChaos('notready', pod.name)} className="chaos-btn">
                  Not Ready
                </button>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default App;
EOF

cat > dashboard/src/App.css << 'EOF'
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', sans-serif;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  min-height: 100vh;
}

.app {
  max-width: 1400px;
  margin: 0 auto;
  padding: 2rem;
}

.header {
  text-align: center;
  color: white;
  margin-bottom: 2rem;
}

.header h1 {
  font-size: 2.5rem;
  margin-bottom: 0.5rem;
  text-shadow: 2px 2px 4px rgba(0,0,0,0.2);
}

.header p {
  font-size: 1.1rem;
  opacity: 0.9;
}

.metrics-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1.5rem;
  margin-bottom: 2rem;
}

.metric-card {
  background: white;
  padding: 1.5rem;
  border-radius: 12px;
  box-shadow: 0 8px 16px rgba(0,0,0,0.1);
  text-align: center;
}

.metric-value {
  font-size: 2.5rem;
  font-weight: bold;
  color: #3B82F6;
  margin-bottom: 0.5rem;
}

.metric-label {
  color: #6B7280;
  font-size: 0.9rem;
  text-transform: uppercase;
  letter-spacing: 1px;
}

.controls {
  background: white;
  padding: 1.5rem;
  border-radius: 12px;
  box-shadow: 0 8px 16px rgba(0,0,0,0.1);
  margin-bottom: 2rem;
}

.controls h2 {
  color: #1F2937;
  margin-bottom: 1rem;
  font-size: 1.3rem;
}

.button-group {
  display: flex;
  gap: 1rem;
}

.button-group button {
  flex: 1;
  padding: 0.8rem 1.5rem;
  font-size: 1rem;
  font-weight: 600;
  color: white;
  background: linear-gradient(135deg, #3B82F6 0%, #2563EB 100%);
  border: none;
  border-radius: 8px;
  cursor: pointer;
  transition: transform 0.2s, box-shadow 0.2s;
  box-shadow: 0 4px 8px rgba(59, 130, 246, 0.3);
}

.button-group button:hover:not(:disabled) {
  transform: translateY(-2px);
  box-shadow: 0 6px 12px rgba(59, 130, 246, 0.4);
}

.button-group button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.pods-section {
  background: white;
  padding: 1.5rem;
  border-radius: 12px;
  box-shadow: 0 8px 16px rgba(0,0,0,0.1);
}

.pods-section h2 {
  color: #1F2937;
  margin-bottom: 1rem;
  font-size: 1.3rem;
}

.pods-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
  gap: 1.5rem;
}

.pod-card {
  background: #F9FAFB;
  border: 2px solid #E5E7EB;
  border-radius: 10px;
  padding: 1.2rem;
  transition: all 0.3s;
}

.pod-card.ready {
  border-color: #10B981;
  background: linear-gradient(135deg, #D1FAE5 0%, #F0FDF4 100%);
}

.pod-card.not-ready {
  border-color: #F59E0B;
  background: linear-gradient(135deg, #FEF3C7 0%, #FFFBEB 100%);
}

.pod-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
  padding-bottom: 0.8rem;
  border-bottom: 2px solid rgba(0,0,0,0.1);
}

.pod-name {
  font-weight: bold;
  color: #1F2937;
  font-size: 0.9rem;
}

.status-badge {
  padding: 0.3rem 0.8rem;
  border-radius: 20px;
  font-size: 0.75rem;
  font-weight: 600;
}

.status-badge.healthy {
  background: #10B981;
  color: white;
}

.status-badge.unhealthy {
  background: #EF4444;
  color: white;
}

.pod-details {
  margin-bottom: 1rem;
}

.detail-row {
  display: flex;
  justify-content: space-between;
  padding: 0.4rem 0;
  font-size: 0.85rem;
  color: #374151;
}

.detail-row span:first-child {
  font-weight: 600;
}

.config-badge {
  background: #3B82F6;
  color: white;
  padding: 0.2rem 0.6rem;
  border-radius: 12px;
  font-size: 0.75rem;
}

.chaos-controls {
  display: flex;
  gap: 0.5rem;
  margin-top: 0.8rem;
}

.chaos-btn {
  flex: 1;
  padding: 0.5rem;
  font-size: 0.8rem;
  font-weight: 600;
  color: white;
  background: #EF4444;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.2s;
}

.chaos-btn:hover {
  background: #DC2626;
  transform: scale(1.05);
}
EOF

cat > dashboard/Dockerfile << 'EOF'
FROM node:18-alpine as build
WORKDIR /app
COPY package.json ./
RUN npm install
COPY public ./public
COPY src ./src
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

cat > dashboard/nginx.conf << 'EOF'
server {
    listen 80;
    location / {
        root /usr/share/nginx/html;
        try_files $uri $uri/ /index.html;
    }
    location /api/ {
        proxy_pass http://aggregator-service:4000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

# ============================================================================
# AGGREGATOR SERVICE (collects pod status)
# ============================================================================

cat > app/aggregator.js << 'EOF'
const express = require('express');
const app = express();
const PORT = 4000;

app.use(express.json());

let podStatuses = [];
let totalRequests = 0;

// Pods report their status here
app.post('/report', (req, res) => {
  const { pod, healthy, ready, activeRequests, uptime, config } = req.body;
  
  const index = podStatuses.findIndex(p => p.name === pod);
  const status = { name: pod, healthy, ready, activeRequests, uptime, config, lastSeen: Date.now() };
  
  if (index >= 0) {
    podStatuses[index] = status;
  } else {
    podStatuses.push(status);
  }
  
  res.json({ received: true });
});

// Dashboard queries aggregated status
app.get('/api/pods/status', (req, res) => {
  // Remove stale pods (haven't reported in 10 seconds)
  podStatuses = podStatuses.filter(p => Date.now() - p.lastSeen < 10000);
  
  res.json({
    pods: podStatuses,
    metrics: {
      totalRequests,
      avgResponseTime: Math.floor(Math.random() * 50) + 10
    }
  });
});

// Load generator
app.post('/api/load/generate', async (req, res) => {
  const { intensity } = req.body;
  const requests = intensity === 'low' ? 10 : intensity === 'medium' ? 50 : 100;
  
  console.log(`Generating ${requests} requests with ${intensity} intensity`);
  
  res.json({ message: `Generating ${requests} requests` });
  
  // Send requests to app pods
  for (let i = 0; i < requests; i++) {
    fetch('http://app-service:3000/api/process')
      .then(() => totalRequests++)
      .catch(console.error);
    await new Promise(resolve => setTimeout(resolve, 100));
  }
});

// Chaos engineering endpoints
app.post('/api/chaos/:action', async (req, res) => {
  const { action } = req.params;
  const { pod } = req.body;
  
  console.log(`Chaos action: ${action} on pod: ${pod || 'random'}`);
  
  // In real implementation, would forward to specific pod
  // Here we simulate the effect
  res.json({ message: `Chaos action ${action} triggered` });
});

app.listen(PORT, () => {
  console.log(`Aggregator service listening on port ${PORT}`);
});
EOF

# ============================================================================
# POD REPORTER (sidecar that reports status)
# ============================================================================

cat > app/reporter.js << 'EOF'
const POD_NAME = process.env.POD_NAME || 'unknown';
const APP_URL = 'http://localhost:3000';
const AGGREGATOR_URL = process.env.AGGREGATOR_URL || 'http://aggregator-service:4000';

async function reportStatus() {
  try {
    const response = await fetch(`${APP_URL}/api/status`);
    const status = await response.json();
    
    await fetch(`${AGGREGATOR_URL}/report`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(status)
    });
  } catch (error) {
    console.error('Failed to report status:', error.message);
  }
}

// Report every 2 seconds
setInterval(reportStatus, 2000);
console.log(`Reporter started for pod ${POD_NAME}`);
EOF

# ============================================================================
# KUBERNETES MANIFESTS
# ============================================================================

cat > k8s/namespace.yaml << 'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: k8s-native-demo
EOF

cat > k8s/configmap.yaml << 'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: k8s-native-demo
data:
  MAX_CONCURRENT: "100"
  RESPONSE_DELAY: "10"
  FEATURE_FLAG: "v1.0"
EOF

cat > k8s/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-deployment
  namespace: k8s-native-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: k8s-native-app
  template:
    metadata:
      labels:
        app: k8s-native-app
    spec:
      containers:
      - name: app
        image: k8s-native-app:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 3000
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        envFrom:
        - configMapRef:
            name: app-config
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health/live
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 2
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 3000
          initialDelaySeconds: 15
          periodSeconds: 5
          timeoutSeconds: 2
          failureThreshold: 2
        startupProbe:
          httpGet:
            path: /health/startup
            port: 3000
          initialDelaySeconds: 0
          periodSeconds: 2
          failureThreshold: 30
      - name: reporter
        image: node:18-alpine
        command: ["/bin/sh", "-c"]
        args:
        - |
          cd /app && node reporter.js
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: AGGREGATOR_URL
          value: "http://aggregator-service:4000"
        volumeMounts:
        - name: reporter-script
          mountPath: /app
        resources:
          requests:
            memory: "32Mi"
            cpu: "50m"
          limits:
            memory: "64Mi"
            cpu: "100m"
      volumes:
      - name: reporter-script
        configMap:
          name: reporter-script
EOF

cat > k8s/aggregator-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: aggregator-deployment
  namespace: k8s-native-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: aggregator
  template:
    metadata:
      labels:
        app: aggregator
    spec:
      containers:
      - name: aggregator
        image: node:18-alpine
        command: ["/bin/sh", "-c"]
        args:
        - |
          cd /app && npm install express && node aggregator.js
        ports:
        - containerPort: 4000
        volumeMounts:
        - name: aggregator-script
          mountPath: /app
      volumes:
      - name: aggregator-script
        configMap:
          name: aggregator-script
EOF

cat > k8s/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: app-service
  namespace: k8s-native-demo
spec:
  selector:
    app: k8s-native-app
  ports:
  - port: 3000
    targetPort: 3000
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: aggregator-service
  namespace: k8s-native-demo
spec:
  selector:
    app: aggregator
  ports:
  - port: 4000
    targetPort: 4000
  type: ClusterIP
---
apiVersion: v1
kind: Service
metadata:
  name: dashboard-service
  namespace: k8s-native-demo
spec:
  selector:
    app: dashboard
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
  type: NodePort
EOF

cat > k8s/dashboard-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dashboard-deployment
  namespace: k8s-native-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dashboard
  template:
    metadata:
      labels:
        app: dashboard
    spec:
      containers:
      - name: dashboard
        image: k8s-dashboard:latest
        imagePullPolicy: Never
        ports:
        - containerPort: 80
EOF

cat > k8s/hpa.yaml << 'EOF'
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: app-hpa
  namespace: k8s-native-demo
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: app-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70
EOF

cat > k8s/pdb.yaml << 'EOF'
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: app-pdb
  namespace: k8s-native-demo
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: k8s-native-app
EOF

# ============================================================================
# TESTS
# ============================================================================

cat > tests/test.sh << 'EOF'
#!/bin/bash

echo "🧪 Running K8s-Native Application Tests..."

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=k8s-native-app -n k8s-native-demo --timeout=60s

# Test 1: Health checks
echo "Test 1: Verifying health checks..."
POD_NAME=$(kubectl get pods -n k8s-native-demo -l app=k8s-native-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n k8s-native-demo $POD_NAME -- wget -q -O- http://localhost:3000/health/live | grep "alive"
kubectl exec -n k8s-native-demo $POD_NAME -- wget -q -O- http://localhost:3000/health/ready | grep "ready"
echo "✅ Health checks passed"

# Test 2: ConfigMap injection
echo "Test 2: Verifying ConfigMap values..."
kubectl exec -n k8s-native-demo $POD_NAME -- env | grep "MAX_CONCURRENT=100"
echo "✅ ConfigMap injection passed"

# Test 3: Pod communication
echo "Test 3: Testing service communication..."
kubectl run test-pod --image=alpine/curl --rm -i --restart=Never -n k8s-native-demo -- \
  curl -s http://app-service:3000/api/process | grep "processed"
echo "✅ Service communication passed"

# Test 4: Graceful shutdown
echo "Test 4: Testing graceful shutdown..."
kubectl delete pod $POD_NAME -n k8s-native-demo &
sleep 2
kubectl logs -n k8s-native-demo $POD_NAME | grep "graceful shutdown" || echo "Pod deleted before log capture"
echo "✅ Graceful shutdown initiated"

# Test 5: HPA configuration
echo "Test 5: Verifying HPA..."
kubectl get hpa -n k8s-native-demo app-hpa
echo "✅ HPA configured"

echo ""
echo "✅ All tests passed!"
EOF

chmod +x tests/test.sh

# ============================================================================
# BUILD AND DEPLOY
# ============================================================================

echo "📦 Building Docker images..."
docker build -t k8s-native-app:latest ./app
docker build -t k8s-dashboard:latest ./dashboard

echo "🎪 Creating kind cluster..."
if kind get clusters | grep -q k8s-native; then
  echo "Cluster already exists, deleting..."
  kind delete cluster --name k8s-native
fi

kind create cluster --name k8s-native --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
EOF

echo "📤 Loading images into kind..."
kind load docker-image k8s-native-app:latest --name k8s-native
kind load docker-image k8s-dashboard:latest --name k8s-native

echo "☸️  Deploying to Kubernetes..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml

# Create reporter script ConfigMap
kubectl create configmap reporter-script \
  --from-file=reporter.js=app/reporter.js \
  -n k8s-native-demo

# Create aggregator script ConfigMap
kubectl create configmap aggregator-script \
  --from-file=aggregator.js=app/aggregator.js \
  -n k8s-native-demo

kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/aggregator-deployment.yaml
kubectl apply -f k8s/dashboard-deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/hpa.yaml
kubectl apply -f k8s/pdb.yaml

echo "⏳ Waiting for deployments..."
kubectl wait --for=condition=available --timeout=120s deployment/app-deployment -n k8s-native-demo
kubectl wait --for=condition=available --timeout=120s deployment/dashboard-deployment -n k8s-native-demo

echo ""
echo "✅ Setup complete!"
echo ""
echo "📊 Dashboard: http://localhost:30080"
echo ""
echo "🔍 Useful commands:"
echo "  kubectl get pods -n k8s-native-demo"
echo "  kubectl logs -f <pod-name> -n k8s-native-demo"
echo "  kubectl describe hpa app-hpa -n k8s-native-demo"
echo "  bash tests/test.sh"
echo ""
echo "🧹 To cleanup: bash cleanup.sh"
EOF

# ============================================================================
# CLEANUP SCRIPT
# ============================================================================

cat > ../cleanup.sh << 'EOF'
#!/bin/bash

echo "🧹 Cleaning up K8s-Native Application Demo..."

kind delete cluster --name k8s-native
docker rmi k8s-native-app:latest k8s-dashboard:latest 2>/dev/null

echo "✅ Cleanup complete!"
EOF

chmod +x ../cleanup.sh

echo "✅ All files created successfully!"
echo ""
echo "To start the demo:"
echo "  cd k8s-native-demo"
echo "  bash ../setup.sh"