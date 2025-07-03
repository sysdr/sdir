// Application state
let currentUser = null;
let serviceType = window.SERVICE_TYPE || 'stateless';
let servicePort = window.SERVICE_PORT || 8000;

// API helper functions
async function apiCall(endpoint, method = 'GET', data = null) {
    const url = `http://localhost:${servicePort}${endpoint}`;
    const options = {
        method,
        headers: {
            'Content-Type': 'application/json',
        },
        credentials: 'include' // Important for cookies
    };
    
    if (data) {
        options.body = JSON.stringify(data);
    }
    
    try {
        const response = await fetch(url, options);
        
        if (!response.ok) {
            const errorData = await response.json().catch(() => ({}));
            throw new Error(errorData.detail || `HTTP ${response.status}`);
        }
        
        return await response.json();
    } catch (error) {
        console.error('API call failed:', error);
        showToast(error.message, 'error');
        throw error;
    }
}

// Authentication functions
async function login(type) {
    const username = document.getElementById('username').value.trim();
    const email = document.getElementById('email').value.trim();
    
    if (!username || !email) {
        showToast('Please enter both username and email', 'error');
        return;
    }
    
    try {
        showLoading(true);
        
        const formData = new FormData();
        formData.append('username', username);
        formData.append('email', email);
        
        const response = await fetch(`http://localhost:${servicePort}/login`, {
            method: 'POST',
            body: formData,
            credentials: 'include'
        });
        
        if (!response.ok) {
            throw new Error('Login failed');
        }
        
        const data = await response.json();
        currentUser = data;
        
        showToast(`Logged in successfully as ${username}`, 'success');
        
        // Show shopping section
        document.getElementById('login-section').style.display = 'none';
        document.getElementById('shopping-section').style.display = 'block';
        document.getElementById('cart-section').style.display = 'block';
        
        // Load initial cart
        await loadCart(type);
        
    } catch (error) {
        showToast('Login failed: ' + error.message, 'error');
    } finally {
        showLoading(false);
    }
}

async function logout(type) {
    try {
        showLoading(true);
        
        await apiCall('/logout', 'POST');
        
        currentUser = null;
        
        // Reset UI
        document.getElementById('login-section').style.display = 'block';
        document.getElementById('shopping-section').style.display = 'none';
        document.getElementById('cart-section').style.display = 'none';
        document.getElementById('cart-items').innerHTML = '';
        
        // Clear form
        document.getElementById('username').value = '';
        document.getElementById('email').value = '';
        
        showToast('Logged out successfully', 'success');
        
    } catch (error) {
        showToast('Logout failed: ' + error.message, 'error');
    } finally {
        showLoading(false);
    }
}

// Shopping cart functions
async function addToCart(type) {
    const productName = document.getElementById('product-name').value.trim();
    const productPrice = parseFloat(document.getElementById('product-price').value);
    
    if (!productName || !productPrice || productPrice <= 0) {
        showToast('Please enter valid product name and price', 'error');
        return;
    }
    
    try {
        showLoading(true);
        
        const item = {
            product_id: `prod_${Date.now()}`,
            name: productName,
            price: productPrice,
            quantity: 1
        };
        
        await apiCall('/cart/add', 'POST', item);
        
        showToast(`Added ${productName} to cart`, 'success');
        
        // Clear form
        document.getElementById('product-name').value = '';
        document.getElementById('product-price').value = '';
        
        // Reload cart
        await loadCart(type);
        
    } catch (error) {
        showToast('Failed to add item: ' + error.message, 'error');
    } finally {
        showLoading(false);
    }
}

