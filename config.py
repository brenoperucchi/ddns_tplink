"""
DDNS server configuration
"""
import os
from dotenv import load_dotenv

load_dotenv()


class Config:
    """Base configuration"""

    # DigitalOcean API
    DO_TOKEN = os.getenv("DO_TOKEN")
    DO_DOMAIN = os.getenv("DO_DOMAIN")
    DO_RECORD_ID = os.getenv("DO_RECORD_ID")

    # DDNS credentials
    DDNS_USERNAME = os.getenv("DDNS_USERNAME")
    DDNS_PASSWORD = os.getenv("DDNS_PASSWORD")

    # Log file
    LOG_FILE = "ips.log"

    # Server
    HOST = os.getenv("HOST", "127.0.0.1")
    PORT = int(os.getenv("PORT", 9876))


class DevelopmentConfig(Config):
    """Development configuration"""

    DEBUG = True


class ProductionConfig(Config):
    """Production configuration"""

    DEBUG = False


config = {
    "development": DevelopmentConfig,
    "production": ProductionConfig,
    "default": DevelopmentConfig,
}


def get_config():
    """Return the appropriate configuration"""
    return config[os.getenv("FLASK_ENV", "default")]
