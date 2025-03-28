# PowerShell Script to set up Google Drive MCP server for Claude Desktop on Windows
# This script:
# 1. Loads settings from gdriveSettings.env
# 2. Ensures the Docker image is built
# 3. Starts a background Docker container for the MCP server if not already running
# 4. Updates claude_desktop_config.json if needed
# 5. Restarts Claude Desktop if it's running

# Stop on any error
$ErrorActionPreference = "Stop"

# Define paths and variables
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SettingsFile = Join-Path $RepoRoot "scripts\settings\gdriveSettings.env"
$DockerImage = "mcp/gdrive:latest"
$ContainerName = "gdrive-mcp-server"
$ClaudeConfigDir = Join-Path $env:APPDATA "Claude"
$ClaudeConfig = Join-Path $ClaudeConfigDir "claude_desktop_config.json"
$CredentialsPath = Join-Path $RepoRoot ".gdrive-server-credentials.json"
$GcpOAuthKeysPath = Join-Path $RepoRoot "gcp-oauth.keys.json"

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

# Step 1: Load settings from gdriveSettings.env if it exists
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
    
    if ($settings.ContainsKey("CREDENTIALS_PATH") -and -not [string]::IsNullOrWhiteSpace($settings["CREDENTIALS_PATH"])) {
        $CredentialsPath = $settings["CREDENTIALS_PATH"]
        if (-not [System.IO.Path]::IsPathRooted($CredentialsPath)) {
            $CredentialsPath = Join-Path $RepoRoot $CredentialsPath
        }
        Write-Host "Using custom credentials path: $CredentialsPath" -ForegroundColor Cyan
    }
    
    if ($settings.ContainsKey("GCP_OAUTH_KEYS_PATH") -and -not [string]::IsNullOrWhiteSpace($settings["GCP_OAUTH_KEYS_PATH"])) {
        $GcpOAuthKeysPath = $settings["GCP_OAUTH_KEYS_PATH"]
        if (-not [System.IO.Path]::IsPathRooted($GcpOAuthKeysPath)) {
            $GcpOAuthKeysPath = Join-Path $RepoRoot $GcpOAuthKeysPath
        }
        Write-Host "Using custom GCP OAuth keys path: $GcpOAuthKeysPath" -ForegroundColor Cyan
    }
}

# Step 2: Check for required files
if (-not (Test-Path $GcpOAuthKeysPath)) {
    Write-Host "Error: GCP OAuth keys file not found at $GcpOAuthKeysPath" -ForegroundColor Red
    Write-Host "Please follow the setup instructions in the README to create and download your OAuth client credentials." -ForegroundColor Yellow
    Write-Host "1. Create a new Google Cloud project" -ForegroundColor Yellow
    Write-Host "2. Enable the Google Drive API" -ForegroundColor Yellow
    Write-Host "3. Configure an OAuth consent screen" -ForegroundColor Yellow
    Write-Host "4. Add OAuth scope https://www.googleapis.com/auth/drive.readonly" -ForegroundColor Yellow
    Write-Host "5. Create an OAuth Client ID for application type 'Desktop App'" -ForegroundColor Yellow
    Write-Host "6. Download the JSON file and rename it to gcp-oauth.keys.json" -ForegroundColor Yellow
    Write-Host "7. Place the file in the repository root" -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $CredentialsPath)) {
    Write-Host "Warning: Google Drive credentials file not found at $CredentialsPath" -ForegroundColor Yellow
    Write-Host "You will need to authenticate with Google Drive after the server is started." -ForegroundColor Yellow
    Write-Host "To authenticate:" -ForegroundColor Yellow
    Write-Host "1. Run 'docker exec -it $ContainerName node ./dist auth'" -ForegroundColor Yellow
    Write-Host "2. Follow the authentication flow in your browser" -ForegroundColor Yellow
    Write-Host "3. Credentials will be saved automatically" -ForegroundColor Yellow
}

# Step 3: Ensure Docker image is built
Write-Host "Checking if Docker image exists..."
$imageExists = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String -Pattern "^$DockerImage$" -Quiet

