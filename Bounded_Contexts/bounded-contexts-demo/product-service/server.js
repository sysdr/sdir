const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// Product Schema - Owned by Product Context
const productSchema = new mongoose.Schema({
  productId: { type: String, unique: true, required: true },
  name: { type: String, required: true },
  description: String,
  price: { type: Number, required: true },
  category: String,
  inventory: {
    stock: { type: Number, default: 0 },
    reserved: { type: Number, default: 0 }
  },
  createdAt: { type: Date, default: Date.now }
});

const Product = mongoose.model('Product', productSchema);

// Connect to Product Context Database
mongoose.connect(process.env.MONGODB_URI || 'mongodb://mongo-product:27017/productdb')
  .then(() => console.log('Product Service: Connected to MongoDB'))
  .catch(err => console.error('Product Service: MongoDB connection error:', err));

// Seed initial products
async function seedProducts() {
  const count = await Product.countDocuments();
  if (count === 0) {
    const products = [
      { productId: 'prod-1', name: 'Laptop Pro', description: 'High-performance laptop', price: 1299.99, category: 'Electronics', inventory: { stock: 50 } },
      { productId: 'prod-2', name: 'Wireless Headphones', description: 'Noise-canceling headphones', price: 199.99, category: 'Electronics', inventory: { stock: 100 } },
      { productId: 'prod-3', name: 'Coffee Maker', description: 'Automatic coffee maker', price: 89.99, category: 'Home', inventory: { stock: 25 } }
    ];
    await Product.insertMany(products);
    console.log('Product Context: Seeded initial products');
  }
}

setTimeout(seedProducts, 2000);

// Product Context API Endpoints
app.get('/health', (req, res) => {
  res.json({ service: 'product-service', status: 'healthy', context: 'Product Catalog' });
});

app.get('/products', async (req, res) => {
  try {
    const products = await Product.find().select('-_id productId name description price category inventory');
    res.json({ products, context: 'Product Catalog', total: products.length });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.get('/products/:productId', async (req, res) => {
  try {
    const product = await Product.findOne({ productId: req.params.productId });
    if (!product) {
      return res.status(404).json({ error: 'Product not found in Product Context' });
    }
    res.json(product);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/products/:productId/reserve', async (req, res) => {
  try {
    const { quantity } = req.body;
    const product = await Product.findOne({ productId: req.params.productId });
    
    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    if (product.inventory.stock < quantity) {
      return res.status(400).json({ error: 'Insufficient stock' });
    }
    
    product.inventory.stock -= quantity;
    product.inventory.reserved += quantity;
    await product.save();
    
    console.log(`Product Context: Reserved ${quantity} units of ${req.params.productId}`);
    res.json({ message: 'Inventory reserved', reserved: quantity });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.put('/products/:productId/price', async (req, res) => {
  try {
    const { price } = req.body;
    const product = await Product.findOneAndUpdate(
      { productId: req.params.productId },
      { price },
      { new: true }
    );
    console.log(`Product Context: Updated price for ${req.params.productId} to $${price}`);
    res.json({ message: 'Price updated', productId: req.params.productId, newPrice: price });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => {
  console.log(`📦 Product Service (Product Catalog Context) running on port ${PORT}`);
});
