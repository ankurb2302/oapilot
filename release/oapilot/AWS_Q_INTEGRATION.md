# OAPilot AWS Q MCP Integration Guide

## Overview

This document describes the integration between OAPilot and AWS Q's Model Context Protocol (MCP) configuration system. The integration allows OAPilot to work seamlessly with AWS Q CLI, replacing the Docker-based MCP server discovery with AWS Q's native configuration format.

## Architecture Changes

### Original Architecture (Docker-based)
- MCP servers run as Docker containers
- Auto-discovery via Docker API
- Container labels for MCP identification
- HTTP communication to container endpoints

### New Architecture (AWS Q Compatible)
- MCP servers defined in JSON configuration files
- Support for both STDIO (local process) and HTTP transports
- STDIO-to-HTTP bridge for process-based servers
- Compatible with AWS Q CLI agent system

## Key Components

### 1. AWS Q MCP Adapter (`awsq_mcp_adapter.py`)
- **AWSQConfigLoader**: Loads and parses AWS Q configuration files
- **STDIOBridge**: Creates HTTP endpoints for STDIO-based MCP servers
- **AWSQMCPManager**: Extended MCP manager with AWS Q support

### 2. Configuration Files
AWS Q configurations are stored in:
- **Global**: `~/.aws/amazonq/cli-agents/*.json` or `~/.aws/amazonq/agents/*.json`
- **Project**: `.amazonq/cli-agents/*.json` or `.amazonq/agents/*.json`

### 3. API Endpoints
New endpoints under `/api/v1/awsq-mcp/`:
- `GET /configurations` - List all AWS Q configurations
- `POST /load` - Load MCP servers from AWS Q configs
- `GET /servers` - List loaded servers and status
- `POST /migrate-from-docker` - Migrate Docker configs to AWS Q format

## Installation & Setup

### Prerequisites
1. **Node.js & npm** - Required for MCP server binaries
2. **Python 3.8+** - Backend runtime
3. **Ollama** - Local LLM support

### Quick Setup

1. **Install MCP Server Binaries**
```bash
# Install common MCP servers globally
npm install -g @modelcontextprotocol/server-filesystem
npm install -g @modelcontextprotocol/server-git
npm install -g @modelcontextprotocol/server-fetch
npm install -g @modelcontextprotocol/server-sqlite
```

2. **Create AWS Q Configuration**
Create `.amazonq/cli-agents/oapilot.json`:
```json
{
  "name": "oapilot",
  "description": "OAPilot with MCP servers",
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"],
      "timeout": 30000
    },
    "git": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-git"],
      "timeout": 30000
    }
  }
}
```

3. **Start OAPilot with AWS Q Support**
```bash
cd /path/to/oapilot
./scripts/start-awsq.sh
```

## Configuration Examples

### STDIO-based MCP Server
```json
{
  "mcpServers": {
    "my-stdio-server": {
      "command": "my-mcp-server",
      "args": ["--port", "8080"],
      "env": {
        "API_KEY": "${API_KEY}"
      },
      "timeout": 30000
    }
  }
}
```

### HTTP-based MCP Server
```json
{
  "mcpServers": {
    "remote-server": {
      "type": "http",
      "url": "https://api.example.com/mcp",
      "headers": {
        "Authorization": "Bearer ${TOKEN}"
      }
    }
  }
}
```

## Migration from Docker-Compose

### Automatic Migration
Use the migration endpoint to analyze Docker containers and generate AWS Q config:
```bash
curl -X POST http://localhost:8080/api/v1/awsq-mcp/migrate-from-docker
```

This will:
1. Scan running Docker containers for MCP servers
2. Generate AWS Q configuration in `.amazonq/cli-agents/migrated.json`
3. Provide migration instructions

### Manual Migration

**Docker-Compose Entry:**
```yaml
services:
  mcp-filesystem:
    image: mcp/filesystem:latest
    ports:
      - "8081:8080"
    environment:
      WORKSPACE: /data
```

