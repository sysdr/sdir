import React, { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { 
  BarChart3, 
  CreditCard, 
  DollarSign, 
  TrendingUp, 
  Users, 
  Activity,
  ArrowRight,
  Calendar,
  Clock
} from 'lucide-react'
import axios from 'axios'

const Dashboard = () => {
  const { user, isAuthenticated } = useAuth()
  const [stats, setStats] = useState(null)
  const [recentTransactions, setRecentTransactions] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (isAuthenticated && user) {
      fetchDashboardData()
    }
  }, [isAuthenticated, user])

  const fetchDashboardData = async () => {
    try {
      const userId = user?.id || 1
      
      // Fetch stats and recent transactions in parallel
      const [statsResponse, transactionsResponse] = await Promise.all([
        axios.get(`/api/transactions/stats/${userId}`),
        axios.get(`/api/transactions/recent/${userId}?limit=5`)
      ])
      
      setStats(statsResponse.data || {})
      setRecentTransactions(transactionsResponse.data || [])
    } catch (error) {
      console.error('Failed to fetch dashboard data:', error)
      // Set default values on error
      setStats({
        total_transactions: 0,
        total_amount: 0,
        avg_amount: 0,
        successful_transactions: 0,
        failed_transactions: 0,
        success_rate: 0
      })
      setRecentTransactions([])
    } finally {
      setLoading(false)
    }
  }

  const formatCurrency = (amount) => {
    if (amount === null || amount === undefined) return '$0.00'
    try {
      return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD'
      }).format(amount)
    } catch (error) {
      console.error('Error formatting currency:', error)
      return '$0.00'
    }
  }

  const formatDate = (dateString) => {
    if (!dateString) return 'N/A'
    try {
      return new Date(dateString).toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric'
      })
    } catch (error) {
      console.error('Error formatting date:', error)
      return 'Invalid Date'
    }
  }

  const getStatusColor = (status) => {
    switch (status) {
      case 'succeeded':
        return 'text-green-600'
      case 'failed':
        return 'text-red-600'
      case 'pending':
        return 'text-yellow-600'
      default:
        return 'text-gray-600'
    }
  }

  if (!isAuthenticated || !user) {
    return (
      <div className="card text-center">
        <h2 className="text-2xl font-bold mb-4">Authentication Required</h2>
        <p className="text-gray mb-4">Please log in to view your dashboard.</p>
        <Link to="/login" className="btn btn-primary">
          Go to Login
        </Link>
      </div>
    )
  }

  if (loading) {
    return (
      <div className="card text-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
        <p>Loading dashboard...</p>
      </div>
    )
  }

  return (
    <div>
      {/* Welcome Section */}
      <div className="card mb-8">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold mb-2">Welcome back, {user?.name || 'User'}!</h1>
            <p className="text-gray">Here's what's happening with your payments</p>
          </div>
          <Link to="/payment" className="btn btn-primary">
            <CreditCard size={16} />
            Make Payment
            <ArrowRight size={16} />
          </Link>
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-3 mb-8">
                 <div className="card text-center">
           <div style={{ color: 'var(--primary-color)' }} className="mb-2">
             <DollarSign size={32} className="mx-auto" />
           </div>
          <h3 className="text-2xl font-bold mb-1">
            {formatCurrency(stats?.total_amount || 0)}
          </h3>
          <p className="text-gray">Total Processed</p>
        </div>

                 <div className="card text-center">
           <div style={{ color: 'var(--success-color)' }} className="mb-2">
             <TrendingUp size={32} className="mx-auto" />
           </div>
          <h3 className="text-2xl font-bold mb-1">
            {stats?.successful_transactions || 0}
          </h3>
          <p className="text-gray">Successful Payments</p>
        </div>

                 <div className="card text-center">
           <div style={{ color: 'var(--secondary-color)' }} className="mb-2">
             <Activity size={32} className="mx-auto" />
           </div>
          <h3 className="text-2xl font-bold mb-1">
            {(stats?.success_rate || 0).toFixed(1)}%
          </h3>
          <p className="text-gray">Success Rate</p>
        </div>
      </div>

      {/* Recent Activity */}
      <div className="grid grid-2 gap-8">
        <div className="card">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-xl font-bold">Recent Transactions</h2>
            <Link to="/transactions" className="text-blue-600 hover:underline text-sm">
              View All
            </Link>
          </div>

          {recentTransactions.length === 0 ? (
            <div className="text-center py-8">
              <CreditCard size={48} className="text-gray-400 mx-auto mb-4" />
              <p className="text-gray">No transactions yet</p>
              <Link to="/payment" className="btn btn-primary mt-4">
                Make Your First Payment
              </Link>
            </div>
          ) : (
                         <div className="space-y-4">
               {recentTransactions.map((transaction) => (
                 <div key={transaction.id || Math.random()} className="flex items-center justify-between p-4 border border-gray-200 rounded-lg">
                   <div className="flex items-center gap-3">
                     <div className="w-10 h-10 rounded-full flex items-center justify-center" style={{ backgroundColor: 'rgba(99, 91, 255, 0.1)' }}>
                       <CreditCard size={20} style={{ color: 'var(--primary-color)' }} />
                     </div>
                     <div>
                       <p className="font-semibold">
                         {formatCurrency(transaction?.amount)}
                       </p>
                       <p className="text-sm text-gray">
                         {transaction?.description || 'Payment'}
                       </p>
                     </div>
                   </div>
                   <div className="text-right">
                     <p className={`font-semibold ${getStatusColor(transaction?.status)}`}>
                       {transaction?.status || 'unknown'}
                     </p>
                     <p className="text-sm text-gray">
                       {formatDate(transaction?.created_at)}
                     </p>
                   </div>
                 </div>
               ))}
             </div>
          )}
        </div>

        <div className="card">
          <h2 className="text-xl font-bold mb-6">Quick Actions</h2>
          
          <div className="space-y-4">
                         <Link to="/payment" className="block p-4 border border-gray-200 rounded-lg hover:border-blue-300 transition-colors">
               <div className="flex items-center gap-3">
                 <div className="w-10 h-10 rounded-full flex items-center justify-center" style={{ backgroundColor: 'rgba(50, 213, 131, 0.1)' }}>
                   <CreditCard size={20} style={{ color: 'var(--success-color)' }} />
                 </div>
                <div>
                  <p className="font-semibold">Make a Payment</p>
                  <p className="text-sm text-gray">Process a new payment</p>
                </div>
                <ArrowRight size={16} className="text-gray-400 ml-auto" />
              </div>
            </Link>

                         <Link to="/transactions" className="block p-4 border border-gray-200 rounded-lg hover:border-blue-300 transition-colors">
               <div className="flex items-center gap-3">
                 <div className="w-10 h-10 rounded-full flex items-center justify-center" style={{ backgroundColor: 'rgba(99, 91, 255, 0.1)' }}>
                   <BarChart3 size={20} style={{ color: 'var(--primary-color)' }} />
                 </div>
                <div>
                  <p className="font-semibold">View Transactions</p>
                  <p className="text-sm text-gray">See all your payments</p>
                </div>
                <ArrowRight size={16} className="text-gray-400 ml-auto" />
              </div>
            </Link>

            <div className="p-4 bg-gray-50 rounded-lg">
              <h3 className="font-semibold mb-2">Account Summary</h3>
                             <div className="space-y-2 text-sm">
                 <div className="flex justify-between">
                   <span className="text-gray">Total Transactions:</span>
                   <span className="font-semibold">{stats?.total_transactions || 0}</span>
                 </div>
                 <div className="flex justify-between">
                   <span className="text-gray">Average Amount:</span>
                   <span className="font-semibold">{formatCurrency(stats?.avg_amount || 0)}</span>
                 </div>
                 <div className="flex justify-between">
                   <span className="text-gray">Failed Transactions:</span>
                   <span className="font-semibold">{stats?.failed_transactions || 0}</span>
                 </div>
               </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

export default Dashboard 