from flask import Flask, request
from werkzeug.middleware.proxy_fix import ProxyFix
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import requests
import json
import os
import logging
import ipaddress
import re
import hmac
from datetime import datetime
from dotenv import load_dotenv

load_dotenv(override=True)

app = Flask(__name__)

# =============================================
# CONFIG
# =============================================
DDNS_USERNAME = os.getenv("DDNS_USERNAME")
DDNS_PASSWORD = os.getenv("DDNS_PASSWORD")

SERVER_HOST  = os.getenv("HOST", "127.0.0.1")
SERVER_PORT  = int(os.getenv("PORT", 9876))
DEBUG_MODE   = os.getenv("DEBUG", "False").lower() == "true"
TRUST_PROXY  = os.getenv("TRUST_PROXY", "False").lower() == "true"

# PROVIDER=multi  → reads endpoints.json, routes by hostname
# PROVIDER=duckdns|cloudflare|digitalocean → single-WAN mode
PROVIDER = os.getenv("PROVIDER", "duckdns").lower()

# Single-provider credentials (used when PROVIDER != "multi")
# ALLOWED_HOSTNAME restricts which hostname is accepted in single-provider mode.
# Derived automatically from provider config if not set explicitly.
ALLOWED_HOSTNAME = os.getenv("ALLOWED_HOSTNAME")

DUCK_TOKEN   = os.getenv("DUCK_TOKEN")
DUCK_DOMAIN  = os.getenv("DUCK_DOMAIN")
DO_TOKEN     = os.getenv("TOKEN") or os.getenv("DO_TOKEN")
DO_DOMAIN    = os.getenv("DOMAIN") or os.getenv("DO_DOMAIN")
DO_RECORD_ID = os.getenv("RECORD_ID") or os.getenv("DO_RECORD_ID")
CF_TOKEN     = os.getenv("CF_TOKEN")
CF_ZONE_ID   = os.getenv("CF_ZONE_ID")
CF_RECORD_ID = os.getenv("CF_RECORD_ID")

IP_CACHE_FILE = "ips_cache.json"
LOG_FILE      = "ips.log"

# ── Multi-provider mode ──────────────────────────────────────────────────────
# endpoints.json structure:
# {
#   "perucchi.duckdns.org": {
#     "provider": "duckdns",
#     "duck_token": "...",
#     "duck_domain": "perucchi"
#   },
#   "home.imentore.com": {
#     "provider": "digitalocean",
#     "token": "...",
#     "domain": "imentore.com",
#     "record_id": "123456"
#   }
# }
ENDPOINTS: dict = {}
if PROVIDER == "multi":
    _ep_file = os.getenv("ENDPOINTS_FILE", "endpoints.json")
    try:
        with open(_ep_file) as _f:
            ENDPOINTS = json.load(_f)
    except (IOError, json.JSONDecodeError) as _e:
        raise RuntimeError(f"Cannot load '{_ep_file}': {_e}")
    if not ENDPOINTS:
        raise RuntimeError(f"'{_ep_file}' has no endpoints configured.")

# ── Validate required config ─────────────────────────────────────────────────
if PROVIDER == "multi":
    _required = {"DDNS_USERNAME": DDNS_USERNAME, "DDNS_PASSWORD": DDNS_PASSWORD}
elif PROVIDER == "duckdns":
    _required = {
        "DDNS_USERNAME": DDNS_USERNAME, "DDNS_PASSWORD": DDNS_PASSWORD,
        "DUCK_TOKEN": DUCK_TOKEN, "DUCK_DOMAIN": DUCK_DOMAIN,
    }
elif PROVIDER == "digitalocean":
    _required = {
        "DDNS_USERNAME": DDNS_USERNAME, "DDNS_PASSWORD": DDNS_PASSWORD,
        "TOKEN": DO_TOKEN, "DOMAIN": DO_DOMAIN, "RECORD_ID": DO_RECORD_ID,
    }
elif PROVIDER == "cloudflare":
    _required = {
        "DDNS_USERNAME": DDNS_USERNAME, "DDNS_PASSWORD": DDNS_PASSWORD,
        "CF_TOKEN": CF_TOKEN, "CF_ZONE_ID": CF_ZONE_ID, "CF_RECORD_ID": CF_RECORD_ID,
    }
else:
    raise RuntimeError(
        f"Unknown PROVIDER '{PROVIDER}'. "
        "Supported: 'duckdns', 'cloudflare', 'digitalocean', 'multi'."
    )

_missing = [k for k, v in _required.items() if not v]
if _missing:
    raise RuntimeError(f"Missing required configuration: {', '.join(_missing)}")

