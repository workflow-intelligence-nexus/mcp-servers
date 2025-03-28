# PowerShell Script to set up Brave Search MCP server for Claude Desktop on Windows
# This script:
# 1. Checks for BRAVE_API_KEY in .env file
# 2. Ensures the Docker image is built
# 3. Starts a background Docker container for the MCP server if not already running
# 4. Updates claude_desktop_config.json if needed
# 5. Restarts Claude Desktop if it's running

# Stop on any error
$ErrorActionPreference = "Stop"

# Define paths and variables
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$EnvFile = Join-Path $RepoRoot ".env"
$SettingsFile = Join-Path $RepoRoot "scripts\settings\braveSettings.env"
$ClaudeConfigDir = Join-Path $env:APPDATA "Claude"
$ClaudeConfig = Join-Path $ClaudeConfigDir "claude_desktop_config.json"
$DockerImage = "mcp/brave-search:latest"
$ContainerName = "brave-mcp-server"

# Function to check if a process is running
function Test-ProcessRunning {
    param (
        [string]$ProcessName
    )
    
    return (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) -ne $null
}

# Function to check if a Docker container is running
function Test-ContainerRunning {
    param (
        [string]$ContainerName
    )
    
    $container = docker ps --filter "name=$ContainerName" --format "{{.Names}}" 2>$null
    return $container -eq $ContainerName
}

# Change to repository root
Set-Location $RepoRoot

# Step 1: Check for BRAVE_API_KEY in .env file
Write-Host "Checking for BRAVE_API_KEY in .env file..."
if (-not (Test-Path $EnvFile)) {
    Write-Host "Error: .env file not found at $EnvFile" -ForegroundColor Red
    exit 1
}

