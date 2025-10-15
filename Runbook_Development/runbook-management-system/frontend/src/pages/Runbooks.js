import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import axios from 'axios';

function Runbooks() {
  const [runbooks, setRunbooks] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');

  useEffect(() => {
    fetchRunbooks();
  }, []);

  const fetchRunbooks = async () => {
    try {
      const response = await axios.get('http://localhost:3001/api/runbooks');
      setRunbooks(response.data);
    } catch (error) {
      console.error('Failed to fetch runbooks:', error);
    } finally {
      setLoading(false);
    }
  };

  const filteredRunbooks = runbooks.filter(runbook => 
    filter === 'all' || runbook.category.toLowerCase() === filter
  );

  const categories = [...new Set(runbooks.map(r => r.category))];

  if (loading) {
    return <div className="text-center py-8">Loading runbooks...</div>;
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold text-gray-800">Runbooks</h1>
        <Link 
          to="/create"
          className="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
        >
          Create Runbook
        </Link>
      </div>

      {/* Filters */}
      <div className="bg-white rounded-lg shadow-md p-4">
        <div className="flex flex-wrap gap-2">
          <button
            onClick={() => setFilter('all')}
            className={`px-3 py-1 rounded-full text-sm ${
              filter === 'all' ? 'bg-blue-600 text-white' : 'bg-gray-200 text-gray-700'
            }`}
          >
            All
          </button>
          {categories.map(category => (
            <button
              key={category}
              onClick={() => setFilter(category.toLowerCase())}
              className={`px-3 py-1 rounded-full text-sm ${
                filter === category.toLowerCase() ? 'bg-blue-600 text-white' : 'bg-gray-200 text-gray-700'
              }`}
            >
              {category}
            </button>
          ))}
        </div>
      </div>

      {/* Runbooks Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {filteredRunbooks.map((runbook) => (
          <div key={runbook.id} className="bg-white rounded-lg shadow-md overflow-hidden">
            <div className="p-6">
              <div className="flex items-start justify-between mb-3">
                <h3 className="text-lg font-semibold text-gray-800 line-clamp-2">
                  {runbook.title}
                </h3>
                <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                  runbook.severity === 'High' ? 'bg-red-100 text-red-800' :
                  runbook.severity === 'Medium' ? 'bg-yellow-100 text-yellow-800' :
                  'bg-green-100 text-green-800'
                }`}>
                  {runbook.severity}
                </span>
              </div>
              
              <p className="text-gray-600 text-sm mb-4 line-clamp-3">
                {runbook.description}
              </p>
              
              <div className="flex items-center justify-between text-sm text-gray-500 mb-4">
                <span className="bg-gray-100 px-2 py-1 rounded">
                  {runbook.category}
                </span>
                <span>~{runbook.estimated_time} min</span>
              </div>
              
              <div className="text-xs text-gray-500 mb-4">
                {runbook.steps?.length || 0} steps
              </div>
              
              <Link 
                to={`/runbooks/${runbook.id}`}
                className="w-full bg-blue-600 text-white text-center py-2 rounded-lg hover:bg-blue-700 block"
              >
                View Details
              </Link>
            </div>
          </div>
        ))}
      </div>

      {filteredRunbooks.length === 0 && (
        <div className="text-center py-12">
          <p className="text-gray-500 text-lg">No runbooks found</p>
          <Link 
            to="/create"
            className="inline-block mt-4 bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
          >
            Create your first runbook
          </Link>
        </div>
      )}
    </div>
  );
}

export default Runbooks;
