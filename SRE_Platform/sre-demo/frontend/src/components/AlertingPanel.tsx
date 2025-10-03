'use client'

import { useState, useEffect } from 'react'
import { Bell, Clock, AlertTriangle } from 'lucide-react'

interface Alert {
  id: string
  severity: 'info' | 'warning' | 'critical'
  title: string
  description: string
  service: string
  timestamp: string
  status: 'active' | 'resolved'
}

export default function AlertingPanel() {
  const [alerts, setAlerts] = useState<Alert[]>([])

  useEffect(() => {
    const fetchAlerts = async () => {
      try {
        const response = await fetch('http://localhost:8080/api/alerts')
        const data = await response.json()
        setAlerts(data)
      } catch (error) {
        console.error('Failed to fetch alerts:', error)
      }
    }

    fetchAlerts()
    const interval = setInterval(fetchAlerts, 8000)
    return () => clearInterval(interval)
  }, [])

  const getSeverityIcon = (severity: string) => {
    switch (severity) {
      case 'critical':
        return <AlertTriangle className="h-4 w-4 text-red-500" />
      case 'warning':
        return <AlertTriangle className="h-4 w-4 text-yellow-500" />
      case 'info':
        return <Bell className="h-4 w-4 text-blue-500" />
      default:
        return <Bell className="h-4 w-4 text-gray-500" />
    }
  }

  const getSeverityBg = (severity: string) => {
    switch (severity) {
      case 'critical': return 'bg-red-50 border-red-200'
      case 'warning': return 'bg-yellow-50 border-yellow-200'
      case 'info': return 'bg-blue-50 border-blue-200'
      default: return 'bg-gray-50 border-gray-200'
    }
  }

  return (
    <div className="bg-white rounded-lg card-shadow p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4">Active Alerts</h3>
      
      <div className="space-y-3 max-h-64 overflow-y-auto">
        {alerts.filter(alert => alert.status === 'active').map((alert) => (
          <div key={alert.id} className={`p-3 rounded-lg border ${getSeverityBg(alert.severity)}`}>
            <div className="flex items-start">
              <div className="flex-shrink-0 mt-0.5">
                {getSeverityIcon(alert.severity)}
              </div>
              <div className="ml-3 flex-1">
                <h4 className="text-sm font-medium text-gray-900">{alert.title}</h4>
                <p className="text-sm text-gray-600 mt-1">{alert.description}</p>
                <div className="flex items-center mt-2 text-xs text-gray-500">
                  <span className="font-medium">{alert.service}</span>
                  <span className="mx-2">•</span>
                  <Clock className="h-3 w-3 mr-1" />
                  <span>{new Date(alert.timestamp).toLocaleTimeString()}</span>
                </div>
              </div>
            </div>
          </div>
        ))}
        
        {alerts.filter(alert => alert.status === 'active').length === 0 && (
          <div className="text-center py-8 text-gray-500">
            <Bell className="h-12 w-12 mx-auto mb-4 text-gray-300" />
            <p>No active alerts</p>
          </div>
        )}
      </div>
    </div>
  )
}
