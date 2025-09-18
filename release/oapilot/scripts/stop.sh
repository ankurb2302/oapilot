#!/bin/bash

# OAPilot Stop Script

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

echo "🛑 Stopping OAPilot services..."

# Stop backend using PID file
if [ -f "logs/backend.pid" ]; then
    BACKEND_PID=$(cat logs/backend.pid)
    if kill -0 $BACKEND_PID 2>/dev/null; then
        print_status "Stopping backend (PID: $BACKEND_PID)..."
        kill $BACKEND_PID
        # Wait for graceful shutdown
        for i in {1..10}; do
            if ! kill -0 $BACKEND_PID 2>/dev/null; then
                break
            fi
            sleep 1
        done
        # Force kill if still running
        if kill -0 $BACKEND_PID 2>/dev/null; then
            kill -9 $BACKEND_PID 2>/dev/null
        fi
        rm -f logs/backend.pid
        print_success "Backend stopped"
    else
        print_warning "Backend PID not found or already stopped"
        rm -f logs/backend.pid
    fi
else
    # Fallback: stop by process name
    print_status "Stopping backend processes..."
    pkill -f "python.*main.py" 2>/dev/null && print_success "Backend stopped" || print_warning "No backend processes found"
fi

# Stop Ollama using PID file
if [ -f "logs/ollama.pid" ]; then
    OLLAMA_PID=$(cat logs/ollama.pid)
    if kill -0 $OLLAMA_PID 2>/dev/null; then
        print_status "Stopping Ollama (PID: $OLLAMA_PID)..."
        kill $OLLAMA_PID
        # Wait for graceful shutdown
        for i in {1..10}; do
            if ! kill -0 $OLLAMA_PID 2>/dev/null; then
                break
            fi
            sleep 1
        done
        # Force kill if still running
        if kill -0 $OLLAMA_PID 2>/dev/null; then
            kill -9 $OLLAMA_PID 2>/dev/null
        fi
        rm -f logs/ollama.pid
        print_success "Ollama stopped"
    else
        print_warning "Ollama PID not found or already stopped"
        rm -f logs/ollama.pid
    fi
else
    # Check if Ollama is running and stop it
    if pgrep -x "ollama" > /dev/null; then
        print_status "Stopping Ollama..."
        pkill ollama 2>/dev/null && print_success "Ollama stopped" || print_warning "Failed to stop Ollama"
    fi
fi

# Stop MCP servers if docker-compose exists
if [ -f "docker/docker-compose.yml" ]; then
    print_status "Stopping MCP servers..."
    cd docker
    if command -v docker-compose &> /dev/null; then
        docker-compose down 2>/dev/null
        print_success "MCP servers stopped"
    else
        print_warning "docker-compose not found"
    fi
    cd ..
fi

# Clean up any remaining processes
print_status "Cleaning up remaining processes..."

# Kill any remaining OAPilot processes
pgrep -f "oapilot\|OAPilot" | xargs -r kill 2>/dev/null || true

# Check for processes using ports 8080 and 11434
for port in 8080 11434; do
    PID=$(lsof -ti:$port 2>/dev/null || true)
    if [ ! -z "$PID" ]; then
        print_warning "Killing process using port $port (PID: $PID)"
        kill $PID 2>/dev/null || true
    fi
done

# Clean up temporary files
rm -f logs/*.pid 2>/dev/null || true

print_success "✅ All OAPilot services stopped"

# Show final status
echo ""
echo "   💡 To restart OAPilot:"
echo "      ./scripts/start.sh"
echo ""
echo "   📝 Logs are preserved in logs/ directory"
echo ""