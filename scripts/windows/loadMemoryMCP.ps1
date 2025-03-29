# PowerShell Script to set up Memory MCP server for Claude Desktop on Windows
# This script:
# 1. Loads settings from memorySettings.env
# 2. Ensures the Docker image is built
# 3. Starts a background Docker container for the MCP server if not already running
# 4. Updates claude_desktop_config.json if needed
# 5. Restarts Claude Desktop if it's running

# Stop on any error
$ErrorActionPreference = "Stop"

# Define paths and variables
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SettingsFile = Join-Path $RepoRoot "scripts\settings\memorySettings.env"
$DockerImage = "mcp/memory:latest"
$ContainerName = "memory-mcp-server"
$ClaudeConfigDir = Join-Path $env:APPDATA "Claude"
$ClaudeConfig = Join-Path $ClaudeConfigDir "claude_desktop_config.json"
$MemoryDataPath = Join-Path $RepoRoot ".memory-data"

# Initialize settings with default values
$settings = @{}

# Function to check if a process is running
function Test-ProcessRunning {
    param (
        [string]$ProcessName
    )
    
    return $null -ne (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
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

# Step 1: Load settings from memorySettings.env if it exists
if (Test-Path $SettingsFile) {
    Write-Host "Loading settings from $SettingsFile..."
    Get-Content $SettingsFile | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#')) {
            $line = $_.Trim()
            if ($line -match '(.+?)=(.*)') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                $settings[$key] = $value
            }
        }
    }
    Write-Host "Settings loaded successfully."
} else {
    Write-Host "Settings file not found at $SettingsFile. Using default settings." -ForegroundColor Yellow
    
    # Create settings directory if it doesn't exist
    $settingsDir = Join-Path $RepoRoot "scripts\settings"
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
        Write-Host "Created settings directory at $settingsDir" -ForegroundColor Green
    }
    
    # Create example settings file if it doesn't exist
    $exampleSettingsFile = Join-Path $RepoRoot "scripts\settings\memorySettings.example.env"
    if (-not (Test-Path $exampleSettingsFile)) {
        @'
# Memory MCP Server Settings
# Copy this file to memorySettings.env and modify as needed

# Set to 'false' to prevent automatic Claude Desktop restart
RESTART_CLAUDE=true

# Memory data storage path (default is .memory-data in repo root)
# MEMORY_DATA_PATH=C:\path\to\memory\data

# Custom container name (optional)
# CONTAINER_NAME=memory-mcp-server

# Custom Docker image (optional)
# DOCKER_IMAGE=mcp/memory:latest
'@ | Set-Content $exampleSettingsFile
        Write-Host "Created example settings file at $exampleSettingsFile" -ForegroundColor Green
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

if ($settings.ContainsKey("MEMORY_DATA_PATH") -and -not [string]::IsNullOrWhiteSpace($settings["MEMORY_DATA_PATH"])) {
    $MemoryDataPath = $settings["MEMORY_DATA_PATH"]
    if (-not [System.IO.Path]::IsPathRooted($MemoryDataPath)) {
        $MemoryDataPath = Join-Path $RepoRoot $MemoryDataPath
    }
    Write-Host "Using custom memory data path: $MemoryDataPath" -ForegroundColor Cyan
}

# Create memory data directory if it doesn't exist
if (-not (Test-Path $MemoryDataPath)) {
    New-Item -ItemType Directory -Path $MemoryDataPath -Force | Out-Null
    Write-Host "Created memory data directory at $MemoryDataPath" -ForegroundColor Green
}

# Step 2: Ensure Docker image is built
Write-Host "Checking if Docker image exists..."
$imageExists = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String -Pattern "^$DockerImage$" -Quiet

if (-not $imageExists) {
    Write-Host "Building Docker image $DockerImage..."
    $dockerfilePath = Join-Path $RepoRoot "src\memory"
    docker build -t $DockerImage -f "$dockerfilePath\Dockerfile" $RepoRoot
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to build Docker image" -ForegroundColor Red
        exit 1
    }
    
    Write-Host " Docker image built successfully" -ForegroundColor Green
} else {
    Write-Host " Docker image already exists" -ForegroundColor Green
}

