import React from 'react';

function CredentialManager() {
  return (
    <div>
      <h1>Credential Manager</h1>
      <p>Securely store and manage your API keys and credentials.</p>
      {/* Placeholder for credential management UI */}
      <div>
        <button>Add New Credential</button>
        <ul>
          <li>
            <strong>Brave API Key</strong> (Used by: Brave Search MCP)
            <button>Edit</button> <button>Delete</button>
          </li>
          {/* Add more credentials dynamically */}
        </ul>
      </div>
    </div>
  );
}

export default CredentialManager;
