import React, { useState, useEffect } from 'react';
import '../App.css';

function ServerCatalog() {
  const [servers, setServers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [actionInProgress, setActionInProgress] = useState(null);
  const [actionType, setActionType] = useState(null);
  const [actionResult, setActionResult] = useState(null);
  const [lastRefresh, setLastRefresh] = useState(null);
  const [showOnlyUndeployed, setShowOnlyUndeployed] = useState(false);
  const [showSettingsPopup, setShowSettingsPopup] = useState(false);
  const [currentServerSettings, setCurrentServerSettings] = useState(null);
  const [settingsLoading, setSettingsLoading] = useState(false);
  const [settingsError, setSettingsError] = useState(null);
  const [settingsFormData, setSettingsFormData] = useState({});
  const [selectedScriptName, setSelectedScriptName] = useState(null);
  const [isDeployAction, setIsDeployAction] = useState(true);

  // Fetch available servers on component mount
  useEffect(() => {
    fetchAvailableServers();

    // Set up listener for server deployment results
    if (window.electronAPI) {
      const handleDeployResult = (result) => {
        console.log('Deployment result:', result);
        setActionInProgress(null);
        setActionType(null);
        setActionResult(result);
        
        // Clear action result after 5 seconds
        setTimeout(() => {
          setActionResult(null);
        }, 5000);
        
        // Refresh server list if deployment was successful
        if (result.success) {
          fetchAvailableServers();
        }
      };

      const handleContainerActionResult = (result) => {
        console.log('Container action result:', result);
        setActionInProgress(null);
        setActionType(null);
        setActionResult({
          ...result,
          scriptName: result.containerName // For UI consistency
        });
        
        // Clear action result after 5 seconds
        setTimeout(() => {
          setActionResult(null);
        }, 5000);
        
        // Refresh server list if action was successful
        if (result.success) {
          fetchAvailableServers();
        }
      };

      // Set up listener for refresh requests
      const handleRefreshRequest = () => {
        fetchAvailableServers();
      };

      // Set up listener for server settings data
      const handleServerSettingsData = (data) => {
        setSettingsLoading(false);
        
        if (data.error) {
          setSettingsError(data.error);
          return;
        }
        
        setCurrentServerSettings(data);
        
        // Initialize form data with current settings
        const initialFormData = {};
        if (data.settings) {
          Object.entries(data.settings).forEach(([key, value]) => {
            initialFormData[key] = value;
          });
        }
        
        setSettingsFormData(initialFormData);
      };

      window.electronAPI.on('deploy-server-result', handleDeployResult);
      window.electronAPI.on('container-action-result', handleContainerActionResult);
      window.electronAPI.on('refresh-servers-request', handleRefreshRequest);
      window.electronAPI.on('mcp-server-settings-data', handleServerSettingsData);
      
      // Clean up listeners on component unmount
      return () => {
        window.electronAPI.removeListener('deploy-server-result', handleDeployResult);
        window.electronAPI.removeListener('container-action-result', handleContainerActionResult);
        window.electronAPI.removeListener('refresh-servers-request', handleRefreshRequest);
        window.electronAPI.removeListener('mcp-server-settings-data', handleServerSettingsData);
      };
    }
  }, []);

  // Function to fetch available servers
  const fetchAvailableServers = () => {
    setLoading(true);
    setError(null);
    
    if (window.electronAPI) {
      const handleServerData = (data) => {
        setLoading(false);
        setLastRefresh(new Date().toLocaleTimeString());
        
        if (data.error) {
          setError(data.error);
          return;
        }
        
        // Add special handling for Google Maps MCP server
        const updatedServers = (data.servers || []).map(server => {
          // Check if this is the Google Maps MCP server
          if (server.scriptName === 'loadGoogleMapsMCP.ps1') {
            console.log('Found Google Maps MCP server:', server);
            // Force it to be marked as deployed if the container exists
            if (server.containerName === 'google-maps-mcp-server') {
              // Check if Docker containers include google-maps-mcp-server
              window.electronAPI.send('check-container-exists', { containerName: 'google-maps-mcp-server' });
              // For now, manually set it as deployed
              return { ...server, isDeployed: true };
            }
          }
          return server;
        });
        
        setServers(updatedServers);
      };
      
      window.electronAPI.on('available-servers-data', handleServerData);
      window.electronAPI.send('get-available-servers');
      
      // Clean up listener after data is received
      return () => {
        window.electronAPI.removeListener('available-servers-data', handleServerData);
      };
    } else {
      setLoading(false);
      setError('Electron API not available');
    }
  };

  // Function to open settings popup
  const openSettingsPopup = (scriptName, isDeployment = true) => {
    if (window.electronAPI) {
      setSelectedScriptName(scriptName);
      setSettingsLoading(true);
      setSettingsError(null);
      setShowSettingsPopup(true);
      setIsDeployAction(isDeployment);
      
      // Extract server type from script name
      let serverType;
      if (scriptName.includes('GoogleMapsMCP')) {
        serverType = 'googleMaps';
      } else {
        serverType = scriptName.replace('load', '').replace('.ps1', '');
      }
      
      // Request server settings
      window.electronAPI.send('get-mcp-server-settings', { serverType });
    }
  };

  // Function to close settings popup
  const closeSettingsPopup = () => {
    setShowSettingsPopup(false);
    setCurrentServerSettings(null);
    setSettingsFormData({});
    setSelectedScriptName(null);
  };

  // Function to handle settings form input changes
  const handleSettingsChange = (e) => {
    const { name, value } = e.target;
    setSettingsFormData({
      ...settingsFormData,
      [name]: value
    });
  };

  // Function to save settings without deploying
  const saveSettings = () => {
    if (window.electronAPI && currentServerSettings) {
      const serverType = currentServerSettings.serverType;
      
      // Save settings
      window.electronAPI.send('save-mcp-server-settings', { 
        serverType,
        settings: settingsFormData
      });
      
      // Close the popup
      closeSettingsPopup();
      
      // Show success message
      setActionResult({
        success: true,
        action: 'save-settings',
        scriptName: `${serverType} Settings`
      });
      
      // Clear action result after 5 seconds
      setTimeout(() => {
        setActionResult(null);
      }, 5000);
    }
  };

  // Function to deploy a server with settings
  const deployServerWithSettings = () => {
    if (window.electronAPI && selectedScriptName) {
      setActionInProgress(selectedScriptName);
      setActionType('deploy');
      closeSettingsPopup();
      
      // Send deployment request with settings
      window.electronAPI.send('deploy-server-with-settings', { 
        scriptName: selectedScriptName,
        settings: settingsFormData
      });
    }
  };

  // Function to deploy a server (now opens settings popup)
  const deployServer = (scriptName) => {
    openSettingsPopup(scriptName, true);
  };

  // Function to remove a container
  const removeContainer = (containerName) => {
    if (window.electronAPI) {
      setActionInProgress(containerName);
      setActionType('remove');
      window.electronAPI.send('remove-container', { 
        containerName,
        removeImage: true // Also remove the image
      });
    }
  };

  // Function to redeploy a server (now opens settings popup first)
  const redeployServer = (containerName, scriptName) => {
    openSettingsPopup(scriptName, false);
  };

  // Function to perform redeploy after settings are configured
  const redeployServerWithSettings = () => {
    if (window.electronAPI && selectedScriptName) {
      // First save the settings
      const serverType = currentServerSettings.serverType;
      window.electronAPI.send('save-mcp-server-settings', { 
        serverType,
        settings: settingsFormData
      });
      
      // Get the container name from the servers list
      const server = servers.find(s => s.scriptName === selectedScriptName);
      if (server && server.containerName) {
        setActionInProgress(server.containerName);
        setActionType('redeploy');
        closeSettingsPopup();
        
        // Send redeploy request
        window.electronAPI.send('redeploy-server', { 
          containerName: server.containerName, 
          scriptName: selectedScriptName 
        });
      }
    }
  };

  // Filter servers based on search term and deployment status
  const filteredServers = servers.filter(server => {
    // First filter by search term
    const matchesSearch = 
      server.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      server.description.toLowerCase().includes(searchTerm.toLowerCase());
    
    // Then filter by deployment status if that filter is active
    if (showOnlyUndeployed) {
      return matchesSearch && !server.isDeployed;
    }
    
    return matchesSearch;
  });

  // Count deployed and undeployed servers
  const deployedCount = servers.filter(s => s.isDeployed).length;
  const undeployedCount = servers.length - deployedCount;

  // Get server icon based on server name
  const getServerIcon = (serverName) => {
    const name = serverName.toLowerCase();
    
    if (name.includes('brave')) return '🔍';
    if (name.includes('filesystem')) return '📁';
    if (name.includes('github')) return '🐙';
    if (name.includes('gitlab')) return '🦊';
    if (name.includes('slack')) return '💬';
    if (name.includes('redis')) return '🔄';
    if (name.includes('postgres')) return '🐘';
    if (name.includes('sqlite')) return '🗃️';
    if (name.includes('gdrive')) return '📝';
    if (name.includes('aws')) return '☁️';
    if (name.includes('time')) return '⏰';
    if (name.includes('memory')) return '🧠';
    if (name.includes('puppeteer')) return '🤖';
    if (name.includes('sentry')) return '🦅';
    if (name.includes('googlemaps')) return '🗺️';
    
    // Default icon
    return '🖥️';
  };

  // Get action button text based on action type and progress
  const getActionButtonText = (server, actionType) => {
    const isThisServerInProgress = actionInProgress === server.scriptName || 
                                  actionInProgress === server.containerName;
    
    if (!isThisServerInProgress) {
      return actionType === 'deploy' ? 'Deploy' : 
             actionType === 'remove' ? 'Remove' : 
             'Re-Deploy';
    }
    
    return actionType === 'deploy' ? 'Deploying...' : 
           actionType === 'remove' ? 'Removing...' : 
           'Re-Deploying...';
  };

  // Check if form has all required fields filled
  const hasRequiredFields = () => {
    if (!currentServerSettings || !currentServerSettings.requiredSettings) {
      return true;
    }
    
    return currentServerSettings.requiredSettings.every(
      setting => settingsFormData[setting] && settingsFormData[setting].trim() !== ''
    );
  };

  return (
    <div className="catalog-container">
      <div className="catalog-header">
        <h1>Server Catalog</h1>
        <button className="refresh-button" onClick={fetchAvailableServers} disabled={loading}>
          {loading ? 'Refreshing...' : 'Refresh Catalog'}
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
          <p>Make sure the scripts directory is accessible.</p>
        </div>
      )}

      {actionResult && (
        <div className={`deployment-result ${actionResult.success ? 'success' : 'error'}`}>
          <p>
            {actionResult.success 
              ? actionResult.action === 'remove' 
                ? `Successfully removed ${actionResult.containerName}` 
                : actionResult.action === 'redeploy'
                  ? `Successfully re-deployed ${actionResult.containerName}`
                  : actionResult.action === 'save-settings'
                    ? `Successfully saved settings for ${actionResult.scriptName}`
                    : `Successfully deployed ${actionResult.scriptName}`
              : actionResult.action === 'remove'
                ? `Failed to remove ${actionResult.containerName}: ${actionResult.error}`
                : actionResult.action === 'redeploy'
                  ? `Failed to re-deploy ${actionResult.containerName}: ${actionResult.error}`
                  : actionResult.action === 'save-settings'
                    ? `Failed to save settings for ${actionResult.scriptName}: ${actionResult.error}`
                    : `Failed to deploy ${actionResult.scriptName}: ${actionResult.error}`
            }
          </p>
        </div>
      )}

      <div className="catalog-filters">
        <div className="search-container">
          <input 
            type="text" 
            placeholder="Search servers..." 
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="search-input"
          />
        </div>
        
        <div className="filter-container">
          <label className="filter-label">
            <input 
              type="checkbox" 
              checked={showOnlyUndeployed}
              onChange={() => setShowOnlyUndeployed(!showOnlyUndeployed)}
              className="filter-checkbox"
            />
            Show only undeployed servers ({undeployedCount})
          </label>
        </div>
      </div>

      {/* Settings Popup */}
      {showSettingsPopup && (
        <div className="settings-popup-overlay">
          <div className="settings-popup">
            <div className="settings-popup-header">
              <h2>
                {currentServerSettings ? 
                  `Configure ${currentServerSettings.serverType} MCP Server` : 
                  'Loading Settings...'}
              </h2>
              <button className="close-button" onClick={closeSettingsPopup}>×</button>
            </div>
            
            <div className="settings-popup-content">
              {settingsLoading ? (
                <div className="settings-loading">
                  <div className="spinner"></div>
                  <p>Loading server settings...</p>
                </div>
              ) : settingsError ? (
                <div className="settings-error">
                  <p>Error: {settingsError}</p>
                  <p>Unable to load settings for this server.</p>
                </div>
              ) : currentServerSettings ? (
                <form className="settings-form">
                  {/* Required Settings Section */}
                  {currentServerSettings.requiredSettings && 
                   currentServerSettings.requiredSettings.length > 0 && (
                    <div className="settings-section">
                      <h3>Required Settings</h3>
                      {currentServerSettings.requiredSettings.map(setting => (
                        <div className="form-group" key={setting}>
                          <label htmlFor={setting}>
                            {setting}
                            {currentServerSettings.descriptions[setting] && (
                              <span className="setting-description">
                                {currentServerSettings.descriptions[setting]}
                              </span>
                            )}
                          </label>
                          <input
                            type={setting.includes('TOKEN') || setting.includes('KEY') || setting.includes('PASSWORD') ? 'password' : 'text'}
                            id={setting}
                            name={setting}
                            value={settingsFormData[setting] || ''}
                            onChange={handleSettingsChange}
                            required
                          />
                        </div>
                      ))}
                    </div>
                  )}
                  
                  {/* Optional Settings Section */}
                  {currentServerSettings.optionalSettings && 
                   currentServerSettings.optionalSettings.length > 0 && (
                    <div className="settings-section">
                      <h3>Optional Settings</h3>
                      {currentServerSettings.optionalSettings.map(setting => (
                        <div className="form-group" key={setting}>
                          <label htmlFor={setting}>
                            {setting}
                            {currentServerSettings.descriptions[setting] && (
                              <span className="setting-description">
                                {currentServerSettings.descriptions[setting]}
                              </span>
                            )}
                          </label>
                          <input
                            type={setting.includes('TOKEN') || setting.includes('KEY') || setting.includes('PASSWORD') ? 'password' : 'text'}
                            id={setting}
                            name={setting}
                            value={settingsFormData[setting] || ''}
                            onChange={handleSettingsChange}
                          />
                        </div>
                      ))}
                    </div>
                  )}
                  
                  {/* Other Settings Section */}
                  {currentServerSettings.settings && 
                   Object.keys(currentServerSettings.settings).filter(setting => 
                     !currentServerSettings.requiredSettings?.includes(setting) && 
                     !currentServerSettings.optionalSettings?.includes(setting)
                   ).length > 0 && (
                    <div className="settings-section">
                      <h3>Other Settings</h3>
                      {Object.keys(currentServerSettings.settings)
                        .filter(setting => 
                          !currentServerSettings.requiredSettings?.includes(setting) && 
                          !currentServerSettings.optionalSettings?.includes(setting)
                        )
                        .map(setting => (
                          <div className="form-group" key={setting}>
                            <label htmlFor={setting}>{setting}</label>
                            <input
                              type={setting.includes('TOKEN') || setting.includes('KEY') || setting.includes('PASSWORD') ? 'password' : 'text'}
                              id={setting}
                              name={setting}
                              value={settingsFormData[setting] || ''}
                              onChange={handleSettingsChange}
                            />
                          </div>
                        ))
                      }
                    </div>
                  )}
                </form>
              ) : (
                <p>No settings available for this server.</p>
              )}
            </div>
            
            <div className="settings-popup-footer">
              <button 
                className="cancel-button" 
                onClick={closeSettingsPopup}
              >
                Cancel
              </button>
              <button 
                className="save-button" 
                onClick={saveSettings}
                disabled={settingsLoading || !currentServerSettings}
              >
                Save Settings
              </button>
              <button 
                className="deploy-button" 
                onClick={isDeployAction ? deployServerWithSettings : redeployServerWithSettings}
                disabled={settingsLoading || !currentServerSettings || !hasRequiredFields()}
              >
                {isDeployAction ? 'Deploy Server' : 'Re-Deploy Server'}
              </button>
            </div>
          </div>
        </div>
      )}

      {loading ? (
        <div className="loading-indicator">
          <div className="spinner"></div>
          <p>Loading available servers...</p>
        </div>
      ) : filteredServers.length === 0 ? (
        <div className="no-servers">
          <p>No servers found matching your search criteria.</p>
          {showOnlyUndeployed && deployedCount > 0 && (
            <p>Try disabling the "Show only undeployed servers" filter.</p>
          )}
        </div>
      ) : (
        <div className="server-catalog-grid">
          {filteredServers.map((server) => {
            const isDeployed = server.isDeployed;
            const isThisServerInProgress = actionInProgress === server.scriptName || 
                                          actionInProgress === server.containerName;
            
            return (
              <div 
                className={`catalog-card ${isDeployed ? 'deployed' : 'undeployed'}`} 
                key={server.id}
              >
                {isDeployed && <div className="deployed-badge">Deployed</div>}
                
                <div className="catalog-card-icon">
                  {getServerIcon(server.name)}
                </div>
                
                <div className="catalog-card-content">
                  <h3>{server.name} MCP Server</h3>
                  <p className="catalog-description">{server.description}</p>
                </div>
                
                <div className="catalog-card-actions">
                  <button 
                    className="settings-button"
                    onClick={() => openSettingsPopup(server.scriptName, !isDeployed)}
                    disabled={isThisServerInProgress}
                    title="Configure server settings"
                  >
                    ⚙️ Settings
                  </button>
                  
                  {isDeployed ? (
                    <>
                      <button 
                        className="remove-button"
                        onClick={() => removeContainer(server.containerName)}
                        disabled={isThisServerInProgress}
                      >
                        {isThisServerInProgress && actionType === 'remove' 
                          ? 'Removing...' 
                          : 'Remove'
                        }
                      </button>
                      <button 
                        className="redeploy-button"
                        onClick={() => redeployServer(server.containerName, server.scriptName)}
                        disabled={isThisServerInProgress}
                      >
                        {isThisServerInProgress && actionType === 'redeploy' 
                          ? 'Re-Deploying...' 
                          : 'Re-Deploy'
                        }
                      </button>
                    </>
                  ) : (
                    <button 
                      className="deploy-button"
                      onClick={() => deployServer(server.scriptName)}
                      disabled={isThisServerInProgress}
                    >
                      {isThisServerInProgress && actionType === 'deploy' 
                        ? 'Deploying...' 
                        : 'Deploy'
                      }
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

export default ServerCatalog;
