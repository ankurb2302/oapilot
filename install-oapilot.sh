#!/bin/bash

# OAPilot One-Line Installer
# Usage: curl -fsSL https://your-domain.com/install-oapilot.sh | bash

set -e

# Configuration
GITHUB_REPO="ankurb2302/oapilot"
INSTALL_DIR="$HOME/oapilot"
RELEASE_URL="https://github.com/$GITHUB_REPO/releases/latest/download"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo ""
    echo -e "${BLUE}   ___   ___  ____  _ _       _   ${NC}"
    echo -e "${BLUE}  / _ \\ / _ \\|  _ \\(_) | ___ | |_ ${NC}"
    echo -e "${BLUE} | | | | |_| | |_) | | |/ _ \\| __|${NC}"
    echo -e "${BLUE} | |_| |  _  |  __/| | | (_) | |_ ${NC}"
    echo -e "${BLUE}  \\___/|_| |_|_|   |_|_|\\___/ \\__|${NC}"
    echo ""
    echo -e "${GREEN}Standalone AI Assistant using AWS Q MCP Config Format${NC}"
    echo "======================================================"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Check system requirements
check_requirements() {
    print_status "Checking system requirements..."

    # Check OS
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        print_error "This installer requires Linux/Ubuntu/WSL2"
        exit 1
    fi

    # Check available memory
    available_mem=$(free -m | awk 'NR==2{print $7}')
    if [ "$available_mem" -lt 4096 ]; then
        print_warning "Less than 4GB RAM available. OAPilot may run slowly."
    else
        print_success "Memory check passed (${available_mem}MB available)"
    fi

    # Check disk space
    available_disk=$(df -BG "$HOME" | awk 'NR==2{print int($4)}')
    if [ "$available_disk" -lt 10 ]; then
        print_error "Insufficient disk space. At least 10GB required."
        exit 1
    else
        print_success "Disk space check passed (${available_disk}GB available)"
    fi

    # Check for required commands
    for cmd in curl wget tar python3 npm; do
        if ! command -v $cmd &> /dev/null; then
            print_warning "$cmd not found. Will install during setup."
        fi
    done
}

# Install system dependencies
install_dependencies() {
    print_status "Installing system dependencies..."

    # Update package list
    sudo apt-get update -qq

    # Install essential packages
    sudo apt-get install -y -qq \
        curl \
        wget \
        tar \
        git \
        build-essential \
        python3 \
        python3-pip \
        python3-venv \
        nodejs \
        npm \
        libssl-dev \
        libffi-dev

    print_success "System dependencies installed"
}

# Install Ollama
install_ollama() {
    if command -v ollama &> /dev/null; then
        print_success "Ollama already installed"
    else
        print_status "Installing Ollama..."
        curl -fsSL https://ollama.ai/install.sh | sh
        print_success "Ollama installed"
    fi

    # Start Ollama service
    if ! pgrep -x "ollama" > /dev/null; then
        ollama serve > /dev/null 2>&1 &
        sleep 3
    fi

    # Pull default model
    print_status "Downloading AI model (phi3:mini - ~2GB)..."
    ollama pull phi3:mini
    print_success "AI model ready"
}

