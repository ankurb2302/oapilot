#!/bin/bash

# OAPilot Quick Start Script
# Downloads model automatically and starts the application

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

echo "🚀 OAPilot Quick Start"
echo "This will set up and start OAPilot with automatic model download"
echo ""

# Check if we're in the right directory
if [ ! -f "backend/app/main.py" ]; then
    print_error "Please run this script from the OAPilot root directory"
    exit 1
fi

# Run setup if not done
if [ ! -d "backend/venv" ]; then
    print_status "Setting up OAPilot for first use..."
    ./scripts/setup.sh
fi

# Check system requirements
print_status "Checking system requirements..."
available_mem=$(free -m | awk 'NR==2{print $7}')
available_disk=$(df -BG . | awk 'NR==2{print int($4)}')

echo "   💾 Available Memory: ${available_mem}MB"
echo "   💿 Available Disk: ${available_disk}GB"

if [ "$available_mem" -lt 4096 ]; then
    print_warning "Less than 4GB RAM available (${available_mem}MB)"
    print_warning "Performance may be limited with large models"
fi

if [ "$available_disk" -lt 10 ]; then
    print_error "Less than 10GB disk space available"
    print_error "Need at least 10GB for models and data"
    exit 1
fi

# Install Ollama if not present
if ! command -v ollama &> /dev/null; then
    print_status "Installing Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
    if [ $? -ne 0 ]; then
        print_error "Failed to install Ollama"
        exit 1
    fi
    print_success "Ollama installed successfully"
fi

# Start Ollama service
if ! pgrep -x "ollama" > /dev/null; then
    print_status "Starting Ollama service..."

    # Set Ollama environment variables for resource optimization
    export OLLAMA_MAX_LOADED_MODELS=1
    export OLLAMA_NUM_PARALLEL=1
    export OLLAMA_KEEP_ALIVE=5m
    export OLLAMA_HOST=0.0.0.0:11434

    # Create logs directory
    mkdir -p logs

    # Start Ollama in background
    nohup ollama serve > logs/ollama.log 2>&1 &
    OLLAMA_PID=$!
    echo "$OLLAMA_PID" > logs/ollama.pid

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

# Download phi3:mini model if not available
print_status "Checking for LLM model..."
if ollama list | grep -q "phi3:mini"; then
    print_success "phi3:mini model is available"
else
    print_status "Downloading phi3:mini model (~2GB)..."
    print_warning "This may take several minutes depending on your internet connection"

    ollama pull phi3:mini
    if [ $? -eq 0 ]; then
        print_success "Model downloaded successfully"
    else
        print_error "Failed to download model"
        exit 1
    fi
fi

# Install npm packages if needed
if [ ! -d "node_modules" ]; then
    print_status "Installing MCP dependencies..."
    npm install @modelcontextprotocol/sdk
fi

# Start the application
print_status "Starting OAPilot application..."
./scripts/start.sh

print_success "🎉 OAPilot Quick Start completed!"
echo ""
echo "   🌐 Access the application at: http://localhost:8080"
echo "   📖 API Documentation: http://localhost:8080/docs"
echo "   🛑 To stop: ./scripts/stop.sh or Ctrl+C"
echo ""