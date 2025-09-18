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
