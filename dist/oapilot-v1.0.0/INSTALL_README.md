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
