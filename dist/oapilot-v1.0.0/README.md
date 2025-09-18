# OAPilot - Standalone AI Assistant

A completely offline, locally-running AI assistant that uses **AWS Q's MCP configuration format** without requiring AWS Q to be installed. OAPilot acts as a standalone replacement for AWS Q while maintaining full compatibility with existing MCP server configurations.

## Features

- 🚀 **100% Offline Operation** - No cloud dependencies after installation
- 💾 **Resource Optimized** - Runs on 8GB RAM with <20GB storage
- 🔌 **AWS Q MCP Compatible** - Uses standard MCP configuration format
- 🧠 **Local LLM** - Uses Ollama with optimized models (Phi-3, Gemma, Qwen)
- 💬 **Persistent Chat** - SQLite-backed conversation history
- 📦 **Artifact Management** - Saves and manages generated code, documents, diagrams
- 🌐 **Web Interface** - React-based UI accessible from any browser
- 🔍 **Resource Monitoring** - Automatic memory and storage management
- ⚡ **One-Line Install** - Simple curl command installation

## Key Difference from AWS Q

**OAPilot is a standalone application** that:
- ✅ Reads and uses AWS Q's MCP configuration format (`.amazonq/cli-agents/*.json`)
- ✅ Works without AWS Q installed
- ✅ Provides the same MCP server functionality
- ✅ Compatible with existing AWS Q MCP configurations
- ❌ Does NOT require AWS Q CLI or AWS account

## System Requirements

- **RAM**: 8GB minimum (4GB available)
- **Storage**: 15GB free space
- **OS**: Ubuntu 18.04+, WSL2, or compatible Linux
- **Internet**: Required for initial setup only

## One-Line Installation

```bash
curl -fsSL https://your-domain.com/install-oapilot.sh | bash
```

After installation:
```bash
oapilot  # Start the application
```

## Manual Installation

### 1. Download and Extract
```bash
wget https://github.com/your-repo/oapilot/releases/latest/download/oapilot-v1.0.0-linux.tar.gz
tar -xzf oapilot-v1.0.0-linux.tar.gz
cd oapilot-v1.0.0
```

### 2. Install Dependencies
```bash
./install.sh
```

### 3. Quick Start
```bash
./quick-start.sh
```

### 4. Access Interface
Open browser: http://localhost:8080

## MCP Configuration

OAPilot uses **the same configuration format as AWS Q** for maximum compatibility.

### Configuration Locations

- **Global**: `~/.aws/amazonq/cli-agents/*.json`
- **Project**: `.amazonq/cli-agents/*.json` (recommended)

### Example Configuration

Create `.amazonq/cli-agents/default.json`:

```json
{
  "name": "my-ai-assistant",
  "description": "AI assistant with file and database access",
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "./workspace"],
      "timeout": 30000
    },
    "sqlite": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sqlite", "--db-path", "./data.db"],
      "timeout": 30000
    },
    "git": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-git"],
      "timeout": 30000
    },
    "remote-api": {
      "type": "http",
      "url": "https://api.example.com/mcp"
    }
  },
  "tools": [
    "@filesystem",
    "@sqlite",
    "@git",
    "@remote-api"
  ]
}
```

## Architecture

```
OAPilot (Standalone)
├── Backend (FastAPI + SQLite)
│   ├── LLM Manager (Ollama)
│   ├── MCP Configuration Reader
│   ├── STDIO-to-HTTP Bridge
│   └── Storage Manager
├── Frontend (React)
│   ├── Chat Interface
│   └── Artifact Viewer
└── MCP Servers
    ├── Local Process (STDIO)
    └── Remote HTTP
```

## Usage Examples

### Basic Chat
```
You: Help me analyze the files in my project
OAPilot: I'll use the filesystem MCP server to explore your project...
```

