import React, { useState } from 'react';
import './App.css';
import Dashboard from './pages/Dashboard';
import ServerCatalog from './pages/ServerCatalog';
import DeploymentManagement from './pages/DeploymentManagement';
import MonitoringPanel from './pages/MonitoringPanel';
import CredentialManager from './pages/CredentialManager';
import Settings from './pages/Settings';

// Import Icons
import {
  FaTachometerAlt,
  FaList,
  FaCubes,
  FaChartLine,
  FaKey,
  FaCog
} from 'react-icons/fa';

function App() {
  const [activePage, setActivePage] = useState('Dashboard');

  const menuItems = [
    { name: 'Dashboard', icon: <FaTachometerAlt />, component: <Dashboard /> },
    { name: 'Server Catalog', icon: <FaList />, component: <ServerCatalog /> },
    { name: 'Deployment Management', icon: <FaCubes />, component: <DeploymentManagement /> },
    { name: 'Monitoring Panel', icon: <FaChartLine />, component: <MonitoringPanel /> },
    { name: 'Credential Manager', icon: <FaKey />, component: <CredentialManager /> },
    { name: 'Settings', icon: <FaCog />, component: <Settings /> },
  ];

  const renderPage = () => {
    const item = menuItems.find(item => item.name === activePage);
    return item ? item.component : <Dashboard />; // Default to Dashboard
  };

  return (
    <div className="App">
      <nav className="sidebar">
        <h2>MCP Deploy</h2>
        <ul>
          {menuItems.map((item) => (
            <li
              key={item.name}
              className={activePage === item.name ? 'active' : ''}
              onClick={() => setActivePage(item.name)}
            >
              {item.icon}
              <span>{item.name}</span>
            </li>
          ))}
        </ul>
      </nav>
      <main className="content">
        {renderPage()}
      </main>
    </div>
  );
}

export default App;
