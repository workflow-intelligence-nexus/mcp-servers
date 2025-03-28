# MCP Server Setup Process Documentation

This document outlines the process, key learnings, and best practices for creating load scripts for Claude Desktop MCP (Model Control Protocol) servers. It serves as a reference for future MCP server implementations.

## Overview

An MCP server setup script typically needs to:

1. Load necessary environment variables (API keys, etc.)
2. Build and configure a Docker image for the MCP server
3. Start the Docker container
4. Update the Claude Desktop configuration file
5. Handle restart of Claude Desktop if it's running

## Key Components

### 1. Environment Variables and Settings Files

- **Environment Variables**:
  - **Location**: Stored in a `.env` file at the repository root for global settings
  - **Loading Process**: Use a separate script (`loadEnv.ps1`) to load variables
  - **Critical Variables**: API keys (e.g., `BRAVE_API_KEY` for Brave Search)

- **Tool-Specific Settings Files**:
  - **Naming Convention**: Create a `{toolname}Settings.env` file for each MCP server
  - **Location**: All settings files should be placed in the `scripts/settings/` directory
  - **Security**: Settings files containing API keys should be added to `.gitignore`
  - **Example Files**: Create a `{toolname}Settings.example.env` file with placeholders
  - **Purpose**: Provides a user-friendly way to configure tool-specific settings
  - **Format**: Use KEY=VALUE format with comments explaining options
  - **Examples**: 
    - `filesystemSettings.env` for directory paths
    - `braveSettings.env` for Brave Search specific settings

### 2. Docker Configuration

- **Image Building**: Check if image exists before building
- **Container Management**: Check if container is already running before starting
- **Container Naming**: Use consistent naming convention (e.g., `brave-mcp-server`)

### 3. Claude Desktop Configuration

- **Config File Location**: `$env:APPDATA\Claude\claude_desktop_config.json` (Windows)
- **Config Structure**: JSON with `mcpServers` section containing server configurations
- **Empty Config Handling**: Treat empty configs (`{}`) as non-existent
- **Error Handling**: Use try/catch for JSON parsing and provide fallbacks

## Implementation Details

### Path Handling

```powershell
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$EnvFile = Join-Path $RepoRoot ".env"
$SettingsFile = Join-Path $RepoRoot "scripts\settings\{toolname}Settings.env"
$ClaudeConfigDir = Join-Path $env:APPDATA "Claude"
$ClaudeConfig = Join-Path $ClaudeConfigDir "claude_desktop_config.json"
```

### Settings File Loading

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
                
                # Expand environment variables if present
                $expandedValue = [Environment]::ExpandEnvironmentVariables($value)
                
                $settings[$key] = $expandedValue
            }
        }
    }
    
    return $settings
}
```

### Environment Variable Loading

```powershell
function Import-EnvFile {
    param (
        [string]$EnvFilePath
    )
    
    # Read and process each line in the .env file
    Get-Content $EnvFilePath | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#')) {
            $line = $_.Trim()
            if ($line -match '(.+?)=(.*)') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                # Remove surrounding quotes if present
                if ($value -match '^[''"](.*)[''"](.*?)$') {
                    $value = $matches[1]
                }
                
                # Set as environment variable
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
    }
}
```

### Docker Container Management

```powershell
# Function to check if a Docker container is running
function Test-ContainerRunning {
    param (
        [string]$ContainerName
    )
    
    $container = docker ps --filter "name=$ContainerName" --format "{{.Names}}" 2>$null
    return $container -eq $ContainerName
}

