import express from 'express';
import { createClient } from 'redis';
import { v4 as uuidv4 } from 'uuid';
import cors from 'cors';

const app = express();
app.use(express.json());
app.use(cors());

const redis = await createClient({ url: 'redis://redis:6379' })
  .on('error', err => console.log('Redis error:', err))
  .connect();

const REGION = process.env.REGION || 'us-east';
const PROCESSOR_URL = process.env.PROCESSOR_URL || 'http://processor:3001';

// Exchange rates (simplified - in production, fetch from real API)
const EXCHANGE_RATES = {
  'USD': { 'EUR': 0.92, 'GBP': 0.79, 'JPY': 148.5, 'INR': 83.2 },
  'EUR': { 'USD': 1.09, 'GBP': 0.86, 'JPY': 161.8, 'INR': 90.5 },
  'GBP': { 'USD': 1.27, 'EUR': 1.16, 'JPY': 188.0, 'INR': 105.3 },
  'JPY': { 'USD': 0.0067, 'EUR': 0.0062, 'GBP': 0.0053, 'INR': 0.56 },
  'INR': { 'USD': 0.012, 'EUR': 0.011, 'GBP': 0.0095, 'JPY': 1.79 }
};

// Validate and enrich payment request
function validatePayment(payment) {
  if (!payment.amount || payment.amount <= 0) {
    throw new Error('Invalid amount');
  }
  if (!payment.sourceCurrency || !payment.targetCurrency) {
    throw new Error('Currency required');
  }
  if (!payment.idempotencyKey) {
    payment.idempotencyKey = uuidv4();
  }
  return payment;
}

// Convert currency
function convertCurrency(amount, from, to) {
  if (from === to) return amount;
  const rate = EXCHANGE_RATES[from]?.[to];
  if (!rate) throw new Error(`No exchange rate for ${from} to ${to}`);
  return parseFloat((amount * rate).toFixed(2));
}

// Process payment
app.post('/api/payment', async (req, res) => {
  try {
    const payment = validatePayment(req.body);
    const { idempotencyKey } = payment;

    // Check idempotency
    const cached = await redis.get(`idempotency:${idempotencyKey}`);
    if (cached) {
      console.log(`Returning cached response for ${idempotencyKey}`);
      return res.json(JSON.parse(cached));
    }

    // Lock exchange rate
    const lockedRate = EXCHANGE_RATES[payment.sourceCurrency][payment.targetCurrency];
    const convertedAmount = convertCurrency(
      payment.amount,
      payment.sourceCurrency,
      payment.targetCurrency
    );

    // Create payment record
    const paymentRecord = {
      id: uuidv4(),
      ...payment,
      convertedAmount,
      lockedRate,
      region: REGION,
      state: 'pending',
      timestamp: new Date().toISOString()
    };

    // Forward to processor
    const processorResponse = await fetch(`${PROCESSOR_URL}/api/process`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(paymentRecord)
    });

    const result = await processorResponse.json();

    // Cache response (24h TTL)
    await redis.setEx(
      `idempotency:${idempotencyKey}`,
      86400,
      JSON.stringify(result)
    );

    res.json(result);
  } catch (error) {
    res.status(400).json({ error: error.message });
  }
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', region: REGION });
});

// Metrics endpoint
app.get('/api/metrics', async (req, res) => {
  const totalPayments = await redis.get('metrics:total') || '0';
  const successfulPayments = await redis.get('metrics:success') || '0';
  
  res.json({
    region: REGION,
    totalPayments: parseInt(totalPayments),
    successfulPayments: parseInt(successfulPayments),
    authorizationRate: totalPayments > 0 
      ? ((parseInt(successfulPayments) / parseInt(totalPayments)) * 100).toFixed(2)
      : 0
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`Gateway [${REGION}] running on port ${PORT}`);
});
