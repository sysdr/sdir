'use client'

import { useState, useEffect } from 'react'
import { Clock, AlertTriangle, CheckCircle } from 'lucide-react'

interface Incident {
  id: string
  title: string
  severity: 'low' | 'medium' | 'high' | 'critical'
  status: 'investigating' | 'identified' | 'resolved'
  startTime: string
  endTime?: string
  impact: string
  services: string[]
  timeline: {
    timestamp: string
    action: string
    author: string
  }[]
}

export default function IncidentTimeline() {
  const [incidents, setIncidents] = useState<Incident[]>([])

  useEffect(() => {
    const fetchIncidents = async () => {
      try {
        const response = await fetch('http://localhost:8080/api/incidents')
        const data = await response.json()
        setIncidents(data)
      } catch (error) {
        console.error('Failed to fetch incidents:', error)
      }
    }

    fetchIncidents()
    const interval = setInterval(fetchIncidents, 12000)
    return () => clearInterval(interval)
  }, [])

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'resolved':
        return <CheckCircle className="h-5 w-5 text-green-500" />
      case 'investigating':
      case 'identified':
        return <AlertTriangle className="h-5 w-5 text-yellow-500" />
      default:
        return <Clock className="h-5 w-5 text-gray-500" />
    }
  }

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'critical': return 'text-red-600 bg-red-100'
      case 'high': return 'text-orange-600 bg-orange-100'
      case 'medium': return 'text-yellow-600 bg-yellow-100'
      case 'low': return 'text-blue-600 bg-blue-100'
      default: return 'text-gray-600 bg-gray-100'
    }
  }

  return (
    <div className="bg-white rounded-lg card-shadow p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4">Incident Timeline</h3>
      
      <div className="space-y-6">
        {incidents.slice(0, 3).map((incident) => (
          <div key={incident.id} className="border rounded-lg p-4">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center">
                {getStatusIcon(incident.status)}
                <h4 className="ml-2 font-medium text-gray-900">{incident.title}</h4>
              </div>
              <span className={`px-2 py-1 rounded text-xs font-medium ${getSeverityColor(incident.severity)}`}>
                {incident.severity.toUpperCase()}
              </span>
            </div>
            
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4 text-sm">
              <div>
                <p className="text-gray-500">Status</p>
                <p className="font-medium capitalize">{incident.status}</p>
              </div>
              <div>
                <p className="text-gray-500">Duration</p>
                <p className="font-medium">
                  {incident.endTime 
                    ? `${Math.round((new Date(incident.endTime).getTime() - new Date(incident.startTime).getTime()) / 60000)}m`
                    : 'Ongoing'
                  }
                </p>
              </div>
              <div>
                <p className="text-gray-500">Affected Services</p>
                <p className="font-medium">{incident.services.join(', ')}</p>
              </div>
            </div>
            
            <div className="border-t pt-3">
              <p className="text-sm text-gray-600 mb-2">Impact: {incident.impact}</p>
              <div className="space-y-2">
                {incident.timeline.slice(-2).map((event, index) => (
                  <div key={index} className="flex items-center text-xs text-gray-500">
                    <Clock className="h-3 w-3 mr-2" />
                    <span className="mr-2">{new Date(event.timestamp).toLocaleTimeString()}</span>
                    <span className="mr-2 font-medium">{event.author}:</span>
                    <span>{event.action}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        ))}
        
        {incidents.length === 0 && (
          <div className="text-center py-8 text-gray-500">
            <CheckCircle className="h-12 w-12 mx-auto mb-4 text-gray-300" />
            <p>No recent incidents</p>
          </div>
        )}
      </div>
    </div>
  )
}
