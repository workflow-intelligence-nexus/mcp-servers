# PowerShell Script to set up Filesystem MCP server for Claude Desktop on Windows
# This script:
# 1. Ensures the Docker image is built
# 2. Starts a background Docker container for the MCP server if not already running
# 3. Updates claude_desktop_config.json if needed
# 4. Restarts Claude Desktop if it's running

# Stop on any error
$ErrorActionPreference = "Stop"

# Define paths and variables
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$ClaudeConfigDir = Join-Path $env:APPDATA "Claude"
$ClaudeConfig = Join-Path $ClaudeConfigDir "claude_desktop_config.json"
$DockerImage = "mcp/filesystem:latest"
$ContainerName = "filesystem-mcp-server"
$SettingsFile = Join-Path $RepoRoot "filesystemSettings.env"

# Function to load directory settings from filesystemSettings.env
function Import-FilesystemSettings {
    param (
        [string]$SettingsFilePath
    )
    
    $directories = @()
    
    if (-not (Test-Path $SettingsFilePath)) {
        Write-Host "Settings file not found at $SettingsFilePath, using default settings" -ForegroundColor Yellow
        # Default directories if settings file doesn't exist
        $directories += @{
            Source = Join-Path $env:USERPROFILE "Documents"
            Target = "/projects/Documents"
            ReadOnly = $false
        }
        $directories += @{
            Source = Join-Path $env:USERPROFILE "Desktop"
            Target = "/projects/Desktop"
            ReadOnly = $false
        }
        return $directories
    }
    
    Write-Host "Loading directory settings from $SettingsFilePath..."
    
    # Read and process each line in the settings file
    Get-Content $SettingsFilePath | ForEach-Object {
        if (-not [string]::IsNullOrWhiteSpace($_) -and -not $_.StartsWith('#')) {
            $line = $_.Trim()
            if ($line -match '(.+?)=(.*)') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                
                # Expand environment variables
                $expandedValue = [Environment]::ExpandEnvironmentVariables($value)
                
                # Check if path is marked as read-only
                $isReadOnly = $false
                if ($expandedValue -match '(.+):ro$') {
                    $expandedValue = $matches[1]
                    $isReadOnly = $true
                }
                
                # Verify the path exists
                if (Test-Path $expandedValue) {
                    $targetPath = "/projects/$key"
                    $directories += @{
                        Source = $expandedValue
                        Target = $targetPath
                        ReadOnly = $isReadOnly
                    }
                    Write-Host "Added directory: $expandedValue -> $targetPath $(if ($isReadOnly) { '(read-only)' } else { '(read-write)' })" -ForegroundColor Green
                } else {
                    Write-Host "Warning: Directory does not exist: $expandedValue" -ForegroundColor Yellow
                }
            }
        }
    }
    
    if ($directories.Count -eq 0) {
        Write-Host "No valid directories found in settings file, using default settings" -ForegroundColor Yellow
        # Default directories if no valid directories found
        $directories += @{
            Source = Join-Path $env:USERPROFILE "Documents"
            Target = "/projects/Documents"
            ReadOnly = $false
        }
        $directories += @{
            Source = Join-Path $env:USERPROFILE "Desktop"
            Target = "/projects/Desktop"
            ReadOnly = $false
        }
    }
    
    return $directories
}

# Load directory settings
$MountDirectories = Import-FilesystemSettings -SettingsFilePath $SettingsFile

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

# Function to build Docker mount arguments
function Get-DockerMountArgs {
    param (
        [array]$Directories
    )
    
    $mountArgs = @()
    foreach ($dir in $Directories) {
        $mountType = "type=bind,src=$($dir.Source),dst=$($dir.Target)"
        if ($dir.ReadOnly) {
            $mountType += ",ro"
        }
        $mountArgs += "--mount"
        $mountArgs += $mountType
    }
    
    return $mountArgs
}

# Change to repository root
Set-Location $RepoRoot

# Step 1: Ensure Docker image is built
Write-Host "Checking if Docker image exists..."
$imageExists = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String -Pattern "^$DockerImage$" -Quiet

if (-not $imageExists) {
    Write-Host "Building Docker image..."
    docker build -t $DockerImage -f src/filesystem/Dockerfile .
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Failed to build Docker image" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Docker image built successfully" -ForegroundColor Green
} else {
    Write-Host "✅ Docker image already exists" -ForegroundColor Green
}

# Step 2: Start Docker container if not already running
Write-Host "Checking if Filesystem MCP server is running..."
if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
    Write-Host "Starting Filesystem MCP server in Docker container..."
    
    # Build mount arguments
    $mountArgs = Get-DockerMountArgs -Directories $MountDirectories
    
    # Build the full Docker run command
    $dockerArgs = @(
        "run",
        "-it",
        "--name", $ContainerName,
        "--rm"
    )
    $dockerArgs += $mountArgs
    $dockerArgs += @(
        $DockerImage,
        "/projects"
    )
    
    # Start Docker container in the background
    $dockerCmd = "docker $($dockerArgs -join ' ')"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $dockerCmd -WindowStyle Hidden
    
    # Give it a moment to start
    Start-Sleep -Seconds 2
    
    if (-not (Test-ContainerRunning -ContainerName $ContainerName)) {
        Write-Host "Error: Failed to start Docker container" -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Filesystem MCP server started in Docker container" -ForegroundColor Green
} else {
    Write-Host "✅ Filesystem MCP server already running in Docker container" -ForegroundColor Green
}

