from flask import Flask, request
from werkzeug.middleware.proxy_fix import ProxyFix
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import requests
import os
import logging
import ipaddress
import re
import hmac
from datetime import datetime
from dotenv import load_dotenv

# Load .env (overrides system env vars)
load_dotenv(override=True)

app = Flask(__name__)

# =============================================
# CONFIG FROM .env
# =============================================
DDNS_USERNAME = os.getenv("DDNS_USERNAME")
DDNS_PASSWORD = os.getenv("DDNS_PASSWORD")

SERVER_HOST = os.getenv("HOST", "127.0.0.1")
SERVER_PORT = int(os.getenv("PORT", 9876))
DEBUG_MODE = os.getenv("DEBUG", "False").lower() == "true"
TRUST_PROXY = os.getenv("TRUST_PROXY", "False").lower() == "true"

PROVIDER = os.getenv("PROVIDER", "duckdns").lower()

# DuckDNS
DUCK_TOKEN  = os.getenv("DUCK_TOKEN")
DUCK_DOMAIN = os.getenv("DUCK_DOMAIN")   # subdomain only, e.g. "myhome" → myhome.duckdns.org

# DigitalOcean
DO_TOKEN     = os.getenv("TOKEN") or os.getenv("DO_TOKEN")
DO_DOMAIN    = os.getenv("DOMAIN") or os.getenv("DO_DOMAIN")
DO_RECORD_ID = os.getenv("RECORD_ID") or os.getenv("DO_RECORD_ID")

# Cloudflare
CF_TOKEN     = os.getenv("CF_TOKEN")
CF_ZONE_ID   = os.getenv("CF_ZONE_ID")
CF_RECORD_ID = os.getenv("CF_RECORD_ID")

LOG_FILE = "ips.log"

# Validate required config for the selected provider
if PROVIDER == "duckdns":
    _required = {
        "DDNS_USERNAME": DDNS_USERNAME,
        "DDNS_PASSWORD": DDNS_PASSWORD,
        "DUCK_TOKEN":    DUCK_TOKEN,
        "DUCK_DOMAIN":   DUCK_DOMAIN,
    }
elif PROVIDER == "digitalocean":
    _required = {
        "DDNS_USERNAME": DDNS_USERNAME,
        "DDNS_PASSWORD": DDNS_PASSWORD,
        "TOKEN":         DO_TOKEN,
        "DOMAIN":        DO_DOMAIN,
        "RECORD_ID":     DO_RECORD_ID,
    }
elif PROVIDER == "cloudflare":
    _required = {
        "DDNS_USERNAME": DDNS_USERNAME,
        "DDNS_PASSWORD": DDNS_PASSWORD,
        "CF_TOKEN":      CF_TOKEN,
        "CF_ZONE_ID":    CF_ZONE_ID,
        "CF_RECORD_ID":  CF_RECORD_ID,
    }
else:
    raise RuntimeError(
        f"Unknown PROVIDER '{PROVIDER}'. "
        "Supported values: 'duckdns', 'digitalocean', 'cloudflare'."
    )

_missing = [k for k, v in _required.items() if not v]
if _missing:
    raise RuntimeError(f"Missing required configuration: {', '.join(_missing)}")

# Harden Flask: reject oversized requests (DDNS requests are tiny)
app.config["MAX_CONTENT_LENGTH"] = 4 * 1024  # 4 KB

if TRUST_PROXY:
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=2, x_proto=2, x_host=2)

# Rate limiter (in-memory; resets on restart)
limiter = Limiter(
    get_remote_address,
    app=app,
    default_limits=["60 per hour"],
    storage_uri="memory://",
)

# =============================================
# LOGGING
# =============================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("ddns_operations.log"),
        logging.StreamHandler(),
    ],
)
logger = logging.getLogger(__name__)

# =============================================
# VALIDATION HELPERS
# =============================================
_HOSTNAME_RE = re.compile(
    r"^(?=.{1,253}$)"
    r"([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)"
    r"(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
)


def sanitize_for_log(value, max_len: int = 120) -> str:
    if value is None:
        return "<none>"
    s = str(value)[:max_len]
    return re.sub(r"[\x00-\x1f\x7f]", "?", s)


