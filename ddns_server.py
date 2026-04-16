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

TOKEN = os.getenv("TOKEN") or os.getenv("DO_TOKEN")
DOMAIN = os.getenv("DOMAIN") or os.getenv("DO_DOMAIN")
RECORD_ID = os.getenv("RECORD_ID") or os.getenv("DO_RECORD_ID")

# If TRUST_PROXY is set, trust X-Forwarded-For from one proxy (nginx)
TRUST_PROXY = os.getenv("TRUST_PROXY", "False").lower() == "true"

LOG_FILE = "ips.log"

# Fail fast if required config is missing
_required = {
    "DDNS_USERNAME": DDNS_USERNAME,
    "DDNS_PASSWORD": DDNS_PASSWORD,
    "TOKEN": TOKEN,
    "DOMAIN": DOMAIN,
    "RECORD_ID": RECORD_ID,
}
_missing = [k for k, v in _required.items() if not v]
if _missing:
    raise RuntimeError(f"Missing required configuration: {', '.join(_missing)}")

# Harden Flask: reject oversized requests (DDNS requests are tiny)
app.config["MAX_CONTENT_LENGTH"] = 4 * 1024  # 4 KB

# If behind nginx, honor X-Forwarded-For for real client IP
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
# RFC 1123 hostname pattern (labels separated by dots, length <= 253)
_HOSTNAME_RE = re.compile(
    r"^(?=.{1,253}$)"
    r"([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)"
    r"(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$"
)


def sanitize_for_log(value, max_len: int = 120) -> str:
    """Strip control chars and cap length to prevent log injection."""
    if value is None:
        return "<none>"
    s = str(value)[:max_len]
    return re.sub(r"[\x00-\x1f\x7f]", "?", s)


def valid_hostname(hostname: str) -> bool:
    return bool(hostname) and _HOSTNAME_RE.match(hostname) is not None


def valid_public_ipv4(ip: str) -> bool:
    """Accept only public, routable IPv4 addresses."""
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
    """Constant-time credential comparison."""
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

    # Credentials first, in constant time. Do not leak whether params are
    # missing before auth; any failure below returns generic error.
    if not check_credentials(username, password):
        logger.warning(f"Auth failed from {remote}")
        return "Unauthorized", 403

    # From here on, the caller is authenticated.
    if not hostname or not ip:
        logger.warning(f"Missing parameters from {remote}")
        return "Missing parameters", 400

    if not valid_hostname(hostname):
        logger.warning(
            f"Invalid hostname from {remote}: {sanitize_for_log(hostname)}"
        )
        return "Invalid hostname", 400

    if not valid_public_ipv4(ip):
        logger.warning(
            f"Invalid or non-public IP from {remote}: {sanitize_for_log(ip)}"
        )
        return "Invalid IP", 400

    # Skip update if IP hasn't changed
    last_ip = get_last_ip()
    if ip == last_ip:
        logger.info(f"IP unchanged: {ip}")
        return "IP unchanged", 200

    logger.info(f"IP change: {last_ip} -> {ip}")

    url = f"https://api.digitalocean.com/v2/domains/{DOMAIN}/records/{RECORD_ID}"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {TOKEN}",
    }
    payload = {"data": ip}

    try:
        response = requests.put(url, headers=headers, json=payload, timeout=10)
        if response.status_code == 200:
            log_ip(ip)
            logger.info(f"DNS updated to {ip}")
            return "DNS updated", 200
        # Log detail server-side; do not leak upstream response to client.
        logger.error(
            f"DO API error {response.status_code}: {response.text[:200]}"
        )
        return "Failed to update DNS", 502
    except requests.Timeout:
        logger.error("DO API timeout")
        return "Upstream timeout", 504
    except requests.RequestException as e:
        logger.error(f"DO API connection error: {type(e).__name__}")
        return "Upstream error", 502


@app.route("/health", methods=["GET"])
@limiter.exempt
def health():
    return "ok", 200


# Generic handlers avoid leaking stack traces or internal info
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
        f"TRUST_PROXY  : {TRUST_PROXY}",
        "",
        "=" * 60,
    ]
    for line in lines:
        print(line)


if __name__ == "__main__":
    logger.info(
        f"Starting DDNS server - Host: {SERVER_HOST}, Port: {SERVER_PORT}"
    )
    print_configuration()
    app.run(host=SERVER_HOST, port=SERVER_PORT, debug=DEBUG_MODE)