# Step 3: Start Docker container if not already running
Write-Host "Checking if Docker container is running..."
if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
    Write-Host "Starting Docker container..."
    
    # Check if container exists before trying to remove it
    $containerExists = docker ps -a --format "{{.Names}}" | Where-Object { $_ -eq $ContainerName }
    if ($containerExists) {
        Write-Host "Removing existing stopped container..."
        docker rm $ContainerName 2>$null
    }
    
    # Start Docker container in interactive mode with a pseudo-TTY
    $dockerRunCommand = "docker run -d --name $ContainerName"
    $dockerRunCommand += " -v `"$($MemoryDataPath):/app/data`""
    $dockerRunCommand += " $DockerImage"
    
    Invoke-Expression $dockerRunCommand
    
    # Wait a moment for the container to start
    Start-Sleep -Seconds 2
    
    if (Test-ContainerRunning -ContainerName $ContainerName) {
        Write-Host " Docker container started successfully" -ForegroundColor Green
    } else {
        Write-Host "Error: Failed to start Docker container" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host " Docker container already running" -ForegroundColor Green
}

# Step 4: Update Claude Desktop config
Write-Host "Updating Claude Desktop config..."

# Create Claude config directory if it doesn't exist
if (-not (Test-Path $ClaudeConfigDir)) {
    New-Item -ItemType Directory -Path $ClaudeConfigDir -Force | Out-Null
    Write-Host "Created Claude config directory at $ClaudeConfigDir" -ForegroundColor Green
}

# Create server configuration
$serverConfig = @{
    command = "docker"
    args = @(
        "run"
        "-i"
        "--rm"
        "-v"
        "$($MemoryDataPath):/app/data"
        $DockerImage
    )
}

# Check for empty or non-existent config
if ((-not (Test-Path $ClaudeConfig)) -or ((Get-Content $ClaudeConfig -Raw -ErrorAction SilentlyContinue).Trim() -eq "{}") -or ((Get-Content $ClaudeConfig -Raw -ErrorAction SilentlyContinue).Trim() -eq "")) {
    # Create new config
    $config = @{
        mcpServers = @{
            "memory" = $serverConfig
        }
    }
    
    # Save the config
    $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
    Write-Host " Created new Claude Desktop config with memory MCP server" -ForegroundColor Green
} else {
    try {
        # Load existing config
        $config = Get-Content $ClaudeConfig -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        
        # Ensure mcpServers section exists
        if (-not $config.ContainsKey("mcpServers")) {
            $config["mcpServers"] = @{}
        }
        
        # Add or update memory server config
        $config["mcpServers"]["memory"] = $serverConfig
        
        # Save the updated config
        $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
        Write-Host " Updated Claude Desktop config with memory MCP server" -ForegroundColor Green
    } catch {
        Write-Host "Warning: Failed to update Claude Desktop config: $_" -ForegroundColor Yellow
        Write-Host "Creating new config file instead..." -ForegroundColor Yellow
        
        # Create new config
        $config = @{
            mcpServers = @{
                "memory" = $serverConfig
            }
        }
        
        # Save the config
        $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
        Write-Host " Created new Claude Desktop config with memory MCP server" -ForegroundColor Green
    }
}

# Step 5: Restart Claude Desktop if it's running
$restartClaude = $true
if ($settings.ContainsKey("RESTART_CLAUDE")) {
    if ($settings["RESTART_CLAUDE"] -eq "false") {
        $restartClaude = $false
    }
}

if ($restartClaude) {
    $claudeProcessName = "Claude"
    if (Test-ProcessRunning -ProcessName $claudeProcessName) {
        Write-Host "Claude Desktop is running. Restarting..."
        Stop-Process -Name $claudeProcessName -Force
        Start-Sleep -Seconds 2
        Start-Process "Claude"
        Write-Host " Claude Desktop restarted" -ForegroundColor Green
    } else {
        Write-Host "Claude Desktop is not running. No need to restart." -ForegroundColor Yellow
    }
} else {
    Write-Host "Skipping Claude Desktop restart as per settings" -ForegroundColor Yellow
}

# Done!
Write-Host "`nMemory MCP server setup complete!" -ForegroundColor Green
Write-Host "You can now use persistent memory features in Claude Desktop" -ForegroundColor Green
Write-Host "`nUseful commands:" -ForegroundColor Cyan
Write-Host "- View container logs: docker logs $ContainerName" -ForegroundColor Cyan
Write-Host "- Stop container: docker stop $ContainerName" -ForegroundColor Cyan
Write-Host "- Restart container: docker restart $ContainerName" -ForegroundColor Cyan
