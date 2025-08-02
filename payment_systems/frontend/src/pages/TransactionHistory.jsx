import React, { useState, useEffect } from 'react'
import { useAuth } from '../contexts/AuthContext'
import { 
  BarChart3, 
  CreditCard, 
  DollarSign, 
  Calendar,
  Filter,
  Search,
  Download,
  Eye
} from 'lucide-react'
import axios from 'axios'

const TransactionHistory = () => {
  const { user, isAuthenticated } = useAuth()
  const [transactions, setTransactions] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [filters, setFilters] = useState({
    status: '',
    search: '',
    startDate: '',
    endDate: ''
  })
  const [pagination, setPagination] = useState({
    page: 1,
    limit: 10,
    total: 0
  })

  useEffect(() => {
    if (isAuthenticated && user) {
      fetchTransactions()
    }
  }, [isAuthenticated, user, filters, pagination.page])

  const fetchTransactions = async () => {
    try {
      setLoading(true)
      const userId = user?.id || 1
      const params = new URLSearchParams({
        limit: pagination.limit,
        offset: (pagination.page - 1) * pagination.limit
      })

      if (filters.status) params.append('status', filters.status)
      if (filters.startDate) params.append('startDate', filters.startDate)
      if (filters.endDate) params.append('endDate', filters.endDate)

      const response = await axios.get(`/api/transactions/user/${userId}?${params}`)
      setTransactions(response.data)
      
      // For demo purposes, set a mock total
      setPagination(prev => ({ ...prev, total: response.data.length + 50 }))
    } catch (error) {
      console.error('Failed to fetch transactions:', error)
      setError('Failed to load transactions')
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
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit'
      })
    } catch (error) {
      console.error('Error formatting date:', error)
      return 'Invalid Date'
    }
  }

  const getStatusBadge = (status) => {
    const statusConfig = {
      succeeded: { color: 'bg-green-100 text-green-800', icon: '✓' },
      failed: { color: 'bg-red-100 text-red-800', icon: '✗' },
      pending: { color: 'bg-yellow-100 text-yellow-800', icon: '⏳' },
      cancelled: { color: 'bg-gray-100 text-gray-800', icon: '⊘' },
      unknown: { color: 'bg-gray-100 text-gray-800', icon: '?' }
    }

    const config = statusConfig[status] || statusConfig.unknown

    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${config.color}`}>
        {config.icon} {status}
      </span>
    )
  }

  const handleFilterChange = (key, value) => {
    setFilters(prev => ({ ...prev, [key]: value }))
    setPagination(prev => ({ ...prev, page: 1 }))
  }

  const handlePageChange = (newPage) => {
    setPagination(prev => ({ ...prev, page: newPage }))
  }

  const exportTransactions = () => {
    const csvContent = [
      ['Date', 'Amount', 'Status', 'Description', 'Payment Method'],
      ...transactions.map(t => [
        formatDate(t.created_at),
        formatCurrency(t.amount),
        t.status,
        t.description || '',
        t.payment_method_type || ''
      ])
    ].map(row => row.join(',')).join('\n')

    const blob = new Blob([csvContent], { type: 'text/csv' })
    const url = window.URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'transactions.csv'
    a.click()
    window.URL.revokeObjectURL(url)
  }

  if (!isAuthenticated || !user) {
    return (
      <div className="card text-center">
        <h2 className="text-2xl font-bold mb-4">Authentication Required</h2>
        <p className="text-gray mb-4">Please log in to view your transaction history.</p>
      </div>
    )
  }

  return (
    <div>
      {/* Header */}
      <div className="card mb-8">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold mb-2">Transaction History</h1>
            <p className="text-gray">View and manage your payment transactions</p>
          </div>
          <button onClick={exportTransactions} className="btn btn-secondary">
            <Download size={16} />
            Export CSV
          </button>
        </div>
      </div>

      {/* Filters */}
      <div className="card mb-6">
        <div className="flex items-center gap-4 mb-4">
          <Filter size={20} className="text-gray-600" />
          <h2 className="text-lg font-semibold">Filters</h2>
        </div>
        
        <div className="grid grid-2 gap-4">
          <div className="form-group">
            <label className="form-label">Search</label>
            <div className="relative">
              <Search size={16} className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400" />
              <input
                type="text"
                className="form-input pl-10"
                placeholder="Search transactions..."
                value={filters.search}
                onChange={(e) => handleFilterChange('search', e.target.value)}
              />
            </div>
          </div>

          <div className="form-group">
            <label className="form-label">Status</label>
            <select
              className="form-input"
              value={filters.status}
              onChange={(e) => handleFilterChange('status', e.target.value)}
            >
              <option value="">All Statuses</option>
              <option value="succeeded">Succeeded</option>
              <option value="failed">Failed</option>
              <option value="pending">Pending</option>
              <option value="cancelled">Cancelled</option>
            </select>
          </div>

          <div className="form-group">
            <label className="form-label">Start Date</label>
            <input
              type="date"
              className="form-input"
              value={filters.startDate}
              onChange={(e) => handleFilterChange('startDate', e.target.value)}
            />
          </div>

          <div className="form-group">
            <label className="form-label">End Date</label>
            <input
              type="date"
              className="form-input"
              value={filters.endDate}
              onChange={(e) => handleFilterChange('endDate', e.target.value)}
            />
          </div>
        </div>
      </div>

      {/* Transactions Table */}
      <div className="card">
        {loading ? (
          <div className="text-center py-8">
            <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mx-auto mb-4"></div>
            <p>Loading transactions...</p>
          </div>
        ) : error ? (
          <div className="text-center py-8">
            <p className="text-red-600">{error}</p>
            <button onClick={fetchTransactions} className="btn btn-primary mt-4">
              Retry
            </button>
          </div>
        ) : transactions.length === 0 ? (
                   <div className="text-center py-8">
           <BarChart3 size={48} style={{ color: 'var(--text-muted)' }} className="mx-auto mb-4" />
           <p className="text-gray mb-4">No transactions found</p>
           <p className="text-sm text-gray">Try adjusting your filters or make your first payment.</p>
         </div>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="w-full">
                <thead>
                  <tr className="border-b border-gray-200">
                    <th className="text-left py-3 px-4 font-semibold">Date</th>
                    <th className="text-left py-3 px-4 font-semibold">Amount</th>
                    <th className="text-left py-3 px-4 font-semibold">Status</th>
                    <th className="text-left py-3 px-4 font-semibold">Description</th>
                    <th className="text-left py-3 px-4 font-semibold">Payment Method</th>
                    <th className="text-left py-3 px-4 font-semibold">Actions</th>
                  </tr>
                </thead>
                <tbody>
                                     {transactions.map((transaction) => (
                     <tr key={transaction.id || Math.random()} className="border-b border-gray-100 hover:bg-gray-50">
                       <td className="py-3 px-4">
                         <div className="flex items-center gap-2">
                           <Calendar size={16} className="text-gray-400" />
                           {formatDate(transaction?.created_at)}
                         </div>
                       </td>
                       <td className="py-3 px-4">
                         <div className="flex items-center gap-2">
                           <DollarSign size={16} style={{ color: 'var(--success-color)' }} />
                           <span className="font-semibold">
                             {formatCurrency(transaction?.amount)}
                           </span>
                         </div>
                       </td>
                       <td className="py-3 px-4">
                         {getStatusBadge(transaction?.status || 'unknown')}
                       </td>
                       <td className="py-3 px-4">
                         <span className="text-gray">
                           {transaction?.description || 'Payment'}
                         </span>
                       </td>
                       <td className="py-3 px-4">
                         <div className="flex items-center gap-2">
                           <CreditCard size={16} style={{ color: 'var(--primary-color)' }} />
                           <span className="text-sm">
                             {transaction?.payment_method_type || 'Card'} 
                             {transaction?.last_four && ` •••• ${transaction.last_four}`}
                           </span>
                         </div>
                       </td>
                       <td className="py-3 px-4">
                         <button style={{ color: 'var(--primary-color)' }} className="hover:opacity-80">
                           <Eye size={16} />
                         </button>
                       </td>
                     </tr>
                   ))}
                </tbody>
              </table>
            </div>

            {/* Pagination */}
            {pagination.total > pagination.limit && (
              <div className="flex items-center justify-between mt-6 pt-6 border-t border-gray-200">
                <div className="text-sm text-gray">
                  Showing {((pagination.page - 1) * pagination.limit) + 1} to{' '}
                  {Math.min(pagination.page * pagination.limit, pagination.total)} of{' '}
                  {pagination.total} transactions
                </div>
                
                <div className="flex gap-2">
                  <button
                    onClick={() => handlePageChange(pagination.page - 1)}
                    disabled={pagination.page === 1}
                    className="btn btn-secondary"
                  >
                    Previous
                  </button>
                  <button
                    onClick={() => handlePageChange(pagination.page + 1)}
                    disabled={pagination.page * pagination.limit >= pagination.total}
                    className="btn btn-secondary"
                  >
                    Next
                  </button>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}

export default TransactionHistory 