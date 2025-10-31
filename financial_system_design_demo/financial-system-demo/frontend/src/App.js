import React, { useState, useEffect } from 'react';
import {
  Container,
  Typography,
  Box,
  Paper,
  Tab,
  Tabs,
  Alert,
  ThemeProvider,
  CssBaseline
} from '@mui/material';
import AccountDashboard from './components/AccountDashboard';
import TransactionDashboard from './components/TransactionDashboard';
import AuditDashboard from './components/AuditDashboard';
import theme from './theme';

function App() {
  const [currentTab, setCurrentTab] = useState(0);
  const [systemHealth, setSystemHealth] = useState({
    account: false,
    transaction: false,
    audit: false
  });

  useEffect(() => {
    const checkHealth = async () => {
      try {
        const services = ['account-service:8001', 'transaction-service:8002', 'audit-service:8003'];
        const healthChecks = await Promise.allSettled(
          services.map(service => fetch(`http://localhost:${service.split(':')[1]}/health`))
        );
        
        setSystemHealth({
          account: healthChecks[0].status === 'fulfilled',
          transaction: healthChecks[1].status === 'fulfilled',
          audit: healthChecks[2].status === 'fulfilled'
        });
      } catch (error) {
        console.log('Health check failed:', error);
      }
    };

    checkHealth();
    const interval = setInterval(checkHealth, 30000);
    return () => clearInterval(interval);
  }, []);

  const handleTabChange = (event, newValue) => {
    setCurrentTab(newValue);
  };

  const TabPanel = ({ children, value, index }) => (
    <div hidden={value !== index}>
      {value === index && <Box sx={{ p: 3 }}>{children}</Box>}
    </div>
  );

  return (
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <Box sx={{ 
        minHeight: '100vh',
        background: 'linear-gradient(135deg, #f8fafc 0%, #e2e8f0 100%)',
        pb: 4
      }}>
        <Container maxWidth="xl" sx={{ pt: 3 }}>
          <Paper 
            elevation={0} 
            sx={{ 
              p: 4, 
              mb: 3, 
              background: 'linear-gradient(135deg, #1e40af 0%, #1e3a8a 100%)',
              color: 'white',
              borderRadius: 3,
              boxShadow: '0px 10px 25px rgba(30, 64, 175, 0.3)'
            }}
          >
            <Typography variant="h3" component="h1" gutterBottom sx={{ fontWeight: 700 }}>
              🏦 Financial System Design Demo
            </Typography>
            <Typography variant="h6" sx={{ color: 'rgba(255,255,255,0.9)', fontWeight: 400, mb: 2 }}>
              ACID Properties & Distributed Transactions Showcase
            </Typography>
            
            <Box sx={{ mt: 3, display: 'flex', gap: 2, flexWrap: 'wrap' }}>
              {Object.entries(systemHealth).map(([service, healthy]) => (
                <Alert 
                  key={service}
                  severity={healthy ? 'success' : 'error'}
                  variant="outlined"
                  sx={{ 
                    color: 'white', 
                    borderColor: 'rgba(255,255,255,0.3)',
                    backgroundColor: healthy ? 'rgba(16, 185, 129, 0.1)' : 'rgba(239, 68, 68, 0.1)',
                    fontWeight: 600,
                    borderRadius: 2
                  }}
                >
                  {service.toUpperCase().replace('-', ' ')}: {healthy ? 'HEALTHY' : 'DOWN'}
                </Alert>
              ))}
            </Box>
          </Paper>

          <Paper elevation={0} sx={{ borderRadius: 3, overflow: 'hidden', boxShadow: '0px 4px 12px rgba(0, 0, 0, 0.08)' }}>
            <Tabs 
              value={currentTab} 
              onChange={handleTabChange}
              variant="fullWidth"
              sx={{
                backgroundColor: '#ffffff',
                borderBottom: '2px solid #e2e8f0',
                '& .MuiTab-root': {
                  minHeight: 72,
                  fontSize: '1rem',
                  fontWeight: 600,
                  color: '#64748b',
                  textTransform: 'none',
                  '&.Mui-selected': {
                    color: '#1e40af',
                  },
                },
                '& .MuiTabs-indicator': {
                  height: 3,
                  backgroundColor: '#1e40af',
                },
              }}
            >
              <Tab label="🏧 Account Management" />
              <Tab label="💰 Transactions & SAGA" />
              <Tab label="📋 Audit & Compliance" />
            </Tabs>

            <Box sx={{ backgroundColor: '#ffffff' }}>
              <TabPanel value={currentTab} index={0}>
                <AccountDashboard />
              </TabPanel>
              
              <TabPanel value={currentTab} index={1}>
                <TransactionDashboard />
              </TabPanel>
              
              <TabPanel value={currentTab} index={2}>
                <AuditDashboard />
              </TabPanel>
            </Box>
          </Paper>
        </Container>
      </Box>
    </ThemeProvider>
  );
}

export default App;
