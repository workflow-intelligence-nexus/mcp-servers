import React, { useEffect, useState } from 'react';

const LogsModal = ({ isOpen, onClose, serverName, serverId }) => {
  const [logs, setLogs] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [autoRefresh, setAutoRefresh] = useState(false);
  const [refreshInterval, setRefreshInterval] = useState(null);

  useEffect(() => {
    if (isOpen && serverId) {
      fetchLogs();
    }

    return () => {
      if (refreshInterval) {
        clearInterval(refreshInterval);
      }
    };
  }, [isOpen, serverId]);

  useEffect(() => {
    if (autoRefresh) {
      const interval = setInterval(() => {
        fetchLogs();
      }, 3000); // Refresh every 3 seconds
      setRefreshInterval(interval);
    } else if (refreshInterval) {
      clearInterval(refreshInterval);
      setRefreshInterval(null);
    }

    return () => {
      if (refreshInterval) {
        clearInterval(refreshInterval);
      }
    };
  }, [autoRefresh]);

  const fetchLogs = () => {
    setLoading(true);
    if (window.electronAPI) {
      window.electronAPI.send('get-container-logs', { id: serverId });
    } else {
      setLoading(false);
      setError('Electron API not available');
    }
  };

  useEffect(() => {
    const handleLogs = (data) => {
      setLoading(false);
      if (data.error) {
        setError(data.error);
        return;
      }
      setLogs(data.logs || '');
    };

    if (window.electronAPI) {
      window.electronAPI.on('container-logs-data', handleLogs);
    }

    return () => {
      if (window.electronAPI) {
        window.electronAPI.removeListener('container-logs-data', handleLogs);
      }
    };
  }, []);

  if (!isOpen) return null;

  return (
    <div className="modal-overlay">
      <div className="logs-modal">
        <div className="logs-modal-header">
          <h2>Logs: {serverName}</h2>
          <div className="logs-modal-controls">
            <label className="auto-refresh-toggle">
              <input
                type="checkbox"
                checked={autoRefresh}
                onChange={() => setAutoRefresh(!autoRefresh)}
              />
              Auto-refresh
            </label>
            <button className="refresh-logs-button" onClick={fetchLogs} disabled={loading}>
              {loading ? 'Refreshing...' : 'Refresh'}
            </button>
            <button className="close-modal-button" onClick={onClose}>
              ×
            </button>
          </div>
        </div>
        <div className="logs-modal-content">
          {error ? (
            <div className="logs-error">
              <p>Error: {error}</p>
            </div>
          ) : loading && !logs ? (
            <div className="logs-loading">
              <div className="spinner"></div>
              <p>Loading logs...</p>
            </div>
          ) : logs ? (
            <pre className="logs-content">{logs}</pre>
          ) : (
            <div className="logs-empty">
              <p>No logs available for this container.</p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default LogsModal;
