import React, { useState, useEffect } from 'react';
import {
  Grid, Paper, Typography, Table, TableBody, TableCell, TableContainer,
  TableHead, TableRow, Button, TextField, Dialog, DialogTitle, DialogContent,
  DialogActions, Box, Chip, Alert
} from '@mui/material';
import { AccountBalance, TrendingUp, Security, Refresh } from '@mui/icons-material';
import axios from 'axios';

const AccountDashboard = () => {
  const [accounts, setAccounts] = useState([]);
  const [openDialog, setOpenDialog] = useState(false);
  const [newAccount, setNewAccount] = useState({ customer_name: '', initial_balance: 0 });
  const [loading, setLoading] = useState(false);
  const [alert, setAlert] = useState(null);

  const fetchAccounts = async () => {
    try {
      setLoading(true);
      const response = await axios.get('http://localhost:8001/accounts');
      setAccounts(response.data);
    } catch (error) {
      setAlert({ severity: 'error', message: 'Failed to fetch accounts' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchAccounts();
  }, []);

  const createAccount = async () => {
    try {
      await axios.post('http://localhost:8001/accounts', newAccount);
      setAlert({ severity: 'success', message: 'Account created successfully!' });
      setOpenDialog(false);
      setNewAccount({ customer_name: '', initial_balance: 0 });
      fetchAccounts();
    } catch (error) {
      setAlert({ severity: 'error', message: error.response?.data?.detail || 'Failed to create account' });
    }
  };

  const formatCurrency = (amount) => 
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);

  const formatDate = (dateString) => 
    new Date(dateString).toLocaleString();

  const getBalanceColor = (balance) => {
    if (balance > 5000) return 'success';
    if (balance > 1000) return 'warning';
    return 'error';
  };

  return (
    <Box>
      {alert && (
        <Alert severity={alert.severity} onClose={() => setAlert(null)} sx={{ mb: 2 }}>
          {alert.message}
        </Alert>
      )}
      
      <Grid container spacing={3} sx={{ mb: 3 }}>
        <Grid item xs={12} md={4}>
          <Paper 
            elevation={0}
            sx={{ 
              p: 3, 
              background: 'linear-gradient(135deg, #1e40af 0%, #3b82f6 100%)', 
              color: 'white',
              borderRadius: 3,
              boxShadow: '0px 4px 12px rgba(30, 64, 175, 0.2)',
              transition: 'transform 0.2s, box-shadow 0.2s',
              '&:hover': {
                transform: 'translateY(-2px)',
                boxShadow: '0px 6px 16px rgba(30, 64, 175, 0.3)',
              }
            }}
          >
            <Box display="flex" alignItems="center">
              <AccountBalance sx={{ fontSize: 48, mr: 2, opacity: 0.9 }} />
              <Box>
                <Typography variant="h4" sx={{ fontWeight: 700, mb: 0.5 }}>{accounts.length}</Typography>
                <Typography variant="body2" sx={{ opacity: 0.9, fontWeight: 500 }}>Total Accounts</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
        
        <Grid item xs={12} md={4}>
          <Paper 
            elevation={0}
            sx={{ 
              p: 3, 
              background: 'linear-gradient(135deg, #0f766e 0%, #14b8a6 100%)', 
              color: 'white',
              borderRadius: 3,
              boxShadow: '0px 4px 12px rgba(15, 118, 110, 0.2)',
              transition: 'transform 0.2s, box-shadow 0.2s',
              '&:hover': {
                transform: 'translateY(-2px)',
                boxShadow: '0px 6px 16px rgba(15, 118, 110, 0.3)',
              }
            }}
          >
            <Box display="flex" alignItems="center">
              <TrendingUp sx={{ fontSize: 48, mr: 2, opacity: 0.9 }} />
              <Box>
                <Typography variant="h4" sx={{ fontWeight: 700, mb: 0.5 }}>
                  {formatCurrency(accounts.reduce((sum, acc) => sum + parseFloat(acc.balance || 0), 0))}
                </Typography>
                <Typography variant="body2" sx={{ opacity: 0.9, fontWeight: 500 }}>Total Balance</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
        
        <Grid item xs={12} md={4}>
          <Paper 
            elevation={0}
            sx={{ 
              p: 3, 
              background: 'linear-gradient(135deg, #1e3a8a 0%, #1e40af 100%)', 
              color: 'white',
              borderRadius: 3,
              boxShadow: '0px 4px 12px rgba(30, 58, 138, 0.2)',
              transition: 'transform 0.2s, box-shadow 0.2s',
              '&:hover': {
                transform: 'translateY(-2px)',
                boxShadow: '0px 6px 16px rgba(30, 58, 138, 0.3)',
              }
            }}
          >
            <Box display="flex" alignItems="center">
              <Security sx={{ fontSize: 48, mr: 2, opacity: 0.9 }} />
              <Box>
                <Typography variant="h4" sx={{ fontWeight: 700, mb: 0.5 }}>ACID</Typography>
                <Typography variant="body2" sx={{ opacity: 0.9, fontWeight: 500 }}>Compliance Guaranteed</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
      </Grid>

      <Paper elevation={0} sx={{ p: 3, borderRadius: 3, backgroundColor: '#ffffff' }}>
        <Box display="flex" justifyContent="space-between" alignItems="center" sx={{ mb: 3 }}>
          <Typography variant="h5" component="h2" sx={{ fontWeight: 600, color: '#1e293b' }}>
            Account Management
          </Typography>
          <Box>
            <Button
              startIcon={<Refresh />}
              onClick={fetchAccounts}
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
                backgroundColor: '#1e40af',
                '&:hover': {
                  backgroundColor: '#1e3a8a',
                },
                boxShadow: '0px 2px 8px rgba(30, 64, 175, 0.3)',
                borderRadius: 2,
                px: 3
              }}
            >
              Create Account
            </Button>
          </Box>
        </Box>

        <TableContainer sx={{ borderRadius: 2, border: '1px solid #e2e8f0' }}>
          <Table>
            <TableHead>
              <TableRow sx={{ backgroundColor: '#f8fafc' }}>
                <TableCell sx={{ fontWeight: 600, color: '#1e293b', fontSize: '0.875rem' }}>
                  Account Number
                </TableCell>
                <TableCell sx={{ fontWeight: 600, color: '#1e293b', fontSize: '0.875rem' }}>
                  Customer Name
                </TableCell>
                <TableCell sx={{ fontWeight: 600, color: '#1e293b', fontSize: '0.875rem' }}>
                  Balance
                </TableCell>
                <TableCell sx={{ fontWeight: 600, color: '#1e293b', fontSize: '0.875rem' }}>
                  Status
                </TableCell>
                <TableCell sx={{ fontWeight: 600, color: '#1e293b', fontSize: '0.875rem' }}>
                  Created
                </TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {accounts.map((account) => (
                <TableRow 
                  key={account.id} 
                  hover
                  sx={{ 
                    '&:hover': {
                      backgroundColor: '#f8fafc',
                    },
                    '&:last-child td': {
                      borderBottom: 0
                    }
                  }}
                >
                  <TableCell sx={{ fontFamily: 'monospace', fontWeight: 600, color: '#1e40af' }}>
                    {account.account_number}
                  </TableCell>
                  <TableCell sx={{ color: '#1e293b', fontWeight: 500 }}>
                    {account.customer_name}
                  </TableCell>
                  <TableCell>
                    <Chip
                      label={formatCurrency(account.balance)}
                      color={getBalanceColor(parseFloat(account.balance))}
                      variant="outlined"
                      sx={{ 
                        fontWeight: 600,
                        borderWidth: 1.5,
                      }}
                    />
                  </TableCell>
                  <TableCell>
                    <Chip 
                      label={account.status}
                      color={account.status === 'ACTIVE' ? 'success' : 'default'}
                      size="small"
                      sx={{ 
                        fontWeight: 600,
                        borderRadius: 2
                      }}
                    />
                  </TableCell>
                  <TableCell sx={{ fontSize: '0.875rem', color: '#64748b' }}>
                    {formatDate(account.created_at)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>

      <Dialog open={openDialog} onClose={() => setOpenDialog(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Create New Account</DialogTitle>
        <DialogContent>
          <TextField
            autoFocus
            margin="dense"
            label="Customer Name"
            fullWidth
            variant="outlined"
            value={newAccount.customer_name}
            onChange={(e) => setNewAccount({...newAccount, customer_name: e.target.value})}
            sx={{ mb: 2 }}
          />
          <TextField
            margin="dense"
            label="Initial Balance"
            type="number"
            fullWidth
            variant="outlined"
            value={newAccount.initial_balance}
            onChange={(e) => setNewAccount({...newAccount, initial_balance: parseFloat(e.target.value) || 0})}
            inputProps={{ min: 0, step: 0.01 }}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setOpenDialog(false)}>Cancel</Button>
          <Button 
            onClick={createAccount} 
            variant="contained"
            disabled={!newAccount.customer_name}
          >
            Create Account
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};

export default AccountDashboard;
