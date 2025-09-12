import React from 'react';
import { Link, useLocation } from 'react-router-dom';

function Navbar() {
  const location = useLocation();
  
  const isActive = (path) => location.pathname === path;
  
  return (
    <nav className="bg-blue-600 text-white shadow-lg">
      <div className="container mx-auto px-4">
        <div className="flex items-center justify-between h-16">
          <div className="flex items-center space-x-4">
            <Link to="/" className="text-xl font-bold">
              📚 Runbook Manager
            </Link>
          </div>
          
          <div className="flex space-x-4">
            <Link 
              to="/" 
              className={`px-3 py-2 rounded-md ${isActive('/') ? 'bg-blue-700' : 'hover:bg-blue-500'}`}
            >
              Dashboard
            </Link>
            <Link 
              to="/runbooks" 
              className={`px-3 py-2 rounded-md ${isActive('/runbooks') ? 'bg-blue-700' : 'hover:bg-blue-500'}`}
            >
              Runbooks
            </Link>
            <Link 
              to="/create" 
              className={`px-3 py-2 rounded-md ${isActive('/create') ? 'bg-blue-700' : 'hover:bg-blue-500'}`}
            >
              Create
            </Link>
            <Link 
              to="/analytics" 
              className={`px-3 py-2 rounded-md ${isActive('/analytics') ? 'bg-blue-700' : 'hover:bg-blue-500'}`}
            >
              Analytics
            </Link>
          </div>
        </div>
      </div>
    </nav>
  );
}

export default Navbar;
