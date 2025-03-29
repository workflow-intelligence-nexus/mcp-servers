# PowerShell Script to set up Google Maps MCP server for Claude Desktop on Windows
# This script:
# 1. Checks for GOOGLE_MAPS_API_KEY in settings or .env file
# 2. Ensures the Docker image is built
# 3. Starts a background Docker container for the MCP server if not already running
# 4. Updates claude_desktop_config.json if needed
# 5. Restarts Claude Desktop if it's running

# Enable error handling
$ErrorActionPreference = "Stop"
# Enable verbose output
$VerbosePreference = "Continue"

# Create a log file for debugging
$logFile = "$PSScriptRoot\googleMapsDeployment.log"
"Starting Google Maps MCP server deployment at $(Get-Date)" | Out-File -FilePath $logFile

# Function to log messages
function Write-Log {
    param (
        [string]$Message,
        [string]$ForegroundColor = "White"
    )
    
    # Write to console
    Write-Host $Message -ForegroundColor $ForegroundColor
    
    # Write to log file
    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')): $Message" | Out-File -FilePath $logFile -Append
}

# Function to check if a process is running
function Test-ProcessRunning {
    param (
        [string]$ProcessName
    )
    
    try {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        return ($null -ne $process)
    } catch {
        Write-Log "Error checking if process $ProcessName is running: $_" "Red"
        return $false
    }
}

# Function to check if a Docker container is running
function Test-ContainerRunning {
    param (
        [string]$ContainerName
    )
    
    try {
        $containerStatus = docker ps --filter "name=$ContainerName" --format "{{.Names}}" 2>$null
        return ($containerStatus -eq $ContainerName)
    } catch {
        Write-Log "Error checking if container $ContainerName is running: $_" "Red"
        return $false
    }
}

# Get the repository root directory
$repoRoot = (Get-Item $PSScriptRoot).Parent.Parent.FullName
Write-Log "Repository root: $repoRoot"

# Define paths
$envFile = Join-Path $repoRoot ".env"
$settingsFile = Join-Path $PSScriptRoot "..\settings\GoogleMapsMCPSettings.env"
Write-Log "Environment file path: $envFile"
Write-Log "Settings file path: $settingsFile"

# Set default values for optional settings
$dockerImage = "mcp/google-maps:custom"
$containerName = "google-maps-mcp-server"

# Load settings from environment file
if (Test-Path $settingsFile) {
    Write-Log "Loading settings from $settingsFile..."
    Get-Content $settingsFile | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#')) {
            $key, $value = $_.Split('=', 2)
            if (-not [string]::IsNullOrWhiteSpace($key) -and -not [string]::IsNullOrWhiteSpace($value)) {
                if ($key -eq "DOCKER_IMAGE") {
                    $dockerImage = $value
                }
                # Set environment variable for Docker container
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
    }
}

# Set the Google Maps API key as a user environment variable for persistence
if ($env:GOOGLE_MAPS_API_KEY) {
    [Environment]::SetEnvironmentVariable("GOOGLE_MAPS_API_KEY", $env:GOOGLE_MAPS_API_KEY, "User")
    Write-Log "Set GOOGLE_MAPS_API_KEY as User environment variable"
    
    # Verify the API key is set for the current process
    if ([Environment]::GetEnvironmentVariable("GOOGLE_MAPS_API_KEY", "Process")) {
        Write-Log "✅ GOOGLE_MAPS_API_KEY confirmed for process"
    } else {
        Write-Log "❌ GOOGLE_MAPS_API_KEY not set for process" "Red"
        exit 1
    }
} else {
    Write-Log "❌ GOOGLE_MAPS_API_KEY not found in settings" "Red"
    Write-Log "Please add your Google Maps API key to the settings file: $settingsFile" "Yellow"
    exit 1
}

