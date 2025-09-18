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

    # Fix broken packages first
    print_status "Fixing any broken packages..."
    sudo apt-get update -qq
    sudo dpkg --configure -a
    sudo apt-get install -f -y -qq
    sudo apt-get autoremove -y -qq
    sudo apt-get autoclean -qq

    # Update package list again
    print_status "Updating package lists..."
    sudo apt-get update -qq

    # Install essential packages one by one to identify issues
    print_status "Installing essential packages..."

    packages=(
        "curl"
        "wget"
        "tar"
        "git"
        "build-essential"
        "python3"
        "python3-pip"
        "python3-venv"
        "python3-dev"
        "libssl-dev"
        "libffi-dev"
        "software-properties-common"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
    )

    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            print_status "Installing $package..."

            # Try multiple installation methods with increasing force
            if ! sudo apt-get install -y "$package" 2>/dev/null; then
                print_warning "Standard install failed for $package, trying with --fix-broken..."

                if ! sudo apt-get install -y --fix-broken "$package" 2>/dev/null; then
                    print_warning "Still failing, trying with --allow-downgrades..."

                    if ! sudo apt-get install -y --fix-broken --allow-downgrades "$package" 2>/dev/null; then
                        print_warning "Trying with --force-yes and --allow-unauthenticated..."

                        if ! sudo apt-get install -y --force-yes --allow-unauthenticated "$package" 2>/dev/null; then
                            # Last resort - force install with dpkg
                            print_warning "Using force install for $package..."
                            sudo apt-get download "$package" 2>/dev/null || true
                            sudo dpkg -i --force-depends *.deb 2>/dev/null || true
                            sudo apt-get install -f -y 2>/dev/null || true
                            rm -f *.deb

                            if ! dpkg -l | grep -q "^ii  $package "; then
                                print_warning "Could not install $package, continuing anyway..."
                            else
                                print_success "$package installed with force"
                            fi
                        else
                            print_success "$package installed"
                        fi
                    else
                        print_success "$package installed"
                    fi
                else
                    print_success "$package installed"
                fi
            else
                print_success "$package installed"
            fi
        else
            print_success "$package already installed"
        fi
    done

    # Install Node.js using NodeSource repository (more reliable)
    if ! command -v node &> /dev/null || [ "$(node --version | cut -d'v' -f2 | cut -d. -f1)" -lt 16 ]; then
        print_status "Installing Node.js 18 LTS..."

        # Remove any existing nodejs installations that might conflict
        sudo apt-get remove -y -qq nodejs npm 2>/dev/null || true

        # Add NodeSource repository
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash - 2>/dev/null

        # Install Node.js
        if ! sudo apt-get install -y -qq nodejs; then
            print_warning "NodeSource installation failed, trying snap..."
            sudo snap install node --classic || print_error "Could not install Node.js"
        fi
    fi

    # Verify installations
    print_status "Verifying installations..."
    if command -v python3 &> /dev/null; then
        print_success "Python3: $(python3 --version)"
    else
        print_error "Python3 installation failed"
        exit 1
    fi

    if command -v node &> /dev/null; then
        print_success "Node.js: $(node --version)"
    else
        print_warning "Node.js not available, some MCP servers may not work"
    fi

    if command -v npm &> /dev/null; then
        print_success "npm: $(npm --version)"
    else
        print_warning "npm not available, installing manually..."
        curl -L https://www.npmjs.com/install.sh | sudo sh || print_warning "Manual npm install failed"
    fi

    print_success "System dependencies installation completed"
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

        # Install dependencies
        npm install

        # Explicitly install terser if missing (common issue with Vite)
        if ! npm list terser > /dev/null 2>&1; then
            print_status "Installing terser for Vite build optimization..."
            npm install --save-dev terser
        fi

        # Build frontend
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

    # Create comprehensive oapilot command in user's bin
    mkdir -p "$HOME/.local/bin"

    # Create the comprehensive oapilot command directly
    cat > "$HOME/.local/bin/oapilot" << 'OAPILOT_SCRIPT_EOF'
#!/bin/bash

# OAPilot Global Command
# Auto-generated by OAPilot installer

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_logo() {
    echo -e "${CYAN}"
    cat << 'EOF'
   ___          ____  _ __      __
  / _ \  ____ _ / __ \(_) /___  / /_
 / // / / __ `// /_/ // // _ \/ __/
/____/  \__,_/ \____//_//_//_/\__/

EOF
    echo -e "${NC}"
    echo -e "${BLUE}Offline AI Pilot - Standalone AWS Q Compatible Assistant${NC}"
    echo ""
}