async function loadCart(type) {
    try {
        const data = await apiCall('/cart');
        
        const cartItemsDiv = document.getElementById('cart-items');
        const cart = data.cart;
        
        if (!cart.items || cart.items.length === 0) {
            cartItemsDiv.innerHTML = '<div class="text-muted text-center py-3">Your cart is empty</div>';
            return;
        }
        
        let html = '';
        cart.items.forEach(item => {
            html += `
                <div class="cart-item fade-in">
                    <div>
                        <strong>${item.name}</strong><br>
                        <small class="text-muted">$${item.price.toFixed(2)} x ${item.quantity}</small>
                    </div>
                    <div class="text-end">
                        <strong>$${(item.price * item.quantity).toFixed(2)}</strong>
                    </div>
                </div>
            `;
        });
        
        html += `
            <div class="mt-3 p-3 bg-light rounded">
                <strong>Total: $${cart.total.toFixed(2)}</strong>
                ${data.service_info ? `<br><small class="text-muted">Service: ${data.service_info.type} (${data.service_info.instance_id})</small>` : ''}
            </div>
        `;
        
        cartItemsDiv.innerHTML = html;
        
    } catch (error) {
        console.error('Failed to load cart:', error);
    }
}

// Metrics functions
async function loadMetrics() {
    try {
        const data = await apiCall('/metrics');
        
        const metricsDiv = document.getElementById(`metrics-${serviceType}`);
        
        const html = `
            <div class="metric-item">
                <div class="metric-label">Service Type</div>
                <div class="metric-value">${data.service_type}</div>
            </div>
            <div class="metric-item">
                <div class="metric-label">Active Sessions</div>
                <div class="metric-value">${data.active_sessions}</div>
            </div>
            <div class="metric-item">
                <div class="metric-label">Memory Usage</div>
                <div class="metric-value">${data.memory_usage.toFixed(1)}%</div>
            </div>
            <div class="metric-item">
                <div class="metric-label">CPU Usage</div>
                <div class="metric-value">${data.cpu_usage.toFixed(1)}%</div>
            </div>
            <div class="metric-item">
                <div class="metric-label">Requests</div>
                <div class="metric-value">${data.request_count}</div>
            </div>
        `;
        
        metricsDiv.innerHTML = html;
        
    } catch (error) {
        console.error('Failed to load metrics:', error);
    }
}

// UI helper functions
function showToast(message, type = 'info') {
    // Create toast element
    const toast = document.createElement('div');
    toast.className = `toast show toast-${type}`;
    toast.innerHTML = `
        <div class="toast-body">
            <i class="fas fa-${type === 'success' ? 'check-circle' : type === 'error' ? 'exclamation-circle' : 'info-circle'} me-2"></i>
            ${message}
        </div>
    `;
    
    // Add to page
    document.body.appendChild(toast);
    
    // Position toast
    toast.style.position = 'fixed';
    toast.style.top = '20px';
    toast.style.right = '20px';
    toast.style.zIndex = '9999';
    toast.style.minWidth = '300px';
    
    // Remove after 3 seconds
    setTimeout(() => {
        toast.remove();
    }, 3000);
}

function showLoading(show) {
    let overlay = document.getElementById('loading-overlay');
    
    if (show) {
        if (!overlay) {
            overlay = document.createElement('div');
            overlay.id = 'loading-overlay';
            overlay.className = 'loading-overlay';
            overlay.innerHTML = `
                <div class="text-center">
                    <div class="spinner-border text-primary" role="status" style="width: 3rem; height: 3rem;">
                        <span class="visually-hidden">Loading...</span>
                    </div>
                    <div class="mt-3">Processing...</div>
                </div>
            `;
            document.body.appendChild(overlay);
        }
        overlay.style.display = 'flex';
    } else {
        if (overlay) {
            overlay.style.display = 'none';
        }
    }
}

// Initialize page
document.addEventListener('DOMContentLoaded', function() {
    console.log(`Initializing ${serviceType} service demo`);
    
    // Load initial metrics
    loadMetrics();
    
    // Start metrics refresh interval
    setInterval(loadMetrics, 5000);
    
    // Add sample products for easy testing
    if (serviceType === 'stateless') {
        document.getElementById('product-name').placeholder = 'e.g., MacBook Pro';
        document.getElementById('product-price').placeholder = '1999.99';
    } else {
        document.getElementById('product-name').placeholder = 'e.g., iPhone 15';
        document.getElementById('product-price').placeholder = '999.99';
    }
});

// Global error handler
window.addEventListener('error', function(e) {
    console.error('Global error:', e.error);
    showToast('An unexpected error occurred', 'error');
});
