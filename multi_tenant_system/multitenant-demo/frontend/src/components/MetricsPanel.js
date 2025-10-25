import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { Activity, TrendingUp, Clock, AlertTriangle } from 'lucide-react';

const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:8080';

const MetricsPanel = () => {
  const [metrics, setMetrics] = useState({});
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchMetrics();
    const interval = setInterval(fetchMetrics, 5000); // Refresh every 5 seconds
    return () => clearInterval(interval);
  }, []);

  const fetchMetrics = async () => {
    try {
      const response = await axios.get(`${API_BASE}/api/metrics`);
      setMetrics(response.data);
    } catch (error) {
      console.error('Error fetching metrics:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-lg shadow p-6">
        <h2 className="text-xl font-semibold mb-4 flex items-center">
          <Activity className="h-6 w-6 mr-2 text-blue-600" />
          Performance Metrics
        </h2>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          <div className="bg-blue-50 rounded-lg p-4">
            <div className="flex items-center">
              <TrendingUp className="h-8 w-8 text-blue-600 mr-3" />
              <div>
                <p className="text-sm font-medium text-gray-500">Total Requests</p>
                <p className="text-2xl font-semibold text-gray-900">
                  {Object.values(metrics.requests_per_tenant || {}).reduce((a, b) => a + b, 0)}
                </p>
              </div>
            </div>
          </div>

          <div className="bg-green-50 rounded-lg p-4">
            <div className="flex items-center">
              <Clock className="h-8 w-8 text-green-600 mr-3" />
              <div>
                <p className="text-sm font-medium text-gray-500">Avg Response Time</p>
                <p className="text-2xl font-semibold text-gray-900">
                  {Object.values(metrics.avg_response_times || {}).length > 0 ? 
                    Math.round(Object.values(metrics.avg_response_times || {}).reduce((a, b) => a + b, 0) / 
                    Object.values(metrics.avg_response_times || {}).length) : 0}ms
                </p>
              </div>
            </div>
          </div>

          <div className="bg-yellow-50 rounded-lg p-4">
            <div className="flex items-center">
              <AlertTriangle className="h-8 w-8 text-yellow-600 mr-3" />
              <div>
                <p className="text-sm font-medium text-gray-500">Users Created</p>
                <p className="text-2xl font-semibold text-gray-900">
                  {Object.values(metrics.users_created_per_tenant || {}).reduce((a, b) => a + b, 0)}
                </p>
              </div>
            </div>
          </div>

          <div className="bg-purple-50 rounded-lg p-4">
            <div className="flex items-center">
              <Activity className="h-8 w-8 text-purple-600 mr-3" />
              <div>
                <p className="text-sm font-medium text-gray-500">Orders Created</p>
                <p className="text-2xl font-semibold text-gray-900">
                  {Object.values(metrics.orders_created_per_tenant || {}).reduce((a, b) => a + b, 0)}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div>
            <h3 className="font-medium mb-3">Requests per Tenant</h3>
            <div className="space-y-2">
              {Object.entries(metrics.requests_per_tenant || {}).map(([tenantId, count]) => (
                <div key={tenantId} className="flex items-center justify-between p-3 bg-gray-50 rounded">
                  <span className="text-sm font-mono">{tenantId.substring(0, 8)}...</span>
                  <span className="font-semibold">{count}</span>
                </div>
              ))}
            </div>
          </div>

          <div>
            <h3 className="font-medium mb-3">Average Response Times</h3>
            <div className="space-y-2">
              {Object.entries(metrics.avg_response_times || {}).map(([tenantId, avgTime]) => (
                <div key={tenantId} className="flex items-center justify-between p-3 bg-gray-50 rounded">
                  <span className="text-sm font-mono">{tenantId.substring(0, 8)}...</span>
                  <span className="font-semibold">{Math.round(avgTime)}ms</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MetricsPanel;
