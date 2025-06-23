#!/bin/bash

# Script de inicialização para produção
# Este script inicia o servidor DDNS usando Gunicorn

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Iniciando servidor DDNS em modo de produção ===${NC}"

# Verifica se o virtual environment existe
if [ ! -d ".venv" ]; then
    echo -e "${RED}Erro: Virtual environment não encontrado!${NC}"
    echo "Execute: python -m venv .venv"
    exit 1
fi

# Ativa o virtual environment
source .venv/bin/activate

# Verifica se as dependências estão instaladas
if ! python -c "import flask, requests, gunicorn" 2>/dev/null; then
    echo -e "${YELLOW}Instalando dependências...${NC}"
    pip install -r requirements.txt
fi

# Para o servidor se estiver rodando
echo -e "${YELLOW}Parando servidor anterior (se existir)...${NC}"
pkill -f "gunicorn.*ddns_server" 2>/dev/null || true

# Inicia o servidor com Gunicorn
echo -e "${GREEN}Iniciando servidor com Gunicorn...${NC}"
gunicorn --config gunicorn.conf.py ddns_server:app &

# Aguarda um momento para o servidor inicializar
sleep 2

# Verifica se o PID foi criado e exibe informações
if [ -f "ddns_server.pid" ]; then
    PID=$(cat ddns_server.pid)
    echo -e "${GREEN}Servidor iniciado com sucesso!${NC}"
    echo -e "PID do processo: ${YELLOW}$PID${NC}"
    echo -e "Arquivo PID: ${YELLOW}ddns_server.pid${NC}"
else
    echo -e "${RED}Erro: Arquivo PID não foi criado${NC}"
    exit 1
fi

echo -e "${GREEN}Servidor iniciado!${NC}"
echo -e "Logs de acesso: ${YELLOW}access.log${NC}"
echo -e "Logs de erro: ${YELLOW}error.log${NC}"
