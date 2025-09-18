#!/bin/bash

# OAPilot AWS Q Integration Startup Script
# This script starts OAPilot with AWS Q MCP configuration support

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_ROOT/backend"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== OAPilot AWS Q Integration Startup ===${NC}"

# Function to check if AWS Q configuration exists
check_awsq_config() {
    local config_found=false

    # Check global AWS Q configurations
    if [ -d "$HOME/.aws/amazonq/cli-agents" ] || [ -d "$HOME/.aws/amazonq/agents" ]; then
        echo -e "${GREEN}✓ Found global AWS Q configuration${NC}"
        config_found=true
    fi

    # Check project-level AWS Q configurations
    if [ -d "$PROJECT_ROOT/.amazonq/cli-agents" ] || [ -d "$PROJECT_ROOT/.amazonq/agents" ]; then
        echo -e "${GREEN}✓ Found project-level AWS Q configuration${NC}"
        config_found=true
    fi

    if [ "$config_found" = false ]; then
        echo -e "${YELLOW}⚠ No AWS Q configuration found${NC}"
        echo "  Configuration locations checked:"
        echo "  - ~/.aws/amazonq/cli-agents/*.json"
        echo "  - ~/.aws/amazonq/agents/*.json"
        echo "  - .amazonq/cli-agents/*.json"
        echo "  - .amazonq/agents/*.json"
        echo ""
        echo "  Using the example configuration..."

        # Create directory if it doesn't exist
        mkdir -p "$PROJECT_ROOT/.amazonq/cli-agents"

        # Check if example config exists
        if [ ! -f "$PROJECT_ROOT/.amazonq/cli-agents/oapilot-dev.json" ]; then
            echo -e "${YELLOW}Creating default AWS Q configuration...${NC}"
            cat > "$PROJECT_ROOT/.amazonq/cli-agents/oapilot-dev.json" << 'EOF'
{
  "name": "oapilot-dev",
  "description": "OAPilot Development Agent",
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "."],
      "timeout": 30000
    }
  }
}
EOF
        fi
    fi
}

# Function to install MCP server dependencies
install_mcp_servers() {
    echo -e "${YELLOW}Checking MCP server dependencies...${NC}"

    # Check if npm is installed
    if ! command -v npm &> /dev/null; then
        echo -e "${RED}✗ npm not found. Please install Node.js and npm first.${NC}"
        exit 1
    fi

    # List of common MCP servers that might be needed
    MCP_SERVERS=(
        "@modelcontextprotocol/server-filesystem"
        "@modelcontextprotocol/server-git"
        "@modelcontextprotocol/server-fetch"
        "@modelcontextprotocol/server-sqlite"
    )

    for server in "${MCP_SERVERS[@]}"; do
        if npm list -g "$server" &> /dev/null; then
            echo -e "${GREEN}✓ $server already installed${NC}"
        else
            echo -e "${YELLOW}Installing $server...${NC}"
            npm install -g "$server" || echo -e "${YELLOW}⚠ Failed to install $server (may not be needed)${NC}"
        fi
    done
}

# Function to start backend with AWS Q support
start_backend() {
    echo -e "${GREEN}Starting backend with AWS Q MCP support...${NC}"

    cd "$BACKEND_DIR"

    # Check if virtual environment exists
    if [ ! -d "venv" ]; then
        echo -e "${YELLOW}Creating Python virtual environment...${NC}"
        python3 -m venv venv
    fi

    # Activate virtual environment
    source venv/bin/activate

    # Install/update dependencies
    pip install -q -r requirements.txt
    pip install -q aiohttp  # Ensure aiohttp is installed for STDIO bridge

    # Set environment variables for AWS Q mode
    export USE_AWSQ_MCP=true
    export MCP_AUTO_DISCOVER=false  # Disable Docker auto-discovery

    # Start backend in background
    python app/main.py &
    BACKEND_PID=$!
    echo -e "${GREEN}✓ Backend started (PID: $BACKEND_PID)${NC}"

    # Store PID for later cleanup
    echo $BACKEND_PID > "$PROJECT_ROOT/.backend.pid"
}

# Function to start frontend (if needed)
start_frontend() {
    echo -e "${GREEN}Starting frontend...${NC}"

    cd "$FRONTEND_DIR"

    # Check if node_modules exists
    if [ ! -d "node_modules" ]; then
        echo -e "${YELLOW}Installing frontend dependencies...${NC}"
        npm install
    fi

    # Start frontend in background
    npm run dev &
    FRONTEND_PID=$!
    echo -e "${GREEN}✓ Frontend started (PID: $FRONTEND_PID)${NC}"

    # Store PID for later cleanup
    echo $FRONTEND_PID > "$PROJECT_ROOT/.frontend.pid"
}

# Function to check Ollama status
check_ollama() {
    echo -e "${YELLOW}Checking Ollama status...${NC}"

    if command -v ollama &> /dev/null; then
        if ollama list &> /dev/null; then
            echo -e "${GREEN}✓ Ollama is running${NC}"

            # Check if required model is available
            if ollama list | grep -q "phi3:mini"; then
                echo -e "${GREEN}✓ phi3:mini model available${NC}"
            else
                echo -e "${YELLOW}Pulling phi3:mini model...${NC}"
                ollama pull phi3:mini
            fi
        else
            echo -e "${YELLOW}Starting Ollama...${NC}"
            ollama serve &
            sleep 3
        fi
    else
        echo -e "${RED}✗ Ollama not found. Please install Ollama first.${NC}"
        echo "  Visit: https://ollama.ai"
        exit 1
    fi
}

# Function to display status and instructions
show_status() {
    echo ""
    echo -e "${GREEN}=== OAPilot AWS Q Integration Ready ===${NC}"
    echo ""
    echo "Services running:"
    echo "  • Backend API: http://localhost:8080"
    echo "  • Frontend UI: http://localhost:3000"
    echo "  • API Documentation: http://localhost:8080/docs"
    echo ""
    echo "AWS Q MCP Endpoints:"
    echo "  • List configurations: GET /api/v1/awsq-mcp/configurations"
    echo "  • Load servers: POST /api/v1/awsq-mcp/load"
    echo "  • Server status: GET /api/v1/awsq-mcp/servers"
    echo "  • Health check: GET /api/v1/awsq-mcp/health-check"
    echo "  • Migrate from Docker: POST /api/v1/awsq-mcp/migrate-from-docker"
    echo ""
    echo "To use with AWS Q CLI:"
    echo "  q chat --agent oapilot-dev"
    echo ""
    echo "To stop all services:"
    echo "  ./scripts/stop.sh"
    echo ""
}

# Main execution
main() {
    echo ""

    # Check prerequisites
    check_ollama
    check_awsq_config
    install_mcp_servers

    # Start services
    start_backend
    sleep 3  # Give backend time to start

    # Optionally start frontend
    read -p "Start frontend UI? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        start_frontend
    fi

    # Show status
    show_status

    # Keep script running
    echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"

    # Trap Ctrl+C to cleanup
    trap 'echo "Stopping services..."; [ -f "$PROJECT_ROOT/.backend.pid" ] && kill $(cat "$PROJECT_ROOT/.backend.pid") 2>/dev/null; [ -f "$PROJECT_ROOT/.frontend.pid" ] && kill $(cat "$PROJECT_ROOT/.frontend.pid") 2>/dev/null; rm -f "$PROJECT_ROOT/.backend.pid" "$PROJECT_ROOT/.frontend.pid"; exit' INT

    # Wait forever
    while true; do
        sleep 1
    done
}

# Run main function
main "$@"