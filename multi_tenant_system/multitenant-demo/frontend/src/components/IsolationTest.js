import React, { useState } from 'react';
import axios from 'axios';
import { Shield, CheckCircle, XCircle, AlertTriangle } from 'lucide-react';

const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:8080';

const IsolationTest = () => {
  const [testResults, setTestResults] = useState({});
  const [testing, setTesting] = useState(false);

  const runIsolationTests = async () => {
    setTesting(true);
    try {
      const response = await axios.post(`${API_BASE}/api/test-isolation`);
      setTestResults(response.data);
    } catch (error) {
      console.error('Error running isolation tests:', error);
      setTestResults({ error: 'Failed to run tests' });
    } finally {
      setTesting(false);
    }
  };

  const getStatusIcon = (isolated) => {
    if (isolated) {
      return <CheckCircle className="h-5 w-5 text-green-500" />;
    }
    return <XCircle className="h-5 w-5 text-red-500" />;
  };

  const getStatusColor = (isolated) => {
    return isolated ? 'bg-green-50 border-green-200' : 'bg-red-50 border-red-200';
  };

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-lg shadow p-6">
        <h2 className="text-xl font-semibold mb-4 flex items-center">
          <Shield className="h-6 w-6 mr-2 text-blue-600" />
          Tenant Isolation Testing
        </h2>
        
        <div className="mb-6">
          <p className="text-gray-600 mb-4">
            Test the isolation mechanisms across all three multi-tenant patterns to ensure 
            cross-tenant data leakage is prevented.
          </p>
          
          <button
            onClick={runIsolationTests}
            disabled={testing}
            className="bg-blue-600 text-white px-6 py-3 rounded-lg hover:bg-blue-700 disabled:opacity-50 flex items-center"
          >
            {testing ? (
              <>
                <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2"></div>
                Running Tests...
              </>
            ) : (
              <>
                <Shield className="h-4 w-4 mr-2" />
                Run Isolation Tests
              </>
            )}
          </button>
        </div>

        {Object.keys(testResults).length > 0 && (
          <div className="space-y-4">
            <h3 className="text-lg font-medium">Test Results</h3>
            
            {testResults.shared_schema && (
              <div className={`border rounded-lg p-4 ${getStatusColor(testResults.shared_schema.isolated)}`}>
                <div className="flex items-center justify-between mb-2">
                  <h4 className="font-medium">Pattern 1: Shared Schema</h4>
                  {getStatusIcon(testResults.shared_schema.isolated)}
                </div>
                <p className="text-sm text-gray-600 mb-2">
                  Tests Row-Level Security (RLS) policies for tenant isolation
                </p>
                {testResults.shared_schema.tenant1_users !== undefined && (
                  <div className="text-sm">
                    <p>Tenant 1 Users: {testResults.shared_schema.tenant1_users}</p>
                    <p>Tenant 2 Users: {testResults.shared_schema.tenant2_users}</p>
                  </div>
                )}
                {testResults.shared_schema.error && (
                  <p className="text-red-600 text-sm">{testResults.shared_schema.error}</p>
                )}
              </div>
            )}

            {testResults.separate_schema && (
              <div className={`border rounded-lg p-4 ${getStatusColor(testResults.separate_schema.isolated)}`}>
                <div className="flex items-center justify-between mb-2">
                  <h4 className="font-medium">Pattern 2: Separate Schema</h4>
                  {getStatusIcon(testResults.separate_schema.isolated)}
                </div>
                <p className="text-sm text-gray-600 mb-2">
                  Tests schema-level isolation within shared database
                </p>
                <div className="text-sm">
                  <p>Schema exists: {testResults.separate_schema.schema_exists ? 'Yes' : 'No'}</p>
                </div>
                {testResults.separate_schema.error && (
                  <p className="text-red-600 text-sm">{testResults.separate_schema.error}</p>
                )}
              </div>
            )}

            {testResults.separate_db && (
              <div className={`border rounded-lg p-4 ${getStatusColor(testResults.separate_db.isolated)}`}>
                <div className="flex items-center justify-between mb-2">
                  <h4 className="font-medium">Pattern 3: Separate Database</h4>
                  {getStatusIcon(testResults.separate_db.isolated)}
                </div>
                <p className="text-sm text-gray-600 mb-2">
                  Tests complete database isolation
                </p>
                <div className="text-sm">
                  <p>Connection successful: {testResults.separate_db.connection_successful ? 'Yes' : 'No'}</p>
                </div>
                {testResults.separate_db.error && (
                  <p className="text-red-600 text-sm">{testResults.separate_db.error}</p>
                )}
              </div>
            )}

            <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
              <div className="flex items-start">
                <AlertTriangle className="h-5 w-5 text-blue-600 mr-2 mt-0.5" />
                <div className="text-sm">
                  <h4 className="font-medium text-blue-800 mb-1">Security Best Practices</h4>
                  <ul className="text-blue-700 space-y-1">
                    <li>• Pattern 1: Relies on application-layer filtering with RLS as backup</li>
                    <li>• Pattern 2: Schema-level isolation provides better security boundaries</li>
                    <li>• Pattern 3: Complete isolation with highest security but operational overhead</li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default IsolationTest;
