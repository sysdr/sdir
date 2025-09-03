const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const axios = require('axios');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// Payment Schema - Owned by Payment Context
const paymentSchema = new mongoose.Schema({
  paymentId: { type: String, unique: true, required: true },
  orderId: { type: String, required: true }, // Reference to Order Context
  amount: { type: Number, required: true },
  currency: { type: String, default: 'USD' },
  method: { type: String, enum: ['credit_card', 'paypal', 'bank_transfer'], required: true },
  status: { 
    type: String, 
    enum: ['pending', 'processing', 'completed', 'failed', 'refunded'],
    default: 'pending' 
  },
  transactionId: String,
  createdAt: { type: Date, default: Date.now }
});

const Payment = mongoose.model('Payment', paymentSchema);

// Connect to Payment Context Database
mongoose.connect(process.env.MONGODB_URI || 'mongodb://mongo-payment:27017/paymentdb')
  .then(() => console.log('Payment Service: Connected to MongoDB'))
  .catch(err => console.error('Payment Service: MongoDB connection error:', err));

// Payment Context API Endpoints
app.get('/health', (req, res) => {
  res.json({ service: 'payment-service', status: 'healthy', context: 'Payment Processing' });
});

app.post('/payments', async (req, res) => {
  try {
    const { orderId, amount, method } = req.body;
    const paymentId = require('uuid').v4();
    
    // Validate order exists (Cross-context API call)
    try {
      const orderResponse = await axios.get(`http://order-service:3003/orders/${orderId}`);
      const order = orderResponse.data;
      
      if (order.totalAmount !== amount) {
        return res.status(400).json({ error: 'Payment amount does not match order total' });
      }
    } catch (error) {
      return res.status(400).json({ error: 'Order not found in Order Context' });
    }
    
    const payment = new Payment({
      paymentId,
      orderId,
      amount,
      method,
      status: 'processing',
      transactionId: `tx_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
    });
    
    await payment.save();
    
    // Simulate payment processing
    setTimeout(async () => {
      const success = Math.random() > 0.1; // 90% success rate
      payment.status = success ? 'completed' : 'failed';
      await payment.save();
      
      if (success) {
        // Update order status (Cross-context API call)
        try {
          await axios.put(`http://order-service:3003/orders/${orderId}/status`, {
            status: 'confirmed'
          });
        } catch (error) {
          console.error('Failed to update order status:', error.message);
        }
      }
      
      console.log(`Payment Context: Payment ${paymentId} ${payment.status}`);
    }, 2000);
    
    console.log(`Payment Context: Processing payment ${paymentId} for order ${orderId}`);
    
    res.status(201).json({
      paymentId,
      orderId,
      amount,
      method,
      status: 'processing',
      message: 'Payment created in Payment Context'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/payments/:paymentId', async (req, res) => {
  try {
    const payment = await Payment.findOne({ paymentId: req.params.paymentId });
    if (!payment) {
      return res.status(404).json({ error: 'Payment not found in Payment Context' });
    }
    res.json(payment);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/payments', async (req, res) => {
  try {
    const payments = await Payment.find()
      .select('-_id paymentId orderId amount method status createdAt')
      .sort({ createdAt: -1 });
    res.json({ payments, context: 'Payment Processing', total: payments.length });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3004;
app.listen(PORT, () => {
  console.log(`💳 Payment Service (Payment Processing Context) running on port ${PORT}`);
});
