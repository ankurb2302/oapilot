#!/bin/bash

# OAPilot Startup Script

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🚀 Starting OAPilot services..."

# Check if we're in the right directory
if [ ! -f "backend/app/main.py" ]; then
    print_error "Please run this script from the OAPilot root directory"
    exit 1
fi

# Check system resources
print_status "Checking system resources..."
available_mem=$(free -m | awk 'NR==2{print $7}')
available_disk=$(df -BG . | awk 'NR==2{print int($4)}')

echo "   💾 Available Memory: ${available_mem}MB"
echo "   💿 Available Disk: ${available_disk}GB"

if [ "$available_mem" -lt 2048 ]; then
    print_warning "Less than 2GB RAM available (${available_mem}MB)"
    print_warning "Consider closing other applications for better performance"
fi

if [ "$available_disk" -lt 5 ]; then
    print_warning "Less than 5GB disk space available"
fi

# Check if backend virtual environment exists
if [ ! -d "backend/venv" ]; then
    print_error "Backend virtual environment not found. Please run ./scripts/setup.sh first"
    exit 1
fi

# Start Ollama if not running
if ! pgrep -x "ollama" > /dev/null; then
    print_status "Starting Ollama service..."
    
    # Set Ollama environment variables for resource optimization
    export OLLAMA_MAX_LOADED_MODELS=1
    export OLLAMA_NUM_PARALLEL=1
    export OLLAMA_KEEP_ALIVE=5m
    export OLLAMA_HOST=0.0.0.0:11434
    
    # Start Ollama in background
    nohup ollama serve > logs/ollama.log 2>&1 &
    OLLAMA_PID=$!
    
    # Wait for Ollama to be ready
    print_status "Waiting for Ollama to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
            print_success "Ollama is ready!"
            break
        fi
        sleep 1
        if [ $i -eq 30 ]; then
            print_error "Ollama failed to start within 30 seconds"
            exit 1
        fi
    done
else
    print_success "Ollama is already running"
fi

# Check if model is available
print_status "Checking LLM model availability..."
if ollama list | grep -q "phi3:mini"; then
    print_success "phi3:mini model is available"
else
    print_warning "phi3:mini model not found. Pulling it now..."
    ollama pull phi3:mini
fi

# Start backend
print_status "Starting OAPilot backend..."
cd backend

# Activate virtual environment
source venv/bin/activate

# Create logs directory
mkdir -p ../logs

# Set environment variables for optimization
export PYTHONOPTIMIZE=1
export PYTHONUNBUFFERED=1
export PYTHONIOENCODING=utf-8
export GEVENT_SUPPORT=1

# Start backend server using startup script that handles Python path
nohup python3 -O start_backend.py > ../logs/backend.log 2>&1 &
BACKEND_PID=$!

cd ..

# Wait for backend to be ready
print_status "Waiting for backend to be ready..."
for i in {1..60}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        print_success "Backend is ready!"
        break
    fi
    sleep 1
    if [ $i -eq 60 ]; then
        print_error "Backend failed to start within 60 seconds"
        print_error "Check logs/backend.log for details"
        exit 1
    fi
done

# Setup MCP configuration (AWS Q compatible format)
print_status "Setting up MCP configuration..."

# Create config directory if it doesn't exist
mkdir -p .amazonq/cli-agents

# Check if MCP config exists, create default if not
if [ ! -f ".amazonq/cli-agents/default.json" ] && [ ! -f "$HOME/.aws/amazonq/cli-agents/default.json" ]; then
    print_status "Creating default MCP configuration..."
    cat > .amazonq/cli-agents/default.json << 'EOCONF'
{
  "name": "oapilot",
  "description": "OAPilot MCP Configuration",
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "./workspace"],
      "timeout": 30000
    }
  }
}
EOCONF
    print_success "Created default MCP configuration at .amazonq/cli-agents/default.json"
else
    print_success "MCP configuration found"
fi

# Display startup information
echo ""
print_success "🎉 OAPilot is running!"
echo ""
echo "   🌐 Web Interface:      http://localhost:8080"
echo "   📊 API Documentation:  http://localhost:8080/docs"
echo "   ❤️  Health Check:      http://localhost:8080/health"
echo "   🤖 Ollama API:         http://localhost:11434"
echo ""
echo "   📝 Logs:"
echo "      Backend:  logs/backend.log"
echo "      Ollama:   logs/ollama.log"
echo ""
echo "   💡 Tips:"
echo "      - Access from Windows: Use the same URLs"
echo "      - Resource usage is monitored automatically"
echo "      - Check /api/v1/resources for system status"
echo ""
echo "   🛑 To stop: ./scripts/stop.sh or Ctrl+C"
echo ""

# Save PIDs for stop script
echo "$BACKEND_PID" > logs/backend.pid
if [ ! -z "$OLLAMA_PID" ]; then
    echo "$OLLAMA_PID" > logs/ollama.pid
fi

# Create cleanup function
cleanup() {
    echo ""
    print_status "Stopping OAPilot services..."
    
    # Stop backend
    if [ -f "logs/backend.pid" ]; then
        kill $(cat logs/backend.pid) 2>/dev/null || true
        rm -f logs/backend.pid
    fi
    
    # Stop Ollama if we started it
    if [ -f "logs/ollama.pid" ]; then
        kill $(cat logs/ollama.pid) 2>/dev/null || true
        rm -f logs/ollama.pid
    fi
    
    # Stop MCP servers
    if [ -f "docker/docker-compose.yml" ]; then
        cd docker
        docker-compose down 2>/dev/null || true
        cd ..
    fi
    
    print_success "Services stopped"
    exit 0
}

# Trap cleanup on script exit
trap cleanup EXIT INT TERM

# Wait for user input or process termination
print_status "OAPilot is running. Press Ctrl+C to stop."
while true; do
    sleep 10
    
    # Check if backend is still running
    if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
        print_error "Backend appears to have stopped"
        break
    fi
done