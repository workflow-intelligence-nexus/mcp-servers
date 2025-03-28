import React, { useState, useEffect } from 'react';
import LogsModal from '../components/LogsModal';

function Dashboard() {
  const [servers, setServers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastRefresh, setLastRefresh] = useState(null);
  const [logsModalOpen, setLogsModalOpen] = useState(false);
  const [selectedServer, setSelectedServer] = useState(null);
  const [actionInProgress, setActionInProgress] = useState(null);

  useEffect(() => {
    // Function to handle server data received from main process
    const handleServerData = (data) => {
      setLoading(false);
      setLastRefresh(new Date().toLocaleTimeString());
      
      if (data.error) {
        console.error("Error fetching server data:", data.error);
        setError(data.error);
        return;
      }
      
      console.log("Received server data:", data.servers);
      setServers(data.servers || []);
    };

    // Set up listener for server data
    if (window.electronAPI) {
      window.electronAPI.on('running-servers-data', handleServerData);
      
      // Request server data
      window.electronAPI.send('get-running-servers');

      // Listen for container action results
      window.electronAPI.on('container-action-result', handleContainerActionResult);
      
      // Listen for refresh requests
      window.electronAPI.on('refresh-servers-request', refreshServers);
    } else {
      setLoading(false);
      setError('Electron API not available. Are you running in development mode without Electron?');
    }

    // Clean up listener when component unmounts
    return () => {
      if (window.electronAPI) {
        window.electronAPI.removeListener('running-servers-data', handleServerData);
        window.electronAPI.removeListener('container-action-result', handleContainerActionResult);
        window.electronAPI.removeListener('refresh-servers-request', refreshServers);
      }
    };
  }, []);

  // Handle container action results
  const handleContainerActionResult = (result) => {
    setActionInProgress(null);
    
    if (result.error) {
      console.error(`Error performing ${result.action} action:`, result.error);
      // Show error message to user
      alert(`Error: ${result.error}`);
    } else if (result.success) {
      console.log(`${result.action} action successful:`, result.message);
      // Refresh server list
      refreshServers();
    }
  };

  // Function to refresh server data
  const refreshServers = () => {
    setLoading(true);
    setError(null);
    if (window.electronAPI) {
      window.electronAPI.send('get-running-servers');
    }
  };

  // Extract server type from image (e.g., "mcp/brave-search" -> "brave-search")
  const getServerType = (image) => {
    if (!image) return 'unknown';
    const match = image.match(/mcp\/([^:]+)/);
    return match ? match[1] : 'unknown';
  };

  // Check if server is running
  const isServerRunning = (status) => {
    return status && status.toLowerCase().includes('up');
  };

  // Get status color based on server status
  const getStatusColor = (status) => {
    if (!status) return '#6c757d'; // gray for unknown
    if (status.toLowerCase().includes('up')) return '#28a745'; // green for running
    if (status.toLowerCase().includes('exited')) return '#dc3545'; // red for stopped
    return '#ffc107'; // yellow for other states
  };

  // Get a random angle for the card tilt effect (subtle 3D-inspired effect)
  const getRandomTilt = () => {
    return Math.floor(Math.random() * 3) - 1; // -1, 0, or 1 degree
  };

  // Handle log button click
  const handleViewLogs = (server) => {
    setSelectedServer(server);
    setLogsModalOpen(true);
  };

  // Handle restart button click
  const handleRestartServer = (serverId) => {
    if (window.electronAPI) {
      setActionInProgress(serverId);
      window.electronAPI.send('restart-container', { id: serverId });
    }
  };

  // Handle stop button click
  const handleStopServer = (serverId) => {
    if (window.electronAPI) {
      setActionInProgress(serverId);
      window.electronAPI.send('stop-container', { id: serverId });
    }
  };

  // Handle start button click
  const handleStartServer = (serverId) => {
    if (window.electronAPI) {
      setActionInProgress(serverId);
      window.electronAPI.send('start-container', { id: serverId });
    }
  };

  return (
    <div className="dashboard-container">
      <div className="dashboard-header">
        <h1>Dashboard</h1>
        <button className="refresh-button" onClick={refreshServers} disabled={loading}>
          {loading ? 'Refreshing...' : 'Refresh Servers'}
        </button>
      </div>

      {lastRefresh && (
        <div className="last-refresh">
          Last refreshed: {lastRefresh}
        </div>
      )}

      {error && (
        <div className="error-message">
          <p>Error: {error}</p>
          <p>Make sure Docker is running and you have permissions to execute Docker commands.</p>
        </div>
      )}

      {loading ? (
        <div className="loading-indicator">
          <div className="spinner"></div>
          <p>Loading server data...</p>
        </div>
      ) : servers.length === 0 ? (
        <div className="no-servers">
          <p>No MCP servers found.</p>
          <p>Deploy a server to get started.</p>
        </div>
      ) : (
        <div className="server-grid">
          {servers.map((server) => {
            const serverType = getServerType(server.image);
            const statusColor = getStatusColor(server.status);
            const tiltAngle = getRandomTilt();
            const running = isServerRunning(server.status);
            const isActionInProgress = actionInProgress === server.id;
            
            return (
              <div 
                className={`server-card ${running ? 'running' : 'stopped'}`}
                key={server.id}
                style={{ transform: `rotate(${tiltAngle}deg)` }}
              >
                <div className="server-card-header">
                  <div 
                    className="status-indicator" 
                    style={{ backgroundColor: statusColor }}
                    title={server.status}
                  ></div>
                  <h3>{server.name}</h3>
                </div>
                
                <div className="server-card-body">
                  <div className="server-info">
                    <p><strong>ID:</strong> {server.id.substring(0, 12)}</p>
                    <p><strong>Type:</strong> {serverType}</p>
                    <p><strong>Image:</strong> {server.image}</p>
                    <p><strong>Status:</strong> {server.status}</p>
                  </div>
                </div>
                
                <div className="server-card-actions">
                  <button 
                    className="action-button"
                    onClick={() => handleViewLogs(server)}
                    disabled={!running || isActionInProgress}
                  >
                    Logs
                  </button>
                  
                  <button 
                    className="action-button"
                    onClick={() => handleRestartServer(server.id)}
                    disabled={!running || isActionInProgress}
                  >
                    {isActionInProgress ? 'Working...' : 'Restart'}
                  </button>
                  
                  {running ? (
                    <button 
                      className="action-button stop"
                      onClick={() => handleStopServer(server.id)}
                      disabled={isActionInProgress}
                    >
                      {isActionInProgress ? 'Working...' : 'Stop'}
                    </button>
                  ) : (
                    <button 
                      className="action-button start"
                      onClick={() => handleStartServer(server.id)}
                      disabled={isActionInProgress}
                    >
                      {isActionInProgress ? 'Working...' : 'Start'}
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {logsModalOpen && selectedServer && (
        <LogsModal
          isOpen={logsModalOpen}
          onClose={() => setLogsModalOpen(false)}
          serverName={selectedServer.name}
          serverId={selectedServer.id}
        />
      )}
    </div>
  );
}

export default Dashboard;
