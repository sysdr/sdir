import React, { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, BarChart, Bar } from 'recharts';

const CHAOS_CONTROLLER_URL = process.env.REACT_APP_CHAOS_CONTROLLER_URL || 'http://localhost:3004';

function App() {
  const [services, setServices] = useState({});
  const [experiments, setExperiments] = useState([]);
  const [metrics, setMetrics] = useState([]);
  const [testResults, setTestResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const wsRef = useRef(null);

  useEffect(() => {
    // Initial data fetch
    fetchServices();
    fetchExperiments();
    
    // Set up WebSocket connection
    const ws = new WebSocket(`ws://localhost:3004`);
    wsRef.current = ws;
    
    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      if (data.type === 'experiment-started' || data.type === 'experiment-stopped') {
        fetchExperiments();
        fetchServices();
      }
    };
    
    // Periodic refresh
    const interval = setInterval(() => {
      fetchServices();
      runHealthTest();
    }, 5000);
    
    return () => {
      clearInterval(interval);
      if (wsRef.current) {
        wsRef.current.close();
      }
    };
  }, []);

  const fetchServices = async () => {
    try {
      const response = await axios.get(`${CHAOS_CONTROLLER_URL}/services`);
      setServices(response.data);
    } catch (error) {
      console.error('Failed to fetch services:', error);
    }
  };

  const fetchExperiments = async () => {
    try {
      const response = await axios.get(`${CHAOS_CONTROLLER_URL}/chaos/experiments`);
      setExperiments(response.data);
    } catch (error) {
      console.error('Failed to fetch experiments:', error);
    }
  };

  const runHealthTest = async () => {
    try {
      const response = await axios.post(`${CHAOS_CONTROLLER_URL}/test/user/1`, { iterations: 1 });
      const result = response.data.results[0];
      const newMetric = {
        timestamp: new Date().toLocaleTimeString(),
        responseTime: result.success ? result.duration : 0,
        success: result.success,
        error: !result.success
      };
      
      setMetrics(prev => [...prev.slice(-19), newMetric]); // Keep last 20 points
    } catch (error) {
      console.error('Health test failed:', error);
    }
  };

  const startExperiment = async (experimentConfig) => {
    setLoading(true);
    try {
      await axios.post(`${CHAOS_CONTROLLER_URL}/chaos/start`, {
        ...experimentConfig,
        experimentId: `exp-${Date.now()}`
      });
    } catch (error) {
      console.error('Failed to start experiment:', error);
    } finally {
      setLoading(false);
    }
  };

  const runLoadTest = async () => {
    setLoading(true);
    try {
      const response = await axios.post(`${CHAOS_CONTROLLER_URL}/test/user/1`, { iterations: 10 });
      setTestResults(response.data.results);
    } catch (error) {
      console.error('Load test failed:', error);
    } finally {
      setLoading(false);
    }
  };

  const getServiceStatusColor = (status) => {
    return status === 'healthy' ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800';
  };

  const renderCircuitBreakers = (circuitBreakers) => {
    if (!circuitBreakers || typeof circuitBreakers !== 'object') {
      return null;
    }

    return (
      <div>
        <span className="font-medium">Circuit Breakers:</span>
        <div className="ml-2">
          {Object.entries(circuitBreakers).map(([cb, state]) => {
            // Handle both object format and string format
            const status = typeof state === 'object' ? (state.open ? 'open' : 'closed') : state;
            return (
              <div key={cb} className="flex justify-between">
                <span>{cb}:</span>
                <span className={status === 'open' ? 'text-red-600' : 'text-green-600'}>
                  {status}
                </span>
              </div>
            );
          })}
        </div>
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center">
              <h1 className="text-3xl font-bold text-gray-900">Resilience Testing Platform</h1>
              <span className="ml-3 px-3 py-1 text-sm font-medium bg-blue-100 text-blue-800 rounded-full">
                Production-Grade Chaos Engineering
              </span>
            </div>
            <div className="flex space-x-4">
              <button
                onClick={runLoadTest}
                disabled={loading}
                className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 disabled:opacity-50"
              >
                {loading ? 'Testing...' : 'Run Load Test'}
              </button>
            </div>
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Service Status Grid */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          {Object.entries(services).map(([name, service]) => (
            <div key={name} className="bg-white rounded-lg shadow p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-medium text-gray-900">{name}</h3>
                <span className={`px-2 py-1 text-xs font-medium rounded-full ${getServiceStatusColor(service.status)}`}>
                  {service.status}
                </span>
              </div>
              {service.data && (
                <div className="space-y-2 text-sm text-gray-600">
                  {service.data.circuitBreakers && renderCircuitBreakers(service.data.circuitBreakers)}
                  {service.data.cacheSize !== undefined && (
                    <div>Cache Size: {service.data.cacheSize}</div>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>

        {/* Chaos Experiments */}
        <div className="bg-white rounded-lg shadow mb-8">
          <div className="px-6 py-4 border-b border-gray-200">
            <h2 className="text-xl font-semibold text-gray-900">Chaos Experiments</h2>
          </div>
          <div className="p-6">
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
              <button
                onClick={() => startExperiment({
                  targetService: 'database-service',
                  type: 'latency',
                  parameters: { latencyMs: 1000 },
                  duration: 30
                })}
                disabled={loading}
                className="p-4 border border-yellow-300 rounded-lg hover:bg-yellow-50 disabled:opacity-50"
              >
                <div className="text-center">
                  <div className="text-lg font-medium text-yellow-800">Network Latency</div>
                  <div className="text-sm text-yellow-600">Add 1s delay to DB</div>
                </div>
              </button>
              
              <button
                onClick={() => startExperiment({
                  targetService: 'database-service',
                  type: 'errors',
                  parameters: { errorRate: 0.3 },
                  duration: 30
                })}
                disabled={loading}
                className="p-4 border border-red-300 rounded-lg hover:bg-red-50 disabled:opacity-50"
              >
                <div className="text-center">
                  <div className="text-lg font-medium text-red-800">Error Injection</div>
                  <div className="text-sm text-red-600">30% error rate</div>
                </div>
              </button>
              
              <button
                onClick={() => startExperiment({
                  targetService: 'database-service',
                  type: 'cpu',
                  parameters: {},
                  duration: 20
                })}
                disabled={loading}
                className="p-4 border border-orange-300 rounded-lg hover:bg-orange-50 disabled:opacity-50"
              >
                <div className="text-center">
                  <div className="text-lg font-medium text-orange-800">CPU Spike</div>
                  <div className="text-sm text-orange-600">High CPU load</div>
                </div>
              </button>
              
              <button
                onClick={() => startExperiment({
                  targetService: 'cache-service',
                  type: 'configure-cache',
                  parameters: { latencyMs: 500, errorRate: 0.2, enabled: true },
                  duration: 25
                })}
                disabled={loading}
                className="p-4 border border-purple-300 rounded-lg hover:bg-purple-50 disabled:opacity-50"
              >
                <div className="text-center">
                  <div className="text-lg font-medium text-purple-800">Cache Chaos</div>
                  <div className="text-sm text-purple-600">Multiple failures</div>
                </div>
              </button>
            </div>
            
            {experiments.length > 0 && (
              <div>
                <h3 className="text-lg font-medium text-gray-900 mb-3">Active Experiments</h3>
                <div className="space-y-2">
                  {experiments.map((exp) => (
                    <div key={exp.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg">
                      <div>
                        <span className="font-medium">{exp.targetService}</span>
                        <span className="ml-2 text-sm text-gray-600">- {exp.type}</span>
                      </div>
                      <span className="px-2 py-1 text-xs font-medium bg-yellow-100 text-yellow-800 rounded-full">
                        {exp.status}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Metrics and Charts */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          {/* Response Time Chart */}
          <div className="bg-white rounded-lg shadow">
            <div className="px-6 py-4 border-b border-gray-200">
              <h3 className="text-lg font-medium text-gray-900">Response Time Monitoring</h3>
            </div>
            <div className="p-6">
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={metrics}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="timestamp" />
                  <YAxis />
                  <Tooltip />
                  <Line type="monotone" dataKey="responseTime" stroke="#3b82f6" strokeWidth={2} />
                </LineChart>
              </ResponsiveContainer>
            </div>
          </div>

          {/* Test Results */}
          <div className="bg-white rounded-lg shadow">
            <div className="px-6 py-4 border-b border-gray-200">
              <h3 className="text-lg font-medium text-gray-900">Load Test Results</h3>
            </div>
            <div className="p-6">
              {testResults.length > 0 ? (
                <ResponsiveContainer width="100%" height={300}>
                  <BarChart data={testResults}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="iteration" />
                    <YAxis />
                    <Tooltip />
                    <Bar dataKey="duration" fill="#10b981" />
                  </BarChart>
                </ResponsiveContainer>
              ) : (
                <div className="text-center text-gray-500 py-12">
                  Click "Run Load Test" to see results
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
