// CQRS Demo Application
class CQRSDemo {
    constructor() {
        this.commandBaseUrl = 'http://localhost:8001';
        this.queryBaseUrl = 'http://localhost:8002';
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.checkServices();
        this.startPeriodicUpdates();
        this.log('🚀 CQRS Demo initialized');
    }

    setupEventListeners() {
        // Product form
        document.getElementById('product-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.createProduct();
        });

        // Stock form
        document.getElementById('stock-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.updateStock();
        });

        // Order form
        document.getElementById('order-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.createOrder();
        });
    }

    async checkServices() {
        try {
            // Check Command Service
            const commandResponse = await fetch(`${this.commandBaseUrl}/health`);
            const commandHealth = await commandResponse.json();
            this.updateServiceStatus('command', commandResponse.ok, commandHealth);

            // Check Query Service
            const queryResponse = await fetch(`${this.queryBaseUrl}/health`);
            const queryHealth = await queryResponse.json();
            this.updateServiceStatus('query', queryResponse.ok, queryHealth);

            this.log(`✅ Services checked - Command: ${commandResponse.ok ? 'Healthy' : 'Error'}, Query: ${queryResponse.ok ? 'Healthy' : 'Error'}`);
        } catch (error) {
            this.log(`❌ Service check failed: ${error.message}`);
        }
    }

    updateServiceStatus(service, isHealthy, health) {
        const indicator = document.getElementById(`${service}-indicator`);
        const stats = document.getElementById(`${service}-stats`);
        
        indicator.textContent = isHealthy ? 'Healthy ✅' : 'Error ❌';
        indicator.className = `status-indicator ${isHealthy ? 'status-healthy' : 'status-error'}`;
        
        if (health && health.service) {
            stats.innerHTML = `<small>Service: ${health.service}</small>`;
        }
    }

    async createProduct() {
        this.log('📝 Creating product...');
        
        const productData = {
            name: document.getElementById('product-name').value,
            description: document.getElementById('product-description').value,
            price: parseFloat(document.getElementById('product-price').value),
            stock_quantity: parseInt(document.getElementById('product-stock').value),
            category: document.getElementById('product-category').value
        };

        try {
            const response = await fetch(`${this.commandBaseUrl}/commands/products`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(productData)
            });

            const result = await response.json();
            
            if (response.ok) {
                this.log(`✅ Product created: ${result.message} (ID: ${result.product_id})`);
                document.getElementById('product-form').reset();
                
                // Auto-refresh products after a short delay to show eventual consistency
                setTimeout(() => this.loadProducts(), 2000);
            } else {
                this.log(`❌ Failed to create product: ${result.detail}`);
            }
        } catch (error) {
            this.log(`❌ Error creating product: ${error.message}`);
        }
    }

    async updateStock() {
        this.log('📦 Updating stock...');
        
        const productId = parseInt(document.getElementById('stock-product-id').value);
        const stockData = {
            product_id: productId,
            quantity: parseInt(document.getElementById('stock-quantity').value)
        };

        try {
            const response = await fetch(`${this.commandBaseUrl}/commands/products/${productId}/stock`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(stockData)
            });

            const result = await response.json();
            
            if (response.ok) {
                this.log(`✅ Stock updated: ${result.message}`);
                document.getElementById('stock-form').reset();
                
                setTimeout(() => this.loadProducts(), 2000);
            } else {
                this.log(`❌ Failed to update stock: ${result.detail}`);
            }
        } catch (error) {
            this.log(`❌ Error updating stock: ${error.message}`);
        }
    }

    async createOrder() {
        this.log('🛒 Creating order...');
        
        const orderData = {
            customer_id: document.getElementById('order-customer-id').value,
            product_id: parseInt(document.getElementById('order-product-id').value),
            quantity: parseInt(document.getElementById('order-quantity').value)
        };

        try {
            const response = await fetch(`${this.commandBaseUrl}/commands/orders`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(orderData)
            });

            const result = await response.json();
            
            if (response.ok) {
                this.log(`✅ Order created: ${result.message} (ID: ${result.order_id}, Total: $${result.total_amount})`);
                document.getElementById('order-form').reset();
                
                setTimeout(() => {
                    this.loadOrders();
                    this.loadProducts(); // Stock will be updated
                }, 2000);
            } else {
                this.log(`❌ Failed to create order: ${result.detail}`);
            }
        } catch (error) {
            this.log(`❌ Error creating order: ${error.message}`);
        }
    }

    async loadProducts() {
        this.log('🔍 Loading products from query service...');
        
        try {
            const response = await fetch(`${this.queryBaseUrl}/queries/products`);
            const products = await response.json();
            
            if (response.ok) {
                this.displayProducts(products);
                this.log(`✅ Loaded ${products.length} products`);
            } else {
                this.log(`❌ Failed to load products: ${products.detail}`);
            }
        } catch (error) {
            this.log(`❌ Error loading products: ${error.message}`);
        }
    }

    async loadOrders() {
        this.log('🔍 Loading orders from query service...');
        
        try {
            const response = await fetch(`${this.queryBaseUrl}/queries/orders`);
            const orders = await response.json();
            
            if (response.ok) {
                this.displayOrders(orders);
                this.log(`✅ Loaded ${orders.length} orders`);
            } else {
                this.log(`❌ Failed to load orders: ${orders.detail}`);
            }
        } catch (error) {
            this.log(`❌ Error loading orders: ${error.message}`);
        }
    }

    async loadStats() {
        this.log('📊 Loading statistics...');
        
        try {
            const [commandResponse, queryResponse] = await Promise.all([
                fetch(`${this.commandBaseUrl}/commands/stats`),
                fetch(`${this.queryBaseUrl}/queries/stats`)
            ]);

            const commandStats = await commandResponse.json();
            const queryStats = await queryResponse.json();
            
            if (commandResponse.ok && queryResponse.ok) {
                this.displayStats(commandStats, queryStats);
                this.log(`✅ Statistics loaded`);
            } else {
                this.log(`❌ Failed to load statistics`);
            }
        } catch (error) {
            this.log(`❌ Error loading statistics: ${error.message}`);
        }
    }

    displayProducts(products) {
        const container = document.getElementById('products-list');
        
        if (products.length === 0) {
            container.innerHTML = '<p>No products found. Create some products using the command form!</p>';
            return;
        }
        
        container.innerHTML = products.map(product => `
            <div class="data-item">
                <h4>${product.name} (ID: ${product.id})</h4>
                <p><strong>Price:</strong> $${product.price.toFixed(2)}</p>
                <p><strong>Stock:</strong> ${product.stock_quantity}</p>
                <p><strong>Category:</strong> ${product.category || 'N/A'}</p>
                <p><strong>Description:</strong> ${product.description || 'No description'}</p>
                <p><strong>Created:</strong> ${new Date(product.created_at).toLocaleString()}</p>
            </div>
        `).join('');
    }

    displayOrders(orders) {
        const container = document.getElementById('orders-list');
        
        if (orders.length === 0) {
            container.innerHTML = '<p>No orders found. Create some orders using the command form!</p>';
            return;
        }
        
        container.innerHTML = orders.map(order => `
            <div class="data-item">
                <h4>Order #${order.id}</h4>
                <p><strong>Customer:</strong> ${order.customer_id}</p>
                <p><strong>Product:</strong> ${order.product_name} (ID: ${order.product_id})</p>
                <p><strong>Quantity:</strong> ${order.quantity}</p>
                <p><strong>Total:</strong> $${order.total_amount.toFixed(2)}</p>
                <p><strong>Status:</strong> ${order.status}</p>
                <p><strong>Created:</strong> ${new Date(order.created_at).toLocaleString()}</p>
            </div>
        `).join('');
    }

    displayStats(commandStats, queryStats) {
        const container = document.getElementById('stats-display');
        
        container.innerHTML = `
            <div class="stat-card">
                <div class="value">${commandStats.products}</div>
                <div class="label">Products (Command)</div>
            </div>
            <div class="stat-card">
                <div class="value">${queryStats.products}</div>
                <div class="label">Products (Query)</div>
            </div>
            <div class="stat-card">
                <div class="value">${commandStats.orders}</div>
                <div class="label">Orders (Command)</div>
            </div>
            <div class="stat-card">
                <div class="value">${queryStats.orders}</div>
                <div class="label">Orders (Query)</div>
            </div>
            <div class="stat-card">
                <div class="value">${commandStats.total_stock_items || 0}</div>
                <div class="label">Total Stock Items</div>
            </div>
            <div class="stat-card">
                <div class="value">$${(queryStats.total_revenue || 0).toFixed(2)}</div>
                <div class="label">Total Revenue</div>
            </div>
        `;
    }

    startPeriodicUpdates() {
        // Check services every 30 seconds
        setInterval(() => this.checkServices(), 30000);
        
        // Auto-refresh stats every 15 seconds
        setInterval(() => {
            this.loadStats();
        }, 15000);
    }

    log(message) {
        const logsContainer = document.getElementById('logs');
        const timestamp = new Date().toLocaleTimeString();
        const logEntry = `[${timestamp}] ${message}\n`;
        
        logsContainer.textContent += logEntry;
        logsContainer.scrollTop = logsContainer.scrollHeight;
    }

    clearLogs() {
        document.getElementById('logs').textContent = '';
        this.log('📋 Logs cleared');
    }
}

// Global functions for buttons
function loadProducts() {
    window.cqrsDemo.loadProducts();
}

function loadOrders() {
    window.cqrsDemo.loadOrders();
}

function loadStats() {
    window.cqrsDemo.loadStats();
}

function clearLogs() {
    window.cqrsDemo.clearLogs();
}

// Initialize when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.cqrsDemo = new CQRSDemo();
});
