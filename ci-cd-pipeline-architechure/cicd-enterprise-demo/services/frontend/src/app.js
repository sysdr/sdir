const express = require('express');
const app = express();

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'frontend',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

app.get('/', (req, res) => {
  res.json({ 
    message: 'Welcome to frontend service',
    service: 'frontend',
    endpoints: ['/health']
  });
});

const PORT = 8080;
app.listen(PORT, '0.0.0.0', () => {
  console.log('frontend service running on port', PORT);
});
