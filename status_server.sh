#!/bin/bash

# Script para verificar o status do servidor DDNS

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Status do Servidor DDNS ===${NC}"

# Verifica arquivo PID
if [ -f "ddns_server.pid" ]; then
    PID=$(cat ddns_server.pid)
    echo -e "Arquivo PID encontrado: ${YELLOW}ddns_server.pid${NC}"
    echo -e "PID do processo: ${YELLOW}$PID${NC}"
    
    # Verifica se o processo está rodando
    if kill -0 "$PID" 2>/dev/null; then
        echo -e "Status: ${GREEN}RODANDO${NC}"
        
        # Informações adicionais do processo
        echo -e "\n${BLUE}Detalhes do processo:${NC}"
        ps -p "$PID" -o pid,ppid,cmd,%cpu,%mem,etime
        
        # Verifica porta
        echo -e "\n${BLUE}Porta em uso:${NC}"
        lsof -i :8443 2>/dev/null | head -2
        
    else
        echo -e "Status: ${RED}PARADO${NC} (PID não encontrado no sistema)"
        echo -e "${YELLOW}Removendo arquivo PID órfão...${NC}"
        rm ddns_server.pid
    fi
else
    echo -e "Arquivo PID: ${RED}NÃO ENCONTRADO${NC}"
    
    # Procura por processos relacionados
    echo -e "\n${BLUE}Procurando processos relacionados:${NC}"
    
    GUNICORN_PROC=$(pgrep -f "gunicorn.*ddns_server")
    FLASK_PROC=$(pgrep -f "python.*ddns_server.py")
    
    if [ -n "$GUNICORN_PROC" ]; then
        echo -e "Processo Gunicorn encontrado: ${YELLOW}$GUNICORN_PROC${NC}"
        ps -p "$GUNICORN_PROC" -o pid,cmd,%cpu,%mem,etime
    elif [ -n "$FLASK_PROC" ]; then
        echo -e "Processo Flask encontrado: ${YELLOW}$FLASK_PROC${NC}"
        ps -p "$FLASK_PROC" -o pid,cmd,%cpu,%mem,etime
    else
        echo -e "Status: ${RED}NENHUM PROCESSO ENCONTRADO${NC}"
    fi
fi

# Verifica logs recentes
echo -e "\n${BLUE}Logs recentes:${NC}"
if [ -f "ddns_operations.log" ]; then
    echo -e "${YELLOW}Últimas 5 linhas do log:${NC}"
    tail -5 ddns_operations.log
else
    echo -e "${RED}Arquivo de log não encontrado${NC}"
fi
