#!/bin/bash

# OAPilot Setup Script
# This script sets up the complete OAPilot environment

set -e  # Exit on any error

echo "🚀 Setting up OAPilot - Offline AI Pilot System"
echo "================================================"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check system requirements
print_status "Checking system requirements..."

# Check available memory
available_mem=$(free -m | awk 'NR==2{print $7}')
if [ "$available_mem" -lt 4096 ]; then
    print_warning "Available memory: ${available_mem}MB (Recommended: 4GB+)"
else
    print_success "Available memory: ${available_mem}MB"
fi

# Check disk space
available_disk=$(df -BG . | awk 'NR==2{print int($4)}')
if [ "$available_disk" -lt 20 ]; then
    print_warning "Available disk space: ${available_disk}GB (Recommended: 20GB+)"
else
    print_success "Available disk space: ${available_disk}GB"
fi

# Check if Python 3.8+ is available
python_version=$(python3 --version 2>&1 | awk '{print $2}' | cut -d. -f1,2)
required_version="3.8"
if [ "$(printf '%s\n' "$required_version" "$python_version" | sort -V | head -n1)" = "$required_version" ]; then
    print_success "Python version: $python_version"
else
    print_error "Python 3.8+ required. Found: $python_version"
    exit 1
fi

# Check if Node.js is available
if command -v node &> /dev/null; then
    node_version=$(node --version)
    print_success "Node.js version: $node_version"
else
    print_error "Node.js not found. Please install Node.js 16+"
    exit 1
fi

# Create directory structure
print_status "Creating directory structure..."
mkdir -p backend/storage/{database,artifacts/{code,documents,diagrams,exports},sessions}
mkdir -p logs
print_success "Directory structure created"

# Set up Python backend
print_status "Setting up Python backend..."
cd backend

# Create virtual environment
if [ ! -d "venv" ]; then
    print_status "Creating Python virtual environment..."
    python3 -m venv venv
    print_success "Virtual environment created"
fi

# Activate virtual environment
source venv/bin/activate
print_status "Activated virtual environment"

# Upgrade pip
pip install --upgrade pip

# Install Python dependencies
print_status "Installing Python dependencies..."
pip install -r requirements.txt
print_success "Python dependencies installed"

# Create .env file if it doesn't exist
if [ ! -f ".env" ]; then
    print_status "Creating .env configuration file..."
    cp .env.example .env
    
    # Generate a secret key
    secret_key=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    sed -i "s/your-secret-key-here/$secret_key/" .env
    
    print_success ".env file created with generated secret key"
else
    print_status ".env file already exists"
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
print_status "Setting up React frontend..."
cd frontend

# Install Node.js dependencies
print_status "Installing Node.js dependencies..."
npm install
print_success "Node.js dependencies installed"

# Create TailwindCSS config
if [ ! -f "tailwind.config.js" ]; then
    print_status "Creating TailwindCSS configuration..."
    cat > tailwind.config.js << 'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
EOF
    print_success "TailwindCSS configuration created"
fi

# Create PostCSS config
if [ ! -f "postcss.config.js" ]; then
    print_status "Creating PostCSS configuration..."
    cat > postcss.config.js << 'EOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF
    print_success "PostCSS configuration created"
fi

# Build frontend for production
print_status "Building frontend for production..."
npm run build
print_success "Frontend built successfully"

cd ..

# Set up Ollama
print_status "Setting up Ollama..."

if ! command -v ollama &> /dev/null; then
    print_status "Installing Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
    print_success "Ollama installed"
else
    print_success "Ollama already installed"
fi

# Start Ollama service if not running
if ! pgrep -x "ollama" > /dev/null; then
    print_status "Starting Ollama service..."
    ollama serve &
    sleep 5
    print_success "Ollama service started"
fi

# Pull recommended model
print_status "Pulling recommended LLM model (phi3:mini)..."
if ollama list | grep -q "phi3:mini"; then
    print_success "phi3:mini model already available"
else
    print_status "Downloading phi3:mini model (this may take a few minutes)..."
    ollama pull phi3:mini
    print_success "phi3:mini model downloaded"
fi

