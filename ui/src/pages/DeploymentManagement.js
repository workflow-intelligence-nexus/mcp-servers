import React from 'react';

function DeploymentManagement() {
  return (
    <div>
      <h1>Active Deployments</h1>
      <p>Manage your currently deployed MCP servers.</p>
      {/* Placeholder for deployment list */}
      <table>
        <thead>
          <tr>
            <th>Server Name</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr>
            <td>brave-mcp-server</td>
            <td>Running</td>
            <td><button>Stop</button> <button>Configure</button> <button>Remove</button></td>
          </tr>
          {/* Add more deployments dynamically */}
        </tbody>
      </table>
    </div>
  );
}

export default DeploymentManagement;
