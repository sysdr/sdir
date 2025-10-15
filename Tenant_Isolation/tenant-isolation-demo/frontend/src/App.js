import React, { useState, useEffect } from 'react';
import axios from 'axios';

// Tenant API keys for demo
const DEMO_TENANTS = {
  'acme-corp': 'acme-key-123',
  'startup-inc': 'startup-key-456',
  'enterprise-ltd': 'enterprise-key-789'
};

function App() {
  const [selectedTenant, setSelectedTenant] = useState('acme-corp');
  const [tenantInfo, setTenantInfo] = useState(null);
  const [tasks, setTasks] = useState([]);
  const [metrics, setMetrics] = useState(null);
  const [newTask, setNewTask] = useState({ title: '', description: '' });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const api = axios.create({
    baseURL: process.env.REACT_APP_API_URL || 'http://localhost:3001',
    headers: {
      'X-API-Key': DEMO_TENANTS[selectedTenant]
    }
  });

  const fetchData = async () => {
    try {
      setLoading(true);
      setError('');
      
      // Update API key for selected tenant
      api.defaults.headers['X-API-Key'] = DEMO_TENANTS[selectedTenant];
      
      const [tenantRes, tasksRes, metricsRes] = await Promise.all([
        api.get('/api/tenant'),
        api.get('/api/tasks'),
        api.get('/api/metrics')
      ]);
      
      setTenantInfo(tenantRes.data);
      setTasks(tasksRes.data);
      setMetrics(metricsRes.data);
    } catch (err) {
      setError(`Failed to load data: ${err.response?.data?.error || err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const createTask = async (e) => {
    e.preventDefault();
    try {
      await api.post('/api/tasks', newTask);
      setNewTask({ title: '', description: '' });
      fetchData();
    } catch (err) {
      setError(`Failed to create task: ${err.response?.data?.error || err.message}`);
    }
  };

  const updateTaskStatus = async (taskId, status) => {
    try {
      const task = tasks.find(t => t.id === taskId);
      await api.put(`/api/tasks/${taskId}`, { ...task, status });
      fetchData();
    } catch (err) {
      setError(`Failed to update task: ${err.response?.data?.error || err.message}`);
    }
  };

  const deleteTask = async (taskId) => {
    try {
      await api.delete(`/api/tasks/${taskId}`);
      fetchData();
    } catch (err) {
      setError(`Failed to delete task: ${err.response?.data?.error || err.message}`);
    }
  };

  const testRateLimit = async () => {
    try {
      const promises = Array(10).fill().map(() => api.get('/api/metrics'));
      await Promise.all(promises);
      fetchData();
    } catch (err) {
      setError(`Rate limit test: ${err.response?.data?.error || err.message}`);
    }
  };

  useEffect(() => {
    fetchData();
  }, [selectedTenant]);

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      {/* Header */}
      <div className="bg-white shadow-lg">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between py-6">
            <div className="flex items-center">
              <h1 className="text-3xl font-bold text-gray-900">Multi-Tenant Task Manager</h1>
              <span className="ml-4 px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm font-medium">
                Tenant Isolation Demo
              </span>
            </div>
            
            {/* Tenant Selector */}
            <div className="flex items-center space-x-4">
              <label className="text-sm font-medium text-gray-700">Switch Tenant:</label>
              <select
                value={selectedTenant}
                onChange={(e) => setSelectedTenant(e.target.value)}
                className="px-4 py-2 border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
              >
                <option value="acme-corp">ACME Corp</option>
                <option value="startup-inc">Startup Inc</option>
                <option value="enterprise-ltd">Enterprise Ltd</option>
              </select>
            </div>
          </div>
        </div>
      </div>

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Error Message */}
        {error && (
          <div className="mb-6 bg-red-50 border border-red-200 rounded-md p-4">
            <div className="flex">
              <div className="ml-3">
                <h3 className="text-sm font-medium text-red-800">Error</h3>
                <div className="mt-2 text-sm text-red-700">{error}</div>
              </div>
            </div>
          </div>
        )}

        {/* Tenant Info & Metrics */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          <div className="glass-effect rounded-lg p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-2">Tenant Info</h3>
            {tenantInfo && (
              <div className="space-y-2">
                <p className="text-sm text-gray-600">Name: <span className="font-medium">{tenantInfo.name}</span></p>
                <p className="text-sm text-gray-600">ID: <span className="font-mono text-xs">{tenantInfo.id}</span></p>
              </div>
            )}
          </div>

          <div className="glass-effect rounded-lg p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-2">Rate Limits</h3>
            {metrics && (
              <div className="space-y-2">
                <p className="text-sm text-gray-600">Limit: <span className="font-medium">{metrics.rate_limit}/15min</span></p>
                <p className="text-sm text-gray-600">Used: <span className="font-medium">{metrics.current_rate_usage}</span></p>
                <div className="w-full bg-gray-200 rounded-full h-2">
                  <div 
                    className="bg-blue-600 h-2 rounded-full" 
                    style={{ width: `${(metrics.current_rate_usage / metrics.rate_limit) * 100}%` }}
                  ></div>
                </div>
              </div>
            )}
          </div>

          <div className="glass-effect rounded-lg p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-2">Resource Usage</h3>
            {metrics && (
              <div className="space-y-2">
                <p className="text-sm text-gray-600">Tasks: <span className="font-medium">{metrics.tasks_count}</span></p>
                <p className="text-sm text-gray-600">Users: <span className="font-medium">{metrics.users_count}</span></p>
                <p className="text-sm text-gray-600">Isolation: <span className="font-medium text-green-600">{metrics.isolation_status}</span></p>
              </div>
            )}
          </div>

          <div className="glass-effect rounded-lg p-6">
            <h3 className="text-lg font-semibold text-gray-900 mb-2">Actions</h3>
            <div className="space-y-2">
              <button
                onClick={fetchData}
                disabled={loading}
                className="w-full px-3 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50 text-sm"
              >
                {loading ? 'Loading...' : 'Refresh Data'}
              </button>
              <button
                onClick={testRateLimit}
                className="w-full px-3 py-2 bg-orange-600 text-white rounded-md hover:bg-orange-700 text-sm"
              >
                Test Rate Limit
              </button>
            </div>
          </div>
        </div>

        {/* Create Task Form */}
        <div className="glass-effect rounded-lg p-6 mb-8">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Create New Task</h3>
          <form onSubmit={createTask} className="space-y-4">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <input
                type="text"
                placeholder="Task title"
                value={newTask.title}
                onChange={(e) => setNewTask({ ...newTask, title: e.target.value })}
                className="px-4 py-2 border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
                required
              />
              <input
                type="text"
                placeholder="Task description"
                value={newTask.description}
                onChange={(e) => setNewTask({ ...newTask, description: e.target.value })}
                className="px-4 py-2 border border-gray-300 rounded-md focus:ring-blue-500 focus:border-blue-500"
              />
            </div>
            <button
              type="submit"
              className="px-6 py-2 bg-green-600 text-white rounded-md hover:bg-green-700"
            >
              Create Task
            </button>
          </form>
        </div>

        {/* Tasks List */}
        <div className="glass-effect rounded-lg p-6">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Tasks (Tenant Isolated)</h3>
          <div className="space-y-4">
            {tasks.map((task) => (
              <div key={task.id} className="border border-gray-200 rounded-lg p-4 bg-white">
                <div className="flex items-center justify-between">
                  <div className="flex-1">
                    <h4 className="font-medium text-gray-900">{task.title}</h4>
                    <p className="text-sm text-gray-600">{task.description}</p>
                    <p className="text-xs text-gray-500 mt-1">
                      Created by: {task.user_name} ({task.user_email})
                    </p>
                  </div>
                  
                  <div className="flex items-center space-x-2">
                    <select
                      value={task.status}
                      onChange={(e) => updateTaskStatus(task.id, e.target.value)}
                      className="px-3 py-1 border border-gray-300 rounded text-sm"
                    >
                      <option value="pending">Pending</option>
                      <option value="in-progress">In Progress</option>
                      <option value="completed">Completed</option>
                    </select>
                    
                    <button
                      onClick={() => deleteTask(task.id)}
                      className="px-3 py-1 bg-red-600 text-white rounded text-sm hover:bg-red-700"
                    >
                      Delete
                    </button>
                  </div>
                </div>
              </div>
            ))}
            
            {tasks.length === 0 && (
              <p className="text-gray-500 text-center py-8">No tasks found for this tenant</p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
