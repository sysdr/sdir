const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const axios = require('axios');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// Order Schema - Owned by Order Context
const orderSchema = new mongoose.Schema({
  orderId: { type: String, unique: true, required: true },
  userId: { type: String, required: true }, // Reference, not foreign key
  items: [{
    productId: String,
    productName: String, // Denormalized for Order Context
    quantity: Number,
    price: Number
  }],
  totalAmount: { type: Number, required: true },
  status: { 
    type: String, 
    enum: ['pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled'],
    default: 'pending' 
  },
  createdAt: { type: Date, default: Date.now }
});

const Order = mongoose.model('Order', orderSchema);

// Connect to Order Context Database
mongoose.connect(process.env.MONGODB_URI || 'mongodb://mongo-order:27017/orderdb')
  .then(() => console.log('Order Service: Connected to MongoDB'))
  .catch(err => console.error('Order Service: MongoDB connection error:', err));

// Order Context API Endpoints
app.get('/health', (req, res) => {
  res.json({ service: 'order-service', status: 'healthy', context: 'Order Processing' });
});

app.post('/orders', async (req, res) => {
  try {
    const { userId, items } = req.body;
    const orderId = require('uuid').v4();
    
    // Validate user exists (Cross-context API call with Anti-corruption layer)
    try {
      await axios.get(`http://user-service:3001/users/${userId}`);
    } catch (error) {
      return res.status(400).json({ error: 'User not found in User Context' });
    }
    
    // Validate products and get current prices (Cross-context API call)
    let totalAmount = 0;
    const orderItems = [];
    
    for (const item of items) {
      try {
        const productResponse = await axios.get(`http://product-service:3002/products/${item.productId}`);
        const product = productResponse.data;
        
        // Reserve inventory
        await axios.post(`http://product-service:3002/products/${item.productId}/reserve`, {
          quantity: item.quantity
        });
        
        const itemTotal = product.price * item.quantity;
        totalAmount += itemTotal;
        
        orderItems.push({
          productId: item.productId,
          productName: product.name, // Denormalized data in Order Context
          quantity: item.quantity,
          price: product.price
        });
      } catch (error) {
        return res.status(400).json({ error: `Product ${item.productId} not available` });
      }
    }
    
    const order = new Order({
      orderId,
      userId,
      items: orderItems,
      totalAmount,
      status: 'pending'
    });
    
    await order.save();
    console.log(`Order Context: Created order ${orderId} for user ${userId}`);
    
    res.status(201).json({
      orderId,
      userId,
      items: orderItems,
      totalAmount,
      status: 'pending',
      message: 'Order created in Order Context'
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/orders/:orderId', async (req, res) => {
  try {
    const order = await Order.findOne({ orderId: req.params.orderId });
    if (!order) {
      return res.status(404).json({ error: 'Order not found in Order Context' });
    }
    res.json(order);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.put('/orders/:orderId/status', async (req, res) => {
  try {
    const { status } = req.body;
    const order = await Order.findOneAndUpdate(
      { orderId: req.params.orderId },
      { status },
      { new: true }
    );
    console.log(`Order Context: Updated order ${req.params.orderId} status to ${status}`);
    res.json({ message: 'Order status updated', orderId: req.params.orderId, status });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/orders', async (req, res) => {
  try {
    const orders = await Order.find()
      .select('-_id orderId userId totalAmount status createdAt')
      .sort({ createdAt: -1 });
    res.json({ orders, context: 'Order Processing', total: orders.length });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3003;
app.listen(PORT, () => {
  console.log(`📋 Order Service (Order Processing Context) running on port ${PORT}`);
});
