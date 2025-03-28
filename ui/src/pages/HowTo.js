import React from 'react';
import './../App.css'; // Ensure CSS is imported if not already globally

function HowTo() {
  return (
    <div className="card how-to-section">
      <h1 className="card-header">🚀 How to Use MCP Deployment Manager 🚀</h1>
      <div className="how-to-content">
        <p>Welcome aboard! Let's get you navigating the MCP Deployment Manager like a pro:</p>
        <ul>
          <li><strong>📊 Dashboard:</strong> Get a quick pulse check on your system and jump into action.</li>
          <li><strong>📚 Server Catalog:</strong> Your library of MCP servers. Browse, search, and manage them here.</li>
          <li><strong>⚙️ Deployment Management:</strong> The control center for your active deployments. Start, stop, and tweak configurations.</li>
          <li><strong>📈 Monitoring Panel:</strong> Keep an eye on performance, logs, and resource usage in real-time.</li>
          <li><strong>🔑 Credential Manager:</strong> Your secure vault for API keys and credentials. Keep everything organized and validated.</li>
          <li><strong>🔧 Settings:</strong> Customize the app to match your workflow perfectly.</li>
        </ul>
        <p>Use the sidebar navigation to explore each section. Happy deploying! 🎉</p>
      </div>
    </div>
  );
}

export default HowTo;
