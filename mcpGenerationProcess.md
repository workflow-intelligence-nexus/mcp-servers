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

### 1. Environment Variables

- **Location**: Stored in a `.env` file at the repository root
- **Loading Process**: Use a separate script (`loadEnv.ps1`) to load variables
- **Critical Variables**: API keys (e.g., `BRAVE_API_KEY` for Brave Search)

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
$ClaudeConfigDir = Join-Path $env:APPDATA "Claude"
$ClaudeConfig = Join-Path $ClaudeConfigDir "claude_desktop_config.json"
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

## Checklist for New MCP Server Implementation

When implementing a new MCP server, ensure you have the following information:

1. **API Requirements**:
   - What API key(s) are needed?
   - Where should they be stored? (typically `.env` file)

2. **Docker Configuration**:
   - Docker image name and tag
   - Required environment variables
   - Container name convention
   - Any special Docker run arguments

3. **Claude Desktop Integration**:
   - Specific MCP server name in the config
   - Any special command arguments
   - Environment variables to pass to the container

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
```
