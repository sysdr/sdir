import React, { useState, useEffect } from 'react';
import {
  Container, Typography, Grid, Card, CardContent, 
  Button, TextField, Box, Chip, Table, TableBody,
  TableCell, TableContainer, TableHead, TableRow,
  Paper, Alert, Tabs, Tab
} from '@mui/material';
import axios from 'axios';

const API_ENDPOINTS = {
  order: 'http://localhost:8001',
  inventory: 'http://localhost:8002', 
  shipping: 'http://localhost:8003'
};

function App() {
  const [currentTab, setCurrentTab] = useState(0);
  const [orders, setOrders] = useState([]);
  const [products, setProducts] = useState([]);
  const [shipments, setShipments] = useState([]);
  const [message, setMessage] = useState('');

  // Form data
  const [customerId, setCustomerId] = useState('CUST001');
  const [productId, setProductId] = useState('LAPTOP001');
  const [quantity, setQuantity] = useState(1);

  const showMessage = (msg) => {
    setMessage(msg);
    setTimeout(() => setMessage(''), 3000);
  };

  const fetchData = async () => {
    try {
      const [ordersRes, productsRes, shipmentsRes] = await Promise.all([
        axios.get(`${API_ENDPOINTS.order}/orders`),
        axios.get(`${API_ENDPOINTS.inventory}/products`),
        axios.get(`${API_ENDPOINTS.shipping}/shipments`)
      ]);
      
      setOrders(ordersRes.data);
      setProducts(productsRes.data);
      setShipments(shipmentsRes.data);
    } catch (error) {
      console.error('Error fetching data:', error);
    }
  };

  const createAndConfirmOrder = async () => {
    try {
      // Create order
      const orderRes = await axios.post(`${API_ENDPOINTS.order}/orders`, {
        customer_id: customerId
      });
      
      const orderId = orderRes.data.order_id;
      
      // Add item
      await axios.post(`${API_ENDPOINTS.order}/orders/${orderId}/items`, {
        product_id: productId,
        product_name: products.find(p => p.product_id === productId)?.name || 'Unknown',
        quantity: quantity,
        price: 299.99
      });
      
      // Set address
      await axios.put(`${API_ENDPOINTS.order}/orders/${orderId}/address`, {
        street: '123 Main St',
        city: 'Springfield',
        state: 'IL',
        zip_code: '62701',
        country: 'US'
      });
      
      // Confirm order (triggers domain events)
      await axios.post(`${API_ENDPOINTS.order}/orders/${orderId}/confirm`);
      
      showMessage(`Order ${orderId} confirmed! Watch the event flow across contexts.`);
      
      // Refresh data after a moment to see the changes
      setTimeout(fetchData, 1000);
      
    } catch (error) {
      showMessage(`Error: ${error.response?.data?.detail || error.message}`);
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 2000); // Auto refresh every 2 seconds
    return () => clearInterval(interval);
  }, []);

  return (
    <Container maxWidth="xl" sx={{ mt: 2 }}>
      <Typography variant="h3" component="h1" gutterBottom sx={{ 
        background: 'linear-gradient(45deg, #2196F3 30%, #21CBF3 90%)',
        WebkitBackgroundClip: 'text',
        WebkitTextFillColor: 'transparent',
        fontWeight: 'bold',
        textAlign: 'center'
      }}>
        🏗️ Domain-Driven Design Demo
      </Typography>
      
      <Typography variant="h6" sx={{ textAlign: 'center', mb: 3, color: '#666' }}>
        Watch bounded contexts communicate via domain events
      </Typography>

      {message && (
        <Alert severity="info" sx={{ mb: 2 }}>
          {message}
        </Alert>
      )}

      {/* Quick Order Creation */}
      <Card sx={{ mb: 3, background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)', color: 'white' }}>
        <CardContent>
          <Typography variant="h5" gutterBottom>
            🛒 Create Order (Triggers DDD Event Flow)
          </Typography>
          <Grid container spacing={2} alignItems="center">
            <Grid item xs={3}>
              <TextField
                label="Customer ID"
                value={customerId}
                onChange={(e) => setCustomerId(e.target.value)}
                size="small"
                fullWidth
                InputLabelProps={{ style: { color: 'white' } }}
                InputProps={{ style: { color: 'white' } }}
              />
            </Grid>
            <Grid item xs={3}>
              <TextField
                select
                label="Product"
                value={productId}
                onChange={(e) => setProductId(e.target.value)}
                size="small"
                fullWidth
                InputLabelProps={{ style: { color: 'white' } }}
                InputProps={{ style: { color: 'white' } }}
                SelectProps={{ native: true }}
              >
                {products.map(p => (
                  <option key={p.product_id} value={p.product_id}>
                    {p.name} (Available: {p.available_quantity})
                  </option>
                ))}
              </TextField>
            </Grid>
            <Grid item xs={2}>
              <TextField
                label="Quantity"
                type="number"
                value={quantity}
                onChange={(e) => setQuantity(parseInt(e.target.value) || 1)}
                size="small"
                fullWidth
                InputLabelProps={{ style: { color: 'white' } }}
                InputProps={{ style: { color: 'white' } }}
              />
            </Grid>
            <Grid item xs={4}>
              <Button 
                variant="contained" 
                onClick={createAndConfirmOrder}
                size="large"
                sx={{ 
                  background: 'white', 
                  color: '#667eea',
                  '&:hover': { background: '#f5f5f5' }
                }}
              >
                🚀 Create & Confirm Order
              </Button>
            </Grid>
          </Grid>
        </CardContent>
      </Card>

      {/* Context Tabs */}
      <Tabs value={currentTab} onChange={(e, v) => setCurrentTab(v)} sx={{ mb: 2 }}>
        <Tab label="🛒 Order Context" />
        <Tab label="📦 Inventory Context" />
        <Tab label="🚚 Shipping Context" />
      </Tabs>

      {/* Order Context */}
      {currentTab === 0 && (
        <Card>
          <CardContent>
            <Typography variant="h5" gutterBottom color="#1976d2">
              Order Context (Aggregate Root)
            </Typography>
            <TableContainer component={Paper}>
              <Table>
                <TableHead>
                  <TableRow>
                    <TableCell>Order ID</TableCell>
                    <TableCell>Customer</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell>Items</TableCell>
                    <TableCell>Total</TableCell>
                    <TableCell>Created</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {orders.map(order => (
                    <TableRow key={order.order_id}>
                      <TableCell>{order.order_id.substring(0, 8)}</TableCell>
                      <TableCell>{order.customer_id}</TableCell>
                      <TableCell>
                        <Chip 
                          label={order.status} 
                          color={order.status === 'confirmed' ? 'success' : 'default'}
                          size="small"
                        />
                      </TableCell>
                      <TableCell>{order.item_count}</TableCell>
                      <TableCell>${order.total}</TableCell>
                      <TableCell>{new Date(order.created_at).toLocaleTimeString()}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          </CardContent>
        </Card>
      )}

      {/* Inventory Context */}
      {currentTab === 1 && (
        <Card>
          <CardContent>
            <Typography variant="h5" gutterBottom color="#388e3c">
              Inventory Context (Stock Management)
            </Typography>
            <TableContainer component={Paper}>
              <Table>
                <TableHead>
                  <TableRow>
                    <TableCell>Product ID</TableCell>
                    <TableCell>Name</TableCell>
                    <TableCell>Total Stock</TableCell>
                    <TableCell>Reserved</TableCell>
                    <TableCell>Available</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {products.map(product => (
                    <TableRow key={product.product_id}>
                      <TableCell>{product.product_id}</TableCell>
                      <TableCell>{product.name}</TableCell>
                      <TableCell>{product.stock_quantity}</TableCell>
                      <TableCell>
                        <Chip 
                          label={product.reserved_quantity}
                          color={product.reserved_quantity > 0 ? 'warning' : 'default'}
                          size="small"
                        />
                      </TableCell>
                      <TableCell>
                        <Chip 
                          label={product.available_quantity}
                          color={product.available_quantity > 0 ? 'success' : 'error'}
                          size="small"
                        />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          </CardContent>
        </Card>
      )}

      {/* Shipping Context */}
      {currentTab === 2 && (
        <Card>
          <CardContent>
            <Typography variant="h5" gutterBottom color="#f57c00">
              Shipping Context (Fulfillment)
            </Typography>
            <TableContainer component={Paper}>
              <Table>
                <TableHead>
                  <TableRow>
                    <TableCell>Shipment ID</TableCell>
                    <TableCell>Order ID</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell>Items</TableCell>
                    <TableCell>Est. Delivery</TableCell>
                    <TableCell>Created</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {shipments.map(shipment => (
                    <TableRow key={shipment.shipment_id}>
                      <TableCell>{shipment.shipment_id.substring(0, 8)}</TableCell>
                      <TableCell>{shipment.order_id.substring(0, 8)}</TableCell>
                      <TableCell>
                        <Chip 
                          label={shipment.status}
                          color="info"
                          size="small"
                        />
                      </TableCell>
                      <TableCell>{shipment.item_count}</TableCell>
                      <TableCell>{new Date(shipment.estimated_delivery).toLocaleDateString()}</TableCell>
                      <TableCell>{new Date(shipment.created_at).toLocaleTimeString()}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </TableContainer>
          </CardContent>
        </Card>
      )}

      <Typography variant="body2" sx={{ textAlign: 'center', mt: 4, color: '#888' }}>
        🔄 Data auto-refreshes every 2 seconds • Watch events flow between bounded contexts
      </Typography>
    </Container>
  );
}

export default App;

