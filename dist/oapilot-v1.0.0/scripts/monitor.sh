#!/bin/bash

# OAPilot System Monitor

echo "📊 OAPilot System Monitor"
echo "========================"

# Check if OAPilot is running
if curl -s http://localhost:8080/health > /dev/null 2>&1; then
    echo "✅ OAPilot is running"
    
    # Get detailed status
    echo ""
    echo "🔍 System Status:"
    curl -s http://localhost:8080/api/v1/resources | python3 -m json.tool 2>/dev/null || echo "   API not responding"
    
else
    echo "❌ OAPilot is not running"
    echo "   Start with: ./scripts/start.sh"
fi

echo ""
echo "💾 System Resources:"
echo "   $(free -h | grep Mem)"
echo "   $(df -h . | tail -n1)"

echo ""
echo "🤖 Ollama Status:"
if pgrep -x "ollama" > /dev/null; then
    echo "   ✅ Ollama is running"
    echo "   Models: $(ollama list | grep -v NAME | wc -l) installed"
else
    echo "   ❌ Ollama is not running"
fi

echo ""
echo "📝 Recent Logs:"
if [ -f "logs/backend.log" ]; then
    echo "   Last 5 backend log entries:"
    tail -n5 logs/backend.log | sed 's/^/     /'
else
    echo "   No logs found"
fi