# Download and extract OAPilot
download_oapilot() {
    print_status "Downloading OAPilot..."

    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Try to get latest release from GitHub
    if [ -n "$GITHUB_REPO" ]; then
        # Get latest release info
        LATEST_RELEASE=$(curl -s "https://api.github.com/repos/$GITHUB_REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

        if [ -n "$LATEST_RELEASE" ]; then
            DOWNLOAD_URL="$RELEASE_URL/oapilot-${LATEST_RELEASE}-linux.tar.gz"
            print_status "Downloading version $LATEST_RELEASE..."

            if wget -q "$DOWNLOAD_URL" -O oapilot.tar.gz; then
                tar -xzf oapilot.tar.gz --strip-components=1
                rm oapilot.tar.gz
                print_success "OAPilot downloaded and extracted"
            else
                print_error "Failed to download from GitHub releases"
                exit 1
            fi
        fi
    fi

    # Alternative: Clone from repository
    if [ ! -f "backend/app/main.py" ]; then
        print_warning "Downloading from repository..."
        git clone "https://github.com/$GITHUB_REPO.git" temp
        mv temp/* .
        rm -rf temp
    fi
}

# Setup OAPilot
setup_oapilot() {
    print_status "Setting up OAPilot..."

    cd "$INSTALL_DIR"

    # Setup Python backend
    print_status "Setting up Python backend..."
    cd backend

    # Create virtual environment
    python3 -m venv venv
    source venv/bin/activate

    # Install Python dependencies
    pip install --upgrade pip
    pip install -r requirements.txt

    # Create configuration
    if [ ! -f ".env" ]; then
        cp .env.example .env 2>/dev/null || cat > .env << EOF
HOST=0.0.0.0
PORT=8080
DEBUG=False
DATABASE_URL=sqlite:///./storage/database/oapilot.db
LLM_MODEL=phi3:mini
OLLAMA_HOST=http://localhost:11434
SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
EOF
    fi

    print_success "Backend configured"

    cd "$INSTALL_DIR"

    # Setup frontend (optional)
    if [ -d "frontend" ]; then
        print_status "Setting up frontend..."
        cd frontend
        npm install
        npm run build
        cd "$INSTALL_DIR"
        print_success "Frontend built"
    fi

    # Create default MCP configuration
    print_status "Creating MCP configuration..."
    mkdir -p .amazonq/cli-agents

    cat > .amazonq/cli-agents/default.json << 'EOF'
{
  "name": "oapilot",
  "description": "OAPilot with local MCP servers",
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "./workspace"],
      "timeout": 30000
    },
    "sqlite": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sqlite", "--db-path", "./backend/storage/database/oapilot.db"],
      "timeout": 30000
    }
  },
  "tools": ["@filesystem", "@sqlite"]
}
EOF

    print_success "MCP configuration created"

    # Create workspace directory
    mkdir -p workspace
    mkdir -p logs

    # Make scripts executable
    chmod +x scripts/*.sh

    print_success "OAPilot setup complete"
}

# Create convenience scripts
create_scripts() {
    print_status "Creating convenience scripts..."

    # Create start script in user's bin
    mkdir -p "$HOME/.local/bin"

    cat > "$HOME/.local/bin/oapilot" << EOF
#!/bin/bash
cd "$INSTALL_DIR"
./scripts/start.sh
EOF
    chmod +x "$HOME/.local/bin/oapilot"

    # Create desktop shortcut (if desktop exists)
    if [ -d "$HOME/Desktop" ]; then
        cat > "$HOME/Desktop/OAPilot.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=OAPilot
Comment=Standalone AI Assistant
Exec=$HOME/.local/bin/oapilot
Icon=$INSTALL_DIR/frontend/public/favicon.ico
Terminal=true
Categories=Development;
EOF
        chmod +x "$HOME/Desktop/OAPilot.desktop"
    fi

    print_success "Convenience scripts created"
}

# Main installation flow
main() {
    print_banner

    # Check if already installed
    if [ -d "$INSTALL_DIR" ]; then
        print_warning "OAPilot appears to be already installed at $INSTALL_DIR"
        read -p "Reinstall? This will overwrite existing installation (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Installation cancelled"
            exit 0
        fi
        rm -rf "$INSTALL_DIR"
    fi

    # Run installation steps
    check_requirements
    install_dependencies
    install_ollama
    download_oapilot
    setup_oapilot
    create_scripts

    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        print_status "Added OAPilot to PATH. Run 'source ~/.bashrc' to update current session."
    fi

    print_success "🎉 OAPilot installation completed successfully!"
    echo ""
    echo "📋 Installation Summary:"
    echo "   • Location: $INSTALL_DIR"
    echo "   • MCP Config: $INSTALL_DIR/.amazonq/cli-agents/"
    echo "   • Start command: oapilot (or $INSTALL_DIR/scripts/start.sh)"
    echo ""
    echo "🚀 Quick Start:"
    echo "   1. Reload PATH: source ~/.bashrc"
    echo "   2. Start OAPilot: oapilot"
    echo "   3. Open browser: http://localhost:8080"
    echo ""
    echo "📖 MCP Configuration:"
    echo "   OAPilot uses AWS Q's MCP configuration format."
    echo "   Edit configs in: $INSTALL_DIR/.amazonq/cli-agents/"
    echo "   No AWS Q installation required!"
    echo ""
    echo "🛑 To uninstall:"
    echo "   rm -rf $INSTALL_DIR"
    echo "   rm $HOME/.local/bin/oapilot"
    echo ""
}

# Run main installation
main "$@"