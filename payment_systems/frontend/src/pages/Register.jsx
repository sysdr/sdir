import React, { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { User, Lock, Mail, AlertCircle, CheckCircle } from 'lucide-react'

const Register = () => {
  const [formData, setFormData] = useState({
    name: '',
    email: '',
    password: '',
    confirmPassword: ''
  })
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  
  const { register } = useAuth()
  const navigate = useNavigate()

  const handleChange = (e) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.value
    })
  }

  const validateForm = () => {
    if (formData.password !== formData.confirmPassword) {
      setError('Passwords do not match')
      return false
    }
    
    if (formData.password.length < 6) {
      setError('Password must be at least 6 characters long')
      return false
    }
    
    return true
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    
    if (!validateForm()) {
      return
    }
    
    setLoading(true)
    setError('')
    setSuccess('')

    const result = await register(formData.email, formData.password, formData.name)
    
    if (result.success) {
      setSuccess('Registration successful! Redirecting to dashboard...')
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
           <h1 className="text-3xl font-bold mb-2">Create Account</h1>
           <p className="text-gray">Join our payment system</p>
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
              Full Name
            </label>
            <input
              type="text"
              name="name"
              className="form-input"
              value={formData.name}
              onChange={handleChange}
              placeholder="Enter your full name"
              required
            />
          </div>

          <div className="form-group">
            <label className="form-label">
              <Mail size={16} className="inline mr-2" />
              Email Address
            </label>
            <input
              type="email"
              name="email"
              className="form-input"
              value={formData.email}
              onChange={handleChange}
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
              name="password"
              className="form-input"
              value={formData.password}
              onChange={handleChange}
              placeholder="Create a password"
              required
            />
            <small className="text-gray">Minimum 6 characters</small>
          </div>

          <div className="form-group">
            <label className="form-label">
              <Lock size={16} className="inline mr-2" />
              Confirm Password
            </label>
            <input
              type="password"
              name="confirmPassword"
              className="form-input"
              value={formData.confirmPassword}
              onChange={handleChange}
              placeholder="Confirm your password"
              required
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="btn btn-primary w-full mb-4"
          >
            {loading ? 'Creating Account...' : 'Create Account'}
          </button>
        </form>

        <div className="text-center">
          <p className="text-gray">
            Already have an account?{' '}
            <Link to="/login" className="text-blue-600 hover:underline">
              Sign in here
            </Link>
          </p>
        </div>

        <div className="mt-8 p-4 bg-gray-50 rounded-lg">
          <h3 className="font-bold mb-2">Account Benefits</h3>
          <ul className="text-sm text-gray space-y-1">
            <li>• Secure payment processing</li>
            <li>• Transaction history</li>
            <li>• Multiple payment methods</li>
            <li>• Real-time analytics</li>
          </ul>
        </div>
      </div>
    </div>
  )
}

export default Register 