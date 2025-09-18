#!/bin/bash

# OAPilot Installation Script
# Automated installation for Ubuntu/WSL2

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

echo "🚀 Installing OAPilot - Standalone AI Assistant"
echo "==============================================="
echo "Uses AWS Q MCP configuration format (no AWS Q required)"

# Check if running on supported OS
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    print_error "This installer is designed for Linux/Ubuntu/WSL2"
    print_error "Current OS: $OSTYPE"
    exit 1
fi

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root. This is not recommended."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# System requirements check
print_status "Checking system requirements..."

# Check available memory
available_mem=$(free -m | awk 'NR==2{print $7}')
if [ "$available_mem" -lt 4096 ]; then
    print_warning "Available memory: ${available_mem}MB (Recommended: 4GB+)"
    print_warning "OAPilot may run slowly with limited memory"
else
    print_success "Available memory: ${available_mem}MB"
fi

# Check disk space
available_disk=$(df -BG . | awk 'NR==2{print int($4)}')
if [ "$available_disk" -lt 15 ]; then
    print_error "Insufficient disk space: ${available_disk}GB (Required: 15GB+)"
    exit 1
else
    print_success "Available disk space: ${available_disk}GB"
fi

# Check and install Python 3.8+
print_status "Checking Python installation..."
if command -v python3 &> /dev/null; then
    python_version=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
    required_version="3.8"
    if [ "$(printf '%s\n' "$required_version" "$python_version" | sort -V | head -n1)" = "$required_version" ]; then
        print_success "Python version: $python_version"
    else
        print_error "Python 3.8+ required. Found: $python_version"
        print_status "Installing Python 3.8+..."
        sudo apt update
        sudo apt install -y python3.8 python3.8-venv python3.8-dev python3-pip
    fi
else
    print_error "Python 3 not found. Installing..."
    sudo apt update
    sudo apt install -y python3 python3-venv python3-dev python3-pip
fi

# Check and install pip
if ! command -v pip3 &> /dev/null; then
    print_status "Installing pip..."
    sudo apt install -y python3-pip
fi

# Check and install Node.js
print_status "Checking Node.js installation..."
if command -v node &> /dev/null; then
    node_version=$(node --version | cut -d'v' -f2 | cut -d. -f1)
    if [ "$node_version" -ge 16 ]; then
        print_success "Node.js version: $(node --version)"
    else
        print_warning "Node.js version too old. Installing latest..."
        install_nodejs=true
    fi
else
    print_status "Installing Node.js..."
    install_nodejs=true
fi

if [ "$install_nodejs" = true ]; then
    # Install Node.js 18 LTS
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
    print_success "Node.js installed: $(node --version)"
fi

# Install system dependencies
print_status "Installing system dependencies..."
sudo apt update
sudo apt install -y curl wget git build-essential libssl-dev libffi-dev

# Check and install Docker (optional for MCP servers)
if ! command -v docker &> /dev/null; then
    print_status "Docker not found. Installing Docker (optional for MCP servers)..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    print_success "Docker installed. Please log out and back in for group changes to take effect."
fi

# Install Docker Compose
if ! command -v docker-compose &> /dev/null; then
    print_status "Installing Docker Compose..."
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Set up Python backend
print_status "Setting up Python backend..."
cd backend

# Create virtual environment
if [ ! -d "venv" ]; then
    python3 -m venv venv
    print_success "Virtual environment created"
fi

# Activate virtual environment
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install Python dependencies
print_status "Installing Python dependencies..."
pip install -r requirements.txt
print_success "Python dependencies installed"

# Create .env file
if [ ! -f ".env" ]; then
    print_status "Creating configuration file..."
    cp .env.example .env
    
    # Generate secret key
    secret_key=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    sed -i "s/your-secret-key-here/$secret_key/" .env
    
    print_success "Configuration file created"
fi

# Initialize database
print_status "Initializing database..."
python3 -c "
import sys
sys.path.append('.')
from app.core.database import init_db
init_db()
print('Database initialized successfully')
"
print_success "Database initialized"

cd ..

# Set up frontend
print_status "Setting up frontend..."
cd frontend

# Install Node.js dependencies
print_status "Installing frontend dependencies..."
npm install
print_success "Frontend dependencies installed"

# Build frontend
print_status "Building frontend..."
npm run build
print_success "Frontend built"

cd ..

# Install and setup Ollama
print_status "Setting up Ollama..."

if ! command -v ollama &> /dev/null; then
    print_status "Installing Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
    print_success "Ollama installed"
else
    print_success "Ollama already installed"
fi

# Create directories
mkdir -p logs
mkdir -p backend/storage/{database,artifacts/{code,documents,diagrams,exports},sessions}

# Set permissions
chmod +x scripts/*.sh

print_success "🎉 OAPilot installation completed!"
echo ""
echo "📋 What's been installed:"
echo "   ✅ Python backend with dependencies"
echo "   ✅ React frontend (built)"
echo "   ✅ Ollama LLM engine"
echo "   ✅ Database initialized"
echo "   ✅ Configuration files created"
echo ""
echo "🚀 Next steps:"
echo "   1. Download a model: ollama pull phi3:mini"
echo "   2. Start OAPilot:    ./scripts/start.sh"
echo "   3. Open browser:     http://localhost:8080"
echo ""
echo "📝 Optional:"
echo "   - Configure MCP servers in docker/docker-compose.yml"
echo "   - Adjust settings in backend/.env"
echo "   - View documentation in docs/"
echo ""
print_status "Installation completed successfully!"
