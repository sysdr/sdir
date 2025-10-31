import React, { useState, useEffect } from 'react';
import {
  Grid, Paper, Typography, Table, TableBody, TableCell, TableContainer,
  TableHead, TableRow, Box, Chip, Alert, TextField, Button, FormControl,
  InputLabel, Select, MenuItem, Card, CardContent, LinearProgress
} from '@mui/material';
import { Security, Verified, Warning, Search, Assessment } from '@mui/icons-material';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import axios from 'axios';

const AuditDashboard = () => {
  const [auditLogs, setAuditLogs] = useState([]);
  const [statistics, setStatistics] = useState(null);
  const [integrityStatus, setIntegrityStatus] = useState(null);
  const [filters, setFilters] = useState({
    entity_type: '',
    event_type: '',
    hours_back: 24
  });
  const [loading, setLoading] = useState(false);
  const [alert, setAlert] = useState(null);

  const fetchAuditLogs = async () => {
    try {
      setLoading(true);
      const params = new URLSearchParams();
      Object.entries(filters).forEach(([key, value]) => {
        if (value) params.append(key, value);
      });
      
      const response = await axios.get(`http://localhost:8003/audit/logs?${params}`);
      setAuditLogs(response.data.logs);
    } catch (error) {
      setAlert({ severity: 'error', message: 'Failed to fetch audit logs' });
    } finally {
      setLoading(false);
    }
  };

  const fetchStatistics = async () => {
    try {
      const response = await axios.get('http://localhost:8003/audit/statistics');
      setStatistics(response.data);
    } catch (error) {
      console.error('Failed to fetch statistics:', error);
    }
  };

  const checkIntegrity = async () => {
    try {
      const response = await axios.get('http://localhost:8003/audit/integrity/verify');
      setIntegrityStatus(response.data);
    } catch (error) {
      setAlert({ severity: 'error', message: 'Failed to verify integrity' });
    }
  };

  useEffect(() => {
    fetchAuditLogs();
    fetchStatistics();
    checkIntegrity();
  }, []);

  const formatDate = (dateString) => 
    new Date(dateString).toLocaleString();

  const getIntegrityColor = (verified) => verified ? 'success' : 'error';

  const pieChartColors = ['#667eea', '#764ba2', '#f093fb', '#f5576c', '#4facfe'];

  return (
    <Box>
      {alert && (
        <Alert severity={alert.severity} onClose={() => setAlert(null)} sx={{ mb: 2 }}>
          {alert.message}
        </Alert>
      )}
      
      {/* Statistics Cards */}
      <Grid container spacing={3} sx={{ mb: 3 }}>
        <Grid item xs={12} md={3}>
          <Paper sx={{ p: 2, background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)', color: 'white' }}>
            <Box display="flex" alignItems="center">
              <Assessment sx={{ fontSize: 40, mr: 2 }} />
              <Box>
                <Typography variant="h4">{statistics?.overview?.total_logs || 0}</Typography>
                <Typography variant="body2">Total Audit Logs</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
        
        <Grid item xs={12} md={3}>
          <Paper sx={{ p: 2, background: 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)', color: 'white' }}>
            <Box display="flex" alignItems="center">
              <Security sx={{ fontSize: 40, mr: 2 }} />
              <Box>
                <Typography variant="h4">{statistics?.overview?.unique_entity_types || 0}</Typography>
                <Typography variant="body2">Entity Types</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
        
        <Grid item xs={12} md={3}>
          <Paper sx={{ p: 2, background: 'linear-gradient(135deg, #4facfe 0%, #00f2fe 100%)', color: 'white' }}>
            <Box display="flex" alignItems="center">
              <Verified sx={{ fontSize: 40, mr: 2 }} />
              <Box>
                <Typography variant="h4">
                  {integrityStatus ? `${integrityStatus.integrity_percentage.toFixed(1)}%` : 'N/A'}
                </Typography>
                <Typography variant="body2">Integrity Score</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
        
        <Grid item xs={12} md={3}>
          <Paper sx={{ p: 2, background: 'linear-gradient(135deg, #fa709a 0%, #fee140 100%)', color: 'white' }}>
            <Box display="flex" alignItems="center">
              <Warning sx={{ fontSize: 40, mr: 2 }} />
              <Box>
                <Typography variant="h4">{integrityStatus?.corrupted_records_count || 0}</Typography>
                <Typography variant="body2">Integrity Issues</Typography>
              </Box>
            </Box>
          </Paper>
        </Grid>
      </Grid>

      {/* Charts */}
      <Grid container spacing={3} sx={{ mb: 3 }}>
        <Grid item xs={12} md={6}>
          <Paper sx={{ p: 2 }}>
            <Typography variant="h6" gutterBottom>Event Type Distribution</Typography>
            <ResponsiveContainer width="100%" height={300}>
              <BarChart data={statistics?.event_type_distribution || []}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="event_type" angle={-45} textAnchor="end" height={100} />
                <YAxis />
                <Tooltip />
                <Bar dataKey="count" fill="#667eea" />
              </BarChart>
            </ResponsiveContainer>
          </Paper>
        </Grid>
        
        <Grid item xs={12} md={6}>
          <Paper sx={{ p: 2 }}>
            <Typography variant="h6" gutterBottom>Entity Type Distribution</Typography>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie
                  data={statistics?.entity_type_distribution || []}
                  cx="50%"
                  cy="50%"
                  outerRadius={80}
                  fill="#8884d8"
                  dataKey="count"
                  label={({ entity_type, count }) => `${entity_type}: ${count}`}
                >
                  {(statistics?.entity_type_distribution || []).map((entry, index) => (
                    <Cell key={`cell-${index}`} fill={pieChartColors[index % pieChartColors.length]} />
                  ))}
                </Pie>
                <Tooltip />
              </PieChart>
            </ResponsiveContainer>
          </Paper>
        </Grid>
      </Grid>

      {/* Integrity Status */}
      {integrityStatus && (
        <Card sx={{ mb: 3, border: integrityStatus.corrupted_records_count > 0 ? '2px solid #ff6b6b' : '2px solid #11998e' }}>
          <CardContent>
            <Typography variant="h6" gutterBottom>
              Audit Trail Integrity Status
            </Typography>
            <Box sx={{ mb: 2 }}>
              <Box display="flex" justifyContent="space-between" alignItems="center" sx={{ mb: 1 }}>
                <Typography variant="body2">
                  Verified: {integrityStatus.verified_records} / {integrityStatus.total_records_checked}
                </Typography>
                <Typography variant="body2" color={integrityStatus.corrupted_records_count > 0 ? 'error' : 'success'}>
                  {integrityStatus.integrity_percentage.toFixed(2)}%
                </Typography>
              </Box>
              <LinearProgress 
                variant="determinate" 
                value={integrityStatus.integrity_percentage} 
                color={integrityStatus.corrupted_records_count > 0 ? 'error' : 'success'}
              />
            </Box>
            {integrityStatus.corrupted_records_count > 0 && (
              <Alert severity="warning" sx={{ mt: 2 }}>
                <strong>{integrityStatus.corrupted_records_count} corrupted records detected!</strong>
                <br />
                Immediate investigation required for compliance.
              </Alert>
            )}
          </CardContent>
        </Card>
      )}

      {/* Filters */}
      <Paper sx={{ p: 2, mb: 3 }}>
        <Typography variant="h6" gutterBottom>Audit Log Filters</Typography>
        <Grid container spacing={2} alignItems="center">
          <Grid item xs={12} md={3}>
            <FormControl fullWidth>
              <InputLabel>Entity Type</InputLabel>
              <Select
                value={filters.entity_type}
                onChange={(e) => setFilters({...filters, entity_type: e.target.value})}
              >
                <MenuItem value="">All</MenuItem>
                <MenuItem value="account">Account</MenuItem>
                <MenuItem value="transaction">Transaction</MenuItem>
              </Select>
            </FormControl>
          </Grid>
          <Grid item xs={12} md={3}>
            <FormControl fullWidth>
              <InputLabel>Event Type</InputLabel>
              <Select
                value={filters.event_type}
                onChange={(e) => setFilters({...filters, event_type: e.target.value})}
              >
                <MenuItem value="">All</MenuItem>
                <MenuItem value="ACCOUNT_CREATED">Account Created</MenuItem>
                <MenuItem value="BALANCE_DEBIT">Balance Debit</MenuItem>
                <MenuItem value="BALANCE_CREDIT">Balance Credit</MenuItem>
              </Select>
            </FormControl>
          </Grid>
          <Grid item xs={12} md={2}>
            <TextField
              fullWidth
              label="Hours Back"
              type="number"
              value={filters.hours_back}
              onChange={(e) => setFilters({...filters, hours_back: parseInt(e.target.value) || 24})}
              inputProps={{ min: 1, max: 168 }}
            />
          </Grid>
          <Grid item xs={12} md={2}>
            <Button
              fullWidth
              variant="contained"
              onClick={fetchAuditLogs}
              startIcon={<Search />}
              disabled={loading}
            >
              Search
            </Button>
          </Grid>
          <Grid item xs={12} md={2}>
            <Button
              fullWidth
              variant="outlined"
              onClick={checkIntegrity}
            >
              Check Integrity
            </Button>
          </Grid>
        </Grid>
      </Paper>

      {/* Audit Logs Table */}
      <Paper sx={{ p: 2 }}>
        <Typography variant="h5" component="h2" gutterBottom>
          Audit Trail ({auditLogs.length} records)
        </Typography>
        
        <TableContainer sx={{ maxHeight: 600 }}>
          <Table stickyHeader>
            <TableHead>
              <TableRow>
                <TableCell><strong>Timestamp</strong></TableCell>
                <TableCell><strong>Event Type</strong></TableCell>
                <TableCell><strong>Entity</strong></TableCell>
                <TableCell><strong>Entity ID</strong></TableCell>
                <TableCell><strong>Changes</strong></TableCell>
                <TableCell><strong>Integrity</strong></TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {auditLogs.map((log) => (
                <TableRow key={log.id} hover>
                  <TableCell sx={{ fontSize: '0.875rem' }}>
                    {formatDate(log.timestamp)}
                  </TableCell>
                  <TableCell>
                    <Chip
                      label={log.event_type}
                      size="small"
                      sx={{ fontSize: '0.75rem' }}
                    />
                  </TableCell>
                  <TableCell>
                    <Chip
                      label={log.entity_type}
                      variant="outlined"
                      size="small"
                    />
                  </TableCell>
                  <TableCell sx={{ fontFamily: 'monospace', fontSize: '0.75rem' }}>
                    {log.entity_id}
                  </TableCell>
                  <TableCell>
                    <Box sx={{ maxWidth: 200 }}>
                      {log.old_data && (
                        <Typography variant="caption" display="block" color="text.secondary">
                          Old: {JSON.stringify(log.old_data).substring(0, 50)}...
                        </Typography>
                      )}
                      {log.new_data && (
                        <Typography variant="caption" display="block">
                          New: {JSON.stringify(log.new_data).substring(0, 50)}...
                        </Typography>
                      )}
                    </Box>
                  </TableCell>
                  <TableCell>
                    <Chip
                      label={log.integrity_verified ? 'VERIFIED' : 'CORRUPTED'}
                      color={getIntegrityColor(log.integrity_verified)}
                      size="small"
                      variant={log.integrity_verified ? 'outlined' : 'filled'}
                    />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </TableContainer>
      </Paper>
    </Box>
  );
};

export default AuditDashboard;