print_help() {
    print_logo
    echo "Usage: oapilot [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  start         Start OAPilot services (default if no command)"
    echo "  stop          Stop all OAPilot services"
    echo "  restart       Restart OAPilot services"
    echo "  status        Show service status"
    echo "  monitor       System monitoring dashboard"
    echo "  logs          Show recent logs"
    echo "  setup         Run initial setup"
    echo "  quick-start   Quick setup and start with model download"
    echo "  health        Check system health"
    echo "  config        Show configuration"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  -v, --version Show version information"
    echo ""
    echo "Examples:"
    echo "  oapilot                 # Start OAPilot"
    echo "  oapilot quick-start     # Setup and start with model download"
    echo "  oapilot monitor         # Show monitoring dashboard"
    echo "  oapilot logs            # Show recent logs"
    echo ""
    echo "Access Points:"
    echo "  🌐 Web Interface:     http://localhost:8080"
    echo "  📊 API Documentation: http://localhost:8080/docs"
    echo "  ❤️  Health Check:     http://localhost:8080/health"
    echo ""
}

get_install_dir() {
    # Check if OAPILOT_HOME is set
    if [ ! -z "$OAPILOT_HOME" ]; then
        echo "$OAPILOT_HOME"
        return
    fi

    # Default location
    echo "$HOME/oapilot"
}

ensure_in_directory() {
    local install_dir=$(get_install_dir)

    if [ ! -d "$install_dir" ]; then
        echo -e "${RED}Error: OAPilot installation not found at $install_dir${NC}"
        echo ""
        echo "To install OAPilot:"
        echo "  curl -fsSL https://raw.githubusercontent.com/ankurb2302/oapilot/main/install-oapilot.sh | bash"
        exit 1
    fi

    if [ ! -f "$install_dir/backend/app/main.py" ]; then
        echo -e "${RED}Error: Invalid OAPilot installation at $install_dir${NC}"
        echo "Missing required files. Please reinstall OAPilot."
        exit 1
    fi

    cd "$install_dir"
}

