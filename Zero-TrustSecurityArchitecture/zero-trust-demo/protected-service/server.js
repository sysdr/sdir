const express = require('express');
const cors = require('cors');

const app = express();
app.use(express.json());
app.use(cors());

// Mock databases
const databases = {
  users: [
    { id: 1, name: 'John Doe', email: 'john@example.com', role: 'user' },
    { id: 2, name: 'Jane Smith', email: 'jane@example.com', role: 'admin' }
  ],
  transactions: [
    { id: 1, amount: 1250.50, status: 'completed', timestamp: new Date() },
    { id: 2, amount: 899.99, status: 'pending', timestamp: new Date() }
  ]
};

// Access log
const accessLog = [];

function logAccess(user, resource, action) {
  const entry = {
    timestamp: new Date(),
    user: user || 'anonymous',
    resource,
    action
  };
  accessLog.push(entry);
  if (accessLog.length > 200) accessLog.shift();
  console.log(`[Service] Access: ${user} -> ${resource} (${action})`);
}

// Protected endpoints
app.get('/database', (req, res) => {
  const user = req.headers['x-user-email'];
  logAccess(user, '/database', 'READ');
  
  res.json({
    message: 'Database access granted',
    data: databases,
    accessedBy: user,
    timestamp: new Date()
  });
});

app.get('/users', (req, res) => {
  const user = req.headers['x-user-email'];
  logAccess(user, '/users', 'READ');
  
  res.json({
    users: databases.users,
    count: databases.users.length,
    accessedBy: user
  });
});

app.get('/public', (req, res) => {
  const user = req.headers['x-user-email'] || 'anonymous';
  logAccess(user, '/public', 'READ');
  
  res.json({
    message: 'Public API endpoint',
    version: '1.0.0',
    timestamp: new Date()
  });
});

app.get('/access-log', (req, res) => {
  res.json({
    log: accessLog.slice(-50).reverse(),
    total: accessLog.length
  });
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    service: 'protected-service', 
    status: 'healthy',
    accessEvents: accessLog.length
  });
});

const PORT = 3004;
app.listen(PORT, () => {
  console.log(`[Protected Service] Running on port ${PORT}`);
});