if (-not $imageExists) {
    Write-Host "Building Docker image $DockerImage..."
    $dockerfilePath = Join-Path $RepoRoot "src\gdrive"
    docker build -t $DockerImage -f "$dockerfilePath\Dockerfile" $RepoRoot
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to build Docker image" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ Docker image built successfully" -ForegroundColor Green
} else {
    Write-Host "✅ Docker image already exists" -ForegroundColor Green
}

# Step 4: Start Docker container if not already running
Write-Host "Checking if Docker container is running..."
if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
    Write-Host "Starting Docker container..."
    
    # Remove container if it exists but is not running
    docker rm $ContainerName 2>$null
    
    # Create volume mounts for credentials and OAuth keys
    $credentialsDir = Split-Path -Parent $CredentialsPath
    $oauthKeysDir = Split-Path -Parent $GcpOAuthKeysPath
    $credentialsFileName = Split-Path -Leaf $CredentialsPath
    $oauthKeysFileName = Split-Path -Leaf $GcpOAuthKeysPath
    
    # Start Docker container in interactive mode with a pseudo-TTY
    $dockerRunCommand = "docker run -it --name $ContainerName"
    $dockerRunCommand += " -v `"$credentialsDir\$credentialsFileName`":/app/$credentialsFileName"
    $dockerRunCommand += " -v `"$oauthKeysDir\$oauthKeysFileName`":/app/$oauthKeysFileName"
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

# Step 5: Update Claude Desktop config
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
        "$credentialsDir\$credentialsFileName:/app/$credentialsFileName"
        "-v"
        "$oauthKeysDir\$oauthKeysFileName:/app/$oauthKeysFileName"
        $DockerImage
    )
}

# Check for empty or non-existent config
if ((-not (Test-Path $ClaudeConfig)) -or ((Get-Content $ClaudeConfig -Raw).Trim() -eq "{}") -or ((Get-Content $ClaudeConfig -Raw).Trim() -eq "")) {
    # Create new config
    $config = @{
        mcpServers = @{
            "gdrive" = $serverConfig
        }
    }
    
    # Save the config
    $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
    Write-Host "✅ Created new Claude Desktop config with gdrive MCP server" -ForegroundColor Green
} else {
    # Update existing config
    try {
        $config = Get-Content $ClaudeConfig -Raw | ConvertFrom-Json
        
        # Add mcpServers section if it doesn't exist
        if (-not $config.mcpServers) {
            $config | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value @{}
        }
        
        # Add server configuration
        $config.mcpServers | Add-Member -MemberType NoteProperty -Name "gdrive" -Value $serverConfig -Force
        
        # Save the updated config
        $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
        Write-Host "✅ Updated Claude Desktop config with gdrive MCP server" -ForegroundColor Green
    }
    catch {
        Write-Host "Error updating Claude Desktop config: $_" -ForegroundColor Red
        Write-Host "Creating new config file..." -ForegroundColor Yellow
        
        # Create new config
        $config = @{
            mcpServers = @{
                "gdrive" = $serverConfig
            }
        }
        
        # Save the config
        $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
        Write-Host "✅ Created new Claude Desktop config with gdrive MCP server" -ForegroundColor Green
    }
}

# Step 6: Restart Claude Desktop if it's running
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

Write-Host "`nGoogle Drive MCP server setup complete!" -ForegroundColor Green
Write-Host "You can now use Google Drive features in Claude Desktop" -ForegroundColor Green

# Provide instructions for authentication if needed
if (-not (Test-Path $CredentialsPath)) {
    Write-Host "`nIMPORTANT: You need to authenticate with Google Drive before using the server" -ForegroundColor Yellow
    Write-Host "Run the following command to authenticate:" -ForegroundColor Yellow
    Write-Host "docker exec -it $ContainerName node ./dist auth" -ForegroundColor Cyan
    Write-Host "Then follow the authentication flow in your browser" -ForegroundColor Yellow
}

Write-Host "`nUseful commands:" -ForegroundColor Cyan
Write-Host "- View container logs: docker logs $ContainerName" -ForegroundColor Cyan
Write-Host "- Stop container: docker stop $ContainerName" -ForegroundColor Cyan
Write-Host "- Remove container: docker rm $ContainerName" -ForegroundColor Cyan
Write-Host "- Authenticate with Google Drive: docker exec -it $ContainerName node ./dist auth" -ForegroundColor Cyan
