import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

const payments = [];

app.post('/api/payments', (req, res) => {
  const { orderId, amount } = req.body;
  
  const payment = {
    id: `PAY-NEW-${Date.now()}`,
    orderId,
    amount,
    status: 'completed',
    processor: 'new-service',
    processedAt: new Date().toISOString()
  };
  payments.push(payment);
  
  res.json(payment);
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'new-payment' }));

const PORT = 3007;
app.listen(PORT, () => console.log(`New Payment Service running on port ${PORT}`));