def valid_hostname(hostname: str) -> bool:
    return bool(hostname) and _HOSTNAME_RE.match(hostname) is not None


def valid_public_ipv4(ip: str) -> bool:
    try:
        ip_obj = ipaddress.ip_address(ip)
    except ValueError:
        return False
    if ip_obj.version != 4:
        return False
    return not (
        ip_obj.is_private
        or ip_obj.is_loopback
        or ip_obj.is_multicast
        or ip_obj.is_reserved
        or ip_obj.is_link_local
        or ip_obj.is_unspecified
    )


def check_credentials(username: str, password: str) -> bool:
    user_ok = hmac.compare_digest(username or "", DDNS_USERNAME)
    pass_ok = hmac.compare_digest(password or "", DDNS_PASSWORD)
    return user_ok and pass_ok


def get_last_ip():
    if not os.path.exists(LOG_FILE):
        return None
    try:
        with open(LOG_FILE, "r") as f:
            lines = f.readlines()
        if lines:
            return lines[-1].strip().split(",")[1]
    except (IOError, IndexError):
        return None
    return None


def log_ip(ip: str):
    with open(LOG_FILE, "a") as f:
        f.write(f"{datetime.now()},{ip}\n")


# =============================================
# DNS PROVIDER BACKENDS
# =============================================
def _update_duckdns(ip: str) -> tuple:
    """Update A record via DuckDNS API. Returns (success, status_code, message)."""
    try:
        resp = requests.get(
            "https://www.duckdns.org/update",
            params={"domains": DUCK_DOMAIN, "token": DUCK_TOKEN, "ip": ip},
            timeout=10,
        )
        if resp.status_code == 200 and resp.text.strip().upper() == "OK":
            return True, 200, "DNS updated"
        logger.error(f"DuckDNS API error: HTTP {resp.status_code} — {resp.text[:50]}")
        return False, 502, "Failed to update DNS"
    except requests.Timeout:
        logger.error("DuckDNS API timeout")
        return False, 504, "Upstream timeout"
    except requests.RequestException as e:
        logger.error(f"DuckDNS API connection error: {type(e).__name__}")
        return False, 502, "Upstream error"


def _update_digitalocean(ip: str) -> tuple:
    """Update A record via DigitalOcean API v2. Returns (success, status_code, message)."""
    url = f"https://api.digitalocean.com/v2/domains/{DO_DOMAIN}/records/{DO_RECORD_ID}"
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {DO_TOKEN}"}
    try:
        resp = requests.put(url, headers=headers, json={"data": ip}, timeout=10)
        if resp.status_code == 200:
            return True, 200, "DNS updated"
        logger.error(f"DigitalOcean API error {resp.status_code}: {resp.text[:200]}")
        return False, 502, "Failed to update DNS"
    except requests.Timeout:
        logger.error("DigitalOcean API timeout")
        return False, 504, "Upstream timeout"
    except requests.RequestException as e:
        logger.error(f"DigitalOcean API connection error: {type(e).__name__}")
        return False, 502, "Upstream error"


def _update_cloudflare(ip: str) -> tuple:
    """Update A record via Cloudflare API v4. Returns (success, status_code, message)."""
    url = f"https://api.cloudflare.com/client/v4/zones/{CF_ZONE_ID}/dns_records/{CF_RECORD_ID}"
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {CF_TOKEN}"}
    try:
        resp = requests.patch(url, headers=headers, json={"content": ip}, timeout=10)
        if resp.status_code == 200:
            return True, 200, "DNS updated"
        logger.error(f"Cloudflare API error {resp.status_code}: {resp.text[:200]}")
        return False, 502, "Failed to update DNS"
    except requests.Timeout:
        logger.error("Cloudflare API timeout")
        return False, 504, "Upstream timeout"
    except requests.RequestException as e:
        logger.error(f"Cloudflare API connection error: {type(e).__name__}")
        return False, 502, "Upstream error"


def push_dns_update(ip: str) -> tuple:
    """Dispatch DNS update to the configured provider."""
    if PROVIDER == "digitalocean":
        return _update_digitalocean(ip)
    if PROVIDER == "cloudflare":
        return _update_cloudflare(ip)
    return _update_duckdns(ip)


