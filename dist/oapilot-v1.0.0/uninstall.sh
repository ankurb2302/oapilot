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
