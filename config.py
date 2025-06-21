"""
Configurações do servidor DDNS
"""
import os
from dotenv import load_dotenv

# Carrega variáveis do arquivo .env
load_dotenv()

class Config:
    """Configurações base"""
    # DigitalOcean API
    DO_TOKEN = os.getenv('DO_TOKEN')
    DO_DOMAIN = os.getenv('DO_DOMAIN')
    DO_RECORD_ID = os.getenv('DO_RECORD_ID')
    
    # Credenciais DDNS
    DDNS_USERNAME = os.getenv('DDNS_USERNAME')
    DDNS_PASSWORD = os.getenv('DDNS_PASSWORD')
    
    # Arquivo de log
    LOG_FILE = "ips.log"
    
    # Servidor
    HOST = os.getenv('HOST', '0.0.0.0')
    PORT = int(os.getenv('PORT', 8443))

class DevelopmentConfig(Config):
    """Configurações para desenvolvimento"""
    DEBUG = True

class ProductionConfig(Config):
    """Configurações para produção"""
    DEBUG = True

# Seleciona a configuração baseada na variável de ambiente
config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'default': DevelopmentConfig
}

def get_config():
    """Retorna a configuração apropriada"""
    return config[os.getenv('FLASK_ENV', 'default')]
