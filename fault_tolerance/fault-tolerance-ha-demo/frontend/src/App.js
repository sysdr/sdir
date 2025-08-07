import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer, BarChart, Bar } from 'recharts';
import { Activity, Server, Zap, Shield, AlertTriangle, CheckCircle, XCircle } from 'lucide-react';
import './App.css';

const Dashboard = () => {
  const [metrics, setMetrics] = useState({
    payment: { status: 'unknown', circuitState: 'CLOSED', retryCount: 0, lastResponse: null },
    userServices: [
      { id: 'user-1', status: 'unknown', responseTime: 0 },
      { id: 'user-2', status: 'unknown', responseTime: 0 },
      { id: 'user-3', status: 'unknown', responseTime: 0 }
    ],
    requestHistory: []
  });

  const [isTestRunning, setIsTestRunning] = useState(false);

  useEffect(() => {
    const interval = setInterval(fetchMetrics, 2000);
    return () => clearInterval(interval);
  }, []);

  const fetchMetrics = async () => {
    try {
      const response = await axios.get('http://localhost:8080/api/metrics');
      setMetrics(response.data);
    } catch (error) {
      console.error('Failed to fetch metrics:', error);
    }
  };

  const testPaymentFaultTolerance = async () => {
    setIsTestRunning(true);
    try {
      await axios.post('http://localhost:8080/api/test/payment-failure');
    } catch (error) {
      console.error('Test failed:', error);
    }
    setIsTestRunning(false);
  };

  const testUserServiceHA = async () => {
    setIsTestRunning(true);
    try {
      await axios.post('http://localhost:8080/api/test/user-service-failure');
    } catch (error) {
      console.error('Test failed:', error);
    }
    setIsTestRunning(false);
  };

  const resetSystem = async () => {
    try {
      await axios.post('http://localhost:8080/api/reset');
    } catch (error) {
      console.error('Reset failed:', error);
    }
  };

  const verifyAllMetrics = async () => {
    setIsTestRunning(true);
    const results = {
      payment: { success: false, details: '' },
      userServices: { success: false, details: '' },
      loadBalancer: { success: false, details: '' },
      faultTolerance: { success: false, details: '' },
      metrics: { success: false, details: '' }
    };

    try {
      // 1. Test Payment Service
      console.log('🔍 Verifying Payment Service...');
      const paymentResponse = await axios.post('http://localhost:8080/api/payment', {
        amount: 100
      }, { timeout: 10000 });
      
      if (paymentResponse.data.success) {
        results.payment.success = true;
        results.payment.details = 'Payment processed successfully';
      }

      // 2. Test User Services Load Balancing
      console.log('🔍 Verifying User Services Load Balancing...');
      const userResponses = [];
      for (let i = 0; i < 3; i++) {
        const userResponse = await axios.get('http://localhost:8080/api/users', { timeout: 5000 });
        userResponses.push(userResponse.data.servedBy);
      }
      
      const uniqueInstances = [...new Set(userResponses)];
      if (uniqueInstances.length >= 2) {
        results.userServices.success = true;
        results.loadBalancer.success = true;
        results.userServices.details = `Load balanced across ${uniqueInstances.length} instances: ${uniqueInstances.join(', ')}`;
        results.loadBalancer.details = 'Load balancer distributing requests correctly';
      }

      // 3. Test Fault Tolerance
      console.log('🔍 Verifying Fault Tolerance...');
      await axios.post('http://localhost:8080/api/test/payment-failure');
      
      const faultToleranceResponse = await axios.post('http://localhost:8080/api/payment', {
        amount: 50
      }, { timeout: 10000 });
      
      if (faultToleranceResponse.data.fallback) {
        results.faultTolerance.success = true;
        results.faultTolerance.details = 'Circuit breaker working with fallback response';
      }

      // 4. Test High Availability
      console.log('🔍 Verifying High Availability...');
      await axios.post('http://localhost:8080/api/test/user-service-failure');
      
      const haResponses = [];
      for (let i = 0; i < 5; i++) {
        const haResponse = await axios.get('http://localhost:8080/api/users', { timeout: 5000 });
        haResponses.push(haResponse.data.servedBy);
      }
      
      const successfulRequests = haResponses.filter(instance => instance !== null).length;
      if (successfulRequests >= 4) {
        results.faultTolerance.success = true;
        results.faultTolerance.details += ' | High availability working with failover';
      }

      // 5. Test Metrics Collection
      console.log('🔍 Verifying Metrics Collection...');
      const metricsResponse = await axios.get('http://localhost:8080/api/metrics');
      const metrics = metricsResponse.data;
      
      if (metrics.payment && metrics.userServices && metrics.requestHistory) {
        results.metrics.success = true;
        results.metrics.details = 'All metrics being collected and updated';
      }

      // Reset system after testing
      await axios.post('http://localhost:8080/api/reset');
      
      // Display results
      const allPassed = Object.values(results).every(r => r.success);
      if (allPassed) {
        alert('✅ All verifications passed!\n\n' + 
              Object.entries(results).map(([key, result]) => 
                `${key}: ${result.details}`
              ).join('\n'));
      } else {
        const failed = Object.entries(results).filter(([key, result]) => !result.success);
        alert('❌ Some verifications failed:\n\n' + 
              failed.map(([key, result]) => 
                `${key}: ${result.details || 'Failed'}`
              ).join('\n'));
      }

    } catch (error) {
      console.error('Verification failed:', error);
      alert('❌ Verification failed: ' + error.message);
    } finally {
      setIsTestRunning(false);
    }
  };

  const getStatusIcon = (status) => {
    switch (status) {
      case 'healthy': return <CheckCircle className="w-5 h-5 text-green-500" />;
      case 'degraded': return <AlertTriangle className="w-5 h-5 text-yellow-500" />;
      case 'failed': return <XCircle className="w-5 h-5 text-red-500" />;
      default: return <Activity className="w-5 h-5 text-gray-400" />;
    }
  };

  const getCircuitColor = (state) => {
    switch (state) {
      case 'CLOSED': return 'bg-green-500';
      case 'HALF_OPEN': return 'bg-yellow-500';
      case 'OPEN': return 'bg-red-500';
      default: return 'bg-gray-400';
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-3">
              <Shield className="w-8 h-8 text-blue-600" />
              <div>
                <h1 className="text-2xl font-bold text-gray-900">Fault Tolerance vs High Availability</h1>
                <p className="text-sm text-gray-600">Real-time System Resilience Demo</p>
              </div>
            </div>
            <div className="flex space-x-2">
              <button
                onClick={verifyAllMetrics}
                disabled={isTestRunning}
                className="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 disabled:opacity-50 flex items-center space-x-2"
              >
                <CheckCircle className="w-4 h-4" />
                <span>Verify All</span>
              </button>
              <button
                onClick={testPaymentFaultTolerance}
                disabled={isTestRunning}
                className="px-4 py-2 bg-yellow-600 text-white rounded-lg hover:bg-yellow-700 disabled:opacity-50"
              >
                Test Fault Tolerance
              </button>
              <button
                onClick={testUserServiceHA}
                disabled={isTestRunning}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
              >
                Test High Availability
              </button>
              <button
                onClick={resetSystem}
                className="px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700"
              >
                Reset System
              </button>
            </div>
          </div>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-4 py-8">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          
          {/* Fault Tolerance Section */}
          <div className="bg-white rounded-xl shadow-lg p-6">
            <div className="flex items-center space-x-3 mb-6">
              <Zap className="w-6 h-6 text-yellow-600" />
              <h2 className="text-xl font-bold text-gray-900">Fault Tolerance</h2>
              <span className="text-sm text-gray-500">Payment Service</span>
            </div>
            
            {/* Payment Service Status */}
            <div className="space-y-4">
              <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                <div className="flex items-center space-x-3">
                  {getStatusIcon(metrics.payment.status)}
                  <span className="font-medium">Payment Service</span>
                </div>
                <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                  metrics.payment.status === 'healthy' ? 'bg-green-100 text-green-800' :
                  metrics.payment.status === 'degraded' ? 'bg-yellow-100 text-yellow-800' :
                  'bg-red-100 text-red-800'
                }`}>
                  {metrics.payment.status}
                </span>
              </div>
              
              {/* Circuit Breaker State */}
              <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                <div className="flex items-center space-x-3">
                  <div className={`w-3 h-3 rounded-full ${getCircuitColor(metrics.payment.circuitState)}`}></div>
                  <span className="font-medium">Circuit Breaker</span>
                </div>
                <span className="text-sm font-medium">{metrics.payment.circuitState}</span>
              </div>
              
              {/* Retry Counter */}
              <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                <span className="font-medium">Retry Attempts</span>
                <span className="text-lg font-bold text-blue-600">{metrics.payment.retryCount}</span>
              </div>
            </div>
            
            <div className="mt-6">
              <h3 className="font-semibold mb-3">Mechanisms Active</h3>
              <div className="space-y-2 text-sm">
                <div className="flex items-center space-x-2">
                  <CheckCircle className="w-4 h-4 text-green-500" />
                  <span>Circuit Breaker Pattern</span>
                </div>
                <div className="flex items-center space-x-2">
                  <CheckCircle className="w-4 h-4 text-green-500" />
                  <span>Exponential Backoff Retry</span>
                </div>
                <div className="flex items-center space-x-2">
                  <CheckCircle className="w-4 h-4 text-green-500" />
                  <span>Graceful Degradation</span>
                </div>
              </div>
            </div>
          </div>

          {/* High Availability Section */}
          <div className="bg-white rounded-xl shadow-lg p-6">
            <div className="flex items-center space-x-3 mb-6">
              <Server className="w-6 h-6 text-blue-600" />
              <h2 className="text-xl font-bold text-gray-900">High Availability</h2>
              <span className="text-sm text-gray-500">User Services</span>
            </div>
            
            {/* Service Instances */}
            <div className="space-y-3">
              {metrics.userServices.map((service, index) => (
                <div key={service.id} className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
                  <div className="flex items-center space-x-3">
                    {getStatusIcon(service.status)}
                    <span className="font-medium">{service.id}</span>
                  </div>
                  <div className="text-right">
                    <div className="text-sm text-gray-600">{service.responseTime}ms</div>
                    <div className={`text-xs px-2 py-1 rounded-full ${
                      service.status === 'healthy' ? 'bg-green-100 text-green-800' :
                      'bg-red-100 text-red-800'
                    }`}>
                      {service.status}
                    </div>
                  </div>
                </div>
              ))}
            </div>
            
            <div className="mt-6">
              <h3 className="font-semibold mb-3">HA Mechanisms</h3>
              <div className="space-y-2 text-sm">
                <div className="flex items-center space-x-2">
                  <CheckCircle className="w-4 h-4 text-green-500" />
                  <span>Load Balancer Health Checks</span>
                </div>
                <div className="flex items-center space-x-2">
                  <CheckCircle className="w-4 h-4 text-green-500" />
                  <span>Automatic Failover</span>
                </div>
                <div className="flex items-center space-x-2">
                  <CheckCircle className="w-4 h-4 text-green-500" />
                  <span>Redundant Instances</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Request History Chart */}
        <div className="mt-8 bg-white rounded-xl shadow-lg p-6">
          <h3 className="text-lg font-bold mb-4">Request History</h3>
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={metrics.requestHistory}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="time" />
              <YAxis />
              <Tooltip />
              <Legend />
              <Line type="monotone" dataKey="successRate" stroke="#10b981" strokeWidth={2} name="Success Rate %" />
              <Line type="monotone" dataKey="responseTime" stroke="#3b82f6" strokeWidth={2} name="Response Time (ms)" />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  );
};

export default Dashboard;
