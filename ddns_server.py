from flask import Flask, request, jsonify
import requests
import os
import logging
from datetime import datetime
from dotenv import load_dotenv

# Carrega variáveis do arquivo .env (sobrescreve variáveis de ambiente do sistema)
load_dotenv(override=True)

app = Flask(__name__)

# =============================================
# CONFIGURAÇÕES - CARREGADAS DO ARQUIVO .env
# =============================================

# Credenciais de autenticação
DDNS_USERNAME = os.getenv('DDNS_USERNAME')
DDNS_PASSWORD = os.getenv('DDNS_PASSWORD')

# Configurações do servidor
SERVER_HOST = os.getenv('HOST', '0.0.0.0')
SERVER_PORT = int(os.getenv('PORT', 8443))
DEBUG_MODE = os.getenv('DEBUG', 'False').lower() == 'true'

# Configurações da DigitalOcean API
TOKEN = os.getenv('TOKEN') or os.getenv('DO_TOKEN')  # Aceita ambos os nomes
DOMAIN = os.getenv('DOMAIN') or os.getenv('DO_DOMAIN')
RECORD_ID = os.getenv('RECORD_ID') or os.getenv('DO_RECORD_ID')

# Arquivo de log
LOG_FILE = "ips.log"

# =============================================

# Configuração de logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('ddns_operations.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

def get_last_ip():
    """Recupera o último IP registrado no arquivo de log"""
    if not os.path.exists(LOG_FILE):
        return None
    with open(LOG_FILE, "r") as f:
        lines = f.readlines()
        if lines:
            # Pega a última linha e extrai o IP (formato: timestamp,ip)
            return lines[-1].strip().split(",")[1]
    return None

def log_ip(ip):
    """Registra o IP no arquivo de log com timestamp"""
    with open(LOG_FILE, "a") as f:
        f.write(f"{datetime.now()},{ip}\n")

@app.route("/ddns/update", methods=["GET"])
# @app.route("/ddns/update", methods=["GET"])
def ddns_update():
    """Endpoint para atualização de DNS dinâmico"""
    username = request.args.get("username")
    password = request.args.get("password")
    hostname = request.args.get("hostname")
    # Aceita tanto 'ip' quanto 'myip' para compatibilidade
    ip = request.args.get("ip") or request.args.get("myip")
    
    logger.info(f"Request received - Host: {hostname}, IP: {ip}, User: {username}")

    # Validação básica dos parâmetros obrigatórios
    if not username or not password or not hostname or not ip:
        logger.warning("Request rejected - Missing parameters")
        return "Missing parameters", 400

    # Validação de credenciais
    if username != DDNS_USERNAME or password != DDNS_PASSWORD:
        logger.warning(f"Request rejected - Invalid credentials for user: {username}")
        return "Unauthorized", 403

    # Verifica se o IP mudou
    last_ip = get_last_ip()
    logger.info(f"Checking IP change - Current: {ip}, Last: {last_ip}")
    
    if ip == last_ip:
        logger.info("IP unchanged - No action needed")
        return "IP unchanged", 200

    logger.info(f"IP changed from {last_ip} to {ip} - Starting DNS update")

    # Atualiza DNS na DigitalOcean
    url = f"https://api.digitalocean.com/v2/domains/{DOMAIN}/records/{RECORD_ID}"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {TOKEN}"
    }
    payload = {"data": ip}

    try:
        logger.info(f"Sending request to DigitalOcean - Domain: {DOMAIN}, Record ID: {RECORD_ID}")
        response = requests.put(url, headers=headers, json=payload)
        
        if response.status_code == 200:
            log_ip(ip)
            logger.info(f"DNS updated successfully! New IP: {ip}")
            return "DNS updated", 200
        else:
            logger.error(f"Failed to update DNS - Status: {response.status_code}, Response: {response.text}")
            return f"Failed to update DNS: {response.text}", 500
    except requests.RequestException as e:
        logger.error(f"Error connecting to DigitalOcean API: {str(e)}")
        return f"Error connecting to DigitalOcean API: {str(e)}", 500

def print_configuration():
    """Exibe as configurações do servidor em um quadro visual"""
    config_lines = [
        "=" * 60,
        "                    DDNS SERVER CONFIGURATION",
        "=" * 60,
        "",
        "# DigitalOcean API Configuration",
        f"TOKEN        : {'*' * 20 if TOKEN else 'NOT SET'}",
        f"DOMAIN       : {DOMAIN or 'NOT SET'}",
        f"RECORD_ID    : {RECORD_ID or 'NOT SET'}",
        "",
        "# DDNS Authentication",
        f"DDNS_USERNAME: {DDNS_USERNAME or 'NOT SET'}",
        f"DDNS_PASSWORD: {'*' * len(DDNS_PASSWORD) if DDNS_PASSWORD else 'NOT SET'}",
        "",
        "# Server Configuration",
        f"HOST         : {SERVER_HOST}",
        f"PORT         : {SERVER_PORT}",
        f"DEBUG        : {DEBUG_MODE}",
        "",
        "=" * 60,
    ]
    
    for line in config_lines:
        print(line)

if __name__ == "__main__":
    logger.info(f"Starting DDNS server - Host: {SERVER_HOST}, Port: {SERVER_PORT}")
    logger.info(f"Configured domain: {DOMAIN}")
    logger.info(f"Debug mode: {DEBUG_MODE}")
    print_configuration()
    app.run(host=SERVER_HOST, port=SERVER_PORT, debug=DEBUG_MODE)
