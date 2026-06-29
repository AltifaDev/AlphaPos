#!/bin/bash
# AlphaPos Customer Web — FastAPI Server Launcher
cd "$(dirname "$0")"
source venv/bin/activate 2>/dev/null

echo "==========================================="
echo "  AlphaPos FastAPI Server"
echo "  http://localhost:8080"
echo "  Docs: http://localhost:8080/docs"
echo "==========================================="

uvicorn server_fastapi:app --host 0.0.0.0 --port 8080 --reload