# Derive ALLOWED_HOSTNAME for single-provider mode if not set explicitly.
if PROVIDER != "multi" and not ALLOWED_HOSTNAME:
    if PROVIDER == "duckdns":
        ALLOWED_HOSTNAME = f"{DUCK_DOMAIN}.duckdns.org"
    # For digitalocean/cloudflare, must be set via ALLOWED_HOSTNAME env var.

app.config["MAX_CONTENT_LENGTH"] = 4 * 1024

if TRUST_PROXY:
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=2, x_proto=2, x_host=2)

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
    return re.sub(r"[\x00-\x1f\x7f]", "?", str(value)[:max_len])


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
        ip_obj.is_private or ip_obj.is_loopback or ip_obj.is_multicast
        or ip_obj.is_reserved or ip_obj.is_link_local or ip_obj.is_unspecified
    )


def check_credentials(username: str, password: str) -> bool:
    return (
        hmac.compare_digest(username or "", DDNS_USERNAME)
        and hmac.compare_digest(password or "", DDNS_PASSWORD)
    )


# =============================================
# IP CACHE  (keyed by hostname in multi mode, "default" in single mode)
# =============================================
def get_last_ip(key: str = "default") -> str | None:
    try:
        with open(IP_CACHE_FILE) as f:
            return json.load(f).get(key)
    except (IOError, json.JSONDecodeError):
        return None


def log_ip(ip: str, key: str = "default"):
    try:
        with open(IP_CACHE_FILE) as f:
            cache = json.load(f)
    except (IOError, json.JSONDecodeError):
        cache = {}
    cache[key] = ip
    with open(IP_CACHE_FILE, "w") as f:
        json.dump(cache, f, indent=2)
    with open(LOG_FILE, "a") as f:
        f.write(f"{datetime.now()},{key},{ip}\n")


# =============================================
# DNS PROVIDER BACKENDS
# All accept explicit credentials so they work in both single and multi mode.
# =============================================
def _update_duckdns(ip: str, token: str, subdomain: str) -> tuple:
    try:
        resp = requests.get(
            "https://www.duckdns.org/update",
            params={"domains": subdomain, "token": token, "ip": ip},
            timeout=10,
        )
        if resp.status_code == 200 and resp.text.strip().upper() == "OK":
            return True, 200, "DNS updated"
        logger.error(f"DuckDNS error: HTTP {resp.status_code} — {resp.text[:50]}")
        return False, 502, "Failed to update DNS"
    except requests.Timeout:
        logger.error("DuckDNS timeout")
        return False, 504, "Upstream timeout"
    except requests.RequestException as e:
        logger.error(f"DuckDNS connection error: {type(e).__name__}")
        return False, 502, "Upstream error"


def _update_digitalocean(ip: str, token: str, domain: str, record_id: str) -> tuple:
    url = f"https://api.digitalocean.com/v2/domains/{domain}/records/{record_id}"
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {token}"}
    try:
        resp = requests.put(url, headers=headers, json={"data": ip}, timeout=10)
        if resp.status_code == 200:
            return True, 200, "DNS updated"
        logger.error(f"DigitalOcean error {resp.status_code}: {resp.text[:200]}")
        return False, 502, "Failed to update DNS"
    except requests.Timeout:
        logger.error("DigitalOcean timeout")
        return False, 504, "Upstream timeout"
    except requests.RequestException as e:
        logger.error(f"DigitalOcean connection error: {type(e).__name__}")
        return False, 502, "Upstream error"


def _update_cloudflare(ip: str, token: str, zone_id: str, record_id: str) -> tuple:
    url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{record_id}"
    headers = {"Content-Type": "application/json", "Authorization": f"Bearer {token}"}
    try:
        resp = requests.patch(url, headers=headers, json={"content": ip}, timeout=10)
        if resp.status_code == 200:
            return True, 200, "DNS updated"
        logger.error(f"Cloudflare error {resp.status_code}: {resp.text[:200]}")
        return False, 502, "Failed to update DNS"
    except requests.Timeout:
        logger.error("Cloudflare timeout")
        return False, 504, "Upstream timeout"
    except requests.RequestException as e:
        logger.error(f"Cloudflare connection error: {type(e).__name__}")
        return False, 502, "Upstream error"


def _dispatch(ip: str, endpoint: dict) -> tuple:
    """Dispatch update to the provider described by an endpoint dict."""
    p = endpoint.get("provider", "")
    if p == "duckdns":
        return _update_duckdns(ip, endpoint["duck_token"], endpoint["duck_domain"])
    if p == "digitalocean":
        return _update_digitalocean(ip, endpoint["token"], endpoint["domain"], endpoint["record_id"])
    if p == "cloudflare":
        return _update_cloudflare(ip, endpoint["cf_token"], endpoint["zone_id"], endpoint["record_id"])
    logger.error(f"Unknown provider '{p}' in endpoint config")
    return False, 500, "Configuration error"


