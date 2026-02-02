const express = require('express');
const React = require('react');
const ReactDOMServer = require('react-dom/server');
const compression = require('compression');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();
app.use(compression());
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, '../client')));

// Performance tracking
const metrics = {
  ssr: { requests: 0, totalTime: 0, avgTime: 0 },
  csr: { requests: 0, totalTime: 0, avgTime: 0 }
};

// Mock product data
const generateProducts = () => {
  const products = [];
  for (let i = 1; i <= 24; i++) {
    products.push({
      id: i,
      name: `Product ${i}`,
      price: (Math.random() * 100 + 10).toFixed(2),
      rating: (Math.random() * 2 + 3).toFixed(1),
      reviews: Math.floor(Math.random() * 1000),
      image: `https://picsum.photos/seed/product${i}/200/200`
    });
  }
  return products;
};

// React component for SSR
const ProductCard = ({ product }) => {
  return React.createElement('div', {
    className: 'product-card',
    style: {
      background: 'white',
      borderRadius: '12px',
      padding: '16px',
      boxShadow: '0 4px 6px rgba(59, 130, 246, 0.1)',
      transition: 'transform 0.2s'
    }
  }, [
    React.createElement('img', {
      key: 'img',
      src: product.image,
      alt: product.name,
      style: { width: '100%', borderRadius: '8px', marginBottom: '12px' }
    }),
    React.createElement('h3', {
      key: 'name',
      style: { color: '#1e3a8a', margin: '0 0 8px 0', fontSize: '18px' }
    }, product.name),
    React.createElement('div', {
      key: 'price',
      style: { fontSize: '24px', fontWeight: 'bold', color: '#3b82f6', marginBottom: '8px' }
    }, `$${product.price}`),
    React.createElement('div', {
      key: 'rating',
      style: { color: '#6b7280', fontSize: '14px' }
    }, `⭐ ${product.rating} (${product.reviews} reviews)`)
  ]);
};

const ProductGrid = ({ products }) => {
  return React.createElement('div', {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(auto-fill, minmax(250px, 1fr))',
      gap: '24px',
      padding: '24px'
    }
  }, products.map(product => 
    React.createElement(ProductCard, { key: product.id, product })
  ));
};

// SSR endpoint
app.get('/api/ssr', (req, res) => {
  const startTime = Date.now();
  
  try {
    const products = generateProducts();
    const productGrid = React.createElement(ProductGrid, { products });
    const html = ReactDOMServer.renderToString(productGrid);
    
    const renderTime = Math.max(Date.now() - startTime, 1);
    metrics.ssr.requests++;
    metrics.ssr.totalTime += renderTime;
    metrics.ssr.avgTime = metrics.ssr.totalTime / metrics.ssr.requests;
    
    const fullHtml = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>SSR Product Grid</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { 
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: linear-gradient(135deg, #e0f2fe 0%, #f0f9ff 100%);
      min-height: 100vh;
      padding: 20px;
    }
    .header {
      background: linear-gradient(135deg, #3b82f6 0%, #2563eb 100%);
      color: white;
      padding: 24px;
      border-radius: 12px;
      margin-bottom: 24px;
      box-shadow: 0 8px 16px rgba(59, 130, 246, 0.2);
    }
    .product-card:hover { transform: translateY(-4px); }
  </style>
</head>
<body>
  <div class="header">
    <h1>🚀 Server-Side Rendered Products</h1>
    <p>Rendered in ${renderTime}ms on the server</p>
  </div>
  ${html}
</body>
</html>`;
    
    res.send(fullHtml);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// CSR endpoint - returns empty shell
app.get('/api/csr', (req, res) => {
  const startTime = Date.now();
  
  const renderTime = Math.max(Date.now() - startTime, 1);
  metrics.csr.requests++;
  metrics.csr.totalTime += renderTime;
  metrics.csr.avgTime = metrics.csr.totalTime / metrics.csr.requests;
  
  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CSR Product Grid</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { 
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: linear-gradient(135deg, #e0f2fe 0%, #f0f9ff 100%);
      min-height: 100vh;
      padding: 20px;
    }
  </style>
</head>
<body>
  <div id="root">
    <div style="text-align: center; padding: 100px 20px;">
      <div style="display: inline-block; width: 50px; height: 50px; border: 5px solid #3b82f6; border-radius: 50%; border-top-color: transparent; animation: spin 1s linear infinite;"></div>
      <p style="margin-top: 20px; color: #3b82f6; font-size: 18px;">Loading products...</p>
    </div>
  </div>
  <script type="module" src="/csr-app.js"></script>
  <style>
    @keyframes spin {
      to { transform: rotate(360deg); }
    }
  </style>
</body>
</html>`;
  
  res.send(html);
});

// API endpoint for CSR to fetch data
app.get('/api/products', (req, res) => {
  // Simulate network latency
  const delay = parseInt(req.query.delay) || 100;
  setTimeout(() => {
    res.json(generateProducts());
  }, delay);
});

// Metrics endpoint
app.get('/api/metrics', (req, res) => {
  res.json(metrics);
});

// Dashboard page
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, '../client/dashboard.html'));
});

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`✅ Server running on http://localhost:${PORT}`);
  console.log(`📊 Dashboard: http://localhost:${PORT}`);
  console.log(`🔵 SSR Demo: http://localhost:${PORT}/api/ssr`);
  console.log(`🔴 CSR Demo: http://localhost:${PORT}/api/csr`);
});
