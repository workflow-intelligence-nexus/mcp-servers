# PowerShell Script to load environment variables for the Brave Search MCP server
# This script:
# 1. Finds the repository root
# 2. Loads environment variables from .env file
# 3. Makes them available for other scripts

# Stop on any error
$ErrorActionPreference = "Stop"

# Define paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$EnvFile = Join-Path $RepoRoot ".env"

# Function to load environment variables from .env file
function Import-EnvFile {
    param (
        [string]$EnvFilePath
    )
    
    Write-Host "Loading environment variables from $EnvFilePath..."
    
    if (-not (Test-Path $EnvFilePath)) {
        Write-Host "Error: .env file not found at $EnvFilePath" -ForegroundColor Red
        exit 1
    }
    
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
                Write-Host "Set environment variable: $key" -ForegroundColor Green
            }
        }
    }
}

# Check if .env file exists and load it
if (Test-Path $EnvFile) {
    Import-EnvFile -EnvFilePath $EnvFile
    
    # Verify BRAVE_API_KEY was loaded
    if ([string]::IsNullOrWhiteSpace($env:BRAVE_API_KEY)) {
        Write-Host "Warning: BRAVE_API_KEY is empty or not set in .env file" -ForegroundColor Yellow
    } else {
        Write-Host "✅ BRAVE_API_KEY loaded successfully" -ForegroundColor Green
    }
} else {
    Write-Host "Error: .env file not found at $EnvFile" -ForegroundColor Red
    Write-Host "Please create a .env file with BRAVE_API_KEY=your_api_key in the repository root" -ForegroundColor Yellow
    exit 1
}

Write-Host "✅ Environment variables loaded successfully" -ForegroundColor Green
