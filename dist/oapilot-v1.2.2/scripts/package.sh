#!/bin/bash

# OAPilot Packaging Script
# Creates a distributable package for easy deployment

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

echo "📦 Creating OAPilot Distribution Package"
echo "======================================="

# Get version from package.json or set default
VERSION="1.2.2"
PACKAGE_NAME="oapilot-v${VERSION}"
DIST_DIR="dist"

print_status "Packaging OAPilot version $VERSION"

# Create distribution directory
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/$PACKAGE_NAME"

# Copy core application files
print_status "Copying application files..."

# Backend
cp -r backend "$DIST_DIR/$PACKAGE_NAME/"

# Frontend source (users will build it)
cp -r frontend "$DIST_DIR/$PACKAGE_NAME/"

# Scripts
cp -r scripts "$DIST_DIR/$PACKAGE_NAME/"

# Documentation
cp -r docs "$DIST_DIR/$PACKAGE_NAME/"

# AWS Q compatible MCP configurations
mkdir -p "$DIST_DIR/$PACKAGE_NAME/.amazonq/cli-agents"
cp -r .amazonq/* "$DIST_DIR/$PACKAGE_NAME/.amazonq/" 2>/dev/null || true

# Root files
cp README.md "$DIST_DIR/$PACKAGE_NAME/"

# Remove virtual environment and build artifacts
rm -rf "$DIST_DIR/$PACKAGE_NAME/backend/venv"
rm -rf "$DIST_DIR/$PACKAGE_NAME/backend/storage"
rm -rf "$DIST_DIR/$PACKAGE_NAME/backend/__pycache__"
rm -rf "$DIST_DIR/$PACKAGE_NAME/backend/app/__pycache__"
rm -rf "$DIST_DIR/$PACKAGE_NAME/frontend/node_modules"
rm -rf "$DIST_DIR/$PACKAGE_NAME/frontend/dist"
find "$DIST_DIR/$PACKAGE_NAME" -name "*.pyc" -delete
find "$DIST_DIR/$PACKAGE_NAME" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

print_success "Application files copied"

# Create enhanced installation script
print_status "Creating installation script..."

cat > "$DIST_DIR/$PACKAGE_NAME/install.sh" << 'EOF'
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
EOF

chmod +x "$DIST_DIR/$PACKAGE_NAME/install.sh"
print_success "Installation script created"

# Create quick start script
print_status "Creating quick start script..."

cat > "$DIST_DIR/$PACKAGE_NAME/quick-start.sh" << 'EOF'
#!/bin/bash

# OAPilot Quick Start Script
# Downloads model and starts the application

set -e

echo "🚀 OAPilot Quick Start"
echo "====================="

# Check if installation was completed
if [ ! -f "backend/.env" ]; then
    echo "❌ OAPilot not installed. Please run ./install.sh first"
    exit 1
fi

# Download recommended model if not exists
if ! ollama list | grep -q "phi3:mini"; then
    echo "📦 Downloading recommended model (phi3:mini - ~2GB)..."
    echo "   This may take a few minutes depending on your internet speed..."
    ollama pull phi3:mini
    echo "✅ Model downloaded successfully"
else
    echo "✅ Model phi3:mini already available"
fi

# Start OAPilot
echo "🚀 Starting OAPilot..."
./scripts/start.sh
EOF

chmod +x "$DIST_DIR/$PACKAGE_NAME/quick-start.sh"
print_success "Quick start script created"

# Create uninstall script
print_status "Creating uninstall script..."

cat > "$DIST_DIR/$PACKAGE_NAME/uninstall.sh" << 'EOF'
#!/bin/bash

# OAPilot Uninstall Script

echo "🗑️  OAPilot Uninstaller"
echo "======================"

read -p "This will remove OAPilot and all its data. Are you sure? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled"
    exit 0
fi

# Stop services
echo "🛑 Stopping OAPilot services..."
./scripts/stop.sh 2>/dev/null || true

# Remove Ollama models (optional)
read -p "Remove downloaded Ollama models? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing Ollama models..."
    ollama list | grep -E "phi3|gemma|qwen|mistral" | awk '{print $1}' | xargs -r ollama rm
fi

# Remove application data
echo "🗑️  Removing application data..."
rm -rf backend/storage
rm -rf backend/venv
rm -rf frontend/node_modules
rm -rf frontend/dist
rm -rf logs
rm -rf docker/*/node_modules

