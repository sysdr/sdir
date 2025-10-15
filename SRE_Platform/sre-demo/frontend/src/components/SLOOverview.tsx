'use client'

import { useState, useEffect } from 'react'
import { Line } from 'react-chartjs-2'
import { Chart as ChartJS, CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend } from 'chart.js'

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend)

interface SLOData {
  timestamp: string
  availability: number
  latency: number
  errorRate: number
}

export default function SLOOverview() {
  const [sloData, setSloData] = useState<SLOData[]>([])

  useEffect(() => {
    const fetchSLOData = async () => {
      try {
        const response = await fetch('http://localhost:8080/api/slo/metrics')
        const data = await response.json()
        setSloData(data)
      } catch (error) {
        console.error('Failed to fetch SLO data:', error)
      }
    }

    fetchSLOData()
    const interval = setInterval(fetchSLOData, 10000)
    return () => clearInterval(interval)
  }, [])

  const chartData = {
    labels: sloData.map(d => new Date(d.timestamp).toLocaleTimeString()),
    datasets: [
      {
        label: 'Availability %',
        data: sloData.map(d => d.availability),
        borderColor: '#10b981',
        backgroundColor: 'rgba(16, 185, 129, 0.1)',
        tension: 0.1,
      },
      {
        label: 'Error Rate %',
        data: sloData.map(d => d.errorRate),
        borderColor: '#ef4444',
        backgroundColor: 'rgba(239, 68, 68, 0.1)',
        tension: 0.1,
      }
    ]
  }

  const options = {
    responsive: true,
    plugins: {
      legend: {
        position: 'top' as const,
      },
      title: {
        display: true,
        text: 'SLO Metrics Over Time'
      }
    },
    scales: {
      y: {
        beginAtZero: true,
        max: 100
      }
    }
  }

  return (
    <div className="bg-white rounded-lg card-shadow p-6">
      <h3 className="text-lg font-semibold text-gray-900 mb-4">SLO Overview</h3>
      <div className="h-64">
        <Line data={chartData} options={options} />
      </div>
      
      <div className="mt-4 grid grid-cols-3 gap-4">
        <div className="text-center">
          <p className="text-sm text-gray-500">Availability SLO</p>
          <p className="text-lg font-semibold text-green-600">99.9%</p>
        </div>
        <div className="text-center">
          <p className="text-sm text-gray-500">Latency SLO</p>
          <p className="text-lg font-semibold text-blue-600">&lt; 200ms</p>
        </div>
        <div className="text-center">
          <p className="text-sm text-gray-500">Error Rate SLO</p>
          <p className="text-lg font-semibold text-red-600">&lt; 0.1%</p>
        </div>
      </div>
    </div>
  )
}
