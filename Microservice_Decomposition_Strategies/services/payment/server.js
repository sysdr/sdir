import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

const payments = [];
let requestCount = 0;

app.post('/api/payments', (req, res) => {
  requestCount++;
  const { orderId, amount } = req.body;
  
  // Simulate payment processing latency
  setTimeout(() => {
    const payment = {
      id: `PAY-${Date.now()}`,
      orderId,
      amount,
      status: 'completed',
      processedAt: new Date().toISOString()
    };
    payments.push(payment);
    
    res.json(payment);
  }, 20); // 20ms processing time
});

app.get('/api/payments/metrics', (req, res) => {
  res.json({
    service: 'payment',
    requests: requestCount,
    payments: payments.length,
    avgLatency: '20ms'
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'payment' }));

const PORT = 3003;
app.listen(PORT, () => console.log(`Payment Service running on port ${PORT}`));
