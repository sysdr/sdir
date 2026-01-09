const express = require('express');
const fetch = require('node-fetch');

const app = express();
const FLAG_SERVICE = 'http://flag-service:3000';

let evaluationCount = 0;

async function evaluateFlag(flagId, userId) {
  try {
    const res = await fetch(`${FLAG_SERVICE}/evaluate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ 
        flagId, 
        userId, 
        context: { segment: 'premium', region: 'US' }
      })
    });
    evaluationCount++;
    const data = await res.json();
    return data.enabled;
  } catch (error) {
    console.error('Flag evaluation failed:', error.message);
    return false; // Fail closed
  }
}

app.get('/checkout/:userId', async (req, res) => {
  const { userId } = req.params;
  
  const fastCheckoutEnabled = await evaluateFlag('fast-checkout', userId);
  const newPaymentEnabled = await evaluateFlag('new-payment-flow', userId);
  
  res.json({
    service: 'checkout',
    userId,
    flow: fastCheckoutEnabled ? 'one-click' : 'standard',
    paymentVersion: newPaymentEnabled ? 'v2' : 'v1',
    evaluations: evaluationCount
  });
});

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'checkout' });
});

app.listen(3001, () => console.log('Checkout service on port 3001'));
