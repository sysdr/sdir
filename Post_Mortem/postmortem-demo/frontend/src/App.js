import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import { Navigation } from './components/Navigation';
import { Dashboard } from './pages/Dashboard';
import { Incidents } from './pages/Incidents';
import { PostMortems } from './pages/PostMortems';
import { Analytics } from './pages/Analytics';
import './styles/App.css';

function App() {
  return (
    <Router>
      <div className="app">
        <Navigation />
        <main className="main-content">
          <Routes>
            <Route path="/" element={<Dashboard />} />
            <Route path="/incidents" element={<Incidents />} />
            <Route path="/postmortems" element={<PostMortems />} />
            <Route path="/analytics" element={<Analytics />} />
          </Routes>
        </main>
      </div>
    </Router>
  );
}

export default App;
