# MCP Server Catalog Processes Documentation

This document outlines the design, implementation, and best practices for the MCP Server Catalog UI, focusing particularly on the settings management process for deploying and configuring MCP servers through the UI.

## Overview

The MCP Server Catalog enables users to:
1. Browse available MCP servers in a visual catalog
2. Configure server-specific settings through dedicated settings popups
3. Deploy servers with custom configurations
4. Modify settings after deployment and redeploy with updated configurations
5. Store and retrieve settings persistently across sessions

## Settings Management Architecture

### Core Principles

1. **User-Friendly Configuration**: Provide intuitive UI for configuring complex MCP servers
2. **Persistence**: Save user settings beyond the current session
3. **Security**: Securely handle sensitive information like API keys
4. **Consistency**: Maintain consistent UI and UX patterns across all server types
5. **Flexibility**: Support a variety of configuration parameters based on server requirements

### Settings File Structure

Each MCP server follows a standardized approach for settings management:

1. **Settings File Location**: All settings files are stored in the `scripts/settings/` directory
2. **Naming Convention**: Each MCP server has a dedicated `{toolname}Settings.env` file
3. **Example Files**: Every server provides a `{toolname}Settings.example.env` with placeholders and documentation
4. **Security**: Files containing sensitive information are added to `.gitignore`
5. **Format**: Settings use KEY=VALUE format with explanatory comments

### Backend to Frontend Integration

The settings workflow integrates the following components:

1. **PowerShell Deployment Scripts**: Load settings from `{toolname}Settings.env` files
2. **Electron Main Process**: Mediates between the UI and the file system
3. **React UI Components**: Present settings forms and handle user input
4. **IPC Channels**: Enable secure communication between the UI and Electron process

## Settings Popup Implementation

### UI Requirements

1. **Settings Button**: Each server card in the catalog should display a settings button
2. **Modal Design**: The settings popup should appear as a modal dialog
3. **Form Layout**: Settings should be organized in logical sections (Required/Optional)
4. **Input Validation**: Required fields should be validated before submission
5. **Loading/Error States**: The popup should handle loading and error states gracefully
6. **Responsive Design**: The popup should be responsive and match the main application's UI style

### Settings Persistence

Settings should be saved permanently using the following approach:

1. **Storage Location**: Settings are saved to `{toolname}Settings.env` files in the `scripts/settings/` directory
2. **Loading Process**: When opening the settings popup, existing settings are loaded from the settings file
3. **Saving Process**: When submitting the form, settings are saved to the settings file
4. **Format Preservation**: Comments and formatting in the original file should be preserved when possible
5. **Default Values**: If a settings file doesn't exist, default values should be used based on the example file

### Required Settings Flow

1. **Deployment Initiation**: When a user clicks the Deploy button without having configured required settings
2. **Settings Detection**: The system checks if all required settings are available
3. **Automatic Popup**: If required settings are missing, the settings popup automatically appears
4. **Form Submission**: After completing the form, the system proceeds with deployment
5. **Validation**: The system validates all required fields before allowing deployment

## Implementation Details

### IPC Channels

The following IPC channels should be implemented:

1. **get-server-settings**: Retrieves the current settings for a specific server
   ```javascript
   // Retrieves settings from the {toolname}Settings.env file
   ipcMain.handle('get-server-settings', async (event, serverType) => {
     // Read and parse settings file, returning an object with current values
   });
   ```

2. **save-server-settings**: Saves user-defined settings to the settings file
   ```javascript
   // Saves settings to the {toolname}Settings.env file
   ipcMain.handle('save-server-settings', async (event, { serverType, settings }) => {
     // Write settings to the appropriate file
   });
   ```

3. **deploy-server-with-settings**: Deploys a server with user-defined settings
   ```javascript
   // Deploys server after confirming settings are properly configured
   ipcMain.on('deploy-server-with-settings', (event, { serverType, settings }) => {
     // Save settings and execute deployment script
   });
   ```

