#!/bin/bash

# Script to check DDNS server status

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== DDNS Server Status ===${NC}"

# Check PID file
if [ -f "ddns_server.pid" ]; then
    PID=$(cat ddns_server.pid)
    echo -e "PID file found: ${YELLOW}ddns_server.pid${NC}"
    echo -e "Process PID: ${YELLOW}$PID${NC}"
    
    # Check if process is running
    if kill -0 "$PID" 2>/dev/null; then
        echo -e "Status: ${GREEN}RUNNING${NC}"
        
        # Additional process information
        echo -e "\n${BLUE}Process details:${NC}"
        ps -p "$PID" -o pid,ppid,cmd,%cpu,%mem,etime
        
        # Check port
        echo -e "\n${BLUE}Port in use:${NC}"
        lsof -i :8443 2>/dev/null | head -2
        
    else
        echo -e "Status: ${RED}STOPPED${NC} (PID not found in system)"
        echo -e "${YELLOW}Removing orphaned PID file...${NC}"
        rm ddns_server.pid
    fi
else
    echo -e "PID file: ${RED}NOT FOUND${NC}"
    
    # Look for related processes
    echo -e "\n${BLUE}Looking for related processes:${NC}"
    
    GUNICORN_PROC=$(pgrep -f "gunicorn.*ddns_server")
    FLASK_PROC=$(pgrep -f "python.*ddns_server.py")
    
    if [ -n "$GUNICORN_PROC" ]; then
        echo -e "Gunicorn process found: ${YELLOW}$GUNICORN_PROC${NC}"
        ps -p "$GUNICORN_PROC" -o pid,cmd,%cpu,%mem,etime
    elif [ -n "$FLASK_PROC" ]; then
        echo -e "Flask process found: ${YELLOW}$FLASK_PROC${NC}"
        ps -p "$FLASK_PROC" -o pid,cmd,%cpu,%mem,etime
    else
        echo -e "Status: ${RED}NO PROCESS FOUND${NC}"
    fi
fi

# Check recent logs
echo -e "\n${BLUE}Recent logs:${NC}"
if [ -f "ddns_operations.log" ]; then
    echo -e "${YELLOW}Last 5 log lines:${NC}"
    tail -5 ddns_operations.log
else
    echo -e "${RED}Log file not found${NC}"
fi
