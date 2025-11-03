const express = require('express');
const app = express();

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    service: 'database',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

app.get('/', (req, res) => {
  res.json({ 
    message: 'Welcome to database service',
    service: 'database',
    endpoints: ['/health']
  });
});

const PORT = 8082;
app.listen(PORT, '0.0.0.0', () => {
  console.log('database service running on port', PORT);
});
