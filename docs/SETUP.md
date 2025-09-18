# OAPilot Setup Guide

## System Requirements

### Minimum Requirements
- **RAM**: 8GB (4GB+ available)
- **Storage**: 20GB free space
- **OS**: Ubuntu 18.04+ / WSL2 on Windows
- **Python**: 3.8+
- **Node.js**: 16+

### Recommended Requirements
- **RAM**: 16GB
- **Storage**: 50GB+ SSD
- **CPU**: 4+ cores
- **GPU**: Optional (for faster inference)

## Quick Setup

1. **Clone or extract OAPilot to your desired directory**

2. **Run the setup script**
   ```bash
   cd oapilot
   ./scripts/setup.sh
   ```

3. **Start OAPilot**
   ```bash
   ./scripts/start.sh
   ```

4. **Access the web interface**
   - Open: http://localhost:8080
   - From Windows browser (WSL2): Same URL

## Manual Setup

If the automated setup fails, follow these steps:

### 1. Backend Setup

```bash
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Create configuration
cp .env.example .env

# Generate secret key
python3 -c "import secrets; print(secrets.token_hex(32))" >> .env

# Initialize database
python3 -c "from app.core.database import init_db; init_db()"
```

### 2. Frontend Setup

```bash
cd frontend

# Install dependencies
npm install

# Build for production
npm run build
```

### 3. Ollama Setup

```bash
# Install Ollama
curl -fsSL https://ollama.ai/install.sh | sh

# Start service
ollama serve &

# Pull recommended model
ollama pull phi3:mini
```

## Configuration

### Environment Variables

Edit `backend/.env`:

```env
# Server
HOST=0.0.0.0
PORT=8080

# LLM Model
LLM_MODEL=phi3:mini
LLM_CONTEXT_SIZE=2048
LLM_MAX_TOKENS=512

# Resource Limits
MAX_MEMORY_MB=512
MAX_DB_SIZE_MB=1024
MAX_ARTIFACTS_SIZE_GB=5

# MCP Settings
MAX_MCP_CONNECTIONS=3
MCP_AUTO_DISCOVER=true
```

### Model Selection

Available lightweight models:

| Model | Size | Memory | Speed | Quality |
|-------|------|--------|-------|---------|
| `qwen2:1.5b` | 1GB | Low | Fastest | Good |
| `gemma:2b` | 1.5GB | Low | Fast | Good |
| `phi3:mini` | 2GB | Medium | Medium | Better |
| `mistral:7b-q4` | 3.8GB | High | Slow | Best |

Switch models:
```bash
ollama pull <model-name>
# Update LLM_MODEL in .env
```

## MCP Server Setup

### 1. Create MCP Servers

Example filesystem MCP server:

```bash
mkdir -p docker/mcp-filesystem
cd docker/mcp-filesystem

# Create package.json
cat > package.json << 'EOF'
{
  "name": "mcp-filesystem",
  "version": "1.0.0",
  "type": "module",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.18.0"
  }
}
EOF

# Create simple MCP server
cat > index.js << 'EOF'
import express from 'express';
import fs from 'fs';
import path from 'path';

const app = express();
app.use(express.json());

let requestId = 1;

// MCP JSON-RPC handler
app.post('/', (req, res) => {
  const { method, params, id } = req.body;
  
  switch (method) {
    case 'initialize':
      res.json({
        id: id || requestId++,
        result: {
          capabilities: {
            resources: { list: true, read: true },
            tools: { list: true, call: true }
          }
        }
      });
      break;
      
    case 'resources/list':
      res.json({
        id: id || requestId++,
        result: {
          resources: [
            { name: 'files', description: 'Local filesystem access' }
          ]
        }
      });
      break;
      
    default:
      res.json({
        id: id || requestId++,
        error: { code: -32601, message: 'Method not found' }
      });
  }
});

app.listen(8000, () => {
  console.log('MCP Filesystem server running on port 8000');
});
EOF

npm install
```

### 2. Start MCP Servers

```bash
cd docker
docker-compose up -d
```

### 3. Verify MCP Connection

Check OAPilot web interface at http://localhost:8080/servers

## Troubleshooting

### Common Issues

1. **Out of Memory**
   - Close other applications
   - Use smaller model (`qwen2:1.5b`)
   - Reduce batch size in config

2. **Slow Performance**
   - Check CPU usage
   - Use faster model (`gemma:2b`)
   - Increase available RAM

3. **Backend Won't Start**
   - Check logs: `tail -f logs/backend.log`
   - Verify port 8080 is free
   - Check Python dependencies

4. **Frontend Not Loading**
   - Ensure backend is running
   - Check CORS settings
   - Rebuild frontend: `cd frontend && npm run build`

5. **Ollama Connection Error**
   - Start Ollama: `ollama serve`
   - Check port 11434 is accessible
   - Verify model is pulled: `ollama list`

### Resource Monitoring

Check system resources:
```bash
# Memory usage
free -h

# Disk usage
df -h

# Process monitoring
htop

# OAPilot specific
curl http://localhost:8080/api/v1/resources
```

### Performance Tuning

1. **Memory Optimization**
   - Set `LLM_USE_MMAP=true`
   - Reduce `LLM_CONTEXT_SIZE`
   - Enable automatic cleanup

2. **Storage Optimization**
   - Regular cleanup: `curl -X POST http://localhost:8080/api/v1/storage/cleanup`
   - Reduce retention days
   - Monitor artifact sizes

3. **Network Optimization**
   - Use local MCP servers
   - Reduce MCP timeout
   - Limit concurrent connections

## Logs and Debugging

### Log Locations
- Backend: `logs/backend.log`
- Ollama: `logs/ollama.log`
- Setup: Terminal output

### Debug Mode
Enable debug logging in `.env`:
```env
DEBUG=true
```

### Health Checks
- System: http://localhost:8080/api/v1/health
- Resources: http://localhost:8080/api/v1/resources
- MCP: http://localhost:8080/api/v1/mcp/health

## Updates and Maintenance

### Regular Maintenance
- Clean up old sessions: Monthly
- Update models: As needed
- Monitor storage usage: Weekly
- Check MCP server health: Daily

### Backup Important Data
- Database: `backend/storage/database/oapilot.db`
- Artifacts: `backend/storage/artifacts/`
- Configuration: `backend/.env`

### Model Management
```bash
# List installed models
ollama list

# Remove unused models
ollama rm <model-name>

# Update model
ollama pull <model-name>
```