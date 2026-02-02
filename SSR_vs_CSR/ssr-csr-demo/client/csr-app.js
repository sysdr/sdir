const startTime = performance.now();

async function fetchProducts() {
  const response = await fetch('/api/products?delay=200');
  return response.json();
}

function createProductCard(product) {
  return `
    <div class="product-card" style="
      background: white;
      border-radius: 12px;
      padding: 16px;
      box-shadow: 0 4px 6px rgba(59, 130, 246, 0.1);
      transition: transform 0.2s;
    ">
      <img src="${product.image}" alt="${product.name}" style="
        width: 100%;
        border-radius: 8px;
        margin-bottom: 12px;
      ">
      <h3 style="color: #1e3a8a; margin: 0 0 8px 0; font-size: 18px;">
        ${product.name}
      </h3>
      <div style="font-size: 24px; font-weight: bold; color: #3b82f6; margin-bottom: 8px;">
        $${product.price}
      </div>
      <div style="color: #6b7280; font-size: 14px;">
        ⭐ ${product.rating} (${product.reviews} reviews)
      </div>
    </div>
  `;
}

async function renderProducts() {
  const loadStartTime = performance.now();
  const products = await fetchProducts();
  const loadTime = performance.now() - loadStartTime;
  
  const parseStartTime = performance.now();
  const grid = products.map(createProductCard).join('');
  const parseTime = performance.now() - parseStartTime;
  
  const renderStartTime = performance.now();
  const totalTime = performance.now() - startTime;
  
  document.getElementById('root').innerHTML = `
    <div style="
      background: linear-gradient(135deg, #ef4444 0%, #dc2626 100%);
      color: white;
      padding: 24px;
      border-radius: 12px;
      margin-bottom: 24px;
      box-shadow: 0 8px 16px rgba(239, 68, 68, 0.2);
    ">
      <h1>⚡ Client-Side Rendered Products</h1>
      <p>Total time: ${totalTime.toFixed(2)}ms</p>
      <p style="font-size: 14px; opacity: 0.9; margin-top: 8px;">
        Load: ${loadTime.toFixed(2)}ms | Parse: ${parseTime.toFixed(2)}ms
      </p>
    </div>
    <div style="
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
      gap: 24px;
      padding: 24px;
    ">
      ${grid}
    </div>
  `;
  
  const renderTime = performance.now() - renderStartTime;
  console.log(`CSR Performance: Load=${loadTime}ms, Parse=${parseTime}ms, Render=${renderTime}ms, Total=${totalTime}ms`);
}

renderProducts();
