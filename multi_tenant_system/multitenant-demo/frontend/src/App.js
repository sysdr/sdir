import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { Database, Users, ShoppingCart, Activity, Shield, BarChart3 } from 'lucide-react';
import TenantDashboard from './components/TenantDashboard';
import MetricsPanel from './components/MetricsPanel';
import IsolationTest from './components/IsolationTest';

const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:8080';

function App() {
  const [tenants, setTenants] = useState([]);
  const [selectedTenant, setSelectedTenant] = useState(null);
  const [activeTab, setActiveTab] = useState('overview');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchTenants();
  }, []);

  const fetchTenants = async () => {
    try {
      const response = await axios.get(`${API_BASE}/api/tenants`);
      setTenants(response.data);
      if (response.data.length > 0) {
        setSelectedTenant(response.data[0]);
      }
    } catch (error) {
      console.error('Error fetching tenants:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto"></div>
          <p className="mt-4 text-gray-600">Loading Multi-Tenant Dashboard...</p>
        </div>
      </div>
    );
  }

  const tabs = [
    { id: 'overview', label: 'Overview', icon: BarChart3 },
    { id: 'tenants', label: 'Tenant Management', icon: Database },
    { id: 'metrics', label: 'Performance Metrics', icon: Activity },
    { id: 'isolation', label: 'Isolation Testing', icon: Shield },
  ];

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      {/* Header */}
      <header className="bg-white shadow-lg border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center">
              <Database className="h-8 w-8 text-blue-600 mr-3" />
              <h1 className="text-2xl font-bold text-gray-900">Multi-Tenant Architecture Demo</h1>
            </div>
            <div className="flex items-center space-x-4">
              <div className="text-sm text-gray-500">
                Active Tenants: <span className="font-semibold text-blue-600">{tenants.length}</span>
              </div>
            </div>
          </div>
        </div>
      </header>

      {/* Navigation Tabs */}
      <nav className="bg-white border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex space-x-8">
            {tabs.map((tab) => {
              const Icon = tab.icon;
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center py-4 px-1 border-b-2 font-medium text-sm ${
                    activeTab === tab.id
                      ? 'border-blue-500 text-blue-600'
                      : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                  }`}
                >
                  <Icon className="h-5 w-5 mr-2" />
                  {tab.label}
                </button>
              );
            })}
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto py-6 px-4 sm:px-6 lg:px-8">
        {activeTab === 'overview' && (
          <div className="space-y-6">
            <div className="bg-white rounded-lg shadow p-6">
              <h2 className="text-xl font-semibold mb-4 flex items-center">
                <BarChart3 className="h-6 w-6 mr-2 text-blue-600" />
                Architecture Patterns Overview
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                {tenants.map((tenant) => (
                  <div key={tenant.id} className="border rounded-lg p-4 hover:shadow-md transition-shadow">
                    <h3 className="font-medium text-lg mb-2">{tenant.name}</h3>
                    <div className="text-sm text-gray-600 mb-3">
                      Pattern: <span className="font-mono bg-gray-100 px-2 py-1 rounded">
                        {tenant.isolation_pattern}
                      </span>
                    </div>
                    <button
                      onClick={() => {
                        setSelectedTenant(tenant);
                        setActiveTab('tenants');
                      }}
                      className="w-full bg-blue-600 text-white py-2 px-4 rounded hover:bg-blue-700 transition-colors"
                    >
                      Manage Tenant
                    </button>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {activeTab === 'tenants' && selectedTenant && (
          <TenantDashboard tenant={selectedTenant} />
        )}

        {activeTab === 'metrics' && (
          <MetricsPanel />
        )}

        {activeTab === 'isolation' && (
          <IsolationTest />
        )}
      </main>
    </div>
  );
}

export default App;