### Settings Format

Settings should follow a consistent format in the UI:

```javascript
{
  // Setting ID matches the environment variable name
  "SETTING_NAME": {
    "value": "currentValue", // Current value of the setting
    "label": "Human Readable Name", // Display name in the UI
    "description": "Detailed explanation of the setting", // Help text
    "required": true, // Whether the setting is required
    "type": "text", // Input type (text, password, number, etc.)
    "default": "defaultValue" // Default value if not set
  }
}
```

### Accessing Settings in Deployment Scripts

PowerShell deployment scripts should load settings using a consistent pattern:

```powershell
# Function to load settings from a tool-specific settings file
function Import-ToolSettings {
    param (
        [string]$SettingsFilePath
    )
    
    $settings = @{}
    
    if (-not (Test-Path $SettingsFilePath)) {
        Write-Host "Settings file not found at $SettingsFilePath, using default settings" -ForegroundColor Yellow
        return $settings
    }
    
    # Read and process each line in the settings file
    Get-Content $SettingsFilePath | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#')) {
            $line = $_.Trim()
            if ($line -match '(.+?)=(.*)') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                # Only set if value is not empty
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $settings[$key] = $value
                }
            }
        }
    }
    
    return $settings
}

# Example usage
$settings = Import-ToolSettings -SettingsFilePath $SettingsFile
```

## User Experience Flow

### Initial Deployment

1. User navigates to the Server Catalog page
2. User locates the desired MCP server card
3. User clicks the Settings button on the server card
4. Settings popup appears with form fields for required and optional settings
5. User completes the form and clicks Save
6. Settings are stored in the appropriate settings file
7. User clicks Deploy button
8. System validates settings are complete
9. Deployment process begins with the configured settings

### Changing Settings After Deployment

1. User navigates to the Server Catalog or Dashboard page
2. User locates the deployed MCP server
3. User clicks the Settings button
4. Settings popup appears with current values pre-filled
5. User modifies settings and clicks Save
6. Settings are updated in the settings file
7. User clicks Re-deploy button
8. System updates the deployment with new settings

## Best Practices for Implementation

1. **Field Validation**: Validate all required fields before enabling the Deploy button
2. **Sensitive Data Handling**: Use input type "password" for API keys and sensitive information
3. **Loading States**: Display loading indicators when fetching or saving settings
4. **Error Handling**: Show clear error messages if settings cannot be saved or loaded
5. **Tooltips**: Provide tooltips or help text explaining each setting
6. **Default Values**: Pre-populate fields with sensible default values where appropriate
7. **Consistent Design**: Follow the application's design system for UI components
8. **Keyboard Navigation**: Support keyboard navigation and form submission
9. **Accessibility**: Ensure the popup is accessible to all users

## Settings Examples

### Google Maps MCP Server

The Google Maps MCP server requires the following settings:

```env
# Google Maps API Key (Required)
# You must provide a valid Google Maps API key with appropriate permissions
GOOGLE_MAPS_API_KEY=

# Optional: Default search location
DEFAULT_LOCATION=New York, NY

# Optional: Default map zoom level (1-20)
DEFAULT_ZOOM=10

# Optional: Map type (roadmap, satellite, hybrid, terrain)
MAP_TYPE=roadmap
```

### GitHub MCP Server

The GitHub MCP server requires the following settings:

```env
# GitHub Personal Access Token (Required)
# Generate a token at https://github.com/settings/tokens
# Required scopes: repo, read:user
GITHUB_TOKEN=

# Optional: Default GitHub username to use for operations
DEFAULT_USERNAME=

# Optional: Default repository to open
DEFAULT_REPO=
```

## Security Considerations

1. **API Key Protection**: Never expose API keys in the UI or logs
2. **Environment Variables**: Store sensitive information as environment variables
3. **File Permissions**: Ensure settings files have appropriate file system permissions
4. **In-Memory Protection**: Clear sensitive data from memory when no longer needed
5. **Encryption**: Consider encrypting sensitive settings at rest

