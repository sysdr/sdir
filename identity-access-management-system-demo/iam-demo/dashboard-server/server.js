const express = require('express');
const axios = require('axios');
const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

const app = express();
app.use(express.json());
app.use(express.static('public'));

const AUTH_SERVER = process.env.AUTH_SERVER_URL || 'http://auth-server:3001';
const RESOURCE_SERVER = process.env.RESOURCE_SERVER_URL || 'http://resource-server:3002';

// API endpoint to get health status
app.get('/api/health', async (req, res) => {
  try {
    let authHealth, resourceHealth;
    
    try {
      const authResponse = await axios.get(`${AUTH_SERVER}/health`, { timeout: 3000 });
      authHealth = { status: authResponse.status, data: authResponse.data };
    } catch (err) {
      authHealth = { status: 0, data: null };
    }
    
    try {
      const resourceResponse = await axios.get(`${RESOURCE_SERVER}/health`, { timeout: 3000 });
      resourceHealth = { status: resourceResponse.status, data: resourceResponse.data };
    } catch (err) {
      resourceHealth = { status: 0, data: null };
    }
    
    res.json({
      authServer: {
        healthy: authHealth.status === 200,
        status: authHealth.status || 0,
        data: authHealth.data
      },
      resourceServer: {
        healthy: resourceHealth.status === 200,
        status: resourceHealth.status || 0,
        data: resourceHealth.data
      }
    });
  } catch (error) {
    res.status(500).json({ error: error.message || 'Unknown error' });
  }
});

// API endpoint to get Docker container status
app.get('/api/containers', async (req, res) => {
  // Check containers by trying to connect to their services
  const containers = [
    { Name: 'iam-demo-auth-server-1', Service: 'Auth Server', Port: 3001 },
    { Name: 'iam-demo-resource-server-1', Service: 'Resource Server', Port: 3002 },
    { Name: 'iam-demo-postgres-1', Service: 'PostgreSQL', Port: 5432 },
    { Name: 'iam-demo-redis-1', Service: 'Redis', Port: 6379 }
  ];
  
  const containerStatus = await Promise.all(containers.map(async (container) => {
    // For HTTP services, check via HTTP
    if (container.Port === 3001 || container.Port === 3002) {
      try {
        const url = container.Port === 3001 ? AUTH_SERVER : RESOURCE_SERVER;
        const response = await axios.get(`${url}/health`, { timeout: 2000 });
        return {
          Name: container.Name,
          Service: container.Service,
          State: 'running',
          Status: `Up - ${response.status === 200 ? 'Healthy' : 'Unhealthy'}`
        };
      } catch {
        return {
          Name: container.Name,
          Service: container.Service,
          State: 'stopped',
          Status: 'Down'
        };
      }
    } else {
      // For database services, we'll assume they're running if the HTTP services work
      // (since they depend on them)
      return {
        Name: container.Name,
        Service: container.Service,
        State: 'running',
        Status: 'Up (inferred)'
      };
    }
  }));
  
  res.json(containerStatus);
});

// API endpoint to get database status
app.get('/api/databases', async (req, res) => {
  // Since we're in a container, we can infer DB status from service health
  // If services are responding, databases are likely ready
  try {
    const authHealth = await axios.get(`${AUTH_SERVER}/health`).catch(() => null);
    const resourceHealth = await axios.get(`${RESOURCE_SERVER}/health`).catch(() => null);
    
    // If both services are healthy, databases are likely connected
    const postgresReady = authHealth !== null && resourceHealth !== null;
    const redisReady = authHealth !== null && resourceHealth !== null;
    
    res.json({
      postgres: {
        container: 'iam-demo-postgres-1',
        ready: postgresReady
      },
      redis: {
        container: 'iam-demo-redis-1',
        ready: redisReady
      }
    });
  } catch (error) {
    res.json({
      postgres: { container: 'iam-demo-postgres-1', ready: false },
      redis: { container: 'iam-demo-redis-1', ready: false }
    });
  }
});

// API endpoint to get port status
app.get('/api/ports', async (req, res) => {
  const ports = [
    { port: 3001, service: 'Auth Server', url: AUTH_SERVER },
    { port: 3002, service: 'Resource Server', url: RESOURCE_SERVER },
    { port: 5432, service: 'PostgreSQL', url: null },
    { port: 6379, service: 'Redis', url: null }
  ];
  
  const portStatus = await Promise.all(ports.map(async ({ port, service, url }) => {
    if (url) {
      // For HTTP services, check via HTTP
      try {
        await axios.get(`${url}/health`, { timeout: 2000 });
        return { port, service, inUse: true };
      } catch (err) {
        // Ignore error details to avoid circular references
        return { port, service, inUse: false };
      }
    } else {
      // For DB services, infer from service health
      // If HTTP services work, DBs are likely accessible
      try {
        await axios.get(`${AUTH_SERVER}/health`, { timeout: 2000 });
        await axios.get(`${RESOURCE_SERVER}/health`, { timeout: 2000 });
        return { port, service, inUse: true };
      } catch (err) {
        // Ignore error details to avoid circular references
        return { port, service, inUse: false };
      }
    }
  }));
  
  res.json(portStatus);
});

// API endpoint to test endpoints
app.get('/api/metrics', async (req, res) => {
  try {
    const metrics = [];
    
    // Test public endpoint
    try {
      const publicResponse = await axios.get(`${RESOURCE_SERVER}/api/public/info`, { timeout: 3000 });
      metrics.push({
        name: 'Public Endpoint',
        status: publicResponse.status || 0,
        working: publicResponse.status === 200
      });
    } catch (err) {
      metrics.push({ name: 'Public Endpoint', status: 0, working: false });
    }
    
    // Test OAuth authorization
    try {
      const oauthResponse = await axios.get(`${AUTH_SERVER}/oauth/authorize?client_id=demo-client&redirect_uri=http://localhost:8080/callback&response_type=code&scope=read&state=test123`, { timeout: 3000 });
      metrics.push({
        name: 'OAuth Authorization',
        status: oauthResponse.status || 0,
        working: oauthResponse.status === 200 || oauthResponse.data?.redirect_to
      });
    } catch (err) {
      metrics.push({ name: 'OAuth Authorization', status: 0, working: false });
    }
    
    // Test health endpoints
    try {
      const authHealth = await axios.get(`${AUTH_SERVER}/health`, { timeout: 3000 });
      metrics.push({
        name: 'Auth Server Health',
        status: authHealth.status || 0,
        working: authHealth.status === 200
      });
    } catch (err) {
      metrics.push({ name: 'Auth Server Health', status: 0, working: false });
    }
    
    try {
      const resourceHealth = await axios.get(`${RESOURCE_SERVER}/health`, { timeout: 3000 });
      metrics.push({
        name: 'Resource Server Health',
        status: resourceHealth.status || 0,
        working: resourceHealth.status === 200
      });
    } catch (err) {
      metrics.push({ name: 'Resource Server Health', status: 0, working: false });
    }
    
    const total = metrics.length;
    const passing = metrics.filter(m => m.working).length;
    const percentage = total > 0 ? Math.round((passing / total) * 100) : 0;
    
    res.json({ metrics, summary: { total, passing, percentage } });
  } catch (error) {
    // Catch any unexpected errors and return a safe response
    res.status(500).json({ 
      error: 'Failed to fetch metrics', 
      metrics: [],
      summary: { total: 0, passing: 0, percentage: 0 }
    });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`✓ Dashboard Server running on port ${PORT}`);
});

