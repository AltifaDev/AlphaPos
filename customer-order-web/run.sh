#!/bin/bash
# AlphaPos Mobile Order Web Local Server Launcher

PORT=8080

echo "=========================================================="
echo "      AlphaPos Mobile Ordering System Simulator"
echo "=========================================================="
echo "  Running on local address: http://localhost:$PORT"
echo "  Press Ctrl+C to terminate this server"
echo "=========================================================="
echo ""

# Auto open the browser after a 1 second delay
(sleep 1 && open "http://localhost:$PORT/?table=5&token=table-session-abcde") &

# Start the unified backend server
python3 server.py

