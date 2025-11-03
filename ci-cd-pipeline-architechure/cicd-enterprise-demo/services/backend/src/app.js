const express = require('express');
const app = express();

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'backend',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

app.get('/', (req, res) => {
  res.json({ 
    message: 'Welcome to backend service',
    service: 'backend',
    endpoints: ['/health']
  });
});

const PORT = 8081;
app.listen(PORT, '0.0.0.0', () => {
  console.log('backend service running on port', PORT);
});
