import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { 
  BarChart3, 
  AlertTriangle, 
  FileText, 
  TrendingUp,
  Activity
} from 'lucide-react';

export const Navigation = () => {
  const location = useLocation();
  
  const navItems = [
    { path: '/', label: 'Dashboard', icon: BarChart3 },
    { path: '/incidents', label: 'Incidents', icon: AlertTriangle },
    { path: '/postmortems', label: 'Post-Mortems', icon: FileText },
    { path: '/analytics', label: 'Analytics', icon: TrendingUp },
  ];

  return (
    <nav className="navigation">
      <div className="nav-header">
        <Activity className="nav-logo" />
        <h1>PostMortem Pro</h1>
      </div>
      
      <ul className="nav-menu">
        {navItems.map(item => {
          const Icon = item.icon;
          const isActive = location.pathname === item.path;
          
          return (
            <li key={item.path}>
              <Link 
                to={item.path} 
                className={`nav-link ${isActive ? 'active' : ''}`}
              >
                <Icon size={20} />
                <span>{item.label}</span>
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
};
