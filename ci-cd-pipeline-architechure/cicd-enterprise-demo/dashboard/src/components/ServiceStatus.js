import React from 'react';
import { Server, Play, AlertCircle } from 'lucide-react';

const ServiceStatus = ({ services, onTrigger }) => {
  const getStatusColor = (status) => {
    switch (status) {
      case 'healthy':
        return 'text-green-500 bg-green-100';
      case 'warning':
        return 'text-yellow-500 bg-yellow-100';
      case 'error':
        return 'text-red-500 bg-red-100';
      default:
        return 'text-gray-500 bg-gray-100';
    }
  };

  return (
    <div className="space-y-4">
      {Object.entries(services).map(([serviceName, serviceData]) => (
        <div key={serviceName} className="border border-gray-200 rounded-lg p-4 hover:shadow-sm transition-shadow">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center space-x-3">
              <Server className={`h-5 w-5 ${getStatusColor(serviceData.status).split(' ')[0]}`} />
              <span className="font-medium text-gray-900 capitalize">{serviceName}</span>
            </div>
            <div className={`px-2 py-1 rounded-full text-xs font-medium ${getStatusColor(serviceData.status)}`}>
              {serviceData.status}
            </div>
          </div>
          
          <div className="text-xs text-gray-500 mb-3">
            Last deploy: {new Date(serviceData.lastDeploy).toLocaleString()}
          </div>
          
          <button
            onClick={() => onTrigger(serviceName)}
            className="w-full flex items-center justify-center px-3 py-2 bg-teal-600 text-white text-sm font-medium rounded-md hover:bg-teal-700 transition-colors"
          >
            <Play className="h-4 w-4 mr-2" />
            Trigger Pipeline
          </button>
        </div>
      ))}
      
      <div className="mt-6 p-4 bg-slate-50 rounded-lg border border-slate-200">
        <div className="flex items-start space-x-2">
          <AlertCircle className="h-5 w-5 text-slate-600 flex-shrink-0 mt-0.5" />
          <div className="text-sm">
            <p className="font-medium text-slate-900">Demo Information</p>
            <p className="text-slate-700 mt-1">
              Pipelines trigger automatically every 30 seconds. Manual triggers are also available.
              Approval stages auto-approve after 60 seconds.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ServiceStatus;
