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

let requestCount = 0;

app.post('/api/inventory/check', (req, res) => {
  requestCount++;
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
  requestCount++;
  const { productId, quantity } = req.body;
  
  if (inventory[productId] && inventory[productId].stock >= quantity) {
    inventory[productId].stock -= quantity;
    res.json({ success: true, remaining: inventory[productId].stock });
  } else {
    res.status(400).json({ success: false });
  }
});

app.get('/api/inventory/metrics', (req, res) => {
  res.json({
    service: 'inventory',
    requests: requestCount,
    products: Object.keys(inventory).length
  });
});

app.get('/health', (req, res) => res.json({ status: 'healthy', service: 'inventory' }));

const PORT = 3004;
app.listen(PORT, () => console.log(`Inventory Service running on port ${PORT}`));
