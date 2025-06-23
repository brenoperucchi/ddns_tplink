#!/bin/bash

# Production startup script
# This script starts the DDNS server using Gunicorn

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Starting DDNS server in production mode ===${NC}"

# Check if virtual environment exists
if [ ! -d ".venv" ]; then
    echo -e "${RED}Error: Virtual environment not found!${NC}"
    echo "Run: python -m venv .venv"
    exit 1
fi

# Activate virtual environment
source .venv/bin/activate

# Check if dependencies are installed
if ! python -c "import flask, requests, gunicorn" 2>/dev/null; then
    echo -e "${YELLOW}Installing dependencies...${NC}"
    pip install -r requirements.txt
fi

# Stop server if running
echo -e "${YELLOW}Stopping previous server (if exists)...${NC}"
pkill -f "gunicorn.*ddns_server" 2>/dev/null || true

# Start server with Gunicorn
echo -e "${GREEN}Starting server with Gunicorn...${NC}"
gunicorn --config gunicorn.conf.py ddns_server:app &

# Wait a moment for server to initialize
sleep 2

# Check if PID was created and display information
if [ -f "ddns_server.pid" ]; then
    PID=$(cat ddns_server.pid)
    echo -e "${GREEN}Server started successfully!${NC}"
    echo -e "Process PID: ${YELLOW}$PID${NC}"
    echo -e "PID file: ${YELLOW}ddns_server.pid${NC}"
else
    echo -e "${RED}Error: PID file was not created${NC}"
    exit 1
fi

echo -e "${GREEN}Server started!${NC}"
echo -e "Access logs: ${YELLOW}access.log${NC}"
echo -e "Error logs: ${YELLOW}error.log${NC}"
