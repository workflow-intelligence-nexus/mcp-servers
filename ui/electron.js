const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const isDev = require('electron-is-dev');
const { exec } = require('child_process');
const fs = require('fs');
const os = require('os');

function createWindow() {
  // Create the browser window.
  const mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'), // Securely expose IPC
      nodeIntegration: false, // Disable for security
      contextIsolation: true, // Enable for security
    },
  });

  // Load the index.html of the app.
  mainWindow.loadURL(
    isDev
      ? 'http://localhost:3011' // Dev server URL
      : `file://${path.join(__dirname, 'build/index.html')}` // Production build path - relative to electron.js
  );

  // Open the DevTools if in development mode.
  if (isDev) {
    mainWindow.webContents.openDevTools();
  }
}

// This method will be called when Electron has finished
// initialization and is ready to create browser windows.
// Some APIs can only be used after this event occurs.
app.whenReady().then(() => {
  createWindow();

  // Listen for requests from the renderer process
  ipcMain.on('get-running-servers', (event) => {
    // Use a more inclusive filter to catch all MCP-related containers
    // Include -a flag to show all containers (running and stopped)
    const command = 'docker ps -a --format "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}"';

    exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`Error executing docker ps: ${error.message}`);
        event.reply('running-servers-data', { error: `Failed to execute docker command: ${error.message}` });
        return;
      }
      if (stderr) {
        console.warn(`Docker ps stderr: ${stderr}`);
      }

      try {
        const lines = stdout.trim().split('\n');
        // No header row in this format string
        const servers = lines.map(line => {
          const [id, name, image, ...statusParts] = line.split('|').map(v => v.trim());
          // Join the status parts back together in case it contained the delimiter
          const status = statusParts.join('|').trim();
          
          return { id, name, image, status };
        });
        
        // Filter for MCP containers - look for "mcp/" in the image name
        const mcpServers = servers.filter(s => s.image && s.image.toLowerCase().includes('mcp/'));
        
        console.log('Found MCP servers:', mcpServers);
        event.reply('running-servers-data', { servers: mcpServers });
      } catch (parseError) {
        console.error(`Error parsing docker output: ${parseError.message}`);
        console.error('Docker output was:', stdout);
        event.reply('running-servers-data', { error: `Failed to parse docker output: ${parseError.message}` });
      }
    });
  });

  // Handle container logs request
  ipcMain.on('get-container-logs', (event, { id }) => {
    if (!id) {
      event.reply('container-logs-data', { error: 'Container ID is required' });
      return;
    }

    // Get the last 500 lines of logs
    const command = `docker logs --tail 500 ${id}`;
    
    exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`Error getting logs for container ${id}: ${error.message}`);
        event.reply('container-logs-data', { error: `Failed to get logs: ${error.message}` });
        return;
      }

      // In Docker, stderr is often used for logs too, so we combine them
      const logs = stdout + (stderr ? '\n' + stderr : '');
      event.reply('container-logs-data', { logs });
    });
  });

  // Handle container restart request
  ipcMain.on('restart-container', (event, { id }) => {
    if (!id) {
      event.reply('container-action-result', { error: 'Container ID is required', action: 'restart' });
      return;
    }

    const command = `docker restart ${id}`;
    
    exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`Error restarting container ${id}: ${error.message}`);
        event.reply('container-action-result', { 
          error: `Failed to restart container: ${error.message}`,
          action: 'restart',
          containerId: id
        });
        return;
      }

      console.log(`Container ${id} restarted successfully`);
      event.reply('container-action-result', { 
        success: true, 
        message: `Container restarted successfully`,
        action: 'restart',
        containerId: id
      });
      
      // Refresh the server list after a short delay
      setTimeout(() => {
        event.reply('refresh-servers-request');
      }, 1000);
    });
  });

  // Handle container stop request
  ipcMain.on('stop-container', (event, { id }) => {
    if (!id) {
      event.reply('container-action-result', { error: 'Container ID is required', action: 'stop' });
      return;
    }

    const command = `docker stop ${id}`;
    
    exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`Error stopping container ${id}: ${error.message}`);
        event.reply('container-action-result', { 
          error: `Failed to stop container: ${error.message}`,
          action: 'stop',
          containerId: id
        });
        return;
      }

      console.log(`Container ${id} stopped successfully`);
      event.reply('container-action-result', { 
        success: true, 
        message: `Container stopped successfully`,
        action: 'stop',
        containerId: id
      });
      
      // Refresh the server list after a short delay
      setTimeout(() => {
        event.reply('refresh-servers-request');
      }, 1000);
    });
  });

  // Handle container start request
  ipcMain.on('start-container', (event, { id }) => {
    if (!id) {
      event.reply('container-action-result', { error: 'Container ID is required', action: 'start' });
      return;
    }

    const command = `docker start ${id}`;
    
    exec(command, (error, stdout, stderr) => {
      if (error) {
        console.error(`Error starting container ${id}: ${error.message}`);
        event.reply('container-action-result', { 
          error: `Failed to start container: ${error.message}`,
          action: 'start',
          containerId: id
        });
        return;
      }

      console.log(`Container ${id} started successfully`);
      event.reply('container-action-result', { 
        success: true, 
        message: `Container started successfully`,
        action: 'start',
        containerId: id
      });
      
      // Refresh the server list after a short delay
      setTimeout(() => {
        event.reply('refresh-servers-request');
      }, 1000);
    });
  });

  // Get available servers from scripts/windows folder
  ipcMain.on('get-available-servers', (event) => {
    try {
      // Get the path to the scripts/windows folder
      const scriptsPath = path.join(__dirname, '..', 'scripts', 'windows');
      
      // Read all PowerShell scripts in the directory
      fs.readdir(scriptsPath, (err, files) => {
        if (err) {
          console.error(`Error reading scripts directory: ${err.message}`);
          event.reply('available-servers-data', { 
            error: `Failed to read scripts directory: ${err.message}` 
          });
          return;
        }

        // Filter for PowerShell scripts that start with "load" and end with "MCP.ps1"
        const serverScripts = files.filter(file => 
          file.startsWith('load') && 
          file.endsWith('MCP.ps1')
        );

        // Get list of all Docker containers (running and stopped)
        exec('docker ps -a --format "{{.Names}}"', (dockerErr, dockerStdout) => {
          if (dockerErr) {
            console.error(`Error getting Docker containers: ${dockerErr.message}`);
            // Continue with empty container list
            processServerScripts([]);
            return;
          }

          const containerNames = dockerStdout.trim().split('\n').filter(name => name);
          processServerScripts(containerNames);
        });

        // Process server scripts with container information
        function processServerScripts(containerNames) {
          // Parse server information from script names
          const servers = serverScripts.map(script => {
            // Extract server name from script name (e.g., loadBraveMCP.ps1 -> Brave)
            const scriptName = script.replace('load', '').replace('MCP.ps1', '');
            
            // Read the script file to extract description and other metadata
            const scriptPath = path.join(scriptsPath, script);
            const scriptContent = fs.readFileSync(scriptPath, 'utf8');
            
            // Extract description from script comments (first few lines)
            const lines = scriptContent.split('\n');
            const descriptionLines = lines
              .slice(0, 10) // Look at first 10 lines
              .filter(line => line.trim().startsWith('#') && !line.includes('Step'))
              .map(line => line.trim().replace(/^#\s*/, ''))
              .filter(line => line.length > 0);
            
            // Join description lines, removing the script name if it's the first line
            let description = descriptionLines.join(' ');
            
            // Extract server type from script name
            const serverType = scriptName;
            
            // Check if this server is currently deployed by looking for a container with a matching name
            const containerName = `${serverType.toLowerCase()}-mcp-server`;
            const isDeployed = containerNames.some(name => 
              name.toLowerCase() === containerName.toLowerCase()
            );
            
            return {
              id: serverType.toLowerCase(),
              name: serverType,
              scriptName: script,
              description: description,
              scriptPath: scriptPath,
              isDeployed: isDeployed,
              containerName: containerName
            };
          });

          console.log(`Found ${servers.length} available servers`);
          event.reply('available-servers-data', { servers });
        }
      });
    } catch (error) {
      console.error(`Error getting available servers: ${error.message}`);
      event.reply('available-servers-data', { 
        error: `Failed to get available servers: ${error.message}` 
      });
    }
  });

  // Remove a container and its image
  ipcMain.on('remove-container', (event, { containerName, removeImage }) => {
    if (!containerName) {
      event.reply('container-action-result', { 
        error: 'Container name is required', 
        action: 'remove'
      });
      return;
    }

    console.log(`Removing container: ${containerName}, removeImage: ${removeImage}`);
    
    // First stop the container if it's running
    const stopCommand = `docker stop ${containerName}`;
    exec(stopCommand, (stopError) => {
      if (stopError) {
        console.warn(`Warning stopping container (may already be stopped): ${stopError.message}`);
        // Continue with removal even if stop fails (container might not be running)
      }
      
      // Remove the container
      const removeCommand = `docker rm ${containerName}`;
      exec(removeCommand, (removeError, removeStdout) => {
        if (removeError) {
          console.error(`Error removing container: ${removeError.message}`);
          event.reply('container-action-result', { 
            error: `Failed to remove container: ${removeError.message}`,
            action: 'remove',
            containerName
          });
          return;
        }
        
        console.log(`Container ${containerName} removed successfully`);
        
        // If requested, also remove the image
        if (removeImage) {
          // Get the image ID for this container type
          const imagePattern = `mcp/${containerName.replace('-mcp-server', '')}`;
          const getImageCommand = `docker images --format "{{.ID}} {{.Repository}}" | findstr "${imagePattern}"`;
          
          exec(getImageCommand, (imageError, imageStdout) => {
            if (imageError || !imageStdout.trim()) {
              console.warn(`Could not find image for ${imagePattern}: ${imageError ? imageError.message : 'No matching image'}`);
              // Still consider the operation successful since container was removed
              event.reply('container-action-result', { 
                success: true, 
                message: `Container ${containerName} removed successfully. No matching image found.`,
                action: 'remove',
                containerName
              });
              
              // Refresh the server list
              setTimeout(() => {
                event.reply('refresh-servers-request');
              }, 1000);
              return;
            }
            
            // Extract image ID from output
            const imageId = imageStdout.trim().split(' ')[0];
            const removeImageCommand = `docker rmi -f ${imageId}`;
            
            exec(removeImageCommand, (rmiError, rmiStdout) => {
              if (rmiError) {
                console.error(`Error removing image: ${rmiError.message}`);
                event.reply('container-action-result', { 
                  warning: `Container removed but failed to remove image: ${rmiError.message}`,
                  action: 'remove',
                  containerName
                });
              } else {
                console.log(`Image ${imageId} removed successfully`);
                event.reply('container-action-result', { 
                  success: true, 
                  message: `Container and image removed successfully`,
                  action: 'remove',
                  containerName
                });
              }
              
              // Refresh the server list
              setTimeout(() => {
                event.reply('refresh-servers-request');
              }, 1000);
            });
          });
        } else {
          // No image removal requested, just report container removal success
          event.reply('container-action-result', { 
            success: true, 
            message: `Container ${containerName} removed successfully`,
            action: 'remove',
            containerName
          });
          
          // Refresh the server list
          setTimeout(() => {
            event.reply('refresh-servers-request');
          }, 1000);
        }
      });
    });
  });

  // Re-deploy a server (remove existing and deploy new)
  ipcMain.on('redeploy-server', (event, { containerName, scriptName }) => {
    if (!containerName || !scriptName) {
      event.reply('container-action-result', { 
        error: 'Container name and script name are required', 
        action: 'redeploy'
      });
      return;
    }

    console.log(`Re-deploying server: ${containerName} using script: ${scriptName}`);
    
    // First remove the existing container
    const removeCommand = `docker stop ${containerName} && docker rm ${containerName}`;
    exec(removeCommand, (removeError) => {
      if (removeError) {
        console.warn(`Warning removing container (may not exist): ${removeError.message}`);
        // Continue with deployment even if removal fails
      }
      
      // Now deploy the new container
      const scriptsPath = path.join(__dirname, '..', 'scripts', 'windows');
      const scriptPath = path.join(scriptsPath, scriptName);
      
      // Check if the script exists
      if (!fs.existsSync(scriptPath)) {
        event.reply('container-action-result', { 
          error: `Script not found: ${scriptPath}`,
          action: 'redeploy',
          containerName
        });
        return;
      }

      // Use -NoProfile to avoid loading user profiles that might interfere
      // Use -NonInteractive to prevent any prompts
      // Use -NoLogo to suppress the PowerShell logo
      // Use -OutputFormat Text to ensure clean text output
      const command = `powershell -NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -OutputFormat Text -File "${scriptPath}"`;
      
      // Execute the command
      exec(command, { maxBuffer: 1024 * 1024 }, (error, stdout, stderr) => {
        if (error) {
          console.error(`Error re-deploying server: ${error.message}`);
          console.error(`Stderr: ${stderr}`);
          event.reply('container-action-result', { 
            error: `Failed to re-deploy server: ${error.message}`,
            action: 'redeploy',
            containerName,
            stdout,
            stderr
          });
          return;
        }

        console.log(`Server re-deployed successfully: ${stdout}`);
        event.reply('container-action-result', { 
          success: true,
          message: 'Server re-deployed successfully',
          action: 'redeploy',
          containerName,
          stdout
        });
        
        // Refresh the server list after deployment
        setTimeout(() => {
          event.reply('refresh-servers-request');
        }, 2000);
      });
    });
  });

  // Deploy a server using its script
  ipcMain.on('deploy-server', (event, { scriptName }) => {
    if (!scriptName) {
      event.reply('deploy-server-result', { 
        error: 'Script name is required',
        scriptName
      });
      return;
    }

    try {
      // Get the path to the script
      const scriptsPath = path.join(__dirname, '..', 'scripts', 'windows');
      const scriptPath = path.join(scriptsPath, scriptName);
      
      // Check if the script exists
      if (!fs.existsSync(scriptPath)) {
        event.reply('deploy-server-result', { 
          error: `Script not found: ${scriptPath}`,
          scriptName
        });
        return;
      }

      // Use -NoProfile to avoid loading user profiles that might interfere
      // Use -NonInteractive to prevent any prompts
      // Use -NoLogo to suppress the PowerShell logo
      // Use -OutputFormat Text to ensure clean text output
      const command = `powershell -NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -OutputFormat Text -File "${scriptPath}"`;
      
      // Execute the command
      exec(command, { maxBuffer: 1024 * 1024 }, (error, stdout, stderr) => {
        if (error) {
          console.error(`Error deploying server: ${error.message}`);
          console.error(`Stderr: ${stderr}`);
          event.reply('deploy-server-result', { 
            error: `Failed to deploy server: ${error.message}`,
            scriptName,
            stdout,
            stderr
          });
          return;
        }

        console.log(`Server deployed successfully: ${stdout}`);
        event.reply('deploy-server-result', { 
          success: true,
          scriptName,
          message: 'Server deployed successfully',
          stdout
        });
        
        // Refresh the server list after deployment
        setTimeout(() => {
          event.reply('refresh-servers-request');
        }, 2000);
      });
    } catch (error) {
      console.error(`Error deploying server: ${error.message}`);
      event.reply('deploy-server-result', { 
        error: `Failed to deploy server: ${error.message}`,
        scriptName
      });
    }
  });

  // Handle deploy-server-with-settings IPC event
  ipcMain.on('deploy-server-with-settings', (event, { scriptName, settings }) => {
    if (!scriptName) {
      event.reply('deploy-server-result', { 
        error: 'Script name is required',
        scriptName
      });
      return;
    }

    try {
      // Get the path to the script
      const scriptsPath = path.join(__dirname, '..', 'scripts', 'windows');
      const scriptPath = path.join(scriptsPath, scriptName);
      
      // Check if the script exists
      if (!fs.existsSync(scriptPath)) {
        event.reply('deploy-server-result', { 
          error: `Script not found: ${scriptPath}`,
          scriptName
        });
        return;
      }

      // Save settings to the appropriate .env file
      // Use the same server type extraction logic as in the get-mcp-server-settings handler
      let serverType;
      if (scriptName.includes('GoogleMapsMCP')) {
        serverType = 'googleMaps';
      } else {
        serverType = scriptName.replace('load', '').replace('.ps1', '');
      }
      
      const settingsPath = path.join(__dirname, '..', 'scripts', 'settings', `${serverType}Settings.env`);
      
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
      
      console.log(`Settings saved to: ${settingsPath}`);
      
      // Use -NoProfile to avoid loading user profiles that might interfere
      // Use -NonInteractive to prevent any prompts
      // Use -NoLogo to suppress the PowerShell logo
      // Use -OutputFormat Text to ensure clean text output
      const command = `powershell -NoProfile -NonInteractive -NoLogo -ExecutionPolicy Bypass -OutputFormat Text -File "${scriptPath}"`;
      
      // Execute the command
      exec(command, { maxBuffer: 1024 * 1024 }, (error, stdout, stderr) => {
        if (error) {
          console.error(`Error deploying server: ${error.message}`);
          console.error(`Stderr: ${stderr}`);
          event.reply('deploy-server-result', { 
            error: `Failed to deploy server: ${error.message}`,
            scriptName,
            stdout,
            stderr
          });
          return;
        }

        console.log(`Server deployed successfully: ${stdout}`);
        event.reply('deploy-server-result', { 
          success: true,
          scriptName,
          message: 'Server deployed successfully',
          stdout
        });
        
        // Refresh the server list after deployment
        setTimeout(() => {
          event.reply('refresh-servers-request');
        }, 2000);
      });
    } catch (error) {
      console.error(`Error deploying server: ${error.message}`);
      event.reply('deploy-server-result', { 
        error: `Failed to deploy server: ${error.message}`,
        scriptName
      });
    }
  });

  // Handle get-mcp-server-settings IPC event
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
      
      // Check if example settings file exists and parse it for structure
      if (fs.existsSync(exampleSettingsPath)) {
        const exampleContent = fs.readFileSync(exampleSettingsPath, 'utf8');
        const lines = exampleContent.split('\n');
        
        let currentSection = null;
        
        // Parse example file to extract required/optional settings and descriptions
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
      
      // Check if actual settings file exists and load values
      if (fs.existsSync(settingsPath)) {
        const content = fs.readFileSync(settingsPath, 'utf8');
        const lines = content.split('\n');
        
        // Parse existing settings
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

  // Handle save-mcp-server-settings IPC event
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
      
      console.log(`Settings saved to: ${settingsPath}`);
      
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

  app.on('activate', function () {
    // On macOS it's common to re-create a window in the app when the
    // dock icon is clicked and there are no other windows open.
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

// Quit when all windows are closed, except on macOS. There, it's common
// for applications and their menu bar to stay active until the user quits
// explicitly with Cmd + Q.
app.on('window-all-closed', function () {
  if (process.platform !== 'darwin') app.quit();
});

// In this file you can include the rest of your app's specific main process
// code. You can also put them in separate files and require them here.
// Example: preload.js for secure IPC
/*
const { contextBridge, ipcRenderer } = require('electron')

contextBridge.exposeInMainWorld('electronAPI', {
  // Define functions to expose to the renderer process
})
*/