# Load settings from braveSettings.env if it exists
if (Test-Path $SettingsFile) {
    Write-Host "Loading settings from $SettingsFile..."
    $settings = @{}
    Get-Content $SettingsFile | ForEach-Object {
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
    
    # Apply settings if they exist
    if ($settings.ContainsKey("CONTAINER_NAME") -and -not [string]::IsNullOrWhiteSpace($settings["CONTAINER_NAME"])) {
        $ContainerName = $settings["CONTAINER_NAME"]
        Write-Host "Using custom container name: $ContainerName" -ForegroundColor Cyan
    }
    
    if ($settings.ContainsKey("DOCKER_IMAGE") -and -not [string]::IsNullOrWhiteSpace($settings["DOCKER_IMAGE"])) {
        $DockerImage = $settings["DOCKER_IMAGE"]
        Write-Host "Using custom Docker image: $DockerImage" -ForegroundColor Cyan
    }
    
    if ($settings.ContainsKey("BRAVE_API_KEY") -and -not [string]::IsNullOrWhiteSpace($settings["BRAVE_API_KEY"])) {
        [Environment]::SetEnvironmentVariable("BRAVE_API_KEY", $settings["BRAVE_API_KEY"], "Process")
        Write-Host "Using BRAVE_API_KEY from settings file" -ForegroundColor Cyan
    }
}

# Extract API key from .env file if not already set from settings file
if (-not [Environment]::GetEnvironmentVariable("BRAVE_API_KEY", "Process")) {
    $envContent = Get-Content $EnvFile -Raw
    if ($envContent -match 'BRAVE_API_KEY=(.+)') {
        $BraveApiKey = $matches[1]
        if ([string]::IsNullOrWhiteSpace($BraveApiKey)) {
            Write-Host "Error: BRAVE_API_KEY is empty in .env file" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Error: BRAVE_API_KEY not found in .env file" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ BRAVE_API_KEY found in .env file" -ForegroundColor Green
}

# Step 2: Ensure Docker image is built
Write-Host "Checking if Docker image exists..."
$imageExists = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String -Pattern "^$DockerImage$" -Quiet

if (-not $imageExists) {
    Write-Host "Building Docker image..."
    docker build -t $DockerImage -f src/brave-search/Dockerfile .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to build Docker image" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Docker image built successfully" -ForegroundColor Green
} else {
    Write-Host "✅ Docker image already exists" -ForegroundColor Green
}

# Step 3: Start Docker container if not already running
Write-Host "Checking if Brave MCP server is running..."
if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
    Write-Host "Starting Brave MCP server in Docker container..."
    # Start Docker container in interactive mode with a pseudo-TTY
    # Use 'start-process' to run it in the background
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "docker run -it --name $ContainerName --env-file .env $DockerImage" -WindowStyle Hidden
    
    # Give it a moment to start
    Start-Sleep -Seconds 2
    
    if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
        Write-Host "Error: Failed to start Docker container" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Brave MCP server started in Docker container" -ForegroundColor Green
} else {
    Write-Host "✅ Brave MCP server already running in Docker container" -ForegroundColor Green
}

# Step 4: Update Claude Desktop config if needed
Write-Host "Checking Claude Desktop configuration..."
if ((-not (Test-Path $ClaudeConfig)) -or ((Get-Content $ClaudeConfig -Raw).Trim() -eq "{}")) {
    Write-Host "Creating Claude Desktop config file..."
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $ClaudeConfigDir)) {
        New-Item -ItemType Directory -Path $ClaudeConfigDir | Out-Null
    }
    
    # Create the config file with the Brave MCP server configuration
    $configJson = @"
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
        "BRAVE_API_KEY": "$BraveApiKey"
      }
    }
  }
}
"@
    
    Set-Content -Path $ClaudeConfig -Value $configJson
    Write-Host "✅ Claude Desktop config created" -ForegroundColor Green
} else {
    # Check if config already has brave-search MCP server
    $configContent = Get-Content $ClaudeConfig -Raw
    if ($configContent -match '"brave-search"') {
        Write-Host "✅ Claude Desktop config already contains brave-search MCP server" -ForegroundColor Green
    } else {
        Write-Host "Updating Claude Desktop config..."
        
        # Create a backup of the original config
        Copy-Item $ClaudeConfig "$ClaudeConfig.bak"
        
        # Parse the existing JSON
        try {
            $config = Get-Content $ClaudeConfig -Raw | ConvertFrom-Json
            
            # Add mcpServers section if it doesn't exist
            if (-not $config.mcpServers) {
                $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value @{}
            }
            
            # Add brave-search to mcpServers
            $braveSearch = @{
                command = "docker"
                args = @("run", "-i", "--rm", "-e", "BRAVE_API_KEY", "mcp/brave-search")
                env = @{
                    BRAVE_API_KEY = $BraveApiKey
                }
            }
            
            # Add the new property
            $config.mcpServers | Add-Member -MemberType NoteProperty -Name "brave-search" -Value $braveSearch -Force
            
            # Save the updated config
            $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
            Write-Host "✅ Claude Desktop config updated" -ForegroundColor Green
        }
        catch {
            Write-Host "Error parsing existing config. Creating new config file..." -ForegroundColor Yellow
            
            # Create the config file with the Brave MCP server configuration
            $configJson = @"
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
        "BRAVE_API_KEY": "$BraveApiKey"
      }
    }
  }
}
"@
            
            Set-Content -Path $ClaudeConfig -Value $configJson
            Write-Host "✅ Claude Desktop config created" -ForegroundColor Green
        }
    }
}

# Step 5: Restart Claude Desktop if it's running
Write-Host "Checking if Claude Desktop is running..."
if (Test-ProcessRunning -ProcessName "claude-desktop") {
    Write-Host "Closing Claude Desktop..."
    Stop-Process -Name "claude-desktop" -Force
    Write-Host "✅ Claude Desktop closed" -ForegroundColor Green
} else {
    Write-Host "✅ Claude Desktop is not running" -ForegroundColor Green
}

Write-Host "✅ All done! Claude Desktop is now configured to use the Brave Search MCP server." -ForegroundColor Green
Write-Host "You can now start Claude Desktop and the Brave Search MCP server will be available." -ForegroundColor Green
Write-Host ""
Write-Host "To view the Brave MCP server logs, use: docker logs $ContainerName" -ForegroundColor Cyan
Write-Host "To stop the container when done, use: docker stop $ContainerName" -ForegroundColor Cyan
