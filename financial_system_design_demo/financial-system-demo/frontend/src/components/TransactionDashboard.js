import React, { useState, useEffect } from 'react';
import {
  Grid, Paper, Typography, Table, TableBody, TableCell, TableContainer,
  TableHead, TableRow, Button, TextField, Dialog, DialogTitle, DialogContent,
  DialogActions, Box, Chip, Alert, Select, MenuItem, FormControl, InputLabel,
  Stepper, Step, StepLabel, Card, CardContent
} from '@mui/material';
import { SwapHoriz, Timeline, CheckCircle, Error, Refresh } from '@mui/icons-material';
import axios from 'axios';

const TransactionDashboard = () => {
  const [transactions, setTransactions] = useState([]);
  const [accounts, setAccounts] = useState([]);
  const [openDialog, setOpenDialog] = useState(false);
  const [openSagaDialog, setOpenSagaDialog] = useState(false);
  const [selectedSaga, setSelectedSaga] = useState(null);
  const [newTransfer, setNewTransfer] = useState({
    from_account: '',
    to_account: '',
    amount: 0,
    description: ''
  });
  const [loading, setLoading] = useState(false);
  const [alert, setAlert] = useState(null);

  const fetchTransactions = async () => {
    try {
      setLoading(true);
      const response = await axios.get('http://localhost:8002/transactions');
      setTransactions(response.data);
    } catch (error) {
      setAlert({ severity: 'error', message: 'Failed to fetch transactions' });
    } finally {
      setLoading(false);
    }
  };

  const fetchAccounts = async () => {
    try {
      const response = await axios.get('http://localhost:8001/accounts');
      setAccounts(response.data);
    } catch (error) {
      console.error('Failed to fetch accounts:', error);
    }
  };

  useEffect(() => {
    fetchTransactions();
    fetchAccounts();
  }, []);

  const executeTransfer = async () => {
    try {
      const idempotencyKey = `transfer_${Date.now()}_${Math.random()}`;
      const response = await axios.post('http://localhost:8002/transactions/transfer', {
        ...newTransfer,
        idempotency_key: idempotencyKey
      });
      
      setAlert({ 
        severity: response.data.success ? 'success' : 'error', 
        message: response.data.message 
      });
      setOpenDialog(false);
      setNewTransfer({ from_account: '', to_account: '', amount: 0, description: '' });
      fetchTransactions();
    } catch (error) {
      setAlert({ 
        severity: 'error', 
        message: error.response?.data?.detail || 'Transfer failed' 
      });
    }
  };

  const viewSagaDetails = async (sagaId) => {
    try {
      const response = await axios.get(`http://localhost:8002/saga/${sagaId}/status`);
      setSelectedSaga(response.data);
      setOpenSagaDialog(true);
    } catch (error) {
      setAlert({ severity: 'error', message: 'Failed to fetch SAGA details' });
    }
  };

  const formatCurrency = (amount) => 
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);

  const formatDate = (dateString) => 
    new Date(dateString).toLocaleString();

  const getStatusColor = (status) => {
    switch (status) {
      case 'COMPLETED': return 'success';
      case 'PENDING': return 'warning';
      case 'FAILED': return 'error';
      default: return 'default';
    }
  };

  const getSagaStatusColor = (status) => {
    switch (status) {
      case 'COMPLETED': return 'success';
      case 'IN_PROGRESS': return 'info';
      case 'FAILED': return 'error';
      case 'COMPENSATING': return 'warning';
      case 'COMPENSATED': return 'secondary';
      default: return 'default';
    }
  };

  const getStepStatus = (step) => {
    switch (step.status) {
      case 'COMPLETED': return 'completed';
      case 'FAILED': return 'error';
      default: return 'active';
    }
  };

  const completedTransactions = transactions.filter(t => t.status === 'COMPLETED').length;
  const failedTransactions = transactions.filter(t => t.status === 'FAILED').length;
  const totalVolume = transactions
    .filter(t => t.status === 'COMPLETED')
    .reduce((sum, t) => sum + parseFloat(t.amount || 0), 0);

  return (
    <Box>
      {alert && (
        <Alert severity={alert.severity} onClose={() => setAlert(null)} sx={{ mb: 2 }}>
          {alert.message}
        </Alert>
      )}
      
      <Grid container spacing={3} sx={{ mb: 3 }}>
        <Grid item xs={12} md={3}>
          <Paper 
            elevation={0}
            sx={{ 
              p: 3, 
              background: 'linear-gradient(135deg, #10b981 0%, #34d399 100%)', 
              color: 'white',
              borderRadius: 3,
              boxShadow: '0px 4px 12px rgba(16, 185, 129, 0.2)',
              transition: 'transform 0.2s, box-shadow 0.2s',
              '&:hover': {
                transform: 'translateY(-2px)',
                boxShadow: '0px 6px 16px rgba(16, 185, 129, 0.3)',
              }
            }}
          >
            <Box display="flex" alignItems="center">
              <CheckCircle sx={{ fontSize: 48, mr: 2, opacity: 0.9 }} />
              <Box>
                <Typography variant="h4" sx={{ fontWeight: 700, mb: 0.5 }}>{completedTransactions}</Typography>
                <Typography variant="body2" sx={{ opacity: 0.9, fontWeight: 500 }}>Completed</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
        
        <Grid item xs={12} md={3}>
          <Paper 
            elevation={0}
            sx={{ 
              p: 3, 
              background: 'linear-gradient(135deg, #ef4444 0%, #f87171 100%)', 
              color: 'white',
              borderRadius: 3,
              boxShadow: '0px 4px 12px rgba(239, 68, 68, 0.2)',
              transition: 'transform 0.2s, box-shadow 0.2s',
              '&:hover': {
                transform: 'translateY(-2px)',
                boxShadow: '0px 6px 16px rgba(239, 68, 68, 0.3)',
              }
            }}
          >
            <Box display="flex" alignItems="center">
              <Error sx={{ fontSize: 48, mr: 2, opacity: 0.9 }} />
              <Box>
                <Typography variant="h4" sx={{ fontWeight: 700, mb: 0.5 }}>{failedTransactions}</Typography>
                <Typography variant="body2" sx={{ opacity: 0.9, fontWeight: 500 }}>Failed</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
        
        <Grid item xs={12} md={3}>
          <Paper 
            elevation={0}
            sx={{ 
              p: 3, 
              background: 'linear-gradient(135deg, #3b82f6 0%, #60a5fa 100%)', 
              color: 'white',
              borderRadius: 3,
              boxShadow: '0px 4px 12px rgba(59, 130, 246, 0.2)',
              transition: 'transform 0.2s, box-shadow 0.2s',
              '&:hover': {
                transform: 'translateY(-2px)',
                boxShadow: '0px 6px 16px rgba(59, 130, 246, 0.3)',
              }
            }}
          >
            <Box display="flex" alignItems="center">
              <SwapHoriz sx={{ fontSize: 48, mr: 2, opacity: 0.9 }} />
              <Box>
                <Typography variant="h4" sx={{ fontWeight: 700, mb: 0.5 }}>{formatCurrency(totalVolume)}</Typography>
                <Typography variant="body2" sx={{ opacity: 0.9, fontWeight: 500 }}>Volume</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
        
        <Grid item xs={12} md={3}>
          <Paper 
            elevation={0}
            sx={{ 
              p: 3, 
              background: 'linear-gradient(135deg, #14b8a6 0%, #2dd4bf 100%)', 
              color: 'white',
              borderRadius: 3,
              boxShadow: '0px 4px 12px rgba(20, 184, 166, 0.2)',
              transition: 'transform 0.2s, box-shadow 0.2s',
              '&:hover': {
                transform: 'translateY(-2px)',
                boxShadow: '0px 6px 16px rgba(20, 184, 166, 0.3)',
              }
            }}
          >
            <Box display="flex" alignItems="center">
              <Timeline sx={{ fontSize: 48, mr: 2, opacity: 0.9 }} />
              <Box>
                <Typography variant="h4" sx={{ fontWeight: 700, mb: 0.5 }}>SAGA</Typography>
                <Typography variant="body2" sx={{ opacity: 0.9, fontWeight: 500 }}>Pattern Active</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
      </Grid>

      <Paper elevation={0} sx={{ p: 3, borderRadius: 3, backgroundColor: '#ffffff' }}>
        <Box display="flex" justifyContent="space-between" alignItems="center" sx={{ mb: 3 }}>
          <Typography variant="h5" component="h2" sx={{ fontWeight: 600, color: '#1e293b' }}>
            Transaction History
          </Typography>
          <Box>
            <Button
              startIcon={<Refresh />}
              onClick={fetchTransactions}
              disabled={loading}
              sx={{ 
                mr: 1.5,
                color: '#64748b',
                '&:hover': {
                  backgroundColor: '#f1f5f9',
                }
              }}
            >
              Refresh
            </Button>
            <Button
              variant="contained"
              onClick={() => setOpenDialog(true)}
              sx={{ 
                backgroundColor: '#10b981',
                '&:hover': {
                  backgroundColor: '#059669',
                },
                boxShadow: '0px 2px 8px rgba(16, 185, 129, 0.3)',
                borderRadius: 2,
                px: 3
              }}
            >
              New Transfer
            </Button>
          </Box>
        </Box>

        <TableContainer>
          <Table>
            <TableHead>
              <TableRow>
                <TableCell><strong>Transaction ID</strong></TableCell>
                <TableCell><strong>From → To</strong></TableCell>
                <TableCell><strong>Amount</strong></TableCell>
                <TableCell><strong>Status</strong></TableCell>
                <TableCell><strong>SAGA</strong></TableCell>
                <TableCell><strong>Created</strong></TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {transactions.map((transaction) => (
                <TableRow key={transaction.transaction_id} hover>
                  <TableCell sx={{ fontFamily: 'monospace', fontSize: '0.875rem' }}>
                    {transaction.transaction_id}
                  </TableCell>
                  <TableCell>
                    <Box display="flex" alignItems="center">
                      <Typography variant="body2" sx={{ fontWeight: 'bold' }}>
                        {transaction.from_account}
                      </Typography>
                      <SwapHoriz sx={{ mx: 1, color: 'primary.main' }} />
                      <Typography variant="body2" sx={{ fontWeight: 'bold' }}>
                        {transaction.to_account}
                      </Typography>
                    </Box>
                  </TableCell>
                  <TableCell>
                    <Typography variant="body1" sx={{ fontWeight: 'bold' }}>
                      {formatCurrency(transaction.amount)}
                    </Typography>
                  </TableCell>
                  <TableCell>
                    <Chip
                      label={transaction.status}
                      color={getStatusColor(transaction.status)}
                      size="small"
                    />
                  </TableCell>
                  <TableCell>
                    {transaction.saga_id && (
                      <Button
                        size="small"
                        onClick={() => viewSagaDetails(transaction.saga_id)}
                        sx={{ textTransform: 'none' }}
                      >
                        View SAGA
                      </Button>
                    )}
                  </TableCell>
                  <TableCell sx={{ fontSize: '0.875rem', color: 'text.secondary' }}>
                    {formatDate(transaction.created_at)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>

      {/* New Transfer Dialog */}
      <Dialog open={openDialog} onClose={() => setOpenDialog(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Execute Money Transfer (SAGA Pattern)</DialogTitle>
        <DialogContent>
          <FormControl fullWidth margin="dense" sx={{ mb: 2 }}>
            <InputLabel>From Account</InputLabel>
            <Select
              value={newTransfer.from_account}
              onChange={(e) => setNewTransfer({...newTransfer, from_account: e.target.value})}
            >
              {accounts.map((account) => (
                <MenuItem key={account.id} value={account.account_number}>
                  {account.account_number} - {account.customer_name} ({formatCurrency(account.balance)})
                </MenuItem>
              ))}
            </Select>
          </FormControl>
          
          <FormControl fullWidth margin="dense" sx={{ mb: 2 }}>
            <InputLabel>To Account</InputLabel>
            <Select
              value={newTransfer.to_account}
              onChange={(e) => setNewTransfer({...newTransfer, to_account: e.target.value})}
            >
              {accounts.map((account) => (
                <MenuItem key={account.id} value={account.account_number}>
                  {account.account_number} - {account.customer_name} ({formatCurrency(account.balance)})
                </MenuItem>
              ))}
            </Select>
          </FormControl>
          
          <TextField
            margin="dense"
            label="Amount"
            type="number"
            fullWidth
            variant="outlined"
            value={newTransfer.amount}
            onChange={(e) => setNewTransfer({...newTransfer, amount: parseFloat(e.target.value) || 0})}
            inputProps={{ min: 0.01, step: 0.01 }}
            sx={{ mb: 2 }}
          />
          
          <TextField
            margin="dense"
            label="Description"
            fullWidth
            variant="outlined"
            value={newTransfer.description}
            onChange={(e) => setNewTransfer({...newTransfer, description: e.target.value})}
            multiline
            rows={2}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenDialog(false)}>Cancel</Button>
          <Button 
            onClick={executeTransfer} 
            variant="contained"
            disabled={!newTransfer.from_account || !newTransfer.to_account || newTransfer.amount <= 0}
          >
            Execute Transfer
          </Button>
        </DialogActions>
      </Dialog>

      {/* SAGA Details Dialog */}
      <Dialog open={openSagaDialog} onClose={() => setOpenSagaDialog(false)} maxWidth="md" fullWidth>
        <DialogTitle>
          <Box display="flex" justifyContent="space-between" alignItems="center">
            <Typography variant="h6">SAGA Transaction Details</Typography>
            {selectedSaga && (
              <Chip 
                label={selectedSaga.status}
                color={getSagaStatusColor(selectedSaga.status)}
              />
            )}
          </Box>
        </DialogTitle>
        <DialogContent>
          {selectedSaga && (
            <Box>
              <Card sx={{ mb: 2 }}>
                <CardContent>
                  <Typography variant="subtitle1" gutterBottom>
                    <strong>SAGA ID:</strong> {selectedSaga.saga_id}
                  </Typography>
                  <Typography variant="body2" color="text.secondary">
                    Progress: {selectedSaga.current_step} / {selectedSaga.total_steps} steps
                  </Typography>
                </CardContent>
              </Card>

              <Typography variant="h6" gutterBottom>Execution Steps:</Typography>
              <Stepper orientation="vertical">
                {Object.entries(selectedSaga.steps || {}).map(([stepNum, step]) => (
                  <Step key={stepNum} active={step.status !== 'PENDING'} completed={step.status === 'COMPLETED'}>
                    <StepLabel 
                      error={step.status === 'FAILED'}
                      StepIconProps={{
                        color: getStepStatus(step) === 'error' ? 'error' : 
                               getStepStatus(step) === 'completed' ? 'primary' : 'inherit'
                      }}
                    >
                      <Box>
                        <Typography variant="body1">
                          Step {parseInt(stepNum) + 1}: {step.action}
                        </Typography>
                        <Typography variant="body2" color="text.secondary">
                          Service: {step.service_name}
                        </Typography>
                        <Typography variant="body2" color="text.secondary">
                          Status: {step.status}
                        </Typography>
                      </Box>
                    </StepLabel>
                  </Step>
                ))}
              </Stepper>
            </Box>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenSagaDialog(false)}>Close</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default TransactionDashboard;
