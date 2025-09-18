#!/bin/bash

# OAPilot System Monitor Script

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

print_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                     ${MAGENTA}OAPilot System Monitor${NC}                     ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_section() {
    echo -e "${BLUE}┌─ $1${NC}"
}

print_status() {
    echo -e "${GREEN}├─${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}├─${NC} $1"
}

print_error() {
    echo -e "${RED}├─${NC} $1"
}

check_service_status() {
    local service_name=$1
    local port=$2
    local process_name=$3

    print_section "$service_name Status"

    # Check if process is running
    if pgrep -f "$process_name" > /dev/null; then
        PID=$(pgrep -f "$process_name")
        print_status "✅ Process running (PID: $PID)"

        # Check if port is responding
        if [ ! -z "$port" ]; then
            if curl -s "http://localhost:$port" > /dev/null 2>&1; then
                print_status "✅ Service responding on port $port"
            else
                print_warning "⚠️  Process running but not responding on port $port"
            fi
        fi
    else
        print_error "❌ Process not running"
    fi
    echo ""
}

check_system_resources() {
    print_section "System Resources"

    # Memory usage
    memory_info=$(free -h | awk 'NR==2{printf "Used: %s/%s (%.0f%%)", $3,$2,$3*100/$2}')
    print_status "💾 Memory: $memory_info"

    # Disk usage
    disk_info=$(df -h . | awk 'NR==2{printf "Used: %s/%s (%s)", $3,$2,$5}')
    print_status "💿 Disk: $disk_info"

    # CPU load
    cpu_load=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//')
    print_status "🖥️  CPU Load: $cpu_load"

    # Check GPU if available
    if command -v nvidia-smi &> /dev/null; then
        gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
        gpu_memory=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits | head -1)
        print_status "🎮 GPU: ${gpu_usage}% utilization, Memory: ${gpu_memory}"
    fi

    echo ""
}

check_network_ports() {
    print_section "Network Ports"

    ports=("8080:Backend API" "11434:Ollama API" "3000:Frontend (optional)")

    for port_info in "${ports[@]}"; do
        port=$(echo $port_info | cut -d':' -f1)
        service=$(echo $port_info | cut -d':' -f2)

        if lsof -i:$port > /dev/null 2>&1; then
            PID=$(lsof -ti:$port)
            PROCESS=$(ps -p $PID -o comm= 2>/dev/null || echo "unknown")
            print_status "✅ Port $port ($service): $PROCESS (PID: $PID)"
        else
            print_warning "⚠️  Port $port ($service): Not in use"
        fi
    done
    echo ""
}

check_log_files() {
    print_section "Log Files"

    log_files=("logs/backend.log" "logs/ollama.log")

    for log_file in "${log_files[@]}"; do
        if [ -f "$log_file" ]; then
            size=$(du -h "$log_file" | cut -f1)
            lines=$(wc -l < "$log_file")
            modified=$(stat -c %y "$log_file" | cut -d' ' -f1,2 | cut -d'.' -f1)
            print_status "📝 $log_file: $size, $lines lines, modified: $modified"

            # Check for recent errors
            recent_errors=$(tail -100 "$log_file" | grep -i "error\|exception\|failed" | wc -l)
            if [ $recent_errors -gt 0 ]; then
                print_warning "⚠️  $recent_errors recent errors in last 100 lines"
            fi
        else
            print_warning "⚠️  $log_file: Not found"
        fi
    done
    echo ""
}

check_mcp_servers() {
    print_section "MCP Servers"

    # Check AWS Q configurations
    if [ -d ".amazonq/cli-agents" ]; then
        config_count=$(find .amazonq/cli-agents -name "*.json" | wc -l)
        print_status "📋 Found $config_count AWS Q MCP configuration files"

        # List configuration files
        for config_file in .amazonq/cli-agents/*.json; do
            if [ -f "$config_file" ]; then
                config_name=$(basename "$config_file" .json)
                server_count=$(jq '.mcpServers | length' "$config_file" 2>/dev/null || echo "unknown")
                print_status "   • $config_name: $server_count servers"
            fi
        done
    else
        print_warning "⚠️  No AWS Q MCP configurations found"
    fi

    # Check if backend can list MCP servers
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        mcp_response=$(curl -s http://localhost:8080/api/v1/awsq-mcp/servers 2>/dev/null)
        if [ $? -eq 0 ]; then
            server_count=$(echo "$mcp_response" | jq '.count' 2>/dev/null || echo "unknown")
            print_status "🔗 Active MCP servers: $server_count"
        fi
    fi

    echo ""
}

check_models() {
    print_section "AI Models"

    if command -v ollama &> /dev/null && pgrep -x "ollama" > /dev/null; then
        models=$(ollama list 2>/dev/null)
        if [ $? -eq 0 ]; then
            model_count=$(echo "$models" | grep -v "NAME" | wc -l)
            print_status "🤖 Available models: $model_count"

            # Show model details
            echo "$models" | grep -v "NAME" | while read line; do
                if [ ! -z "$line" ]; then
                    model_name=$(echo "$line" | awk '{print $1}')
                    model_size=$(echo "$line" | awk '{print $2}')
                    print_status "   • $model_name ($model_size)"
                fi
            done
        else
            print_warning "⚠️  Could not list models"
        fi
    else
        print_error "❌ Ollama not available"
    fi

    echo ""
}

show_quick_stats() {
    print_section "Quick Health Check"

    # Backend health
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        print_status "✅ Backend API responding"
    else
        print_error "❌ Backend API not responding"
    fi

    # Ollama health
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        print_status "✅ Ollama API responding"
    else
        print_error "❌ Ollama API not responding"
    fi

    # Check disk space
    disk_usage=$(df . | awk 'NR==2{print $5}' | sed 's/%//')
    if [ "$disk_usage" -lt 90 ]; then
        print_status "✅ Disk space OK ($disk_usage%)"
    else
        print_warning "⚠️  Disk space low ($disk_usage%)"
    fi

    # Check memory
    memory_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$memory_usage" -lt 85 ]; then
        print_status "✅ Memory usage OK ($memory_usage%)"
    else
        print_warning "⚠️  Memory usage high ($memory_usage%)"
    fi

    echo ""
}

# Main monitoring function
main() {
    clear
    print_header

    case "${1:-all}" in
        "quick"|"q")
            show_quick_stats
            ;;
        "services"|"s")
            check_service_status "OAPilot Backend" "8080" "python.*start_backend"
            check_service_status "Ollama" "11434" "ollama"
            ;;
        "resources"|"r")
            check_system_resources
            ;;
        "ports"|"p")
            check_network_ports
            ;;
        "logs"|"l")
            check_log_files
            ;;
        "mcp"|"m")
            check_mcp_servers
            ;;
        "models")
            check_models
            ;;
        "all"|*)
            show_quick_stats
            check_service_status "OAPilot Backend" "8080" "python.*start_backend"
            check_service_status "Ollama" "11434" "ollama"
            check_system_resources
            check_network_ports
            check_mcp_servers
            check_models
            check_log_files
            ;;
    esac

    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Usage: $0 [quick|services|resources|ports|logs|mcp|models|all]"
    echo ""
}

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "Warning: jq not found. Some features may not work properly."
    echo "Install with: sudo apt install jq"
    echo ""
fi

# Run main function
main "$@"