echo "✅ OAPilot uninstalled successfully"
echo "   You may manually remove this directory if desired"
EOF

chmod +x "$DIST_DIR/$PACKAGE_NAME/uninstall.sh"
print_success "Uninstall script created"

# Create README for the package
print_status "Creating package README..."

cat > "$DIST_DIR/$PACKAGE_NAME/INSTALL_README.md" << 'EOF'
# OAPilot - Offline AI Pilot System

## Quick Installation Guide

### System Requirements
- **OS**: Ubuntu 18.04+ or WSL2 on Windows
- **RAM**: 8GB minimum (4GB+ available)
- **Storage**: 15GB+ free space
- **Internet**: Required for initial setup only

### Installation Steps

1. **Extract the package** (if downloaded as archive)
   ```bash
   tar -xzf oapilot-v*.tar.gz
   cd oapilot-v*
   ```

2. **Run the installer**
   ```bash
   chmod +x install.sh
   ./install.sh
   ```

3. **Quick start** (downloads model and starts)
   ```bash
   ./quick-start.sh
   ```

4. **Access OAPilot**
   - Open browser: http://localhost:8080
   - From Windows (WSL2): Same URL works!

### Manual Start/Stop

```bash
# Start services
./scripts/start.sh

# Stop services
./scripts/stop.sh

# Check status
curl http://localhost:8080/health
```

### Troubleshooting

1. **Permission Denied**
   ```bash
   chmod +x *.sh scripts/*.sh
   ```

2. **Port Already in Use**
   ```bash
   # Check what's using port 8080
   lsof -i :8080
   # Or change port in backend/.env
   ```

3. **Out of Memory**
   - Close other applications
   - Use smaller model: `ollama pull qwen2:1.5b`
   - Edit `LLM_MODEL=qwen2:1.5b` in backend/.env

4. **Slow Performance**
   - Check system resources: `./scripts/monitor.sh`
   - Use faster model: `ollama pull gemma:2b`

### Configuration

Edit `backend/.env` to customize:
- `LLM_MODEL`: Change AI model
- `MAX_MEMORY_MB`: Adjust memory limit
- `PORT`: Change web interface port

### Uninstall

```bash
./uninstall.sh
```

### Support

- Documentation: `docs/`
- Logs: `logs/backend.log`
- Health: http://localhost:8080/api/v1/health

---

**Note**: This is a self-contained package. After installation, OAPilot runs completely offline with no internet required.
EOF

print_success "Package README created"

# Create monitoring script
cat > "$DIST_DIR/$PACKAGE_NAME/scripts/monitor.sh" << 'EOF'
#!/bin/bash

# OAPilot System Monitor

echo "📊 OAPilot System Monitor"
echo "========================"

# Check if OAPilot is running
if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo "✅ OAPilot is running"
    
    # Get detailed status
    echo ""
    echo "🔍 System Status:"
    curl -s http://localhost:8080/api/v1/resources | python3 -m json.tool 2>/dev/null || echo "   API not responding"
    
else
    echo "❌ OAPilot is not running"
    echo "   Start with: ./scripts/start.sh"
fi

echo ""
echo "💾 System Resources:"
echo "   $(free -h | grep Mem)"
echo "   $(df -h . | tail -n1)"

echo ""
echo "🤖 Ollama Status:"
if pgrep -x "ollama" > /dev/null; then
    echo "   ✅ Ollama is running"
    echo "   Models: $(ollama list | grep -v NAME | wc -l) installed"
else
    echo "   ❌ Ollama is not running"
fi