## Implementation Details

### IPC Channels Implementation

The following IPC channels have been implemented to facilitate settings management:

1. **get-mcp-server-settings**: Retrieves the current settings for a specific server
   ```javascript
   // In electron.js
   ipcMain.on('get-mcp-server-settings', (event, { serverType }) => {
     try {
       // Determine the settings file path
       const settingsDir = path.join(__dirname, '..', 'scripts', 'settings');
       const settingsPath = path.join(settingsDir, `${serverType}Settings.env`);
       const exampleSettingsPath = path.join(settingsDir, `${serverType}Settings.example.env`);
       
       // Initialize settings object
       let settings = {};
       let requiredSettings = [];
       let optionalSettings = [];
       let settingsDescriptions = {};
       
       // Parse example file to extract required/optional settings and descriptions
       if (fs.existsSync(exampleSettingsPath)) {
         const exampleContent = fs.readFileSync(exampleSettingsPath, 'utf8');
         const lines = exampleContent.split('\n');
         
         let currentSection = null;
         
         for (const line of lines) {
           // Check for section headers
           if (line.includes('Required Settings:')) {
             currentSection = 'required';
             continue;
           } else if (line.includes('Optional Settings:')) {
             currentSection = 'optional';
             continue;
           }
           
           // Parse setting definitions
           if (line.trim().startsWith('#') && line.includes('-')) {
             const settingMatch = line.match(/# ([A-Z_]+) - (.+)/);
             if (settingMatch) {
               const [, settingName, description] = settingMatch;
               settingsDescriptions[settingName] = description;
               
               if (currentSection === 'required') {
                 requiredSettings.push(settingName);
               } else if (currentSection === 'optional') {
                 optionalSettings.push(settingName);
               }
             }
           }
           
           // Look for default values in commented examples
           const defaultMatch = line.match(/^# ?([A-Z_]+)=(.+)/);
           if (defaultMatch) {
             const [, settingName, defaultValue] = defaultMatch;
             if (!settings[settingName]) {
               settings[settingName] = defaultValue;
             }
           }
         }
       }
       
       // Load existing settings if available
       if (fs.existsSync(settingsPath)) {
         const content = fs.readFileSync(settingsPath, 'utf8');
         const lines = content.split('\n');
         
         for (const line of lines) {
           if (!line.trim().startsWith('#') && line.includes('=')) {
             const [key, value] = line.split('=');
             settings[key.trim()] = value.trim();
           }
         }
       }
       
       // Send settings data back to renderer
       event.reply('mcp-server-settings-data', {
         settings,
         requiredSettings,
         optionalSettings,
         descriptions: settingsDescriptions,
         serverType
       });
     } catch (error) {
       console.error(`Error getting server settings: ${error.message}`);
       event.reply('mcp-server-settings-data', { 
         error: `Failed to get server settings: ${error.message}`,
         serverType
       });
     }
   });
   ```