# Check if Docker is running
try {
    Write-Log "Checking if Docker is running..."
    # Try multiple methods to check if Docker is running
    $dockerRunning = $false
    
    # Method 1: Check if Docker process is running
    $dockerProcess = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    if ($dockerProcess) {
        $dockerRunning = $true
        Write-Log "Docker Desktop process is running"
    }
    
    # Method 2: Try to execute a simple Docker command
    if (-not $dockerRunning) {
        $dockerVersion = docker version --format '{{.Server.Version}}' 2>$null
        if ($LASTEXITCODE -eq 0 -and $dockerVersion) {
            $dockerRunning = $true
            Write-Log "Docker daemon is responsive (version: $dockerVersion)"
        }
    }
    
    # Method 3: Check Docker info
    if (-not $dockerRunning) {
        $null = docker info 2>$null
        if ($LASTEXITCODE -eq 0) {
            $dockerRunning = $true
            Write-Log "Docker info command succeeded"
        }
    }
    
    if ($dockerRunning) {
        Write-Log "✅ Docker is running"
    } else {
        throw "Docker is not running or not responding"
    }
} catch {
    Write-Log "❌ Docker is not running or not installed" "Red"
    Write-Log "Please ensure Docker Desktop is running and try again" "Yellow"
    Write-Log "If Docker is already running, try restarting it" "Yellow"
    exit 1
}

# Check if the Docker image exists
Write-Log "Checking if Docker image exists..."
$imageExists = docker images --format "{{.Repository}}:{{.Tag}}" | Where-Object { $_ -eq $dockerImage }
if (-not $imageExists) {
    Write-Log "Docker image not found, pulling from Docker Hub..." "Yellow"
    docker pull $dockerImage
    if ($LASTEXITCODE -ne 0) {
        Write-Log "❌ Failed to pull Docker image: $dockerImage" "Red"
        exit 1
    }
    Write-Log "✅ Docker image pulled successfully" "Green"
}

# Check if a container with the same name is already running
if (Test-ContainerRunning -ContainerName $containerName) {
    Write-Log "Container $containerName is already running" "Yellow"
    
    # Ask if the user wants to stop and remove the existing container
    $choice = Read-Host "Do you want to stop and remove the existing container? (y/n)"
    if ($choice -eq "y") {
        Write-Log "Stopping and removing existing container..."
        try {
            docker stop $containerName
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to stop container: $containerName"
            }
            Write-Log "✅ Container stopped successfully"
        } catch {
            Write-Log "❌ Failed to stop container: $containerName" "Red"
            Write-Log "Error: $_" "Red"
            # Continue anyway, as the container might not exist
        }
    }
}

# Start the Docker container
Write-Log "Starting Docker container..."
Write-Log "Using Google Maps API Key (length): $($env:GOOGLE_MAPS_API_KEY.Length)"
Write-Log "Running Docker command to start container..."

