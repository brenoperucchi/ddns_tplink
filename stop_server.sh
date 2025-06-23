#!/bin/bash

# Script para parar o servidor DDNS

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Parando servidor DDNS...${NC}"

# Verifica se existe arquivo PID
if [ -f "ddns_server.pid" ]; then
    PID=$(cat ddns_server.pid)
    echo -e "Parando processo PID: ${YELLOW}$PID${NC}"
    
    # Tenta parar graciosamente primeiro
    if kill -TERM "$PID" 2>/dev/null; then
        echo -e "${GREEN}Sinal TERM enviado ao processo $PID${NC}"
        sleep 3
        
        # Verifica se o processo ainda está rodando
        if kill -0 "$PID" 2>/dev/null; then
            echo -e "${YELLOW}Processo ainda rodando, enviando KILL...${NC}"
            kill -KILL "$PID" 2>/dev/null
        fi
    else
        echo -e "${YELLOW}Processo $PID não encontrado, tentando outros métodos...${NC}"
    fi
    
    # Remove o arquivo PID
    rm ddns_server.pid
    echo -e "${GREEN}Arquivo PID removido${NC}"
else
    echo -e "${YELLOW}Arquivo PID não encontrado, tentando parar por nome...${NC}"
    
    # Para o servidor Gunicorn
    pkill -f "gunicorn.*ddns_server"
    
    # Para o servidor Flask de desenvolvimento (se estiver rodando)
    pkill -f "python.*ddns_server.py"
fi

echo -e "${GREEN}Servidor parado!${NC}"
