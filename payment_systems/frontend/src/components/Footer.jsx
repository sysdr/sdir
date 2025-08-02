import React from 'react'
import { CreditCard, Github, Linkedin } from 'lucide-react'

const Footer = () => {
  return (
    <footer className="footer">
      <div className="container">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <CreditCard size={20} style={{ color: 'var(--primary-color)' }} />
            <span className="font-bold">Payment Systems Demo</span>
          </div>
          
          <div className="flex items-center gap-4">
            <span className="text-sm">Built with React, Node.js & Stripe</span>
            <div className="flex gap-2">
                             <a 
                 href="https://github.com" 
                 target="_blank" 
                 rel="noopener noreferrer"
                 style={{ color: 'var(--text-secondary)' }}
                 className="hover:opacity-80 transition-opacity"
               >
                 <Github size={20} />
               </a>
               <a 
                 href="https://linkedin.com" 
                 target="_blank" 
                 rel="noopener noreferrer"
                 style={{ color: 'var(--text-secondary)' }}
                 className="hover:opacity-80 transition-opacity"
               >
                 <Linkedin size={20} />
               </a>
            </div>
          </div>
        </div>
        
        <div className="text-center mt-4 text-sm opacity-80">
          <p>© 2024 Payment Systems Demo. All rights reserved.</p>
          <p className="mt-1">
            This is a demonstration project for educational purposes.
          </p>
        </div>
      </div>
    </footer>
  )
}

export default Footer 