# Start Docker container if not already running
if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
    # Start Docker container in interactive mode with a pseudo-TTY
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "docker run -it --name $ContainerName --env-file .env $DockerImage" -WindowStyle Hidden
}
```

### Claude Desktop Config Update

```powershell
# Check for empty or non-existent config
if ((-not (Test-Path $ClaudeConfig)) -or ((Get-Content $ClaudeConfig -Raw).Trim() -eq "{}")) {
    # Create new config
} else {
    # Update existing config
    try {
        $config = Get-Content $ClaudeConfig -Raw | ConvertFrom-Json
        
        # Add mcpServers section if it doesn't exist
        if (-not $config.mcpServers) {
            $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value @{}
        }
        
        # Add server configuration
        $config.mcpServers | Add-Member -MemberType NoteProperty -Name "server-name" -Value $serverConfig -Force
        
        # Save the updated config
        $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
    }
    catch {
        # Fallback to creating new config
    }
}
```

## Key Learnings and Best Practices

1. **PowerShell Verb Usage**: Use approved PowerShell verbs for function names (e.g., `Import-EnvFile` instead of `Load-EnvFile`)

2. **Error Handling**: Implement robust error handling with informative messages
   ```powershell
   $ErrorActionPreference = "Stop"  # Stop on any error
   ```

3. **Config File Handling**: 
   - Check for both non-existent AND empty config files
   - Use try/catch blocks when parsing JSON
   - Create backups before modifying existing configs

4. **Docker Management**:
   - Check if images exist before building
   - Check if containers are running before starting
   - Use background processes for long-running containers

5. **User Feedback**:
   - Provide clear, colorful status messages
   - Use checkmarks (✅) for successful operations
   - Include helpful commands for managing the server

6. **Settings File Best Practices**:
   - Always create a dedicated `{toolname}Settings.env` file for each MCP server
   - Place all settings files in the `scripts/settings/` directory
   - Include detailed comments explaining all available options
   - Provide sensible defaults that work out of the box
   - Support environment variable expansion (e.g., `%USERPROFILE%`)
   - Include validation for critical settings
   - Make the settings file user-editable without requiring code changes

7. **Security Practices**:
   - Add settings files containing API keys to `.gitignore`
   - Create example settings files with placeholders (e.g., `{toolname}Settings.example.env`)
   - Never commit actual API keys or sensitive information to the repository
   - Use environment variables for sensitive information

## Checklist for New MCP Server Implementation

When implementing a new MCP server, ensure you have the following information:

1. **API Requirements**:
   - What API key(s) are needed?
   - Where should they be stored? (typically `.env` file)

2. **Tool-Specific Settings**:
   - What user-configurable settings does the tool need?
   - What are sensible defaults for these settings?
   - Are there any settings that should be read-only?
   - Create both a settings file and an example file with placeholders

3. **Docker Configuration**:
   - Docker image name and tag
   - Required environment variables
   - Container name convention
   - Any special Docker run arguments

4. **Additional Requirements**:
   - Any dependencies that need to be installed
   - Special handling for the specific MCP service
   - Restart requirements for Claude Desktop

## Questions to Ask When Creating a New MCP Server

1. What is the name of the MCP server and what service does it connect to?
2. What API key(s) or credentials are required?
3. Is there an existing Dockerfile or does one need to be created?
4. Are there any special Docker run arguments needed?
5. What is the exact structure needed in the Claude Desktop config file?
6. Are there any special environment variables that need to be passed to the container?
7. Does the MCP server require any special setup or initialization?
8. Are there any specific error handling requirements?
9. Should the script handle Claude Desktop restart differently?
10. Are there any platform-specific considerations (Windows vs macOS vs Linux)?

## Example Settings File Structure

Here's an example of a well-structured settings file:

```
# Filesystem MCP Server Settings
# Use this file to define which folders you want to expose to Claude Desktop
#
# Format:
# FOLDER_1=C:\Path\To\Folder1
# FOLDER_2=C:\Path\To\Folder2
# FOLDER_3=C:\Path\To\Folder3
#
# To make a folder read-only, add :ro at the end:
# FOLDER_4=C:\Path\To\Folder4:ro
#
# Examples:
# DOCUMENTS=C:\Users\username\Documents
# PROJECTS=C:\Users\username\Projects
# READONLY_FOLDER=C:\Path\To\Important\Files:ro
#
# Default settings (uncomment and modify as needed):
DOCUMENTS=%USERPROFILE%\Documents
DESKTOP=%USERPROFILE%\Desktop
# DOWNLOADS=%USERPROFILE%\Downloads
# PICTURES=%USERPROFILE%\Pictures
# PROJECTS=C:\Projects
```

## File Structure

```
mcp-servers/
├── .env                       # Global environment variables (gitignored)
├── .gitignore                 # Git ignore file
├── scripts/
│   ├── settings/              # Settings directory
│   │   ├── braveSettings.env            # Brave Search settings (gitignored)
│   │   ├── braveSettings.example.env    # Example Brave Search settings
│   │   ├── filesystemSettings.env       # Filesystem settings (gitignored)
│   │   └── filesystemSettings.example.env # Example Filesystem settings
│   ├── windows/               # Windows scripts
│   │   ├── loadBraveMCP.ps1   # Brave Search MCP loader
│   │   ├── loadEnv.ps1        # Environment loader
│   │   └── loadFilesystemMCP.ps1 # Filesystem MCP loader
│   └── macos/                 # macOS scripts (if applicable)
├── src/
│   ├── brave/                 # Brave Search MCP source
│   └── filesystem/            # Filesystem MCP source
└── README.md                  # Repository README
```

## Example MCP Server Configuration

Here's an example of a complete MCP server configuration in the Claude Desktop config file:

```json
{
  "mcpServers": {
    "brave-search": {
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--rm",
        "-e",
        "BRAVE_API_KEY",
        "mcp/brave-search"
      ],
      "env": {
        "BRAVE_API_KEY": "your-api-key-here"
      }
    }
  }
}
