#!/bin/bash

# Create GitHub Release Package for OAPilot

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

echo "🐙 Creating OAPilot GitHub Release Package"
echo "=========================================="
echo "Standalone AI Assistant using AWS Q MCP Config Format"

VERSION="1.0.0"
RELEASE_NAME="oapilot-v${VERSION}"

# Clean and create release directory
rm -rf release
mkdir -p release

print_status "Creating GitHub release structure..."

# Copy entire project for GitHub
cp -r . release/oapilot
cd release/oapilot

# Clean up unnecessary files for GitHub
rm -rf dist
rm -rf release
rm -rf backend/venv
rm -rf backend/storage
rm -rf backend/__pycache__
rm -rf frontend/node_modules
rm -rf frontend/dist
rm -rf logs
find . -name "*.pyc" -delete
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

cd ..

# Create the one-liner installer script that downloads from GitHub
cat > oapilot-installer.sh << 'EOF'
#!/bin/bash

# OAPilot One-Line Installer for GitHub
# Usage: curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/installer.sh | bash

set -e

REPO_URL="https://github.com/YOUR_USERNAME/YOUR_REPO"
REPO_NAME="YOUR_REPO"
BRANCH="main"

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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "🚀 OAPilot One-Line Installer"
echo "============================="

# Check if git is available
if ! command -v git &> /dev/null; then
    print_error "Git is required but not installed."
    print_status "Installing git..."
    sudo apt update && sudo apt install -y git
fi

# Check if curl is available
if ! command -v curl &> /dev/null; then
    print_status "Installing curl..."
    sudo apt update && sudo apt install -y curl
fi

# Clone or download the repository
print_status "Downloading OAPilot from GitHub..."
if [ -d "oapilot" ]; then
    print_status "Directory 'oapilot' exists. Removing..."
    rm -rf oapilot
fi

# Option 1: Use git clone (preferred)
if command -v git &> /dev/null; then
    git clone ${REPO_URL}.git oapilot
else
    # Option 2: Download as ZIP
    curl -L "${REPO_URL}/archive/${BRANCH}.zip" -o oapilot.zip
    unzip oapilot.zip
    mv "${REPO_NAME}-${BRANCH}" oapilot
    rm oapilot.zip
fi

cd oapilot

