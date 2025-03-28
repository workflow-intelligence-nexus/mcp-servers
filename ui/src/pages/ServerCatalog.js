import React from 'react';

function ServerCatalog() {
  return (
    <div>
      <h1>Server Catalog</h1>
      <p>Browse and manage available MCP servers.</p>
      {/* Placeholder for server list */}
      <div>
        <input type="text" placeholder="Search servers..." />
        <ul>
          <li>Brave Search MCP Server <button>Deploy</button></li>
          <li>Filesystem MCP Server <button>Deploy</button></li>
          {/* Add more servers dynamically */}
        </ul>
      </div>
    </div>
  );
}

export default ServerCatalog;