# Create sample MCP docker-compose
print_status "Creating sample MCP server configuration..."
cd docker

if [ ! -f "docker-compose.yml" ]; then
    cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  mcp-filesystem:
    image: node:18-alpine
    container_name: mcp-filesystem
    labels:
      - "mcp-server=true"
      - "mcp-port=8000"
    ports:
      - "8001:8000"
    working_dir: /app
    volumes:
      - ./mcp-filesystem:/app
    command: ["npm", "start"]
    restart: unless-stopped

  mcp-database:
    image: node:18-alpine
    container_name: mcp-database
    labels:
      - "mcp-server=true"
      - "mcp-port=8000"
    ports:
      - "8002:8000"
    working_dir: /app
    volumes:
      - ./mcp-database:/app
    command: ["npm", "start"]
    restart: unless-stopped
EOF
    print_success "Sample MCP docker-compose.yml created"
else
    print_status "MCP docker-compose.yml already exists"
fi

cd ..

# Create startup script
print_status "Creating startup script..."
cat > scripts/start.sh << 'EOF'
#!/bin/bash

# OAPilot Startup Script

echo "🚀 Starting OAPilot services..."

# Check system resources
echo "🔍 Checking system resources..."
available_mem=$(free -m | awk 'NR==2{print $7}')
available_disk=$(df -BG . | awk 'NR==2{print int($4)}')

echo "   Available Memory: ${available_mem}MB"
echo "   Available Disk: ${available_disk}GB"

if [ "$available_mem" -lt 2048 ]; then
    echo "⚠️  Warning: Less than 2GB RAM available"
    echo "   Consider closing other applications"
fi

# Start Ollama if not running
if ! pgrep -x "ollama" > /dev/null; then
    echo "📦 Starting Ollama..."
    export OLLAMA_MAX_LOADED_MODELS=1
    export OLLAMA_NUM_PARALLEL=1
    export OLLAMA_KEEP_ALIVE=5m
    ollama serve &
    sleep 3
fi

# Start backend
echo "🔧 Starting OAPilot backend..."
cd backend
source venv/bin/activate

# Set Python optimizations
export PYTHONOPTIMIZE=1
export PYTHONUNBUFFERED=1

# Start backend server
python3 -O app/main.py &
BACKEND_PID=$!

cd ..

# Wait for backend to be ready
echo "⏳ Waiting for backend to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "✅ Backend is ready!"
        break
    fi
    sleep 1
done

echo ""
echo "🎉 OAPilot is running!"
echo ""
echo "   🌐 Web Interface: http://localhost:8080"
echo "   📊 API Documentation: http://localhost:8080/docs"
echo "   ❤️  Health Check: http://localhost:8080/health"
echo ""
echo "   Memory usage will be monitored automatically"
echo "   Press Ctrl+C to stop all services"
echo ""

# Wait for user to stop
trap 'echo ""; echo "🛑 Stopping OAPilot..."; kill $BACKEND_PID 2>/dev/null; pkill ollama 2>/dev/null; exit 0' INT

wait $BACKEND_PID
EOF

chmod +x scripts/start.sh
print_success "Startup script created"

# Create stop script
print_status "Creating stop script..."
cat > scripts/stop.sh << 'EOF'
#!/bin/bash

echo "🛑 Stopping OAPilot services..."

# Stop backend
pkill -f "python.*main.py" 2>/dev/null

# Stop Ollama
pkill ollama 2>/dev/null

echo "✅ All services stopped"
EOF

chmod +x scripts/stop.sh
print_success "Stop script created"

# Final setup completion
print_success "🎉 OAPilot setup completed successfully!"
echo ""
echo "Next steps:"
echo "  1. Start OAPilot:    ./scripts/start.sh"
echo "  2. Open browser:     http://localhost:8080"
echo "  3. Start chatting with your AI pilot!"
echo ""
echo "Optional:"
echo "  - Configure MCP servers in docker/docker-compose.yml"
echo "  - Adjust settings in backend/.env"
echo "  - View logs in oapilot.log"
echo ""
print_status "Setup completed in $(pwd)"
EOF

chmod +x scripts/setup.sh
print_success "Setup script created and made executable"