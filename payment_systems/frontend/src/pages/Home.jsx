import React from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../contexts/AuthContext'
import { 
  CreditCard, 
  Shield, 
  Zap, 
  BarChart3, 
  Users, 
  Globe,
  ArrowRight,
  CheckCircle
} from 'lucide-react'

const Home = () => {
  const { isAuthenticated, demoLogin } = useAuth()

  const handleDemoLogin = async () => {
    const result = await demoLogin()
    if (result.success) {
      // Redirect to dashboard or payment page
      window.location.href = '/payment'
    }
  }

  const features = [
    {
      icon: <CreditCard size={32} />,
      title: 'Secure Payments',
      description: 'Industry-standard encryption and PCI compliance for all transactions.'
    },
    {
      icon: <Zap size={32} />,
      title: 'Fast Processing',
      description: 'Real-time payment processing with instant confirmation.'
    },
    {
      icon: <Shield size={32} />,
      title: 'Fraud Protection',
      description: 'Advanced fraud detection and prevention systems.'
    },
    {
      icon: <BarChart3 size={32} />,
      title: 'Analytics Dashboard',
      description: 'Comprehensive transaction analytics and reporting.'
    },
    {
      icon: <Users size={32} />,
      title: 'User Management',
      description: 'Complete user authentication and profile management.'
    },
    {
      icon: <Globe size={32} />,
      title: 'Global Support',
      description: 'Support for multiple currencies and payment methods.'
    }
  ]

  const benefits = [
    'Secure payment processing with Stripe integration',
    'Real-time transaction monitoring and analytics',
    'User authentication and profile management',
    'Multiple payment method support',
    'Responsive design for all devices',
    'RESTful API with comprehensive documentation'
  ]

  return (
    <div>
      {/* Hero Section */}
      <section className="text-center py-16">
        <div className="card max-w-4xl mx-auto">
          <h1 className="text-4xl md:text-6xl font-bold mb-6" style={{
            background: 'linear-gradient(135deg, var(--primary-color), var(--secondary-color))',
            WebkitBackgroundClip: 'text',
            WebkitTextFillColor: 'transparent',
            backgroundClip: 'text'
          }}>
            Modern Payment Systems
          </h1>
          <p className="text-xl text-gray mb-8 max-w-2xl mx-auto">
            Experience the future of payment processing with our comprehensive demo system. 
            Built with cutting-edge technologies and industry best practices.
          </p>
          
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            {isAuthenticated ? (
              <Link to="/payment" className="btn btn-primary">
                Make a Payment
                <ArrowRight size={16} />
              </Link>
            ) : (
              <button onClick={handleDemoLogin} className="btn btn-primary">
                Try Demo
                <ArrowRight size={16} />
              </button>
            )}
            <Link to="/dashboard" className="btn btn-secondary">
              View Dashboard
            </Link>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="py-16">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-bold mb-4">Key Features</h2>
          <p className="text-gray max-w-2xl mx-auto">
            Our payment system includes everything you need for secure, 
            reliable payment processing.
          </p>
        </div>
        
        <div className="grid grid-3">
                     {features.map((feature, index) => (
             <div key={index} className="card text-center">
               <div style={{ color: 'var(--primary-color)' }} className="mb-4 flex justify-center">
                 {feature.icon}
               </div>
               <h3 className="text-xl font-bold mb-2">{feature.title}</h3>
               <p className="text-gray">{feature.description}</p>
             </div>
           ))}
        </div>
      </section>

      {/* Benefits Section */}
      <section className="py-16">
        <div className="card max-w-4xl mx-auto">
          <div className="grid grid-2 items-center gap-8">
            <div>
              <h2 className="text-3xl font-bold mb-6">Why Choose Our Payment System?</h2>
              <ul className="space-y-3">
                {benefits.map((benefit, index) => (
                  <li key={index} className="flex items-start gap-3">
                    <CheckCircle size={20} className="text-green-500 mt-0.5 flex-shrink-0" />
                    <span>{benefit}</span>
                  </li>
                ))}
              </ul>
            </div>
            
                         <div className="text-center">
               <div style={{
                 background: 'linear-gradient(135deg, rgba(99, 91, 255, 0.05), rgba(10, 37, 64, 0.05))',
                 borderRadius: '1rem',
                 padding: '2rem',
                 border: '1px solid rgba(99, 91, 255, 0.1)'
               }}>
                 <CreditCard size={64} style={{ color: 'var(--primary-color)' }} className="mx-auto mb-4" />
                 <h3 className="text-xl font-bold mb-2">Ready to Get Started?</h3>
                 <p className="text-gray mb-4">
                   Experience our payment system with a demo account
                 </p>
                 <button onClick={handleDemoLogin} className="btn btn-primary">
                   Start Demo
                 </button>
               </div>
             </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-16">
        <div className="card text-center max-w-2xl mx-auto">
          <h2 className="text-3xl font-bold mb-4">Ready to Process Payments?</h2>
          <p className="text-gray mb-6">
            Join thousands of businesses using our secure payment processing system.
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Link to="/register" className="btn btn-primary">
              Get Started
            </Link>
            <Link to="/transactions" className="btn btn-secondary">
              View Transactions
            </Link>
          </div>
        </div>
      </section>
    </div>
  )
}

export default Home 