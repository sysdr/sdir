import React, { useState, useEffect } from 'react';
import { useParams } from 'react-router-dom';
import axios from 'axios';

function RunbookDetail() {
  const { id } = useParams();
  const [runbook, setRunbook] = useState(null);
  const [executions, setExecutions] = useState([]);
  const [currentExecution, setCurrentExecution] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchRunbookDetails();
    fetchExecutions();
  }, [id]);

  const fetchRunbookDetails = async () => {
    try {
      const response = await axios.get(`http://localhost:3001/api/runbooks/${id}`);
      setRunbook(response.data);
    } catch (error) {
      console.error('Failed to fetch runbook details:', error);
    } finally {
      setLoading(false);
    }
  };

  const fetchExecutions = async () => {
    try {
      const response = await axios.get(`http://localhost:3001/api/runbooks/${id}/executions`);
      setExecutions(response.data);
    } catch (error) {
      console.error('Failed to fetch executions:', error);
    }
  };

  const startExecution = async () => {
    try {
      const response = await axios.post('http://localhost:3001/api/executions', {
        runbook_id: id,
        executed_by: 'Demo User'
      });
      
      const newExecution = {
        id: response.data.id,
        status: 'in_progress',
        current_step: 0,
        started_at: new Date().toISOString(),
        executed_by: 'Demo User'
      };
      
      setCurrentExecution(newExecution);
      setExecutions([newExecution, ...executions]);
    } catch (error) {
      console.error('Failed to start execution:', error);
    }
  };

  const updateExecutionStep = async (step) => {
    if (!currentExecution) return;
    
    try {
      await axios.put(`http://localhost:3001/api/executions/${currentExecution.id}`, {
        status: step >= runbook.steps.length - 1 ? 'completed' : 'in_progress',
        current_step: step + 1,
        execution_log: `Completed step ${step + 1}: ${runbook.steps[step]}`
      });
      
      setCurrentExecution({
        ...currentExecution,
        current_step: step + 1,
        status: step >= runbook.steps.length - 1 ? 'completed' : 'in_progress'
      });
    } catch (error) {
      console.error('Failed to update execution:', error);
    }
  };

  if (loading) {
    return <div className="text-center py-8">Loading runbook details...</div>;
  }

  if (!runbook) {
    return <div className="text-center py-8">Runbook not found</div>;
  }

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-lg shadow-md p-6">
        <div className="flex items-start justify-between mb-4">
          <div>
            <h1 className="text-3xl font-bold text-gray-800">{runbook.title}</h1>
            <p className="text-gray-600 mt-2">{runbook.description}</p>
          </div>
          <span className={`px-3 py-1 rounded-full text-sm font-medium ${
            runbook.severity === 'High' ? 'bg-red-100 text-red-800' :
            runbook.severity === 'Medium' ? 'bg-yellow-100 text-yellow-800' :
            'bg-green-100 text-green-800'
          }`}>
            {runbook.severity} Priority
          </span>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">
          <div className="bg-gray-50 p-3 rounded">
            <span className="font-medium">Category:</span> {runbook.category}
          </div>
          <div className="bg-gray-50 p-3 rounded">
            <span className="font-medium">Estimated Time:</span> {runbook.estimated_time} minutes
          </div>
          <div className="bg-gray-50 p-3 rounded">
            <span className="font-medium">Steps:</span> {runbook.steps?.length || 0}
          </div>
        </div>
      </div>

      {/* Prerequisites */}
      {runbook.prerequisites && (
        <div className="bg-white rounded-lg shadow-md p-6">
          <h2 className="text-xl font-bold text-gray-800 mb-3">Prerequisites</h2>
          <p className="text-gray-700">{runbook.prerequisites}</p>
        </div>
      )}

      {/* Execution Section */}
      <div className="bg-white rounded-lg shadow-md p-6">
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-xl font-bold text-gray-800">Execute Runbook</h2>
          {!currentExecution || currentExecution.status === 'completed' ? (
            <button 
              onClick={startExecution}
              className="bg-green-600 text-white px-4 py-2 rounded-lg hover:bg-green-700"
            >
              Start Execution
            </button>
          ) : (
            <span className="bg-blue-100 text-blue-800 px-3 py-1 rounded-full text-sm">
              Execution in Progress
            </span>
          )}
        </div>

        {currentExecution && (
          <div className="border-t pt-4">
            <h3 className="font-semibold mb-3">Current Execution Progress</h3>
            <div className="space-y-2">
              {runbook.steps.map((step, index) => (
                <div key={index} className={`p-3 rounded border-l-4 ${
                  index < currentExecution.current_step ? 'bg-green-50 border-green-500' :
                  index === currentExecution.current_step ? 'bg-blue-50 border-blue-500' :
                  'bg-gray-50 border-gray-300'
                }`}>
                  <div className="flex items-center justify-between">
                    <span className={`${
                      index < currentExecution.current_step ? 'line-through text-gray-500' : ''
                    }`}>
                      {index + 1}. {step}
                    </span>
                    {index === currentExecution.current_step && (
                      <button 
                        onClick={() => updateExecutionStep(index)}
                        className="bg-blue-600 text-white px-3 py-1 rounded text-sm hover:bg-blue-700"
                      >
                        Complete Step
                      </button>
                    )}
                    {index < currentExecution.current_step && (
                      <span className="text-green-600 text-sm">✓ Completed</span>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>

      {/* Steps */}
      <div className="bg-white rounded-lg shadow-md p-6">
        <h2 className="text-xl font-bold text-gray-800 mb-4">Procedure Steps</h2>
        <div className="space-y-3">
          {runbook.steps?.map((step, index) => (
            <div key={index} className="flex items-start space-x-3 p-3 bg-gray-50 rounded">
              <span className="bg-blue-600 text-white rounded-full w-6 h-6 flex items-center justify-center text-sm font-medium">
                {index + 1}
              </span>
              <p className="text-gray-700">{step}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Rollback Steps */}
      {runbook.rollback_steps?.length > 0 && (
        <div className="bg-white rounded-lg shadow-md p-6">
          <h2 className="text-xl font-bold text-gray-800 mb-4">Rollback Procedures</h2>
          <div className="space-y-3">
            {runbook.rollback_steps.map((step, index) => (
              <div key={index} className="flex items-start space-x-3 p-3 bg-red-50 rounded">
                <span className="bg-red-600 text-white rounded-full w-6 h-6 flex items-center justify-center text-sm font-medium">
                  {index + 1}
                </span>
                <p className="text-gray-700">{step}</p>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Execution History */}
      <div className="bg-white rounded-lg shadow-md p-6">
        <h2 className="text-xl font-bold text-gray-800 mb-4">Execution History</h2>
        {executions.length > 0 ? (
          <div className="space-y-3">
            {executions.map((execution) => (
              <div key={execution.id} className="flex items-center justify-between p-3 border rounded">
                <div>
                  <p className="font-medium">Executed by {execution.executed_by}</p>
                  <p className="text-sm text-gray-500">
                    Started: {new Date(execution.started_at).toLocaleString()}
                  </p>
                </div>
                <span className={`px-2 py-1 rounded text-sm ${
                  execution.status === 'completed' ? 'bg-green-100 text-green-800' :
                  execution.status === 'in_progress' ? 'bg-blue-100 text-blue-800' :
                  'bg-red-100 text-red-800'
                }`}>
                  {execution.status}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <p className="text-gray-500">No executions yet</p>
        )}
      </div>
    </div>
  );
}

export default RunbookDetail;
