#!/bin/bash

# Script to set up Brave Search MCP server for Claude Desktop
# This script:
# 1. Checks for BRAVE_API_KEY in .env file
# 2. Ensures the Docker image is built
# 3. Starts a screen session for the MCP server if not already running
# 4. Updates claude_desktop_config.json if needed
# 5. Restarts Claude Desktop if it's running

set -e  # Exit on any error

# Define paths and variables
REPO_ROOT="/home/winadmin/Projects/mcp-servers"
ENV_FILE="$REPO_ROOT/.env"
CLAUDE_CONFIG="$HOME/.config/claude-desktop/claude_desktop_config.json"
SCREEN_NAME="brave-mcp-server"
DOCKER_IMAGE="mcp/brave-search:latest"

# Function to check if a program is running
is_running() {
    pgrep -f "$1" > /dev/null
}

# Function to check if a screen session exists
screen_exists() {
    screen -list | grep -q "$1"
}

# Change to repository root
cd "$REPO_ROOT"

# Step 1: Check for BRAVE_API_KEY in .env file
echo "Checking for BRAVE_API_KEY in .env file..."
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Extract API key from .env file
BRAVE_API_KEY=$(grep -o 'BRAVE_API_KEY=.*' "$ENV_FILE" | cut -d= -f2)
if [ -z "$BRAVE_API_KEY" ]; then
    echo "Error: BRAVE_API_KEY not found in .env file"
    exit 1
fi
echo "✅ BRAVE_API_KEY found in .env file"

# Step 2: Ensure Docker image is built
echo "Checking if Docker image exists..."
if ! docker images | grep -q "$DOCKER_IMAGE"; then
    echo "Building Docker image..."
    docker build -t "$DOCKER_IMAGE" -f src/brave-search/Dockerfile .
    if [ $? -ne 0 ]; then
        echo "Error: Failed to build Docker image"
        exit 1
    fi
    echo "✅ Docker image built successfully"
else
    echo "✅ Docker image already exists"
fi

# Step 3: Start screen session if not already running
echo "Checking if Brave MCP server is running..."
if ! screen_exists "$SCREEN_NAME"; then
    echo "Starting Brave MCP server in screen session..."
    screen -dmS "$SCREEN_NAME" bash -c "docker run -it --rm --env-file .env $DOCKER_IMAGE"
    sleep 2  # Give it a moment to start
    if ! screen_exists "$SCREEN_NAME"; then
        echo "Error: Failed to start screen session"
        exit 1
    fi
    echo "✅ Brave MCP server started in screen session"
else
    echo "✅ Brave MCP server already running in screen session"
fi

# Step 4: Update Claude Desktop config if needed
echo "Checking Claude Desktop configuration..."
if [ ! -f "$CLAUDE_CONFIG" ]; then
    echo "Creating Claude Desktop config file..."
    mkdir -p "$(dirname "$CLAUDE_CONFIG")"
    echo '{
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
        "BRAVE_API_KEY": "'"$BRAVE_API_KEY"'"
      }
    }
  }
}' > "$CLAUDE_CONFIG"
    echo "✅ Claude Desktop config created"
else
    # Check if config already has brave-search MCP server
    if grep -q '"brave-search"' "$CLAUDE_CONFIG"; then
        echo "✅ Claude Desktop config already contains brave-search MCP server"
    else
        echo "Updating Claude Desktop config..."
        # Create a backup of the original config
        cp "$CLAUDE_CONFIG" "${CLAUDE_CONFIG}.bak"
        
        # If the file has mcpServers but not brave-search, add brave-search
        if grep -q '"mcpServers"' "$CLAUDE_CONFIG"; then
            # Use jq to add brave-search to mcpServers if jq is available
            if command -v jq > /dev/null; then
                jq '.mcpServers += {"brave-search": {"command": "docker", "args": ["run", "-i", "--rm", "-e", "BRAVE_API_KEY", "mcp/brave-search"], "env": {"BRAVE_API_KEY": "'"$BRAVE_API_KEY"'"}}}' "$CLAUDE_CONFIG" > "${CLAUDE_CONFIG}.tmp"
                mv "${CLAUDE_CONFIG}.tmp" "$CLAUDE_CONFIG"
            else
                # Simple sed-based approach as fallback
                sed -i 's/"mcpServers": {/"mcpServers": {\n    "brave-search": {\n      "command": "docker",\n      "args": [\n        "run",\n        "-i",\n        "--rm",\n        "-e",\n        "BRAVE_API_KEY",\n        "mcp\/brave-search"\n      ],\n      "env": {\n        "BRAVE_API_KEY": "'"$BRAVE_API_KEY"'"\n      }\n    },/g' "$CLAUDE_CONFIG"
            fi
        else
            # Add mcpServers section if it doesn't exist
            # This is a simplistic approach and may not work for all config files
            sed -i 's/{/{\n  "mcpServers": {\n    "brave-search": {\n      "command": "docker",\n      "args": [\n        "run",\n        "-i",\n        "--rm",\n        "-e",\n        "BRAVE_API_KEY",\n        "mcp\/brave-search"\n      ],\n      "env": {\n        "BRAVE_API_KEY": "'"$BRAVE_API_KEY"'"\n      }\n    }\n  },/g' "$CLAUDE_CONFIG"
        fi
        echo "✅ Claude Desktop config updated"
    fi
fi

# Step 5: Restart Claude Desktop if it's running
echo "Checking if Claude Desktop is running..."
if is_running "claude-desktop"; then
    echo "Closing Claude Desktop..."
    pkill -f "claude-desktop"
    echo "✅ Claude Desktop closed"
else
    echo "✅ Claude Desktop is not running"
fi

echo "✅ All done! Claude Desktop is now configured to use the Brave Search MCP server."
echo "You can now start Claude Desktop and the Brave Search MCP server will be available."
echo ""
echo "To view the Brave MCP server logs, use: screen -r $SCREEN_NAME"
echo "To detach from the screen session, press Ctrl+A, then D"
