#!/bin/bash

# Script para parar o servidor DDNS

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Parando servidor DDNS...${NC}"

# Para o servidor Gunicorn
pkill -f "gunicorn.*ddns_server"

# Para o servidor Flask de desenvolvimento (se estiver rodando)
pkill -f "python.*ddns_server.py"

# Remove o arquivo PID se existir
if [ -f "ddns_server.pid" ]; then
    rm ddns_server.pid
    echo -e "${GREEN}Arquivo PID removido${NC}"
fi

echo -e "${GREEN}Servidor parado!${NC}"
