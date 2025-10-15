import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import Navbar from './components/Navbar';
import Dashboard from './pages/Dashboard';
import Runbooks from './pages/Runbooks';
import RunbookDetail from './pages/RunbookDetail';
import CreateRunbook from './pages/CreateRunbook';
import Analytics from './pages/Analytics';

function App() {
  return (
    <Router>
      <div className="min-h-screen bg-gray-50">
        <Navbar />
        <main className="container mx-auto px-4 py-8">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/runbooks" element={<Runbooks />} />
            <Route path="/runbooks/:id" element={<RunbookDetail />} />
            <Route path="/create" element={<CreateRunbook />} />
            <Route path="/analytics" element={<Analytics />} />
          </Routes>
        </main>
      </div>
    </Router>
  );
}

export default App;
