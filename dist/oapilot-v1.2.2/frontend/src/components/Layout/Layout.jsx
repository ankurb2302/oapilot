import React from 'react'
import { Outlet, Link, useLocation } from 'react-router-dom'
import { MessageSquare, Activity, Server, Settings } from 'lucide-react'

function Layout() {
  const location = useLocation()

  const navigation = [
    { name: 'Chat', href: '/chat', icon: MessageSquare },
    { name: 'Status', href: '/status', icon: Activity },
    { name: 'Servers', href: '/servers', icon: Server },
  ]

  return (
    <div className="flex h-screen bg-gray-900">
      {/* Sidebar */}
      <div className="flex flex-col w-64 bg-gray-800">
        {/* Logo */}
        <div className="flex items-center h-16 px-4 bg-gray-900">
          <div className="flex items-center">
            <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold text-sm">OA</span>
            </div>
            <span className="ml-2 text-white font-semibold">OAPilot</span>
          </div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 px-4 py-4 space-y-2">
          {navigation.map((item) => {
            const isActive = location.pathname.startsWith(item.href)
            return (
              <Link
                key={item.name}
                to={item.href}
                className={`flex items-center px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                  isActive
                    ? 'bg-blue-600 text-white'
                    : 'text-gray-300 hover:bg-gray-700 hover:text-white'
                }`}
              >
                <item.icon className="mr-3 h-5 w-5" />
                {item.name}
              </Link>
            )
          })}
        </nav>

        {/* Footer */}
        <div className="p-4 border-t border-gray-700">
          <div className="text-xs text-gray-400">
            OAPilot v1.0.0
          </div>
        </div>
      </div>

      {/* Main content */}
      <div className="flex-1 flex flex-col overflow-hidden">
        <main className="flex-1 overflow-y-auto">
          <Outlet />
        </main>
      </div>
    </div>
  )
}

export default Layout