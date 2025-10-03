'use client'

import { useState, useEffect } from 'react'
import { Doughnut } from 'react-chartjs-2'
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js'

ChartJS.register(ArcElement, Tooltip, Legend)

interface ErrorBudget {
  service: string
  budgetRemaining: number
  burnRate: number
  status: 'healthy' | 'warning' | 'critical'
}

export default function ErrorBudgetTracker() {
  const [errorBudgets, setErrorBudgets] = useState<ErrorBudget[]>([])

  useEffect(() => {
    const fetchErrorBudgets = async () => {
      try {
        const response = await fetch('http://localhost:8080/api/error-budget')
        const data = await response.json()
        setErrorBudgets(data)
      } catch (error) {
        console.error('Failed to fetch error budgets:', error)
      }
    }

    fetchErrorBudgets()
    const interval = setInterval(fetchErrorBudgets, 15000)
    return () => clearInterval(interval)
  }, [])

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'healthy': return 'text-green-600'
      case 'warning': return 'text-yellow-600'
      case 'critical': return 'text-red-600'
      default: return 'text-gray-600'
    }
  }

  return (
    <div className="bg-white rounded-lg card-shadow p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4">Error Budget Tracking</h3>
      
      <div className="space-y-4">
        {errorBudgets.map((budget, index) => {
          const chartData = {
            labels: ['Used', 'Remaining'],
            datasets: [{
              data: [100 - budget.budgetRemaining, budget.budgetRemaining],
              backgroundColor: [
                budget.status === 'critical' ? '#ef4444' : 
                budget.status === 'warning' ? '#f59e0b' : '#10b981',
                '#e5e7eb'
              ],
              borderWidth: 0
            }]
          }

          return (
            <div key={index} className="flex items-center justify-between p-4 border rounded-lg">
              <div className="flex-1">
                <h4 className="font-medium text-gray-900">{budget.service}</h4>
                <p className="text-sm text-gray-500">
                  Burn Rate: {budget.burnRate.toFixed(2)}x
                </p>
                <p className={`text-sm font-medium ${getStatusColor(budget.status)}`}>
                  {budget.status.toUpperCase()}
                </p>
              </div>
              <div className="w-16 h-16">
                <Doughnut 
                  data={chartData} 
                  options={{
                    plugins: { legend: { display: false } },
                    maintainAspectRatio: false
                  }} 
                />
              </div>
              <div className="text-right ml-4">
                <p className="text-lg font-semibold text-gray-900">
                  {budget.budgetRemaining.toFixed(1)}%
                </p>
                <p className="text-sm text-gray-500">remaining</p>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