# Step 3: Update Claude Desktop config if needed
Write-Host "Checking Claude Desktop configuration..."
if ((-not (Test-Path $ClaudeConfig)) -or ((Get-Content $ClaudeConfig -Raw).Trim() -eq "{}")) {
    Write-Host "Creating Claude Desktop config file..."
    
    # Create directory if it doesn't exist
    if (-not (Test-Path $ClaudeConfigDir)) {
        New-Item -ItemType Directory -Path $ClaudeConfigDir | Out-Null
    }
    
    # Build mount arguments for config
    $mountArgsJson = @()
    foreach ($dir in $MountDirectories) {
        $mountType = "type=bind,src=$($dir.Source),dst=$($dir.Target)"
        if ($dir.ReadOnly) {
            $mountType += ",ro"
        }
        $mountArgsJson += "--mount"
        $mountArgsJson += $mountType
    }
    
    # Create the config file with the Filesystem MCP server configuration
    $configJson = @"
{
  "mcpServers": {
    "filesystem": {
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--rm",
        $(($mountArgsJson | ForEach-Object { "`"$_`"" }) -join ",`n        "),
        "mcp/filesystem",
        "/projects"
      ]
    }
  }
}
"@
    
    Set-Content -Path $ClaudeConfig -Value $configJson
    Write-Host "✅ Claude Desktop config created" -ForegroundColor Green
} else {
    # Check if config already has filesystem MCP server
    $configContent = Get-Content $ClaudeConfig -Raw
    if ($configContent -match '"filesystem"') {
        Write-Host "✅ Claude Desktop config already contains filesystem MCP server" -ForegroundColor Green
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
            
            # Build mount arguments for config
            $mountArgsJson = @()
            foreach ($dir in $MountDirectories) {
                $mountType = "type=bind,src=$($dir.Source),dst=$($dir.Target)"
                if ($dir.ReadOnly) {
                    $mountType += ",ro"
                }
                $mountArgsJson += "--mount"
                $mountArgsJson += $mountType
            }
            
            # Add filesystem to mcpServers
            $filesystemConfig = @{
                command = "docker"
                args = @(
                    "run",
                    "-i",
                    "--rm"
                )
            }
            
            # Add mount arguments
            foreach ($arg in $mountArgsJson) {
                $filesystemConfig.args += $arg
            }
            
            # Add final arguments
            $filesystemConfig.args += "mcp/filesystem"
            $filesystemConfig.args += "/projects"
            
            # Add the new property
            $config.mcpServers | Add-Member -MemberType NoteProperty -Name "filesystem" -Value $filesystemConfig -Force
            
            # Save the updated config
            $config | ConvertTo-Json -Depth 10 | Set-Content $ClaudeConfig
            Write-Host "✅ Claude Desktop config updated" -ForegroundColor Green
        }
        catch {
            Write-Host "Error parsing existing config. Creating new config file..." -ForegroundColor Yellow
            
            # Build mount arguments for config
            $mountArgsJson = @()
            foreach ($dir in $MountDirectories) {
                $mountType = "type=bind,src=$($dir.Source),dst=$($dir.Target)"
                if ($dir.ReadOnly) {
                    $mountType += ",ro"
                }
                $mountArgsJson += "--mount"
                $mountArgsJson += $mountType
            }
            
            # Create the config file with the Filesystem MCP server configuration
            $configJson = @"
{
  "mcpServers": {
    "filesystem": {
      "command": "docker",
      "args": [
        "run",
        "-i",
        "--rm",
        $(($mountArgsJson | ForEach-Object { "`"$_`"" }) -join ",`n        "),
        "mcp/filesystem",
        "/projects"
      ]
    }
  }
}
"@
            
            Set-Content -Path $ClaudeConfig -Value $configJson
            Write-Host "✅ Claude Desktop config created" -ForegroundColor Green
        }
    }
}

# Step 4: Restart Claude Desktop if it's running
Write-Host "Checking if Claude Desktop is running..."
if (Test-ProcessRunning -ProcessName "claude-desktop") {
    Write-Host "Closing Claude Desktop..."
    Stop-Process -Name "claude-desktop" -Force
    Write-Host "✅ Claude Desktop closed" -ForegroundColor Green
} else {
    Write-Host "✅ Claude Desktop is not running" -ForegroundColor Green
}

Write-Host "✅ All done! Claude Desktop is now configured to use the Filesystem MCP server." -ForegroundColor Green
Write-Host "You can now start Claude Desktop and the Filesystem MCP server will be available." -ForegroundColor Green
Write-Host ""
Write-Host "The following directories are accessible to Claude:" -ForegroundColor Cyan
foreach ($dir in $MountDirectories) {
    $readOnlyStatus = if ($dir.ReadOnly) { "(read-only)" } else { "(read-write)" }
    Write-Host "- $($dir.Source) $readOnlyStatus" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "To view the Filesystem MCP server logs, use: docker logs $ContainerName" -ForegroundColor Cyan
Write-Host "To stop the container when done, use: docker stop $ContainerName" -ForegroundColor Cyan
Write-Host ""
Write-Host "To customize directories, edit the filesystemSettings.env file." -ForegroundColor Yellow
