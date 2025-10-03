'use client'

import { useState, useEffect } from 'react'
import { CheckCircle, AlertCircle, XCircle } from 'lucide-react'

interface Service {
  name: string
  status: 'healthy' | 'warning' | 'critical'
  uptime: number
  latency: number
  errorRate: number
  lastChecked: string
}

export default function ServiceHealth() {
  const [services, setServices] = useState<Service[]>([])

  useEffect(() => {
    const fetchServices = async () => {
      try {
        const response = await fetch('http://localhost:8080/api/services/health')
        const data = await response.json()
        setServices(data)
      } catch (error) {
        console.error('Failed to fetch service health:', error)
      }
    }

    fetchServices()
    const interval = setInterval(fetchServices, 5000)
    return () => clearInterval(interval)
  }, [])

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy':
        return <CheckCircle className="h-5 w-5 text-green-500" />
      case 'warning':
        return <AlertCircle className="h-5 w-5 text-yellow-500" />
      case 'critical':
        return <XCircle className="h-5 w-5 text-red-500" />
      default:
        return <AlertCircle className="h-5 w-5 text-gray-500" />
    }
  }

  const getStatusBg = (status: string) => {
    switch (status) {
      case 'healthy': return 'bg-green-50 border-green-200'
      case 'warning': return 'bg-yellow-50 border-yellow-200'
      case 'critical': return 'bg-red-50 border-red-200'
      default: return 'bg-gray-50 border-gray-200'
    }
  }

  return (
    <div className="bg-white rounded-lg card-shadow p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4">Service Health Monitor</h3>
      
      <div className="space-y-3">
        {services.map((service, index) => (
          <div key={index} className={`p-4 rounded-lg border ${getStatusBg(service.status)}`}>
            <div className="flex items-center justify-between">
              <div className="flex items-center">
                {getStatusIcon(service.status)}
                <div className="ml-3">
                  <h4 className="font-medium text-gray-900">{service.name}</h4>
                  <p className="text-sm text-gray-500">
                    Last checked: {new Date(service.lastChecked).toLocaleTimeString()}
                  </p>
                </div>
              </div>
              <div className="text-right">
                <p className="text-sm font-medium text-gray-900">
                  {service.uptime.toFixed(2)}% uptime
                </p>
                <p className="text-xs text-gray-500">
                  {service.latency}ms | {service.errorRate.toFixed(2)}% errors
                </p>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  )
}
