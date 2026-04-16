#!/bin/bash

# Manual production startup (alternative to systemd)
# Run ./setup.sh first to create the virtual environment.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Starting DDNS server in production mode ===${NC}"

if [ ! -d "$SCRIPT_DIR/.venv" ]; then
    echo -e "${RED}Error: virtual environment not found.${NC}"
    echo "Run ./setup.sh first to set up the server."
    exit 1
fi

source "$SCRIPT_DIR/.venv/bin/activate"

if ! python3 -c "import flask, requests, gunicorn" 2>/dev/null; then
    echo -e "${YELLOW}Installing missing dependencies...${NC}"
    pip install -r "$SCRIPT_DIR/requirements.txt"
fi

echo -e "${YELLOW}Stopping previous server (if running)...${NC}"
pkill -f "gunicorn.*ddns_server" 2>/dev/null || true

echo -e "${GREEN}Starting server with Gunicorn...${NC}"
gunicorn --config gunicorn.conf.py ddns_server:app &

sleep 2

if [ -f "$SCRIPT_DIR/ddns_server.pid" ]; then
    PID=$(cat "$SCRIPT_DIR/ddns_server.pid")
    echo -e "${GREEN}Server started (PID: ${YELLOW}${PID}${GREEN}).${NC}"
    echo -e "Logs: ${YELLOW}access.log${NC} / ${YELLOW}error.log${NC}"
else
    echo -e "${RED}Error: PID file not created. Check error.log for details.${NC}"
    exit 1
fi