def push_dns_update(ip: str) -> tuple:
    """Single-provider dispatch — reads from global config vars."""
    if PROVIDER == "digitalocean":
        return _update_digitalocean(ip, DO_TOKEN, DO_DOMAIN, DO_RECORD_ID)
    if PROVIDER == "cloudflare":
        return _update_cloudflare(ip, CF_TOKEN, CF_ZONE_ID, CF_RECORD_ID)
    return _update_duckdns(ip, DUCK_TOKEN, DUCK_DOMAIN)


# =============================================
# ROUTES
# =============================================
@app.route("/ddns/update", methods=["GET"])
@limiter.limit("10 per minute")
def ddns_update():
    username = request.args.get("username", "")
    password = request.args.get("password", "")
    hostname = request.args.get("hostname", "")
    ip       = request.args.get("ip") or request.args.get("myip") or ""

    remote = request.remote_addr or "unknown"
    logger.info(
        f"Request from {remote} — hostname: {sanitize_for_log(hostname)}, "
        f"ip: {sanitize_for_log(ip)}"
    )

    if not check_credentials(username, password):
        logger.warning(f"Auth failed from {remote}")
        return "Unauthorized", 403

    if not hostname or not ip:
        return "Missing parameters", 400

    if not valid_hostname(hostname):
        return "Invalid hostname", 400

    if not valid_public_ipv4(ip):
        return "Invalid IP", 400

    if PROVIDER == "multi":
        endpoint = ENDPOINTS.get(hostname)
        if not endpoint:
            logger.warning(
                f"No endpoint configured for hostname "
                f"'{sanitize_for_log(hostname)}' from {remote}"
            )
            return "Unknown hostname", 400
        cache_key = hostname
        last_ip = get_last_ip(cache_key)
        if ip == last_ip:
            logger.info(f"IP unchanged for {hostname}: {ip}")
            return "IP unchanged", 200
        logger.info(f"IP change for {hostname}: {last_ip} → {ip}")
        success, status, message = _dispatch(ip, endpoint)
        provider_label = endpoint.get("provider", "?")
    else:
        if ALLOWED_HOSTNAME and hostname != ALLOWED_HOSTNAME:
            logger.warning(
                f"Rejected hostname '{sanitize_for_log(hostname)}' from {remote} "
                f"(expected '{ALLOWED_HOSTNAME}')"
            )
            return "Unknown hostname", 400
        cache_key = "default"
        last_ip = get_last_ip(cache_key)
        if ip == last_ip:
            logger.info(f"IP unchanged: {ip}")
            return "IP unchanged", 200
        logger.info(f"IP change: {last_ip} → {ip}")
        success, status, message = push_dns_update(ip)
        provider_label = PROVIDER

    if success:
        log_ip(ip, cache_key)
        logger.info(f"DNS updated via {provider_label}: {hostname} → {ip}")
    return message, status


@app.route("/health", methods=["GET"])
@limiter.exempt
def health():
    return "ok", 200


@app.errorhandler(404)
def not_found(_):       return "Not found", 404

@app.errorhandler(405)
def method_not_allowed(_): return "Method not allowed", 405

@app.errorhandler(429)
def rate_limited(_):    return "Too many requests", 429

@app.errorhandler(500)
def server_error(_):    return "Internal error", 500


# =============================================
# STARTUP
# =============================================
def print_configuration():
    lines = ["=" * 60, "                    DDNS SERVER CONFIGURATION", "=" * 60, ""]
    lines += [f"PROVIDER     : {PROVIDER}", ""]

    if PROVIDER == "multi":
        lines += [f"ENDPOINTS    : {len(ENDPOINTS)} configured"]
        for host, ep in ENDPOINTS.items():
            lines += [f"  {host}  ({ep.get('provider', '?')})"]
    elif PROVIDER == "duckdns":
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
        "# DDNS Auth",
        f"DDNS_USERNAME: {DDNS_USERNAME or 'NOT SET'}",
        f"DDNS_PASSWORD: {'*' * len(DDNS_PASSWORD) if DDNS_PASSWORD else 'NOT SET'}",
        "",
        "# Server",
        f"HOST         : {SERVER_HOST}",
        f"PORT         : {SERVER_PORT}",
        f"TRUST_PROXY  : {TRUST_PROXY}",
        "",
        "=" * 60,
    ]
    for line in lines:
        print(line)


if __name__ == "__main__":
    logger.info(f"Starting DDNS server [{PROVIDER}] — {SERVER_HOST}:{SERVER_PORT}")
    print_configuration()
    app.run(host=SERVER_HOST, port=SERVER_PORT, debug=DEBUG_MODE)