**Becomes AWS Q Config:**
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "mcp-filesystem-binary",
      "args": ["--workspace", "/data"],
      "env": {
        "PORT": "8080"
      }
    }
  }
}
```

## How It Works

### 1. Configuration Discovery
```python
# The system automatically discovers AWS Q configurations
config_files = AWSQConfigLoader.find_config_files()
# Checks: ~/.aws/amazonq/*, .amazonq/*
```

### 2. STDIO Bridge Creation
For STDIO-based servers, a bridge is created:
```python
# Original STDIO server process
server_process = subprocess(command, stdin=PIPE, stdout=PIPE)

# Bridge creates HTTP endpoint
http_bridge = STDIOBridge(server_config)
endpoint = await http_bridge.start()  # Returns: http://localhost:PORT
```

### 3. Unified MCP Manager
```python
# Automatically detects AWS Q configuration
if aws_q_config_exists:
    manager = AWSQMCPManager()
    await manager.load_awsq_configurations()
else:
    # Fallback to Docker-based discovery
    manager = MCPManager()
```

## AWS Q CLI Integration

### Using with AWS Q CLI
```bash
# Start AWS Q chat with OAPilot agent
q chat --agent oapilot

# Within chat session
/mcp  # List available MCP servers
/mcp status  # Check server status
```

### Tool Access in AWS Q
```
# Use tools from MCP servers
@filesystem/read_file path="/workspace/file.txt"
@git/git_status
@fetch/fetch_url url="https://example.com"
```

## Troubleshooting

### Common Issues

1. **MCP Server Not Found**
   - Ensure server binary is in PATH
   - Check command in configuration is correct
   - Verify npm global packages are installed

2. **STDIO Bridge Timeout**
   - Increase timeout in configuration
   - Check server process is responding
   - Review server logs for errors

3. **AWS Q Configuration Not Detected**
   - Verify file location (`.amazonq/` or `~/.aws/amazonq/`)
   - Check JSON syntax is valid
   - Ensure file has `.json` extension

### Debugging

1. **Enable Debug Logging**
```bash
export DEBUG=true
./scripts/start-awsq.sh
```

2. **Check Bridge Status**
```bash
curl http://localhost:8080/api/v1/awsq-mcp/servers
```

3. **View Server Logs**
```bash
# Backend logs
tail -f oapilot.log

# STDIO bridge output
curl http://localhost:8080/api/v1/awsq-mcp/servers/{name}/logs
```

## API Reference

### Load AWS Q Configurations
```http
POST /api/v1/awsq-mcp/load
Content-Type: application/json

{
  "project_root": "/path/to/project"  // Optional
}
```

### List Configured Servers
```http
GET /api/v1/awsq-mcp/servers

Response:
{
  "success": true,
  "servers": {
    "filesystem": {
      "transport": "stdio",
      "command": "npx",
      "connected": true,
      "has_bridge": true
    }
  }
}
```

### Health Check
```http
GET /api/v1/awsq-mcp/health-check

Response:
{
  "success": true,
  "servers": {
    "filesystem": true,
    "git": true
  },
  "healthy": 2,
  "total": 2
}
```

## Benefits of AWS Q Integration

1. **Simplified Deployment**: No Docker required on target systems
2. **Native AWS Q Support**: Works seamlessly with AWS Q CLI
3. **Flexible Transport**: Support for both local processes and remote HTTP servers
4. **Better Resource Management**: Direct process control without container overhead
5. **Configuration Portability**: JSON configs easily shareable across teams

## Future Enhancements

- [ ] OAuth authentication for remote MCP servers
- [ ] Dynamic server reload without restart
- [ ] Configuration validation and linting
- [ ] GUI configuration editor
- [ ] Automatic MCP server binary installation
- [ ] Performance monitoring and metrics

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review logs in `oapilot.log`
3. Test individual MCP servers with AWS Q CLI
4. File issues with configuration examples