# Construct the Docker run command
# Use -i flag to keep stdin open even in detached mode, which is required for MCP servers
$dockerCmd = "docker run --rm -d -i --name $containerName -e GOOGLE_MAPS_API_KEY=`"$($env:GOOGLE_MAPS_API_KEY)`" $dockerImage"
Write-Log "Docker command: $dockerCmd"

try {
    $containerId = Invoke-Expression $dockerCmd
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start Docker container"
    }
    Write-Log "Docker container ID: $containerId"
    
    # Wait for the container to start
    Write-Log "Waiting for container to start..."
    Start-Sleep -Seconds 3
    
    # Check if the container is running
    if (Test-ContainerRunning -ContainerName $containerName) {
        Write-Log "✅ Docker container started successfully" "Green"
        
        # Get container logs to verify it's working properly
        Write-Log "Container logs:" "Cyan"
        docker logs $containerName
        
        # Update Claude Desktop configuration
        try {
            Write-Log "Updating Claude Desktop config..." "Cyan"
            
            # Get the Claude Desktop config path
            $claudeConfigDir = Join-Path $env:APPDATA "Claude"
            $claudeConfigFile = Join-Path $claudeConfigDir "claude_desktop_config.json"
            
            # Check if Claude config directory exists
            if (-not (Test-Path $claudeConfigDir)) {
                Write-Log "Claude config directory not found at $claudeConfigDir. Creating it..." "Yellow"
                New-Item -Path $claudeConfigDir -ItemType Directory -Force | Out-Null
            }
            
            # Load existing config or create new one
            if (Test-Path $claudeConfigFile) {
                $configContent = Get-Content $claudeConfigFile -Raw
                try {
                    $config = $configContent | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-Log "Error parsing Claude config file. Creating a new one..." "Yellow"
                    $config = [PSCustomObject]@{
                        mcpServers = @{}
                    }
                }
            } else {
                Write-Log "Claude config file not found. Creating a new one..." "Yellow"
                $config = [PSCustomObject]@{
                    mcpServers = @{}
                }
            }
            
            # Ensure mcpServers property exists
            if (-not (Get-Member -InputObject $config -Name "mcpServers" -MemberType Properties)) {
                $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value @{} -Force
            }
            
            # Define the server configuration
            $serverConfig = @{
                command = "docker"
                args = @(
                    "run",
                    "-i", # Keep interactive for MCP protocol
                    "--rm",
                    "-e", 
                    "GOOGLE_MAPS_API_KEY=$($env:GOOGLE_MAPS_API_KEY)",
                    $dockerImage
                )
            }
            
            # Update the config
            $config.mcpServers = @{} + $config.mcpServers # Ensure it's a hashtable, not a PSCustomObject
            $config.mcpServers["google-maps"] = $serverConfig
            
            # Save the updated config with proper JSON formatting
            $configJson = ConvertTo-Json -InputObject $config -Depth 10
            $configJson | Out-File -FilePath $claudeConfigFile -Encoding utf8 -NoNewline
            
            Write-Log "✅ Updated Claude Desktop config with google-maps MCP server" "Green"
        } catch {
            Write-Log "Error updating Claude Desktop config: $_" "Red"
            Write-Log $_.ScriptStackTrace "Red"
        }
        
        Write-Log "✅ Google Maps MCP server deployed successfully" "Green"
        exit 0
    } else {
        throw "Container started but is not running"
    }
} catch {
    Write-Log "❌ Error: Failed to start Docker container. Check Docker logs for $containerName" "Red"
    
    # Try to get container logs if possible
    $containerExists = docker ps -a --filter "name=$containerName" --format "{{.Names}}" 2>$null
    if ($containerExists -eq $containerName) {
        Write-Log "Container logs:" "Cyan"
        docker logs $containerName
    } else {
        Write-Log "Container $containerName does not exist, cannot fetch logs."
    }
    
    exit 1
}

# Step 5: Restart Claude Desktop if it's running
try {
    $restartClaude = $true
    if ($env:RESTART_CLAUDE) {
        if ($env:RESTART_CLAUDE -eq "false") {
            $restartClaude = $false
        }
    }

    if ($restartClaude) {
        $claudeProcessName = "Claude"
        if (Test-ProcessRunning -ProcessName $claudeProcessName) {
            Write-Log "Claude Desktop is running. Restarting..." "Cyan"
            Stop-Process -Name $claudeProcessName -Force
            Start-Sleep -Seconds 2
            
            # Try to find Claude executable in common locations
            $claudeExePath = $null
            $currentUser = [System.Environment]::UserName
            $possiblePaths = @(
                "${env:ProgramFiles}\Claude\Claude.exe",
                "${env:ProgramFiles(x86)}\Claude\Claude.exe",
                "${env:LOCALAPPDATA}\Programs\Claude\Claude.exe",
                "C:\Users\$currentUser\AppData\Local\AnthropicClaude\Claude.exe"
            )
            
            foreach ($path in $possiblePaths) {
                if (Test-Path $path) {
                    $claudeExePath = $path
                    Write-Log "Found Claude at: $claudeExePath" "Cyan"
                    break
                }
            }
            
            if ($claudeExePath) {
                Start-Process $claudeExePath
                Write-Log "✅ Claude Desktop restarted" "Green"
            } else {
                Write-Log "⚠️ Claude Desktop was stopped but couldn't be restarted automatically." "Yellow"
                Write-Log "   Please restart Claude Desktop manually." "Yellow"
            }
        } else {
            Write-Log "Claude Desktop is not running. No need to restart." "Yellow"
        }
    } else {
        Write-Log "Skipping Claude Desktop restart as per settings" "Yellow"
    }
} catch {
    Write-Log "Error restarting Claude Desktop: $_" "Red"
    Write-Log $_.ScriptStackTrace "Red"
    # Don't exit on Claude restart failure, as it's not critical
}

Write-Log "`nGoogle Maps MCP server setup complete!" "Green"
Write-Log "You can now use Google Maps features in Claude Desktop" "Green"
Write-Log "`nUseful commands:" "Cyan"
Write-Log "- View container logs: docker logs $containerName" "Cyan"
Write-Log "- Stop container: docker stop $containerName" "Cyan"
Write-Log "- Remove container: docker rm $containerName" "Cyan"

# Final success message for the log
Write-Log "Deployment completed successfully at $(Get-Date)" "Green"
