const express = require('express');
const router = express.Router();
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY || 'sk_test_demo_key');
const db = require('../database/db');

// Create payment intent
router.post('/create-payment-intent', async (req, res) => {
  try {
    const { amount, currency = 'usd', description } = req.body;

    if (!amount || amount < 0.5) {
      return res.status(400).json({ error: 'Amount must be at least $0.50' });
    }

    // Demo mode - create a mock payment intent
    const demoPaymentIntent = {
      id: `pi_demo_${Date.now()}`,
      client_secret: `pi_demo_${Date.now()}_secret_${Math.random().toString(36).substr(2, 9)}`,
      amount: Math.round(amount * 100),
      currency,
      status: 'requires_payment_method',
      description: description || 'Payment Systems Demo',
      metadata: {
        integration_check: 'accept_a_payment',
        demo: 'true'
      }
    };

    res.json({
      clientSecret: demoPaymentIntent.client_secret,
      paymentIntentId: demoPaymentIntent.id,
    });
  } catch (error) {
    console.error('Payment intent creation error:', error);
    res.status(500).json({ error: 'Failed to create payment intent' });
  }
});

// Process payment
router.post('/process', async (req, res) => {
  try {
    const { paymentIntentId, userId = 1, description } = req.body;

    if (!paymentIntentId) {
      return res.status(400).json({ error: 'Payment intent ID is required' });
    }

    // Demo mode - simulate payment processing
    const isDemoPayment = paymentIntentId.startsWith('pi_demo_');
    
    if (isDemoPayment) {
      // Simulate successful payment for demo
      const amount = 1000; // Default to $10.00 for demo
      
      // Store transaction in database
      const stmt = db.prepare(`
        INSERT INTO transactions (user_id, amount, currency, status, payment_intent_id, description)
        VALUES (?, ?, ?, ?, ?, ?)
      `);

      stmt.run(
        userId,
        amount / 100, // Convert from cents
        'usd',
        'succeeded',
        paymentIntentId,
        description || 'Demo Payment processed'
      );

      stmt.finalize();

      res.json({
        success: true,
        transaction: {
          id: paymentIntentId,
          amount: amount / 100,
          currency: 'usd',
          status: 'succeeded',
        },
      });
    } else {
      // For real payments, use Stripe
      try {
        const paymentIntent = await stripe.paymentIntents.retrieve(paymentIntentId);

        if (paymentIntent.status === 'succeeded') {
          // Store transaction in database
          const stmt = db.prepare(`
            INSERT INTO transactions (user_id, amount, currency, status, payment_intent_id, description)
            VALUES (?, ?, ?, ?, ?, ?)
          `);

          stmt.run(
            userId,
            paymentIntent.amount / 100, // Convert from cents
            paymentIntent.currency,
            paymentIntent.status,
            paymentIntentId,
            description || 'Payment processed'
          );

          stmt.finalize();

          res.json({
            success: true,
            transaction: {
              id: paymentIntent.id,
              amount: paymentIntent.amount / 100,
              currency: paymentIntent.currency,
              status: paymentIntent.status,
            },
          });
        } else {
          res.status(400).json({ error: 'Payment not completed', status: paymentIntent.status });
        }
      } catch (stripeError) {
        console.error('Stripe error:', stripeError);
        res.status(500).json({ error: 'Failed to process payment with Stripe' });
      }
    }
  } catch (error) {
    console.error('Payment processing error:', error);
    res.status(500).json({ error: 'Failed to process payment' });
  }
});

// Get payment methods
router.get('/methods/:userId', (req, res) => {
  const { userId } = req.params;

  db.all(
    'SELECT * FROM payment_methods WHERE user_id = ? ORDER BY is_default DESC',
    [userId],
    (err, rows) => {
      if (err) {
        console.error('Database error:', err);
        return res.status(500).json({ error: 'Database error' });
      }
      res.json(rows);
    }
  );
});

// Add payment method
router.post('/methods', (req, res) => {
  const { userId, type, lastFour, brand, isDefault = false } = req.body;

  if (isDefault) {
    // Remove default from other methods
    db.run('UPDATE payment_methods SET is_default = 0 WHERE user_id = ?', [userId]);
  }

  const stmt = db.prepare(`
    INSERT INTO payment_methods (user_id, type, last_four, brand, is_default)
    VALUES (?, ?, ?, ?, ?)
  `);

  stmt.run(userId, type, lastFour, brand, isDefault ? 1 : 0, (err) => {
    if (err) {
      console.error('Database error:', err);
      return res.status(500).json({ error: 'Failed to add payment method' });
    }
    res.json({ success: true, message: 'Payment method added successfully' });
  });

  stmt.finalize();
});

// Get payment history
router.get('/history/:userId', (req, res) => {
  const { userId } = req.params;

  db.all(
    `SELECT t.*, pm.type as payment_method_type, pm.last_four, pm.brand
     FROM transactions t
     LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
     WHERE t.user_id = ?
     ORDER BY t.created_at DESC`,
    [userId],
    (err, rows) => {
      if (err) {
        console.error('Database error:', err);
        return res.status(500).json({ error: 'Database error' });
      }
      res.json(rows);
    }
  );
});

module.exports = router; 