show_status() {
    ensure_in_directory

    echo -e "${BLUE}OAPilot Service Status${NC}"
    echo ""

    # Check backend
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo -e "✅ Backend API:    ${GREEN}Running${NC} (http://localhost:8080)"
    else
        echo -e "❌ Backend API:    ${RED}Not Running${NC}"
    fi

    # Check Ollama
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo -e "✅ Ollama LLM:     ${GREEN}Running${NC} (http://localhost:11434)"
    else
        echo -e "❌ Ollama LLM:     ${RED}Not Running${NC}"
    fi

    # Check MCP servers
    if curl -s http://localhost:8080/api/v1/awsq-mcp/servers > /dev/null 2>&1; then
        mcp_count=$(curl -s http://localhost:8080/api/v1/awsq-mcp/servers | grep -o '"count":[0-9]*' | cut -d':' -f2 || echo "0")
        echo -e "🔗 MCP Servers:    ${GREEN}$mcp_count active${NC}"
    else
        echo -e "🔗 MCP Servers:    ${YELLOW}Unknown${NC}"
    fi

    echo ""
}

show_logs() {
    ensure_in_directory

    echo -e "${BLUE}Recent OAPilot Logs${NC}"
    echo ""

    if [ -f "logs/backend.log" ]; then
        echo -e "${CYAN}Backend Log (last 20 lines):${NC}"
        tail -20 logs/backend.log
        echo ""
    fi

    if [ -f "logs/ollama.log" ]; then
        echo -e "${CYAN}Ollama Log (last 10 lines):${NC}"
        tail -10 logs/ollama.log
        echo ""
    fi
}

check_health() {
    ensure_in_directory

    echo -e "${BLUE}OAPilot Health Check${NC}"
    echo ""

    # Backend health
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo -e "✅ Backend:        ${GREEN}Healthy${NC}"
    else
        echo -e "❌ Backend:        ${RED}Unhealthy${NC}"
    fi

    # Ollama health
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo -e "✅ Ollama:         ${GREEN}Healthy${NC}"
    else
        echo -e "❌ Ollama:         ${RED}Unhealthy${NC}"
    fi

    echo ""
}

show_config() {
    ensure_in_directory

    echo -e "${BLUE}OAPilot Configuration${NC}"
    echo ""
    echo "Installation Directory: $(pwd)"

    # Check for AWS Q MCP configurations
    config_found=false

    # Global configurations
    if [ -d "$HOME/.aws/amazonq/cli-agents" ]; then
        echo ""
        echo "Global AWS Q MCP Configurations:"
        for config in "$HOME/.aws/amazonq/cli-agents"/*.json; do
            if [ -f "$config" ]; then
                config_name=$(basename "$config" .json)
                echo "   $config_name"
                config_found=true
            fi
        done
    fi

    # Project configurations
    if [ -d ".amazonq/cli-agents" ]; then
        echo ""
        echo "Project AWS Q MCP Configurations:"
        for config in .amazonq/cli-agents/*.json; do
            if [ -f "$config" ]; then
                config_name=$(basename "$config" .json)
                echo "   $config_name"
                config_found=true
            fi
        done
    fi

    if [ "$config_found" = false ]; then
        echo ""
        echo "No AWS Q MCP configurations found."
        echo "Place configurations in:"
        echo "  - Global: $HOME/.aws/amazonq/cli-agents/*.json"
        echo "  - Project: .amazonq/cli-agents/*.json"
    fi

    echo ""
}

# Main command dispatcher
main() {
    local command="${1:-start}"

    case "$command" in
        "-h"|"--help"|"help")
            print_help
            ;;
        "-v"|"--version"|"version")
            echo "OAPilot v1.1.0"
            echo "Offline AI Pilot with AWS Q MCP Integration"
            ;;
        "start"|"")
            ensure_in_directory
            ./scripts/start.sh
            ;;
        "stop")
            ensure_in_directory
            ./scripts/stop.sh
            ;;
        "restart")
            ensure_in_directory
            ./scripts/stop.sh
            sleep 2
            ./scripts/start.sh
            ;;
        "quick-start")
            ensure_in_directory
            ./quick-start.sh
            ;;
        "setup")
            ensure_in_directory
            ./scripts/setup.sh
            ;;
        "status")
            show_status
            ;;
        "monitor")
            ensure_in_directory
            ./scripts/monitor.sh "${2:-all}"
            ;;
        "logs")
            show_logs
            ;;
        "health")
            check_health
            ;;
        "config")
            show_config
            ;;
        *)
            echo -e "${RED}Unknown command: $command${NC}"
            echo ""
            print_help
            exit 1
            ;;
    esac
}

# Check dependencies
if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}Error: curl is required but not installed${NC}"
    exit 1
fi

# Run main function
main "$@"
OAPILOT_SCRIPT_EOF

    # Set the installation directory in the script
    sed -i "s|echo \"\$HOME/oapilot\"|echo \"$INSTALL_DIR\"|" "$HOME/.local/bin/oapilot"

    chmod +x "$HOME/.local/bin/oapilot"

    # Create desktop shortcut (if desktop exists)
    if [ -d "$HOME/Desktop" ]; then
        cat > "$HOME/Desktop/OAPilot.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=OAPilot
Comment=Standalone AI Assistant with AWS Q MCP Integration
Exec=$HOME/.local/bin/oapilot
Icon=$INSTALL_DIR/frontend/public/favicon.ico
Terminal=true
Categories=Development;Office;
StartupNotify=true
EOF
        chmod +x "$HOME/Desktop/OAPilot.desktop"
        print_success "Desktop shortcut created"
    fi

    # Also create a symlink for system-wide access (optional)
    if [ -w "/usr/local/bin" ] 2>/dev/null; then
        ln -sf "$HOME/.local/bin/oapilot" "/usr/local/bin/oapilot" 2>/dev/null && \
        print_success "System-wide oapilot command created" || \
        print_status "User-level oapilot command created"
    else
        print_status "User-level oapilot command created"
    fi

    print_success "Convenience scripts created"
}

# Fix common Ubuntu/Debian package issues
fix_system_issues() {
    print_status "PERFORMING COMPREHENSIVE SYSTEM FIX..."

    print_warning "This will fix broken packages, clear locks, and resolve conflicts"
    print_status "This may take a few minutes..."

    # Step 1: Kill all package manager processes
    print_status "Step 1/8: Stopping package manager processes..."
    sudo systemctl stop packagekit 2>/dev/null || true
    sudo systemctl stop unattended-upgrades 2>/dev/null || true
    sudo systemctl stop apt-daily.timer 2>/dev/null || true
    sudo systemctl stop apt-daily-upgrade.timer 2>/dev/null || true

    # Force kill any hanging processes
    sudo pkill -9 -f apt 2>/dev/null || true
    sudo pkill -9 -f dpkg 2>/dev/null || true
    sudo pkill -9 -f unattended 2>/dev/null || true
    sudo pkill -9 -f packagekit 2>/dev/null || true

    sleep 2

    # Step 2: Remove all locks
    print_status "Step 2/8: Removing package manager locks..."
    sudo rm -f /var/lib/dpkg/lock-frontend
    sudo rm -f /var/lib/dpkg/lock
    sudo rm -f /var/cache/apt/archives/lock
    sudo rm -f /var/lib/apt/lists/lock
    sudo rm -f /var/cache/debconf/*.dat

    # Step 3: Fix dpkg database
    print_status "Step 3/8: Repairing dpkg database..."
    sudo dpkg --configure -a --force-confdef --force-confold

    # Step 4: Clean package cache
    print_status "Step 4/8: Cleaning package cache..."
    sudo apt-get clean
    sudo apt-get autoclean -y

    # Step 5: Fix broken dependencies
    print_status "Step 5/8: Fixing broken dependencies..."
    sudo apt-get update --fix-missing
    sudo apt-get install -f -y
    sudo apt-get autoremove -y --purge

    # Step 6: Update package lists with all repositories
    print_status "Step 6/8: Updating all package lists..."
    sudo apt-get update

    # Step 7: Upgrade packages to resolve version conflicts
    print_status "Step 7/8: Resolving version conflicts..."
    sudo apt-get upgrade -y --fix-broken --allow-downgrades
    sudo apt-get dist-upgrade -y --fix-broken --allow-downgrades

    # Step 8: Final cleanup
    print_status "Step 8/8: Final cleanup..."
    sudo dpkg --configure -a
    sudo apt-get install -f -y
    sudo apt-get autoremove -y
    sudo apt-get autoclean

    # Verify system is fixed
    if sudo apt-get check 2>/dev/null; then
        print_success "✅ SYSTEM FIXED SUCCESSFULLY!"
    else
        print_warning "⚠️ Some issues remain but continuing with installation..."
    fi

    # Check and free disk space if needed
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 15728640 ]; then  # 15GB in KB
        print_warning "Low disk space detected. Performing aggressive cleanup..."

        # Clean journal logs
        sudo journalctl --vacuum-time=1d || true

        # Clean apt cache
        sudo apt-get clean
        sudo rm -rf /var/cache/apt/archives/*.deb

        # Clean temp files
        sudo rm -rf /tmp/*
        sudo rm -rf /var/tmp/*

        # Clean snap cache
        sudo rm -rf /var/lib/snapd/cache/* 2>/dev/null || true

        # Clean docker if present
        docker system prune -af --volumes 2>/dev/null || true

        # Clean old kernels
        sudo apt-get autoremove --purge -y

        print_success "Disk cleanup completed"
    fi

    print_success "System preparation completed!"
}

# Main installation flow
main() {
    # Check for --fix-only flag
    if [ "$1" = "--fix-only" ]; then
        print_banner
        print_warning "Running in FIX-ONLY mode - will only repair system packages"
        fix_system_issues
        print_success "System fix completed! You can now run the installer normally."
        exit 0
    fi

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
    fix_system_issues
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
    echo "   • Global Command: oapilot (added to PATH)"
    echo "   • MCP Config: $INSTALL_DIR/.amazonq/cli-agents/"
    echo "   • Desktop Shortcut: ~/Desktop/OAPilot.desktop"
    echo ""
    echo "🚀 Quick Start:"
    echo "   1. Reload PATH: source ~/.bashrc"
    echo "   2. Start OAPilot: oapilot"
    echo "   3. Open browser: http://localhost:8080"
    echo ""
    echo "🔧 Available Commands:"
    echo "   oapilot                 # Start OAPilot services"
    echo "   oapilot quick-start     # Setup and start with model download"
    echo "   oapilot stop            # Stop all services"
    echo "   oapilot status          # Show service status"
    echo "   oapilot monitor         # System monitoring dashboard"
    echo "   oapilot logs            # Show recent logs"
    echo "   oapilot health          # Check system health"
    echo "   oapilot --help          # Show all commands"
    echo ""
    echo "📖 MCP Configuration:"
    echo "   OAPilot uses AWS Q's MCP configuration format."
    echo "   Edit configs in: $INSTALL_DIR/.amazonq/cli-agents/"
    echo "   No AWS Q installation required!"
    echo ""
    echo "🌐 Access Points:"
    echo "   • Web Interface:     http://localhost:8080"
    echo "   • API Documentation: http://localhost:8080/docs"
    echo "   • Health Check:      http://localhost:8080/health"
    echo ""
    echo "🛑 To uninstall:"
    echo "   rm -rf $INSTALL_DIR"
    echo "   rm $HOME/.local/bin/oapilot"
    echo "   rm ~/Desktop/OAPilot.desktop"
    echo ""
}

# Run main installation
main "$@"