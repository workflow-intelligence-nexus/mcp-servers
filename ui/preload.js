const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // Send from renderer to main
  send: (channel, data) => {
    // Whitelist channels
    const validChannels = [
      'get-running-servers', 
      'get-container-logs',
      'restart-container',
      'stop-container',
      'start-container',
      'get-available-servers',
      'deploy-server',
      'remove-container',
      'redeploy-server',
      'get-server-settings',
      'save-server-settings',
      'deploy-server-with-settings',
      'get-mcp-server-settings',
      'save-mcp-server-settings'
    ];
    if (validChannels.includes(channel)) {
      ipcRenderer.send(channel, data);
    }
  },
  // Receive from main to renderer
  on: (channel, func) => {
    const validChannels = [
      'running-servers-data', 
      'container-logs-data',
      'container-action-result',
      'refresh-servers-request',
      'available-servers-data',
      'deploy-server-result',
      'server-settings-data',
      'mcp-server-settings-data'
    ];
    if (validChannels.includes(channel)) {
      // Deliberately strip event as it includes `sender`
      ipcRenderer.on(channel, (event, ...args) => func(...args));
    }
  },
  // Clean up listener
  removeListener: (channel, func) => {
    const validChannels = [
      'running-servers-data', 
      'container-logs-data',
      'container-action-result',
      'refresh-servers-request',
      'available-servers-data',
      'deploy-server-result',
      'server-settings-data',
      'mcp-server-settings-data'
    ];
    if (validChannels.includes(channel)) {
      ipcRenderer.removeListener(channel, func);
    }
  }
});

console.log('Preload script loaded.');
