# MCP Servers Launch Commands

This document provides simple commands to build and run various MCP servers in this repository.

## Automated Setup Scripts

The repository includes automation scripts that handle the complete setup of MCP servers for both Linux and Windows environments.

### Linux Setup

```bash
# Make the script executable (first time only)
chmod +x scripts/linux/loadBraveMCP.sh

# Run the script to set up the Brave Search MCP server
./scripts/linux/loadBraveMCP.sh
```

### Windows Setup

```powershell
# Run the PowerShell script as Administrator
.\scripts\windows\loadBraveMCP.ps1
```

Both scripts perform the following actions:

1. Check for the required API key in the `.env` file
2. Ensure the Docker image is built
3. Start the MCP server if not already running
   - Linux: Uses screen to run in background while maintaining interactive session
   - Windows: Uses a background Docker container with TTY
4. Update the Claude Desktop configuration file if needed
5. Close Claude Desktop if it's running (so it will pick up the new configuration on restart)

After running the appropriate script for your platform, you can open Claude Desktop and the Brave Search MCP server will be fully configured and ready to use.

### Managing the Running Server

#### Linux (Screen Session)
```bash
# View the logs of the running MCP server
screen -r brave-mcp-server

# Detach from the screen session (Ctrl+A, then D)

# List all screen sessions
screen -ls
```

#### Windows (Docker Container)
```powershell
# View the logs of the running MCP server
docker logs brave-mcp-server

# Follow the logs in real-time
docker logs -f brave-mcp-server

# Stop the container when done
docker stop brave-mcp-server
```

## Brave Search MCP Server

### Build the Docker Image
```bash
# From the repository root directory
docker build -t mcp/brave-search:latest -f src/brave-search/Dockerfile .
```

### Run the Docker Container
```bash
# Method 1: Interactive mode (keeps terminal open)
docker run -it --rm --name "brave-mcp-server" --env-file .env mcp/brave-search
```

### Run in Background with Screen (recommended)
```bash
# Install screen if not already installed
# sudo apt-get install screen

# Start a new screen session for the MCP server
screen -S brave-mcp-server

# Inside the screen session, run the container
docker run -it --rm --env-file .env mcp/brave-search

# Detach from screen session (container keeps running)
# Press Ctrl+A, then D

# Reattach to the screen session later
screen -r brave-mcp-server

# List all screen sessions
screen -ls
```

### Stop the Container
If using interactive mode, press Ctrl+C in the terminal.
If using screen, reattach to the screen session and press Ctrl+C.

### Required Environment Variables
- `BRAVE_API_KEY`: Your Brave Search API key

### Claude Desktop Configuration
Add this to your `claude_desktop_config.json` file to enable the Brave Search MCP server:

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
        "BRAVE_API_KEY": "YOUR_API_KEY_HERE"
      }
    }
  }
}
```

Replace `YOUR_API_KEY_HERE` with your actual Brave Search API key.

### Features
- Web search with pagination and filtering
- Local search for businesses and services
- Automatic fallback from local to web search when no results are found

### API Tools
- `brave_web_search`: Execute web searches
- `brave_local_search`: Search for local businesses and services
