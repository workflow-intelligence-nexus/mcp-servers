import React from 'react';

function MonitoringPanel() {
  return (
    <div>
      <h1>Monitoring Panel</h1>
      <p>View logs and status for running MCP servers.</p>
      {/* Placeholder for monitoring details */}
      <div>
        <h2>Server Logs (brave-mcp-server)</h2>
        <pre>
          <code>
            Log line 1...
            Log line 2...
            {/* Add live logs here */}
          </code>
        </pre>
      </div>
      <div>
        <h2>Resource Usage</h2>
        <p>CPU: 5%, Memory: 128MB</p>
        {/* Add graphs or more details */}
      </div>
    </div>
  );
}

export default MonitoringPanel;
