import React, { useState, useEffect } from 'react';
import axios from 'axios';
import { Users, ShoppingCart, Plus, Trash2 } from 'lucide-react';

const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:8080';

const TenantDashboard = ({ tenant }) => {
  const [users, setUsers] = useState([]);
  const [orders, setOrders] = useState([]);
  const [stats, setStats] = useState({});
  const [loading, setLoading] = useState(true);
  const [showUserForm, setShowUserForm] = useState(false);
  const [showOrderForm, setShowOrderForm] = useState(false);
  const [newUser, setNewUser] = useState({ username: '', email: '' });
  const [newOrder, setNewOrder] = useState({ user_id: '', product_name: '', amount: '' });

  useEffect(() => {
    if (tenant) {
      fetchTenantData();
    }
  }, [tenant]);

  const fetchTenantData = async () => {
    setLoading(true);
    try {
      const [usersRes, ordersRes, statsRes] = await Promise.all([
        axios.get(`${API_BASE}/api/users`, { headers: { 'X-Tenant-ID': tenant.id } }),
        axios.get(`${API_BASE}/api/orders`, { headers: { 'X-Tenant-ID': tenant.id } }),
        axios.get(`${API_BASE}/api/tenants/${tenant.id}/stats`)
      ]);

      setUsers(usersRes.data);
      setOrders(ordersRes.data);
      setStats(statsRes.data);
    } catch (error) {
      console.error('Error fetching tenant data:', error);
    } finally {
      setLoading(false);
    }
  };

  const createUser = async () => {
    try {
      await axios.post(`${API_BASE}/api/users`, newUser, {
        headers: { 'X-Tenant-ID': tenant.id }
      });
      setNewUser({ username: '', email: '' });
      setShowUserForm(false);
      fetchTenantData();
    } catch (error) {
      console.error('Error creating user:', error);
    }
  };

  const createOrder = async () => {
    try {
      await axios.post(`${API_BASE}/api/orders`, {
        ...newOrder,
        amount: parseFloat(newOrder.amount)
      }, {
        headers: { 'X-Tenant-ID': tenant.id }
      });
      setNewOrder({ user_id: '', product_name: '', amount: '' });
      setShowOrderForm(false);
      fetchTenantData();
    } catch (error) {
      console.error('Error creating order:', error);
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
      {/* Tenant Header */}
      <div className="bg-white rounded-lg shadow p-6">
        <h2 className="text-2xl font-bold mb-2">{tenant.name}</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-blue-50 rounded-lg p-4">
            <div className="flex items-center">
              <Users className="h-8 w-8 text-blue-600 mr-3" />
              <div>
                <p className="text-sm font-medium text-gray-500">Total Users</p>
                <p className="text-2xl font-semibold text-gray-900">{stats.userCount || 0}</p>
              </div>
            </div>
          </div>
          <div className="bg-green-50 rounded-lg p-4">
            <div className="flex items-center">
              <ShoppingCart className="h-8 w-8 text-green-600 mr-3" />
              <div>
                <p className="text-sm font-medium text-gray-500">Total Orders</p>
                <p className="text-2xl font-semibold text-gray-900">{stats.orderCount || 0}</p>
              </div>
            </div>
          </div>
          <div className="bg-purple-50 rounded-lg p-4">
            <div>
              <p className="text-sm font-medium text-gray-500">Isolation Pattern</p>
              <p className="text-lg font-semibold text-gray-900 font-mono">{stats.isolationPattern}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Users Management */}
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-lg font-semibold flex items-center">
            <Users className="h-5 w-5 mr-2 text-blue-600" />
            Users
          </h3>
          <button
            onClick={() => setShowUserForm(true)}
            className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 transition-colors flex items-center"
          >
            <Plus className="h-4 w-4 mr-1" />
            Add User
          </button>
        </div>

        {showUserForm && (
          <div className="mb-4 p-4 bg-gray-50 rounded-lg">
            <h4 className="font-medium mb-3">Create New User</h4>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <input
                type="text"
                placeholder="Username"
                value={newUser.username}
                onChange={(e) => setNewUser({ ...newUser, username: e.target.value })}
                className="border rounded px-3 py-2"
              />
              <input
                type="email"
                placeholder="Email"
                value={newUser.email}
                onChange={(e) => setNewUser({ ...newUser, email: e.target.value })}
                className="border rounded px-3 py-2"
              />
            </div>
            <div className="mt-3 flex gap-2">
              <button
                onClick={createUser}
                className="bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700"
              >
                Create User
              </button>
              <button
                onClick={() => setShowUserForm(false)}
                className="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600"
              >
                Cancel
              </button>
            </div>
          </div>
        )}

        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Username</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Email</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Created</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {users.map((user) => (
                <tr key={user.id}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{user.username}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{user.email}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {new Date(user.created_at).toLocaleDateString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Orders Management */}
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex justify-between items-center mb-4">
          <h3 className="text-lg font-semibold flex items-center">
            <ShoppingCart className="h-5 w-5 mr-2 text-green-600" />
            Orders
          </h3>
          <button
            onClick={() => setShowOrderForm(true)}
            className="bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700 transition-colors flex items-center"
          >
            <Plus className="h-4 w-4 mr-1" />
            Add Order
          </button>
        </div>

        {showOrderForm && (
          <div className="mb-4 p-4 bg-gray-50 rounded-lg">
            <h4 className="font-medium mb-3">Create New Order</h4>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <select
                value={newOrder.user_id}
                onChange={(e) => setNewOrder({ ...newOrder, user_id: e.target.value })}
                className="border rounded px-3 py-2"
              >
                <option value="">Select User</option>
                {users.map((user) => (
                  <option key={user.id} value={user.id}>{user.username}</option>
                ))}
              </select>
              <input
                type="text"
                placeholder="Product Name"
                value={newOrder.product_name}
                onChange={(e) => setNewOrder({ ...newOrder, product_name: e.target.value })}
                className="border rounded px-3 py-2"
              />
              <input
                type="number"
                placeholder="Amount"
                value={newOrder.amount}
                onChange={(e) => setNewOrder({ ...newOrder, amount: e.target.value })}
                className="border rounded px-3 py-2"
              />
            </div>
            <div className="mt-3 flex gap-2">
              <button
                onClick={createOrder}
                className="bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700"
              >
                Create Order
              </button>
              <button
                onClick={() => setShowOrderForm(false)}
                className="bg-gray-500 text-white px-4 py-2 rounded hover:bg-gray-600"
              >
                Cancel
              </button>
            </div>
          </div>
        )}

        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Product</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Customer</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Amount</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Created</th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {orders.map((order) => (
                <tr key={order.id}>
                  <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{order.product_name}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">{order.username}</td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">${order.amount}</td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-green-100 text-green-800">
                      {order.status}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    {new Date(order.created_at).toLocaleDateString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};

export default TenantDashboard;
