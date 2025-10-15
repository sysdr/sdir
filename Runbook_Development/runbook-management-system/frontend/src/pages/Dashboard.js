import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import axios from 'axios';

function Dashboard() {
  const [stats, setStats] = useState({
    totalRunbooks: 0,
    totalExecutions: 0,
    recentRunbooks: [],
    recentExecutions: []
  });

  useEffect(() => {
    fetchDashboardData();
  }, []);

  const fetchDashboardData = async () => {
    try {
      const [runbooksRes, analyticsRes] = await Promise.all([
        axios.get('http://localhost:3001/api/runbooks'),
        axios.get('http://localhost:3001/api/analytics')
      ]);
      
      setStats({
        totalRunbooks: analyticsRes.data.totalRunbooks[0]?.count || 0,
        totalExecutions: analyticsRes.data.totalExecutions[0]?.count || 0,
        recentRunbooks: runbooksRes.data.slice(0, 3),
        recentExecutions: []
      });
    } catch (error) {
      console.error('Failed to fetch dashboard data:', error);
    }
  };

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-lg shadow-md p-6">
        <h1 className="text-3xl font-bold text-gray-800 mb-2">
          Runbook Management Dashboard
        </h1>
        <p className="text-gray-600">
          Standardize and streamline your operational procedures
        </p>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-white rounded-lg shadow-md p-6">
          <div className="flex items-center">
            <div className="p-3 bg-blue-100 rounded-full">
              <span className="text-2xl">📚</span>
            </div>
            <div className="ml-4">
              <p className="text-sm text-gray-600">Total Runbooks</p>
              <p className="text-2xl font-bold text-gray-800">{stats.totalRunbooks}</p>
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
              <p className="text-2xl font-bold text-gray-800">{stats.totalExecutions}</p>
            </div>
          </div>
        </div>
        
        <div className="bg-white rounded-lg shadow-md p-6">
          <div className="flex items-center">
            <div className="p-3 bg-purple-100 rounded-full">
              <span className="text-2xl">🎯</span>
            </div>
            <div className="ml-4">
              <p className="text-sm text-gray-600">Success Rate</p>
              <p className="text-2xl font-bold text-gray-800">94%</p>
            </div>
          </div>
        </div>
      </div>

      {/* Recent Runbooks */}
      <div className="bg-white rounded-lg shadow-md p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-bold text-gray-800">Recent Runbooks</h2>
          <Link to="/runbooks" className="text-blue-600 hover:text-blue-800">
            View all →
          </Link>
        </div>
        
        <div className="space-y-3">
          {stats.recentRunbooks.map((runbook) => (
            <div key={runbook.id} className="border-l-4 border-blue-500 pl-4 py-2">
              <Link to={`/runbooks/${runbook.id}`} className="block">
                <h3 className="font-semibold text-gray-800 hover:text-blue-600">
                  {runbook.title}
                </h3>
                <p className="text-sm text-gray-600">{runbook.description}</p>
                <div className="flex items-center space-x-4 mt-2 text-xs text-gray-500">
                  <span className={`px-2 py-1 rounded-full ${
                    runbook.severity === 'High' ? 'bg-red-100 text-red-800' :
                    runbook.severity === 'Medium' ? 'bg-yellow-100 text-yellow-800' :
                    'bg-green-100 text-green-800'
                  }`}>
                    {runbook.severity}
                  </span>
                  <span>{runbook.category}</span>
                  <span>~{runbook.estimated_time} min</span>
                </div>
              </Link>
            </div>
          ))}
        </div>
      </div>

      {/* Quick Actions */}
      <div className="bg-white rounded-lg shadow-md p-6">
        <h2 className="text-xl font-bold text-gray-800 mb-4">Quick Actions</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <Link 
            to="/create" 
            className="flex items-center p-4 border border-gray-200 rounded-lg hover:bg-gray-50"
          >
            <span className="text-2xl mr-3">➕</span>
            <div>
              <h3 className="font-semibold">Create New Runbook</h3>
              <p className="text-sm text-gray-600">Build a new operational procedure</p>
            </div>
          </Link>
          
          <Link 
            to="/analytics" 
            className="flex items-center p-4 border border-gray-200 rounded-lg hover:bg-gray-50"
          >
            <span className="text-2xl mr-3">📊</span>
            <div>
              <h3 className="font-semibold">View Analytics</h3>
              <p className="text-sm text-gray-600">Analyze runbook performance</p>
            </div>
          </Link>
        </div>
      </div>
    </div>
  );
}

export default Dashboard;
