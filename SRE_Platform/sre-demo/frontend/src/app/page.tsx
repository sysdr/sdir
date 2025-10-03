'use client'

import { useState, useEffect } from 'react'
import SLOOverview from '@/components/SLOOverview'
import ErrorBudgetTracker from '@/components/ErrorBudgetTracker'
import IncidentTimeline from '@/components/IncidentTimeline'
import ServiceHealth from '@/components/ServiceHealth'
import AlertingPanel from '@/components/AlertingPanel'
import { Activity, Shield, Clock, AlertTriangle } from 'lucide-react'

interface DashboardStats {
  totalServices: number
  healthyServices: number
  activeIncidents: number
  errorBudgetHealth: number
}

export default function Dashboard() {
  const [stats, setStats] = useState<DashboardStats>({
    totalServices: 0,
    healthyServices: 0,
    activeIncidents: 0,
    errorBudgetHealth: 0
  })

  useEffect(() => {
    const fetchStats = async () => {
      try {
        const response = await fetch('http://localhost:8080/api/dashboard/stats')
        const data = await response.json()
        setStats(data)
      } catch (error) {
        console.error('Failed to fetch dashboard stats:', error)
      }
    }

    fetchStats()
    const interval = setInterval(fetchStats, 5000)
    return () => clearInterval(interval)
  }, [])

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <header className="bg-white shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between items-center py-6">
            <div className="flex items-center">
              <Shield className="h-8 w-8 text-primary mr-3" />
              <h1 className="text-2xl font-bold text-gray-900">SRE Dashboard</h1>
            </div>
            <div className="text-sm text-gray-500">
              Core Principles Demo
            </div>
          </div>
        </div>
      </header>

      {/* Stats Overview */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <div className="bg-white rounded-lg card-shadow p-6">
            <div className="flex items-center">
              <Activity className="h-8 w-8 text-green-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-500">Healthy Services</p>
                <p className="text-2xl font-bold text-gray-900">
                  {stats.healthyServices}/{stats.totalServices}
                </p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg card-shadow p-6">
            <div className="flex items-center">
              <AlertTriangle className="h-8 w-8 text-red-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-500">Active Incidents</p>
                <p className="text-2xl font-bold text-gray-900">{stats.activeIncidents}</p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg card-shadow p-6">
            <div className="flex items-center">
              <Clock className="h-8 w-8 text-blue-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-500">Error Budget</p>
                <p className="text-2xl font-bold text-gray-900">
                  {stats.errorBudgetHealth.toFixed(1)}%
                </p>
              </div>
            </div>
          </div>

          <div className="bg-white rounded-lg card-shadow p-6">
            <div className="flex items-center">
              <Shield className="h-8 w-8 text-purple-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-500">SLO Compliance</p>
                <p className="text-2xl font-bold text-gray-900">99.9%</p>
              </div>
            </div>
          </div>
        </div>

        {/* Main Dashboard Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <SLOOverview />
          <ErrorBudgetTracker />
          <ServiceHealth />
          <AlertingPanel />
        </div>

        {/* Incident Timeline */}
        <div className="mt-8">
          <IncidentTimeline />
        </div>
      </div>
    </div>
  )
}