# =============================================
# ROUTES
# =============================================
@app.route("/ddns/update", methods=["GET"])
@limiter.limit("10 per minute")
def ddns_update():
    username = request.args.get("username", "")
    password = request.args.get("password", "")
    hostname = request.args.get("hostname", "")
    ip = request.args.get("ip") or request.args.get("myip") or ""

    remote = request.remote_addr or "unknown"
    logger.info(
        f"Request from {remote} - Host: {sanitize_for_log(hostname)}, "
        f"IP: {sanitize_for_log(ip)}"
    )

    if not check_credentials(username, password):
        logger.warning(f"Auth failed from {remote}")
        return "Unauthorized", 403

    if not hostname or not ip:
        logger.warning(f"Missing parameters from {remote}")
        return "Missing parameters", 400

    if not valid_hostname(hostname):
        logger.warning(f"Invalid hostname from {remote}: {sanitize_for_log(hostname)}")
        return "Invalid hostname", 400

    if not valid_public_ipv4(ip):
        logger.warning(f"Invalid or non-public IP from {remote}: {sanitize_for_log(ip)}")
        return "Invalid IP", 400

    last_ip = get_last_ip()
    if ip == last_ip:
        logger.info(f"IP unchanged: {ip}")
        return "IP unchanged", 200

    logger.info(f"IP change detected: {last_ip} -> {ip}")

    success, status, message = push_dns_update(ip)
    if success:
        log_ip(ip)
        logger.info(f"DNS updated to {ip} via {PROVIDER}")
    return message, status


@app.route("/health", methods=["GET"])
@limiter.exempt
def health():
    return "ok", 200


@app.errorhandler(404)
def not_found(_):
    return "Not found", 404


@app.errorhandler(405)
def method_not_allowed(_):
    return "Method not allowed", 405


@app.errorhandler(429)
def rate_limited(_):
    return "Too many requests", 429


@app.errorhandler(500)
def server_error(_):
    return "Internal error", 500


# =============================================
# STARTUP
# =============================================
def print_configuration():
    lines = [
        "=" * 60,
        "                    DDNS SERVER CONFIGURATION",
        "=" * 60,
        "",
        f"PROVIDER     : {PROVIDER}",
        "",
    ]

    if PROVIDER == "duckdns":
        lines += [
            "# DuckDNS",
            f"DUCK_TOKEN   : {'*' * 20 if DUCK_TOKEN else 'NOT SET'}",
            f"DUCK_DOMAIN  : {DUCK_DOMAIN + '.duckdns.org' if DUCK_DOMAIN else 'NOT SET'}",
        ]
    elif PROVIDER == "digitalocean":
        lines += [
            "# DigitalOcean",
            f"TOKEN        : {'*' * 20 if DO_TOKEN else 'NOT SET'}",
            f"DOMAIN       : {DO_DOMAIN or 'NOT SET'}",
            f"RECORD_ID    : {DO_RECORD_ID or 'NOT SET'}",
        ]
    else:
        lines += [
            "# Cloudflare",
            f"CF_TOKEN     : {'*' * 20 if CF_TOKEN else 'NOT SET'}",
            f"CF_ZONE_ID   : {CF_ZONE_ID or 'NOT SET'}",
            f"CF_RECORD_ID : {CF_RECORD_ID or 'NOT SET'}",
        ]

    lines += [
        "",
        "# DDNS Authentication",
        f"DDNS_USERNAME: {DDNS_USERNAME or 'NOT SET'}",
        f"DDNS_PASSWORD: {'*' * len(DDNS_PASSWORD) if DDNS_PASSWORD else 'NOT SET'}",
        "",
        "# Server",
        f"HOST         : {SERVER_HOST}",
        f"PORT         : {SERVER_PORT}",
        f"DEBUG        : {DEBUG_MODE}",
        f"TRUST_PROXY  : {TRUST_PROXY}",
        "",
        "=" * 60,
    ]
    for line in lines:
        print(line)


if __name__ == "__main__":
    logger.info(f"Starting DDNS server [{PROVIDER}] - {SERVER_HOST}:{SERVER_PORT}")
    print_configuration()
    app.run(host=SERVER_HOST, port=SERVER_PORT, debug=DEBUG_MODE)
