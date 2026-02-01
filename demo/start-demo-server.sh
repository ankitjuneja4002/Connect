#!/bin/bash

# Simple HTTP server to serve the demo page
# This avoids CORS issues when opening HTML file directly

PORT=${1:-8000}

echo "🚀 Starting Demo Server..."
echo "📱 Open http://localhost:$PORT/index.html in your browser"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

cd "$(dirname "$0")"
python3 -m http.server $PORT 2>/dev/null || python -m http.server $PORT 2>/dev/null || {
    echo "❌ Python not found. Using alternative method..."
    # Fallback: Use Node.js if available
    if command -v npx > /dev/null 2>&1; then
        npx http-server -p $PORT
    else
        echo "Please install Python 3 or Node.js to run the demo server"
        echo "Or open demo/index.html directly in your browser"
        exit 1
    fi
}