2. **save-mcp-server-settings**: Saves user-defined settings to the settings file
   ```javascript
   // In electron.js
   ipcMain.on('save-mcp-server-settings', (event, { serverType, settings }) => {
     try {
       // Determine the settings file path
       const settingsDir = path.join(__dirname, '..', 'scripts', 'settings');
       const settingsPath = path.join(settingsDir, `${serverType}Settings.env`);
       
       // Create settings directory if it doesn't exist
       if (!fs.existsSync(settingsDir)) {
         fs.mkdirSync(settingsDir, { recursive: true });
       }
       
       // Create settings content
       let settingsContent = `# ${serverType} MCP Server Settings\n# Generated by MCP Deployment Manager\n\n`;
       
       // Add each setting to the content
       Object.entries(settings).forEach(([key, value]) => {
         if (value) {
           settingsContent += `${key}=${value}\n`;
         }
       });
       
       // Write settings to file
       fs.writeFileSync(settingsPath, settingsContent);
       
       // Send success response
       event.reply('mcp-server-settings-data', {
         success: true,
         message: 'Settings saved successfully',
         serverType
       });
     } catch (error) {
       console.error(`Error saving server settings: ${error.message}`);
       event.reply('mcp-server-settings-data', { 
         error: `Failed to save server settings: ${error.message}`,
         serverType
       });
     }
   });
   ```

3. **deploy-server-with-settings**: Deploys a server with user-defined settings
   ```javascript
   // In electron.js
   ipcMain.on('deploy-server-with-settings', (event, { scriptName, settings }) => {
     if (!scriptName) {
       event.reply('deploy-server-result', { 
         error: 'Script name is required',
         scriptName
       });
       return;
     }
     
     try {
       // First save the settings
       const serverType = scriptName.replace('load', '').replace('.ps1', '');
       const settingsDir = path.join(__dirname, '..', 'scripts', 'settings');
       const settingsPath = path.join(settingsDir, `${serverType}Settings.env`);
       
       // Create settings directory if it doesn't exist
       if (!fs.existsSync(settingsDir)) {
         fs.mkdirSync(settingsDir, { recursive: true });
       }
       
       // Create settings content
       let settingsContent = `# ${serverType} MCP Server Settings\n# Generated by MCP Deployment Manager\n\n`;
       
       // Add each setting to the content
       Object.entries(settings).forEach(([key, value]) => {
         if (value) {
           settingsContent += `${key}=${value}\n`;
         }
       });
       
       // Write settings to file
       fs.writeFileSync(settingsPath, settingsContent);
       
       // Now deploy the server
       const scriptsPath = path.join(__dirname, '..', 'scripts', 'windows');
       const scriptPath = path.join(scriptsPath, scriptName);
       
       if (!fs.existsSync(scriptPath)) {
         event.reply('deploy-server-result', { 
           error: `Script not found: ${scriptPath}`,
           scriptName
         });
         return;
       }
       
       // Execute the PowerShell script
       const command = `powershell -ExecutionPolicy Bypass -File "${scriptPath}"`;
       
       exec(command, (error, stdout, stderr) => {
         if (error) {
           console.error(`Error deploying server: ${error.message}`);
           event.reply('deploy-server-result', { 
             error: `Deployment failed: ${error.message}`,
             scriptName,
             stdout,
             stderr
           });
           return;
         }
         
         console.log(`Server deployed: ${scriptName}`);
         console.log(`Output: ${stdout}`);
         
         event.reply('deploy-server-result', { 
           success: true,
           message: 'Server deployed successfully',
           scriptName,
           stdout
         });
         
         // Refresh the server list
         event.reply('refresh-servers-request');
       });
     } catch (error) {
       console.error(`Error deploying server: ${error.message}`);
       event.reply('deploy-server-result', { 
         error: `Deployment failed: ${error.message}`,
         scriptName
       });
     }
   });
   ```

### React Component Implementation

The settings popup is implemented in the ServerCatalog.js component with the following key features:

1. **State Management**: Uses React state to manage settings form data and UI states
   ```javascript
   const [showSettingsPopup, setShowSettingsPopup] = useState(false);
   const [currentServerSettings, setCurrentServerSettings] = useState(null);
   const [settingsLoading, setSettingsLoading] = useState(false);
   const [settingsError, setSettingsError] = useState(null);
   const [settingsFormData, setSettingsFormData] = useState({});
   const [selectedScriptName, setSelectedScriptName] = useState(null);
   const [isDeployAction, setIsDeployAction] = useState(true);
   ```

2. **Settings Button**: Each server card includes a dedicated settings button
   ```javascript
   <button 
     className="settings-button"
     onClick={() => openSettingsPopup(server.scriptName, !isDeployed)}
     disabled={isThisServerInProgress}
     title="Configure server settings"
   >
     ⚙️ Settings
   </button>
   ```

3. **Settings Popup**: A modal dialog that displays settings form
   ```javascript
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
           {/* Settings form content */}
         </div>
         
         <div className="settings-popup-footer">
           <button className="cancel-button" onClick={closeSettingsPopup}>
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
   ```

4. **Form Validation**: Validates required fields before enabling deployment
   ```javascript
   const hasRequiredFields = () => {
     if (!currentServerSettings || !currentServerSettings.requiredSettings) {
       return true;
     }
     
     return currentServerSettings.requiredSettings.every(
       setting => settingsFormData[setting] && settingsFormData[setting].trim() !== ''
     );
   };
   ```

5. **Sensitive Data Handling**: Uses password input type for sensitive information
   ```javascript
   <input
     type={setting.includes('TOKEN') || setting.includes('KEY') || setting.includes('PASSWORD') ? 'password' : 'text'}
     id={setting}
     name={setting}
     value={settingsFormData[setting] || ''}
     onChange={handleSettingsChange}
     required
   />
   ```

## Final Implementation Notes

The MCP Server Settings popup implementation successfully addresses all the requirements outlined in this document:

1. **User-Friendly Configuration**: The settings popup provides a clear, organized interface for configuring MCP servers
2. **Persistence**: Settings are saved to dedicated files in the `scripts/settings/` directory
3. **Security**: Sensitive information like API keys are handled securely with password fields
4. **Consistency**: The UI follows a consistent pattern across all server types
5. **Flexibility**: The implementation supports both required and optional settings

The architecture enables users to securely store their configuration preferences beyond the current session and easily modify them as needed, enhancing the overall usability of the MCP Deployment Manager.

## Future Enhancements

Potential future enhancements to the settings management system could include:

1. **Settings Profiles**: Allow users to save and switch between multiple configuration profiles
2. **Validation Rules**: Add more sophisticated validation for specific setting types
3. **Import/Export**: Enable importing and exporting settings between installations
4. **Secure Storage**: Implement more secure storage options for sensitive credentials
5. **UI Improvements**: Add more advanced form controls like toggles, dropdowns, and autocomplete

These enhancements would further improve the user experience while maintaining the core principles of the settings management architecture.

## Settings Examples

### Google Maps MCP Server

Example settings file (`googleMapsSettings.example.env`):
```
# Google Maps MCP Server Settings
# Use this file to configure the Google Maps MCP server for Claude Desktop
#
# Format:
# SETTING_NAME=value
#
# Required Settings:
# -----------------
# GOOGLE_MAPS_API_KEY - Your Google Maps API key
#   Get your API key from: https://developers.google.com/maps/documentation/javascript/get-api-key
#   This key is required for the Google Maps MCP server to function
#
# Optional Settings:
# -----------------
# CONTAINER_NAME - Name of the Docker container (default: google-maps-mcp-server)
# DOCKER_IMAGE - Docker image name and tag (default: mcp/google-maps:latest)
# RESTART_CLAUDE - Whether to restart Claude Desktop if it's running (true/false, default: true)
#
# Examples:
# GOOGLE_MAPS_API_KEY=your_api_key_here
# CONTAINER_NAME=my-google-maps-server
# DOCKER_IMAGE=mcp/google-maps:custom
# RESTART_CLAUDE=false
#
# Default settings (uncomment and modify as needed):
GOOGLE_MAPS_API_KEY=
# CONTAINER_NAME=google-maps-mcp-server
# DOCKER_IMAGE=mcp/google-maps:latest
# RESTART_CLAUDE=true
```

## Conclusion

The settings popup mechanism provides a flexible, user-friendly approach to configuring MCP servers while maintaining security and persistence. By following this design, all MCP servers can offer consistent configuration experiences while supporting their unique requirements.

The architecture enables users to securely store their configuration preferences beyond the current session and easily modify them as needed, enhancing the overall usability of the MCP Deployment Manager.
