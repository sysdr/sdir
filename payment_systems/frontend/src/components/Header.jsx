import React from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { CreditCard, User, LogOut, Home, BarChart3 } from 'lucide-react'

const Header = () => {
  const { user, logout, isAuthenticated } = useAuth()
  const navigate = useNavigate()

  const handleLogout = () => {
    logout()
    navigate('/')
  }

  return (
    <header className="header">
      <div className="container">
        <div className="header-content">
          <Link to="/" className="logo">
            <CreditCard className="inline mr-2" size={24} style={{ color: 'var(--primary-color)' }} />
            Payment Systems
          </Link>
          
          <nav className="nav">
            <Link to="/" className="nav-link">
              <Home size={16} className="inline mr-1" />
              Home
            </Link>
            
            {isAuthenticated ? (
              <>
                <Link to="/payment" className="nav-link">
                  <CreditCard size={16} className="inline mr-1" />
                  Make Payment
                </Link>
                <Link to="/transactions" className="nav-link">
                  <BarChart3 size={16} className="inline mr-1" />
                  Transactions
                </Link>
                <Link to="/dashboard" className="nav-link">
                  <User size={16} className="inline mr-1" />
                  Dashboard
                </Link>
                <button 
                  onClick={handleLogout}
                  className="nav-link"
                  style={{ background: 'none', border: 'none', cursor: 'pointer' }}
                >
                  <LogOut size={16} className="inline mr-1" />
                  Logout
                </button>
              </>
            ) : (
              <>
                <Link to="/login" className="nav-link">
                  <User size={16} className="inline mr-1" />
                  Login
                </Link>
                <Link to="/register" className="nav-link">
                  Register
                </Link>
              </>
            )}
          </nav>
        </div>
      </div>
    </header>
  )
}

export default Header 