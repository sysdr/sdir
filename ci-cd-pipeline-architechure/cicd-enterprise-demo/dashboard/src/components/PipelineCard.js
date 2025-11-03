import React from 'react';
import { CheckCircle, XCircle, Clock, Play, AlertTriangle, User, Shield, Bug } from 'lucide-react';

const SecurityFindings = ({ findings }) => {
  const getSeverityColor = (severity) => {
    switch (severity) {
      case 'high': return 'text-red-600 bg-red-100';
      case 'medium': return 'text-orange-600 bg-orange-100';
      case 'low': return 'text-yellow-600 bg-yellow-100';
      default: return 'text-teal-600 bg-teal-100';
    }
  };

  const totalFindings = findings.reduce((sum, f) => sum + f.count, 0);

  return (
    <div className="flex items-center space-x-1">
      <Shield className="h-4 w-4 text-gray-500" />
      <span className="text-xs text-gray-600">{totalFindings}</span>
    </div>
  );
};

const SecuritySummary = ({ findings }) => {
  return (
    <div className="space-y-1">
      {findings.map((finding, index) => (
        <div key={index} className="flex items-center justify-between text-xs">
          <span className="text-gray-600">{finding.type}</span>
          <div className="flex items-center space-x-2">
            <span className={`px-2 py-1 rounded text-xs ${
              finding.severity === 'high' ? 'bg-red-100 text-red-700' :
              finding.severity === 'medium' ? 'bg-orange-100 text-orange-700' :
              finding.severity === 'low' ? 'bg-yellow-100 text-yellow-700' :
              'bg-teal-100 text-teal-700'
            }`}>
              {finding.severity}
            </span>
            <span className="font-medium">{finding.count}</span>
          </div>
        </div>
      ))}
    </div>
  );
};

const PipelineCard = ({ pipeline, onApprove }) => {
  const getStatusIcon = (status) => {
    switch (status) {
      case 'success':
        return <CheckCircle className="h-4 w-4 text-green-500" />;
      case 'failed':
        return <XCircle className="h-4 w-4 text-red-500" />;
      case 'running':
        return <Play className="h-4 w-4 text-teal-500" />;
      case 'waiting-approval':
        return <AlertTriangle className="h-4 w-4 text-yellow-500" />;
      default:
        return <Clock className="h-4 w-4 text-gray-400" />;
    }
  };

  const getStatusColor = (status) => {
    switch (status) {
      case 'completed':
        return 'bg-green-50 border-green-200 text-green-800';
      case 'failed':
        return 'bg-red-50 border-red-200 text-red-800';
      case 'running':
        return 'bg-teal-50 border-teal-200 text-teal-800';
      default:
        return 'bg-gray-50 border-gray-200 text-gray-800';
    }
  };

  const formatDuration = (start, end) => {
    if (!start) return '';
    const startTime = new Date(start);
    const endTime = end ? new Date(end) : new Date();
    const duration = Math.round((endTime - startTime) / 1000);
    return `${duration}s`;
  };

  return (
    <div className={`border rounded-xl p-6 ${getStatusColor(pipeline.status)} transition-all duration-200 hover:shadow-md`}>
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center space-x-3">
          <div className="flex-shrink-0">
            <div className="h-10 w-10 bg-teal-100 rounded-full flex items-center justify-center">
              <span className="text-teal-600 font-semibold text-sm">
                {pipeline.service.substring(0, 2).toUpperCase()}
              </span>
            </div>
          </div>
          <div>
            <h3 className="text-lg font-semibold text-gray-900 capitalize">{pipeline.service} Service</h3>
            <div className="flex items-center text-sm text-gray-600">
              <User className="h-3 w-3 mr-1" />
              {pipeline.metadata?.author || 'system'}
              <span className="mx-2">•</span>
              {new Date(pipeline.createdAt).toLocaleTimeString()}
            </div>
          </div>
        </div>
        <div className="flex items-center space-x-2">
          <span className={`px-3 py-1 rounded-full text-xs font-medium ${getStatusColor(pipeline.status)}`}>
            {pipeline.status}
          </span>
        </div>
      </div>

      <div className="space-y-2">
        {pipeline.stages.map((stage, index) => (
          <div key={stage.id} className={`flex items-center justify-between p-3 rounded-lg border pipeline-stage stage-${stage.status}`}>
            <div className="flex items-center space-x-3">
              {getStatusIcon(stage.status)}
              <div className="flex flex-col">
                <span className="font-medium text-gray-900 capitalize">{stage.name.replace('-', ' ')}</span>
                {stage.description && (
                  <span className="text-xs text-gray-500">{stage.description}</span>
                )}
              </div>
              {stage.startTime && (
                <span className="text-xs text-gray-500">
                  {formatDuration(stage.startTime, stage.endTime)}
                </span>
              )}
            </div>
            
            <div className="flex items-center space-x-2">
              {stage.status === 'waiting-approval' && (
                <button
                  onClick={() => onApprove(pipeline.id, index)}
                  className="px-3 py-1 bg-green-500 text-white rounded-md text-xs font-medium hover:bg-green-600 transition-colors"
                >
                  Approve
                </button>
              )}
              {stage.status === 'running' && (
                <div className="flex space-x-1">
                  <div className="w-1 h-4 bg-teal-500 rounded animate-pulse"></div>
                  <div className="w-1 h-4 bg-teal-400 rounded animate-pulse" style={{ animationDelay: '0.1s' }}></div>
                  <div className="w-1 h-4 bg-teal-300 rounded animate-pulse" style={{ animationDelay: '0.2s' }}></div>
                </div>
              )}
              {stage.name === 'security-scan' && stage.securityFindings && stage.status !== 'pending' && (
                <SecurityFindings findings={stage.securityFindings} />
              )}
            </div>
          </div>
        ))}
      </div>

      {/* Security Summary */}
      {pipeline.stages.some(s => s.name === 'security-scan' && s.securityFindings) && (
        <div className="mt-4 p-3 bg-gray-50 rounded-lg">
          <h4 className="text-sm font-medium text-gray-700 mb-2">Security Scan Summary</h4>
          {pipeline.stages
            .filter(s => s.name === 'security-scan' && s.securityFindings)
            .map((stage, idx) => (
              <SecuritySummary key={idx} findings={stage.securityFindings} />
            ))
          }
        </div>
      )}

      {pipeline.metadata?.message && (
        <div className="mt-4 p-3 bg-gray-50 rounded-lg">
          <p className="text-sm text-gray-700">{pipeline.metadata.message}</p>
        </div>
      )}
    </div>
  );
};

export default PipelineCard;
