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
    
    if ($settings.ContainsKey("MEMORY_DATA_PATH") -and -not [string]::IsNullOrWhiteSpace($settings["MEMORY_DATA_PATH"])) {
        $MemoryDataPath = $settings["MEMORY_DATA_PATH"]
        if (-not [System.IO.Path]::IsPathRooted($MemoryDataPath)) {
            $MemoryDataPath = Join-Path $RepoRoot $MemoryDataPath
        }
        Write-Host "Using custom memory data path: $MemoryDataPath" -ForegroundColor Cyan
    }
}

# Ensure memory data directory exists
if (-not (Test-Path $MemoryDataPath)) {
    New-Item -ItemType Directory -Path $MemoryDataPath | Out-Null
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
    
    Write-Host "✅ Docker image built successfully" -ForegroundColor Green
} else {
    Write-Host "✅ Docker image already exists" -ForegroundColor Green
}

# Step 3: Start Docker container if not already running
Write-Host "Checking if Docker container is running..."
if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
    Write-Host "Starting Docker container..."
    
    # Remove container if it exists but is not running
    docker rm $ContainerName 2>$null
    
    # Create volume mount for memory data
    $memoryDataDir = Split-Path -Parent $MemoryDataPath
    $memoryDataDirName = Split-Path -Leaf $MemoryDataPath
    
    # Start Docker container in interactive mode with a pseudo-TTY
    $dockerRunCommand = "docker run -it --name $ContainerName"
    $dockerRunCommand += " -v `"$MemoryDataPath`":/app/data"
    $dockerRunCommand += " $DockerImage"
    
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $dockerRunCommand -WindowStyle Hidden
    
    # Wait a moment for the container to start
    Start-Sleep -Seconds 2
    
    if (Test-ContainerRunning -ContainerName $ContainerName) {
        Write-Host "✅ Docker container started successfully" -ForegroundColor Green
    } else {
        Write-Host "Error: Failed to start Docker container" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "✅ Docker container already running" -ForegroundColor Green
}

# Step 4: Update Claude Desktop config
Write-Host "Updating Claude Desktop config..."

# Create Claude config directory if it doesn't exist
if (-not (Test-Path $ClaudeConfigDir)) {
    New-Item -ItemType Directory -Path $ClaudeConfigDir | Out-Null
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
        "$MemoryDataPath:/app/data"
        $DockerImage
    )
}

# Check for empty or non-existent config
if ((-not (Test-Path $ClaudeConfig)) -or ((Get-Content $ClaudeConfig -Raw).Trim() -eq "{}") -or ((Get-Content $ClaudeConfig -Raw).Trim() -eq "")) {
    # Create new config
    $config = @{
        mcpServers = @{
            "memory" = $serverConfig
        }
    }
    
    # Save the config
    $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
    Write-Host "✅ Created new Claude Desktop config with memory MCP server" -ForegroundColor Green
} else {
    # Update existing config
    try {
        $config = Get-Content $ClaudeConfig -Raw | ConvertFrom-Json
        
        # Add mcpServers section if it doesn't exist
        if (-not $config.mcpServers) {
            $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value @{}
        }
        
        # Add server configuration
        $config.mcpServers | Add-Member -MemberType NoteProperty -Name "memory" -Value $serverConfig -Force
        
        # Save the updated config
        $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
        Write-Host "✅ Updated Claude Desktop config with memory MCP server" -ForegroundColor Green
    }
    catch {
        Write-Host "Error updating Claude Desktop config: $_" -ForegroundColor Red
        Write-Host "Creating new config file..." -ForegroundColor Yellow
        
        # Create new config
        $config = @{
            mcpServers = @{
                "memory" = $serverConfig
            }
        }
        
        # Save the config
        $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
        Write-Host "✅ Created new Claude Desktop config with memory MCP server" -ForegroundColor Green
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
        Write-Host "✅ Claude Desktop restarted" -ForegroundColor Green
    } else {
        Write-Host "Claude Desktop is not running. No need to restart." -ForegroundColor Yellow
    }
} else {
    Write-Host "Skipping Claude Desktop restart as per settings" -ForegroundColor Yellow
}

Write-Host "`nMemory MCP server setup complete!" -ForegroundColor Green
Write-Host "You can now use persistent memory features in Claude Desktop" -ForegroundColor Green
Write-Host "`nUseful commands:" -ForegroundColor Cyan
Write-Host "- View container logs: docker logs $ContainerName" -ForegroundColor Cyan
Write-Host "- Stop container: docker stop $ContainerName" -ForegroundColor Cyan
Write-Host "- Remove container: docker rm $ContainerName" -ForegroundColor Cyan
