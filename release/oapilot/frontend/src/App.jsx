import React, { useState, useEffect } from 'react'
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom'
import Chat from './components/Chat/Chat'
import Layout from './components/Layout/Layout'
import { MessageSquare, Activity, Server } from 'lucide-react'

function App() {
  const [isLoading, setIsLoading] = useState(true)
  const [systemHealth, setSystemHealth] = useState(null)

  useEffect(() => {
    checkSystemHealth()
  }, [])

  const checkSystemHealth = async () => {
    try {
      const response = await fetch('/api/v1/health')
      const health = await response.json()
      setSystemHealth(health)
    } catch (error) {
      console.error('Failed to check system health:', error)
    } finally {
      setIsLoading(false)
    }
  }

  if (isLoading) {
    return (
      <div className="min-h-screen bg-gray-900 flex items-center justify-center">
        <div className="text-center text-white">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-500 mx-auto mb-4"></div>
          <h2 className="text-xl font-semibold mb-2">Starting OAPilot...</h2>
          <p className="text-gray-400">Initializing AI services</p>
        </div>
      </div>
    )
  }

  return (
    <Router>
      <div className="min-h-screen bg-gray-900 text-white">
        <Routes>
          <Route path="/" element={<Layout />}>
            <Route index element={<Navigate to="/chat" replace />} />
            <Route path="chat" element={<Chat />} />
            <Route path="chat/:sessionId" element={<Chat />} />
            <Route path="status" element={<SystemStatus health={systemHealth} />} />
          </Route>
        </Routes>
      </div>
    </Router>
  )
}

function SystemStatus({ health }) {
  return (
    <div className="p-6">
      <h1 className="text-2xl font-bold mb-6 flex items-center">
        <Activity className="mr-2" />
        System Status
      </h1>
      
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {/* System Health */}
        <div className="bg-gray-800 rounded-lg p-4">
          <h3 className="font-semibold mb-3 flex items-center">
            <Server className="mr-2 h-5 w-5" />
            System Health
          </h3>
          <div className="space-y-2">
            <div className={`px-2 py-1 rounded text-sm ${
              health?.status === 'healthy' ? 'bg-green-900 text-green-200' : 'bg-red-900 text-red-200'
            }`}>
              Status: {health?.status || 'Unknown'}
            </div>
            <div className="text-sm text-gray-400">
              Version: {health?.version || '1.0.0'}
            </div>
          </div>
        </div>

        {/* Services */}
        <div className="bg-gray-800 rounded-lg p-4">
          <h3 className="font-semibold mb-3">Services</h3>
          <div className="space-y-2">
            {health?.services && Object.entries(health.services).map(([service, status]) => (
              <div key={service} className="flex justify-between text-sm">
                <span className="capitalize">{service}:</span>
                <span className={status.includes('error') ? 'text-red-400' : 'text-green-400'}>
                  {status}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Resources */}
        <div className="bg-gray-800 rounded-lg p-4">
          <h3 className="font-semibold mb-3">Resources</h3>
          <div className="space-y-2">
            {health?.resources?.memory && (
              <div className="text-sm">
                <div className="flex justify-between">
                  <span>Memory:</span>
                  <span>{health.resources.memory.percent}%</span>
                </div>
                <div className="w-full bg-gray-700 rounded-full h-2 mt-1">
                  <div 
                    className="bg-blue-600 h-2 rounded-full" 
                    style={{ width: `${health.resources.memory.percent}%` }}
                  ></div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

export default App