### With MCP Tools
```
You: Show me recent git commits
OAPilot: [Uses @git/git_log tool to show commit history]

You: Create a summary of all Python files
OAPilot: [Uses @filesystem to read files and create summary]
```

## Memory Usage

| Component | Idle | Active | Peak |
|-----------|------|--------|------|
| Backend | 200MB | 400MB | 600MB |
| Frontend | 100MB | 150MB | 200MB |
| LLM Model | - | 2-3GB | 4GB |
| MCP Servers | 50MB | 100MB | 150MB |
| **Total** | 350MB | 2.6-3.6GB | 4.9GB |

## Supported Models

Recommended models for 8GB RAM:
- **phi3:mini** (2GB) - Best balance of speed and quality
- **gemma:2b** (1.5GB) - Fastest responses
- **qwen2:1.5b** (1GB) - Minimal memory usage

## Commands

### Start/Stop
```bash
# Start OAPilot
oapilot
# OR
./scripts/start.sh

# Stop OAPilot
./scripts/stop.sh
```

### Management
```bash
# Check status
curl http://localhost:8080/health

# List MCP servers
curl http://localhost:8080/api/v1/awsq-mcp/servers

# View logs
tail -f logs/backend.log
```

## API Endpoints

- **Web UI**: http://localhost:8080
- **API Docs**: http://localhost:8080/docs
- **Health**: http://localhost:8080/health
- **MCP Status**: http://localhost:8080/api/v1/awsq-mcp/servers

## Migrating from AWS Q

If you have existing AWS Q MCP configurations:

1. **Copy configurations** to OAPilot:
   ```bash
   cp -r ~/.aws/amazonq .amazonq
   ```

2. **Install MCP server binaries**:
   ```bash
   npm install -g @modelcontextprotocol/server-filesystem
   npm install -g @modelcontextprotocol/server-git
   npm install -g @modelcontextprotocol/server-sqlite
   ```

3. **Start OAPilot** - it will automatically load your configurations

## Troubleshooting

### Common Issues

1. **Port 8080 in use**
   ```bash
   # Check what's using the port
   lsof -i :8080
   # Or change port in backend/.env
   echo "PORT=8081" >> backend/.env
   ```

2. **Out of memory**
   ```bash
   # Use smaller model
   ollama pull qwen2:1.5b
   # Update config
   echo "LLM_MODEL=qwen2:1.5b" >> backend/.env
   ```

3. **MCP server not found**
   ```bash
   # Install MCP servers globally
   npm install -g @modelcontextprotocol/server-filesystem
   # Or use absolute paths in configuration
   ```

### Debug Mode
```bash
export DEBUG=true
./scripts/start.sh
```

## Development

### Local Development
```bash
# Backend
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python app/main.py

# Frontend
cd frontend
npm install
npm run dev
```

### Adding MCP Servers

1. Create configuration in `.amazonq/cli-agents/`
2. Install server binary: `npm install -g your-mcp-server`
3. Restart OAPilot

## Uninstalling

```bash
# If installed via curl installer
rm -rf ~/oapilot
rm ~/.local/bin/oapilot

# If manually installed
rm -rf /path/to/oapilot
```

## Support

- **Documentation**: See `docs/` directory
- **Logs**: `logs/backend.log`
- **Health Check**: http://localhost:8080/health
- **MCP Status**: http://localhost:8080/api/v1/awsq-mcp/servers

## What Makes OAPilot Different

| Feature | AWS Q | OAPilot |
|---------|--------|---------|
| Installation | Requires AWS account & CLI | One curl command |
| Dependencies | AWS services | Only local dependencies |
| Internet | Required for operation | Only for initial setup |
| Cost | Per-usage billing | Completely free |
| Privacy | Data sent to AWS | 100% local processing |
| MCP Config | AWS Q format | Same format (compatible) |

## License

MIT License - Free for personal and commercial use.

---

**OAPilot**: The offline AI assistant that speaks AWS Q's language but runs independently.