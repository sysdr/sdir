import React, { useState, useEffect } from 'react';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, PieChart, Pie, Cell } from 'recharts';
import axios from 'axios';

function Analytics() {
  const [analytics, setAnalytics] = useState({
    totalRunbooks: [],
    totalExecutions: [],
    executionsByStatus: [],
    runbooksByCategory: []
  });

  useEffect(() => {
    fetchAnalytics();
  }, []);

  const fetchAnalytics = async () => {
    try {
      const response = await axios.get('http://localhost:3001/api/analytics');
      setAnalytics(response.data);
    } catch (error) {
      console.error('Failed to fetch analytics:', error);
    }
  };

  const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884d8'];

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-lg shadow-md p-6">
        <h1 className="text-3xl font-bold text-gray-800 mb-2">
          Runbook Analytics
        </h1>
        <p className="text-gray-600">
          Track runbook usage, effectiveness, and operational metrics
        </p>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <div className="bg-white rounded-lg shadow-md p-6">
          <div className="flex items-center">
            <div className="p-3 bg-blue-100 rounded-full">
              <span className="text-2xl">📚</span>
            </div>
            <div className="ml-4">
              <p className="text-sm text-gray-600">Total Runbooks</p>
              <p className="text-2xl font-bold text-gray-800">
                {analytics.totalRunbooks[0]?.count || 0}
              </p>
            </div>
          </div>
        </div>
        
        <div className="bg-white rounded-lg shadow-md p-6">
          <div className="flex items-center">
            <div className="p-3 bg-green-100 rounded-full">
              <span className="text-2xl">⚡</span>
            </div>
            <div className="ml-4">
              <p className="text-sm text-gray-600">Total Executions</p>
              <p className="text-2xl font-bold text-gray-800">
                {analytics.totalExecutions[0]?.count || 0}
              </p>
            </div>
          </div>
        </div>
        
        <div className="bg-white rounded-lg shadow-md p-6">
          <div className="flex items-center">
            <div className="p-3 bg-yellow-100 rounded-full">
              <span className="text-2xl">📊</span>
            </div>
            <div className="ml-4">
              <p className="text-sm text-gray-600">Success Rate</p>
              <p className="text-2xl font-bold text-gray-800">94.2%</p>
            </div>
          </div>
        </div>
        
        <div className="bg-white rounded-lg shadow-md p-6">
          <div className="flex items-center">
            <div className="p-3 bg-purple-100 rounded-full">
              <span className="text-2xl">⏱️</span>
            </div>
            <div className="ml-4">
              <p className="text-sm text-gray-600">Avg Resolution Time</p>
              <p className="text-2xl font-bold text-gray-800">12.5m</p>
            </div>
          </div>
        </div>
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Runbooks by Category */}
        <div className="bg-white rounded-lg shadow-md p-6">
          <h2 className="text-xl font-bold text-gray-800 mb-4">Runbooks by Category</h2>
          <ResponsiveContainer width="100%" height={300}>
            <PieChart>
              <Pie
                data={analytics.runbooksByCategory}
                cx="50%"
                cy="50%"
                labelLine={false}
                label={({ category, value }) => `${category}: ${value}`}
                outerRadius={80}
                fill="#8884d8"
                dataKey="count"
              >
                {analytics.runbooksByCategory.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
                ))}
              </Pie>
              <Tooltip />
            </PieChart>
          </ResponsiveContainer>
        </div>

        {/* Execution Status */}
        <div className="bg-white rounded-lg shadow-md p-6">
          <h2 className="text-xl font-bold text-gray-800 mb-4">Execution Status</h2>
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={analytics.executionsByStatus}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="status" />
              <YAxis />
              <Tooltip />
              <Bar dataKey="count" fill="#8884d8" />
            </BarChart>
          </ResponsiveContainer>
        </div>
      </div>

      {/* Performance Metrics */}
      <div className="bg-white rounded-lg shadow-md p-6">
        <h2 className="text-xl font-bold text-gray-800 mb-4">Performance Insights</h2>
        
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          <div className="text-center p-4 bg-green-50 rounded-lg">
            <h3 className="text-lg font-semibold text-green-800">Most Used</h3>
            <p className="text-2xl font-bold text-green-600">Database Recovery</p>
            <p className="text-sm text-green-600">45% of executions</p>
          </div>
          
          <div className="text-center p-4 bg-blue-50 rounded-lg">
            <h3 className="text-lg font-semibold text-blue-800">Fastest Resolution</h3>
            <p className="text-2xl font-bold text-blue-600">API Gateway Fix</p>
            <p className="text-sm text-blue-600">Avg 8.2 minutes</p>
          </div>
          
          <div className="text-center p-4 bg-purple-50 rounded-lg">
            <h3 className="text-lg font-semibold text-purple-800">Most Reliable</h3>
            <p className="text-2xl font-bold text-purple-600">Service Restart</p>
            <p className="text-sm text-purple-600">100% success rate</p>
          </div>
        </div>
      </div>

      {/* Recommendations */}
      <div className="bg-white rounded-lg shadow-md p-6">
        <h2 className="text-xl font-bold text-gray-800 mb-4">Recommendations</h2>
        
        <div className="space-y-4">
          <div className="flex items-start space-x-3 p-4 bg-yellow-50 rounded-lg">
            <span className="text-xl">💡</span>
            <div>
              <h3 className="font-semibold text-yellow-800">Create Missing Runbook</h3>
              <p className="text-yellow-700">
                Consider creating a runbook for "SSL Certificate Renewal" - this incident type appeared 3 times without a standardized procedure.
              </p>
            </div>
          </div>
          
          <div className="flex items-start space-x-3 p-4 bg-blue-50 rounded-lg">
            <span className="text-xl">🔧</span>
            <div>
              <h3 className="font-semibold text-blue-800">Optimize High-Usage Runbook</h3>
              <p className="text-blue-700">
                "Database Recovery" runbook has high usage. Consider adding automation scripts to reduce manual steps.
              </p>
            </div>
          </div>
          
          <div className="flex items-start space-x-3 p-4 bg-green-50 rounded-lg">
            <span className="text-xl">📈</span>
            <div>
              <h3 className="font-semibold text-green-800">Training Opportunity</h3>
              <p className="text-green-700">
                Team members are executing runbooks successfully. Consider advanced training on runbook automation.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default Analytics;
