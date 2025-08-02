import React, { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { User, Lock, AlertCircle, CheckCircle } from 'lucide-react'

const Login = () => {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  
  const { login, demoLogin } = useAuth()
  const navigate = useNavigate()

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError('')
    setSuccess('')

    const result = await login(email, password)
    
    if (result.success) {
      setSuccess('Login successful! Redirecting...')
      setTimeout(() => {
        navigate('/dashboard')
      }, 1000)
    } else {
      setError(result.error)
    }
    
    setLoading(false)
  }

  const handleDemoLogin = async () => {
    setLoading(true)
    setError('')
    setSuccess('')

    const result = await demoLogin()
    
    if (result.success) {
      setSuccess('Demo login successful! Redirecting...')
      setTimeout(() => {
        navigate('/dashboard')
      }, 1000)
    } else {
      setError(result.error)
    }
    
    setLoading(false)
  }

  return (
    <div className="max-w-md mx-auto">
      <div className="card">
                 <div className="text-center mb-8">
           <User size={48} style={{ color: 'var(--primary-color)' }} className="mx-auto mb-4" />
           <h1 className="text-3xl font-bold mb-2">Welcome Back</h1>
           <p className="text-gray">Sign in to your account</p>
         </div>

        {error && (
          <div className="alert alert-error mb-4">
            <AlertCircle size={16} className="inline mr-2" />
            {error}
          </div>
        )}

        {success && (
          <div className="alert alert-success mb-4">
            <CheckCircle size={16} className="inline mr-2" />
            {success}
          </div>
        )}

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label className="form-label">
              <User size={16} className="inline mr-2" />
              Email Address
            </label>
            <input
              type="email"
              className="form-input"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="Enter your email"
              required
            />
          </div>

          <div className="form-group">
            <label className="form-label">
              <Lock size={16} className="inline mr-2" />
              Password
            </label>
            <input
              type="password"
              className="form-input"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter your password"
              required
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="btn btn-primary w-full mb-4"
          >
            {loading ? 'Signing In...' : 'Sign In'}
          </button>
        </form>

        <div className="text-center mb-4">
          <span className="text-gray">or</span>
        </div>

        <button
          onClick={handleDemoLogin}
          disabled={loading}
          className="btn btn-secondary w-full mb-4"
        >
          Try Demo Account
        </button>

        <div className="text-center">
          <p className="text-gray">
            Don't have an account?{' '}
            <Link to="/register" className="text-blue-600 hover:underline">
              Sign up here
            </Link>
          </p>
        </div>

        <div className="mt-8 p-4 bg-gray-50 rounded-lg">
          <h3 className="font-bold mb-2">Demo Account</h3>
          <p className="text-sm text-gray">
            Use the demo login to experience the payment system without creating an account.
            All demo transactions are stored in the test database.
          </p>
        </div>
      </div>
    </div>
  )
}

export default Login 