import React, { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { useStripe, useElements, CardElement } from '@stripe/react-stripe-js'
import { 
  CreditCard, 
  DollarSign, 
  AlertCircle, 
  CheckCircle,
  Loader
} from 'lucide-react'
import axios from 'axios'

const CARD_ELEMENT_OPTIONS = {
  style: {
    base: {
      fontSize: '16px',
      color: '#424770',
      '::placeholder': {
        color: '#aab7c4',
      },
    },
    invalid: {
      color: '#9e2146',
    },
  },
}

const PaymentForm = () => {
  const stripe = useStripe()
  const elements = useElements()
  const navigate = useNavigate()
  const { user, isAuthenticated } = useAuth()
  
  const [amount, setAmount] = useState('')
  const [description, setDescription] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [clientSecret, setClientSecret] = useState('')

  useEffect(() => {
    if (!isAuthenticated) {
      navigate('/login')
    }
  }, [isAuthenticated, navigate])

  const createPaymentIntent = async () => {
    try {
      const response = await axios.post('/api/payments/create-payment-intent', {
        amount: parseFloat(amount),
        description: description || 'Payment Systems Demo',
        currency: 'usd'
      })
      
      setClientSecret(response.data.clientSecret)
      return response.data.paymentIntentId
    } catch (error) {
      throw new Error(error.response?.data?.error || 'Failed to create payment intent')
    }
  }

  const handleSubmit = async (event) => {
    event.preventDefault()
    
    if (!stripe || !elements) {
      return
    }

    if (!amount || parseFloat(amount) < 0.5) {
      setError('Amount must be at least $0.50')
      return
    }

    setLoading(true)
    setError('')
    setSuccess('')

    try {
      // Create payment intent
      const paymentIntentId = await createPaymentIntent()
      
      // For demo mode, simulate payment confirmation
      if (paymentIntentId.startsWith('pi_demo_')) {
        // Simulate a delay to show processing
        await new Promise(resolve => setTimeout(resolve, 1500))
        
        // Process demo payment on backend
        await axios.post('/api/payments/process', {
          paymentIntentId: paymentIntentId,
          userId: user?.id || 1,
          description: description || 'Demo Payment processed'
        })

        setSuccess('Demo payment successful! Your transaction has been processed.')
        setAmount('')
        setDescription('')
        elements.getElement(CardElement).clear()
        
        // Redirect to transactions page after 2 seconds
        setTimeout(() => {
          navigate('/transactions')
        }, 2000)
      } else {
        // Real Stripe payment flow
        const { error: stripeError, paymentIntent } = await stripe.confirmCardPayment(
          clientSecret,
          {
            payment_method: {
              card: elements.getElement(CardElement),
              billing_details: {
                name: user?.name || 'Demo User',
                email: user?.email || 'demo@example.com',
              },
            },
          }
        )

        if (stripeError) {
          setError(stripeError.message || 'Payment failed')
          return
        }

        if (paymentIntent.status === 'succeeded') {
          // Process payment on backend
          await axios.post('/api/payments/process', {
            paymentIntentId: paymentIntent.id,
            userId: user?.id || 1,
            description: description || 'Payment processed'
          })

          setSuccess('Payment successful! Your transaction has been processed.')
          setAmount('')
          setDescription('')
          elements.getElement(CardElement).clear()
          
          // Redirect to transactions page after 2 seconds
          setTimeout(() => {
            navigate('/transactions')
          }, 2000)
        }
      }
    } catch (error) {
      setError(error.message || 'Payment failed')
    } finally {
      setLoading(false)
    }
  }

  const handleAmountChange = (e) => {
    const value = e.target.value
    // Only allow numbers and decimal point
    if (/^\d*\.?\d{0,2}$/.test(value) || value === '') {
      setAmount(value)
    }
  }

  if (!isAuthenticated) {
    return (
      <div className="card text-center">
        <AlertCircle size={48} className="text-red-500 mx-auto mb-4" />
        <h2 className="text-2xl font-bold mb-4">Authentication Required</h2>
        <p className="text-gray mb-4">Please log in to make a payment.</p>
        <button 
          onClick={() => navigate('/login')}
          className="btn btn-primary"
        >
          Go to Login
        </button>
      </div>
    )
  }

  return (
    <div className="max-w-2xl mx-auto">
      <div className="card">
                 <div className="text-center mb-8">
           <CreditCard size={48} style={{ color: 'var(--primary-color)' }} className="mx-auto mb-4" />
           <h1 className="text-3xl font-bold mb-2">Make a Payment</h1>
           <p className="text-gray">Complete your payment securely with Stripe</p>
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
              <DollarSign size={16} className="inline mr-2" />
              Amount (USD)
            </label>
            <input
              type="text"
              className="form-input"
              value={amount}
              onChange={handleAmountChange}
              placeholder="0.00"
              required
            />
            <small className="text-gray">Minimum amount: $0.50</small>
          </div>

          <div className="form-group">
            <label className="form-label">Description (Optional)</label>
            <input
              type="text"
              className="form-input"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="Payment description"
            />
          </div>

          <div className="form-group">
            <label className="form-label">
              <CreditCard size={16} className="inline mr-2" />
              Card Details
            </label>
                       <div className="border border-gray-300 rounded-lg p-3">
             <CardElement options={CARD_ELEMENT_OPTIONS} />
           </div>
           <small className="text-gray">
             Demo mode: Any card details will work for demonstration
           </small>
          </div>

          <button
            type="submit"
            disabled={!stripe || loading}
            className="btn btn-primary w-full"
          >
            {loading ? (
              <>
                <Loader size={16} className="animate-spin" />
                Processing Payment...
              </>
            ) : (
              <>
                <DollarSign size={16} />
                Pay ${amount || '0.00'}
              </>
            )}
          </button>
        </form>

                 <div className="mt-8 p-4 bg-gray-50 rounded-lg">
           <h3 className="font-bold mb-2">Demo Mode</h3>
           <ul className="text-sm text-gray space-y-1">
             <li>• This is a demo payment system - no real payments are processed</li>
             <li>• All payments are simulated for demonstration purposes</li>
             <li>• You can use any card details - they won't be validated</li>
             <li>• Transactions are stored in the local demo database</li>
             <li>• For real payments, configure Stripe API keys in production</li>
           </ul>
         </div>
      </div>
    </div>
  )
}

export default PaymentForm 