# Make scripts executable
chmod +x scripts/*.sh *.sh 2>/dev/null || true

print_success "OAPilot downloaded successfully!"

# Run the installer
print_status "Starting installation..."
if [ -f "install.sh" ]; then
    ./install.sh
elif [ -f "scripts/setup.sh" ]; then
    ./scripts/setup.sh
else
    print_error "Installation script not found!"
    exit 1
fi

print_success "🎉 OAPilot installation completed!"
echo ""
echo "🚀 Quick start:"
echo "   cd oapilot"
echo "   ./quick-start.sh"
echo ""
echo "📖 Manual start:"
echo "   cd oapilot"
echo "   ollama pull phi3:mini"
echo "   ./scripts/start.sh"
echo ""
echo "🌐 Access: http://localhost:8080"
EOF

chmod +x oapilot-installer.sh

# Create GitHub README for the installer
cat > GITHUB_README.md << 'EOF'
# OAPilot - Offline AI Pilot System

🤖 **Fully offline AI assistant** with local LLM and MCP server integration, optimized for resource-constrained environments (8GB RAM).

## ⚡ Quick Install (Ubuntu/WSL2)

### One-Line Installation
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/oapilot-installer.sh | bash
```

### Alternative: Manual Clone
```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git oapilot
cd oapilot
./install.sh
./quick-start.sh
```

## 🎯 Features

- ✅ **100% Offline** - No cloud dependencies after setup
- ✅ **Resource Optimized** - Runs on 8GB RAM with <100GB storage
- ✅ **Local LLM** - Uses Ollama with quantized models (Phi-3, Gemma, Qwen)
- ✅ **MCP Integration** - Auto-discovers and connects to MCP servers
- ✅ **Persistent Chat** - SQLite-backed conversation history
- ✅ **Artifact Management** - Saves generated code, documents, diagrams
- ✅ **Web Interface** - React-based UI accessible from Windows browser
- ✅ **Air-Gapped Ready** - Perfect for secure environments

## 🖥️ System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **RAM** | 8GB (4GB+ available) | 16GB |
| **Storage** | 15GB free | 50GB+ SSD |
| **OS** | Ubuntu 18.04+ / WSL2 | Ubuntu 22.04+ |
| **CPU** | 4 cores | 8+ cores |

## 🚀 Usage

After installation:

```bash
# Start OAPilot
./scripts/start.sh

# Access web interface
# Open: http://localhost:8080

# Stop OAPilot
./scripts/stop.sh

# Monitor system resources
./scripts/monitor.sh
```

## 🔧 Configuration

Edit `backend/.env` to customize:

```env
# LLM Model (choose based on available RAM)
LLM_MODEL=phi3:mini          # 2GB RAM - Best balance
LLM_MODEL=gemma:2b           # 1.5GB RAM - Fastest
LLM_MODEL=qwen2:1.5b         # 1GB RAM - Minimal memory
LLM_MODEL=mistral:7b-q4      # 3.8GB RAM - Best quality

# Resource Limits
MAX_MEMORY_MB=512
MAX_DB_SIZE_MB=1024
MAX_ARTIFACTS_SIZE_GB=5

# Web Interface
HOST=0.0.0.0
PORT=8080
```

## 🛠️ MCP Server Setup

OAPilot auto-discovers MCP servers running in Docker:

```bash
cd docker
# Edit docker-compose.yml with your MCP servers
docker-compose up -d
```

## 📊 Resource Usage

| State | RAM Usage | Storage |
|-------|-----------|---------|
| Idle | ~1.5GB | ~500MB |
| Active | ~4-5GB | ~10-15GB |
| Peak | ~6GB | ~20GB |

## 🔍 Troubleshooting

### Common Issues

1. **Out of Memory**
   ```bash
   # Use smaller model
   ollama pull qwen2:1.5b
   # Edit backend/.env: LLM_MODEL=qwen2:1.5b
   ```

2. **Port Already in Use**
   ```bash
   # Check what's using port 8080
   sudo lsof -i :8080
   # Or change port in backend/.env
   ```

3. **Backend Won't Start**
   ```bash
   # Check logs
   tail -f logs/backend.log
   # Restart services
   ./scripts/stop.sh && ./scripts/start.sh
   ```

### Performance Optimization

```bash
# Monitor resources
curl http://localhost:8080/api/v1/resources

# Clean up storage
curl -X POST http://localhost:8080/api/v1/storage/cleanup

# Switch to faster model
ollama pull gemma:2b
# Edit backend/.env: LLM_MODEL=gemma:2b
```

## 📚 Documentation

- [Setup Guide](docs/SETUP.md) - Detailed installation instructions
- [API Reference](http://localhost:8080/docs) - API documentation (when running)
- [Architecture](docs/ARCHITECTURE.md) - System design overview

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔒 Security

OAPilot is designed for air-gapped environments:
- All data stays local
- No telemetry or external calls
- Secure by default configuration
- Perfect for regulated industries

---

**Made with ❤️ for secure, offline AI assistance**
EOF

# Create deployment instructions
cat > DEPLOYMENT_INSTRUCTIONS.md << 'EOF'
# OAPilot GitHub Deployment Instructions

## 1. Repository Setup

### Create GitHub Repository
1. Create a new repository on GitHub (e.g., `oapilot`)
2. Clone this release folder to your repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/oapilot.git
   cd oapilot
   ```

### Upload OAPilot Files
1. Copy all files from the `oapilot` folder to your repository root
2. Copy `oapilot-installer.sh` to the repository root
3. Update the installer script with your repository details

## 2. Update Repository URLs

### In `oapilot-installer.sh`:
```bash
REPO_URL="https://github.com/YOUR_USERNAME/YOUR_REPO"
REPO_NAME="YOUR_REPO"
```

### In `GITHUB_README.md`:
Replace all instances of:
- `YOUR_USERNAME` with your GitHub username
- `YOUR_REPO` with your repository name

## 3. Repository Structure
```
your-repo/
├── backend/
├── frontend/
├── scripts/
├── docs/
├── docker/
├── oapilot-installer.sh    # One-line installer
├── install.sh              # Full installer
├── quick-start.sh           # Quick start script
├── README.md                # GitHub README
└── LICENSE                  # License file
```

## 4. Create GitHub Release

### Option 1: Using GitHub Web Interface
1. Go to your repository on GitHub
2. Click "Releases" → "Create a new release"
3. Tag version: `v1.0.0`
4. Release title: `OAPilot v1.0.0 - Offline AI Pilot System`
5. Upload the tar.gz package as release asset

### Option 2: Using GitHub CLI
```bash
gh release create v1.0.0 \
  --title "OAPilot v1.0.0 - Offline AI Pilot System" \
  --notes "Initial release of OAPilot offline AI system"
```

## 5. User Installation Commands

### One-Line Install (Recommended)
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/oapilot-installer.sh | bash
```

### Manual Install
```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git oapilot
cd oapilot
./install.sh
./quick-start.sh
```

### Download Release Package
```bash
wget https://github.com/YOUR_USERNAME/YOUR_REPO/releases/download/v1.0.0/oapilot-v1.0.0-linux.tar.gz
tar -xzf oapilot-v1.0.0-linux.tar.gz
cd oapilot-v1.0.0
./install.sh
```

## 6. Repository Configuration

### Enable GitHub Pages (Optional)
For documentation hosting:
1. Go to repository Settings
2. Pages → Source: Deploy from branch
3. Branch: main, folder: /docs

### Branch Protection (Recommended)
1. Settings → Branches
2. Add rule for `main` branch
3. Enable "Require pull request reviews"

## 7. Testing

Test the installation on a fresh Ubuntu/WSL2 system:
```bash
# Test one-liner
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/oapilot-installer.sh | bash

# Test manual
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git test-oapilot
cd test-oapilot
./install.sh
```

## 8. Documentation Updates

Update the following files with your repository information:
- `README.md` - Main repository readme
- `docs/SETUP.md` - Installation guide
- `oapilot-installer.sh` - One-line installer
- Any other documentation referring to repository URLs

## 9. Marketing Your Release

### README Badges (Optional)
Add to your README.md:
```markdown
![License](https://img.shields.io/github/license/YOUR_USERNAME/YOUR_REPO)
![Release](https://img.shields.io/github/v/release/YOUR_USERNAME/YOUR_REPO)
![Downloads](https://img.shields.io/github/downloads/YOUR_USERNAME/YOUR_REPO/total)
```

### Share Commands
Provide users with these simple commands:
```bash
# Quick install
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/oapilot-installer.sh | bash

# Or clone and install
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git oapilot && cd oapilot && ./install.sh
```
EOF

cd ..

print_success "🐙 GitHub release package created!"
echo ""
echo "📁 Release structure:"
echo "   release/oapilot/              - Complete source code"
echo "   release/oapilot-installer.sh  - One-line installer"
echo "   release/GITHUB_README.md      - Repository README"
echo "   release/DEPLOYMENT_INSTRUCTIONS.md - Setup guide"
echo ""
echo "🚀 Next steps:"
echo "1. Create GitHub repository"
echo "2. Upload release/oapilot/ contents to repository root"
echo "3. Update URLs in oapilot-installer.sh and README"
echo "4. Users can install with:"
echo "   curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/oapilot-installer.sh | bash"
echo ""
echo "📝 See DEPLOYMENT_INSTRUCTIONS.md for detailed setup"