import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

const inventory = {
  'PROD-001': { id: 'PROD-001', name: 'Laptop', stock: 50, price: 999.99 },
  'PROD-002': { id: 'PROD-002', name: 'Mouse', stock: 200, price: 29.99 },
  'PROD-003': { id: 'PROD-003', name: 'Keyboard', stock: 150, price: 79.99 }
};

const orders = [];
const payments = [];

app.post('/api/order', (req, res) => {
  const { productId, quantity } = req.body;
  
  if (!inventory[productId] || inventory[productId].stock < quantity) {
    return res.status(400).json({ error: 'Insufficient inventory' });
  }
  
  const order = {
    id: `ORD-${Date.now()}`,
    productId,
    quantity,
    total: inventory[productId].price * quantity,
    status: 'pending'
  };
  orders.push(order);
  
  const payment = {
    id: `PAY-${Date.now()}`,
    orderId: order.id,
    amount: order.total,
    status: 'completed'
  };
  payments.push(payment);
  
  inventory[productId].stock -= quantity;
  order.status = 'completed';
  
  res.json({ order, payment });
});

app.post('/api/inventory/check', (req, res) => {
  const { productId, quantity } = req.body;
  const product = inventory[productId];
  
  if (!product) {
    return res.json({ available: false });
  }
  
  res.json({
    available: product.stock >= quantity,
    stock: product.stock,
    price: product.price
  });
});

app.post('/api/inventory/reserve', (req, res) => {
  const { productId, quantity } = req.body;
  
  if (inventory[productId] && inventory[productId].stock >= quantity) {
    inventory[productId].stock -= quantity;
    res.json({ success: true });
  } else {
    res.status(400).json({ success: false });
  }
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'legacy-monolith' }));

const PORT = 3006;
app.listen(PORT, () => console.log(`Legacy Monolith running on port ${PORT}`));