echo ""
echo "📝 Recent Logs:"
if [ -f "logs/backend.log" ]; then
    echo "   Last 5 backend log entries:"
    tail -n5 logs/backend.log | sed 's/^/     /'
else
    echo "   No logs found"
fi
EOF

chmod +x "$DIST_DIR/$PACKAGE_NAME/scripts/monitor.sh"

# Create the final package archive
print_status "Creating distributable archive..."

cd "$DIST_DIR"
tar -czf "${PACKAGE_NAME}-linux.tar.gz" "$PACKAGE_NAME/"

# Create checksums
sha256sum "${PACKAGE_NAME}-linux.tar.gz" > "${PACKAGE_NAME}-linux.tar.gz.sha256"

cd ..

# Create package info
PACKAGE_SIZE=$(du -sh "$DIST_DIR/${PACKAGE_NAME}-linux.tar.gz" | cut -f1)
PACKAGE_PATH="$DIST_DIR/${PACKAGE_NAME}-linux.tar.gz"

print_success "📦 Package created successfully!"
echo ""
echo "📋 Package Information:"
echo "   Name: ${PACKAGE_NAME}-linux.tar.gz"
echo "   Size: $PACKAGE_SIZE"
echo "   Path: $(realpath "$PACKAGE_PATH")"
echo "   SHA256: $(cat "$DIST_DIR/${PACKAGE_NAME}-linux.tar.gz.sha256" | cut -d' ' -f1)"
echo ""
echo "📤 Distribution Instructions:"
echo ""
echo "1. Share the package file:"
echo "   $(realpath "$PACKAGE_PATH")"
echo ""
echo "2. Users should extract and install:"
echo "   tar -xzf ${PACKAGE_NAME}-linux.tar.gz"
echo "   cd ${PACKAGE_NAME}"
echo "   ./install.sh"
echo "   ./quick-start.sh"
echo ""
echo "3. Alternative quick commands for users:"
echo "   wget <your-download-url>/${PACKAGE_NAME}-linux.tar.gz"
echo "   tar -xzf ${PACKAGE_NAME}-linux.tar.gz && cd ${PACKAGE_NAME} && ./install.sh"
echo ""

# Create distribution summary
cat > "$DIST_DIR/DISTRIBUTION_GUIDE.md" << EOF
# OAPilot Distribution Guide

## Package Details
- **File**: ${PACKAGE_NAME}-linux.tar.gz
- **Size**: $PACKAGE_SIZE
- **Target**: Ubuntu/WSL2 systems
- **Requirements**: 8GB RAM, 15GB disk space

## Distribution Options

### Option 1: Direct File Sharing
Share the package file directly:
\`\`\`
${PACKAGE_NAME}-linux.tar.gz
\`\`\`

### Option 2: Web Download
Host on a web server and provide download link:
\`\`\`bash
wget https://your-server.com/oapilot/${PACKAGE_NAME}-linux.tar.gz
\`\`\`

### Option 3: Git Repository
Upload to a repository and provide clone instructions.

## User Instructions

### Quick Install (Recommended)
\`\`\`bash
# Download and extract
tar -xzf ${PACKAGE_NAME}-linux.tar.gz
cd ${PACKAGE_NAME}

# Install and start
./install.sh
./quick-start.sh
\`\`\`

### Manual Install
\`\`\`bash
# Extract
tar -xzf ${PACKAGE_NAME}-linux.tar.gz
cd ${PACKAGE_NAME}

# Install dependencies
./install.sh

# Download AI model
ollama pull phi3:mini

# Start application
./scripts/start.sh
\`\`\`

## What's Included
- Complete OAPilot application
- Automated installer
- Quick start script
- System monitor
- Uninstaller
- Documentation

## Support Information
- Installation requires internet for dependencies
- Runtime is completely offline
- Includes resource monitoring
- Automatic cleanup and optimization
EOF

print_success "📚 Distribution guide created"
print_success "🎉 OAPilot packaging completed!"
EOF

chmod +x scripts/package.sh