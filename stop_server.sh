#!/bin/bash

# Script to stop DDNS server

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Stopping DDNS server...${NC}"

# Check if PID file exists
if [ -f "ddns_server.pid" ]; then
    PID=$(cat ddns_server.pid)
    echo -e "Stopping process PID: ${YELLOW}$PID${NC}"
    
    # Try to stop gracefully first
    if kill -TERM "$PID" 2>/dev/null; then
        echo -e "${GREEN}TERM signal sent to process $PID${NC}"
        sleep 3
        
        # Check if process is still running
        if kill -0 "$PID" 2>/dev/null; then
            echo -e "${YELLOW}Process still running, sending KILL...${NC}"
            kill -KILL "$PID" 2>/dev/null
        fi
    else
        echo -e "${YELLOW}Process $PID not found, trying other methods...${NC}"
    fi
    
    # Remove PID file
    rm ddns_server.pid
    echo -e "${GREEN}PID file removed${NC}"
else
    echo -e "${YELLOW}PID file not found, trying to stop by name...${NC}"
    
    # Stop Gunicorn server
    pkill -f "gunicorn.*ddns_server"
    
    # Stop Flask development server (if running)
    pkill -f "python.*ddns_server.py"
fi

echo -e "${GREEN}Server stopped!${NC}"
