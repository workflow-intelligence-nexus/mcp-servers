import React from 'react';

function Settings() {
  return (
    <div>
      <h1>Settings</h1>
      <p>Configure the MCP Deployment Manager application.</p>
      {/* Placeholder for settings form */}
      <form>
        <div>
          <label htmlFor="dockerPath">Docker Path:</label>
          <input type="text" id="dockerPath" defaultValue="/usr/local/bin/docker" />
        </div>
        <div>
          <label htmlFor="claudeConfigPath">Claude Config Path:</label>
          <input type="text" id="claudeConfigPath" defaultValue="%APPDATA%\Claude\claude_desktop_config.json" />
        </div>
        <button type="submit">Save Settings</button>
      </form>
    </div>
  );
}

export default Settings;
