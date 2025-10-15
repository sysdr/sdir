const http = require('http');
const os = require('os');

const hostname = os.hostname();
let requestCount = 0;

const server = http.createServer((req, res) => {
  requestCount++;
  
  if (req.url === '/health') {
    res.writeHead(200);
    res.end('OK');
    return;
  }

  // Simulate some processing
  const start = Date.now();
  while (Date.now() - start < 10) {} // 10ms busy work
  
  const response = {
    server: hostname,
    requestNumber: requestCount,
    loadBalancer: req.headers['x-load-balancer'] || 'unknown',
    timestamp: new Date().toISOString()
  };
  
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(response, null, 2));
});

server.listen(3000, () => {
  console.log(`Server ${hostname} running on port 3000`);
});
