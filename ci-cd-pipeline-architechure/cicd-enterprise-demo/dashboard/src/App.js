import React, { useState, useEffect } from 'react';
import { io } from 'socket.io-client';
import axios from 'axios';
import PipelineCard from './components/PipelineCard';
import ServiceStatus from './components/ServiceStatus';
import { Play, GitBranch, Zap, BarChart3 } from 'lucide-react';

const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:3001';

function App() {
  const [pipelines, setPipelines] = useState([]);
  const [services, setServices] = useState({});
  const [metrics, setMetrics] = useState({});
  const [socket, setSocket] = useState(null);

  useEffect(() => {
    const newSocket = io(API_BASE);
    setSocket(newSocket);

    newSocket.on('pipeline-triggered', (pipeline) => {
      setPipelines(prev => [pipeline, ...prev.slice(0, 19)]);
    });

    newSocket.on('pipeline-updated', (updatedPipeline) => {
      setPipelines(prev => prev.map(p => 
        p.id === updatedPipeline.id ? updatedPipeline : p
      ));
    });

    newSocket.on('metrics-updated', (updatedMetrics) => {
      setMetrics(updatedMetrics);
    });

    newSocket.on('stage-execution', (stageData) => {
      console.log('Stage execution:', stageData);
    });

    loadInitialData();

    return () => newSocket.close();
  }, []);

  const loadInitialData = async () => {
    try {
      const [pipelinesRes, servicesRes, metricsRes] = await Promise.all([
        axios.get(`${API_BASE}/api/pipelines`),
        axios.get(`${API_BASE}/api/services`),
        axios.get(`${API_BASE}/api/metrics`)
      ]);
      
      setPipelines(pipelinesRes.data.slice(0, 20));
      setServices(servicesRes.data);
      setMetrics(metricsRes.data);
    } catch (error) {
      console.error('Failed to load data:', error);
    }
  };

  const triggerPipeline = async (service) => {
    try {
      await axios.post(`${API_BASE}/api/pipelines/${service}/trigger`, {
        commit: Math.random().toString(36).substring(7),
        author: 'demo-user',
        message: 'Manual trigger from dashboard'
      });
    } catch (error) {
      console.error('Failed to trigger pipeline:', error);
    }
  };

  const approvePipelineStage = async (pipelineId, stageIndex) => {
    try {
      await axios.post(`${API_BASE}/api/pipelines/${pipelineId}/approve/${stageIndex}`);
    } catch (error) {
      console.error('Failed to approve stage:', error);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-50 to-slate-100">
      <div className="container mx-auto px-4 py-6">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-4xl font-bold text-gray-800 mb-2 flex items-center">
            <GitBranch className="mr-3 text-teal-600" />
            Enterprise CI/CD Pipeline
          </h1>
          <p className="text-gray-600">Multi-stage deployment pipeline with approval workflows</p>
        </div>

        {/* Stats Cards - Four Golden Signals */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <div className="bg-white rounded-xl shadow-lg p-6 border-l-4 border-teal-500">
            <div className="flex items-center">
              <BarChart3 className="h-8 w-8 text-teal-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Deployment Frequency</p>
                <p className="text-2xl font-bold text-gray-900">{metrics.deploymentFrequency || 0}</p>
                <p className="text-xs text-gray-500">Last 24 hours</p>
              </div>
            </div>
          </div>
          
          <div className="bg-white rounded-xl shadow-lg p-6 border-l-4 border-green-500">
            <div className="flex items-center">
              <Zap className="h-8 w-8 text-green-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Lead Time</p>
                <p className="text-2xl font-bold text-gray-900">{Math.round((metrics.averageLeadTime || 0) / 60)}m</p>
                <p className="text-xs text-gray-500">Commit to production</p>
              </div>
            </div>
          </div>
          
          <div className="bg-white rounded-xl shadow-lg p-6 border-l-4 border-yellow-500">
            <div className="flex items-center">
              <Play className="h-8 w-8 text-yellow-500" />
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Success Rate</p>
                <p className="text-2xl font-bold text-gray-900">
                  {metrics.totalPipelines > 0 ? 
                    Math.round((metrics.successfulPipelines / metrics.totalPipelines) * 100) : 0}%
                </p>
                <p className="text-xs text-gray-500">Overall pipeline success</p>
              </div>
            </div>
          </div>
          
          <div className="bg-white rounded-xl shadow-lg p-6 border-l-4 border-red-500">
            <div className="flex items-center">
              <div className="h-8 w-8 bg-red-100 rounded-full flex items-center justify-center">
                <div className="h-4 w-4 bg-red-500 rounded-full"></div>
              </div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Change Failure Rate</p>
                <p className="text-2xl font-bold text-gray-900">
                  {metrics.totalPipelines > 0 ? 
                    Math.round((metrics.failedPipelines / metrics.totalPipelines) * 100) : 0}%
                </p>
                <p className="text-xs text-gray-500">Failed deployments</p>
              </div>
            </div>
          </div>
        </div>

        {/* Additional Metrics Row */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <div className="bg-white rounded-xl shadow-lg p-6">
            <h3 className="text-lg font-semibold text-gray-800 mb-4">Stage Failure Rates</h3>
            <div className="space-y-3">
              {metrics.stageFailureRates && Object.keys(metrics.stageFailureRates).length > 0 ? (
                Object.entries(metrics.stageFailureRates)
                  .sort(([, a], [, b]) => (typeof b === 'number' ? b : parseFloat(b) || 0) - (typeof a === 'number' ? a : parseFloat(a) || 0))
                  .map(([stage, rate]) => {
                    const rateValue = typeof rate === 'number' ? rate : parseFloat(rate) || 0;
                    return (
                      <div key={stage} className="flex justify-between items-center">
                        <span className="text-sm text-gray-600 capitalize">{stage.replace(/-/g, ' ')}</span>
                        <div className="flex items-center">
                          <div className="w-24 bg-gray-200 rounded-full h-2 mr-2">
                            <div 
                              className={`h-2 rounded-full ${rateValue > 10 ? 'bg-red-400' : rateValue > 5 ? 'bg-yellow-400' : 'bg-green-400'}`}
                              style={{ width: `${Math.min(rateValue, 100)}%` }}
                            ></div>
                          </div>
                          <span className="text-sm font-medium text-gray-900 w-14 text-right">{rateValue.toFixed(1)}%</span>
                        </div>
                      </div>
                    );
                  })
              ) : (
                <div className="text-center py-8 text-gray-500">
                  <p className="text-sm">No stage failure data available yet</p>
                  <p className="text-xs mt-1">Stage failure rates will appear after pipelines have been executed</p>
                </div>
              )}
            </div>
          </div>
          
          <div className="bg-white rounded-xl shadow-lg p-6">
            <h3 className="text-lg font-semibold text-gray-800 mb-4">Pipeline Health</h3>
            <div className="space-y-3">
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Total Pipelines</span>
                <span className="font-medium">{metrics.totalPipelines || 0}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Successful</span>
                <span className="font-medium text-green-600">{metrics.successfulPipelines || 0}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Failed</span>
                <span className="font-medium text-red-600">{metrics.failedPipelines || 0}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Running</span>
                <span className="font-medium text-teal-600">
                  {pipelines.filter(p => p.status === 'running').length}
                </span>
              </div>
            </div>
          </div>
          
          <div className="bg-white rounded-xl shadow-lg p-6">
            <h3 className="text-lg font-semibold text-gray-800 mb-4">System Performance</h3>
            <div className="space-y-3">
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Avg Build Time</span>
                <span className="font-medium">
                  {metrics.averageLeadTime ? `${Math.round(metrics.averageLeadTime / 60)}m` : 'N/A'}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Queue Depth</span>
                <span className="font-medium">0</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Agent Utilization</span>
                <span className="font-medium text-green-600">67%</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Cache Hit Rate</span>
                <span className="font-medium text-teal-600">84%</span>
              </div>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 xl:grid-cols-4 gap-8">
          {/* Service Status */}
          <div className="xl:col-span-1">
            <div className="bg-white rounded-xl shadow-lg p-6">
              <h2 className="text-xl font-bold text-gray-800 mb-4">Service Status</h2>
              <ServiceStatus services={services} onTrigger={triggerPipeline} />
            </div>
          </div>

          {/* Pipeline List */}
          <div className="xl:col-span-3">
            <div className="bg-white rounded-xl shadow-lg p-6">
              <h2 className="text-xl font-bold text-gray-800 mb-6">Recent Pipelines</h2>
              <div className="space-y-4 max-h-screen overflow-y-auto">
                {pipelines.length === 0 ? (
                  <div className="text-center py-12">
                    <GitBranch className="mx-auto h-12 w-12 text-gray-400" />
                    <h3 className="mt-2 text-sm font-medium text-gray-900">No pipelines</h3>
                    <p className="mt-1 text-sm text-gray-500">Trigger a service deployment to get started.</p>
                  </div>
                ) : (
                  pipelines.map((pipeline) => (
                    <PipelineCard
                      key={pipeline.id}
                      pipeline={pipeline}
                      onApprove={approvePipelineStage}
                    />
                  ))
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

export default App;
