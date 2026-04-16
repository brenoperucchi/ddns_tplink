#!/bin/bash

# setup_nginx.sh — Configure nginx as TLS reverse proxy for the DDNS server
#
# Designed for hosts where ports 80/443 are already in use by another
# stack (e.g. kamal-proxy, docker). Nginx binds to a custom HTTPS port
# (default 8443). TLS certificate is obtained via DNS-01 challenge using
# the DigitalOcean API token already in .env, so no port 80 is needed.
#
# This script:
#   1. Cleans up any leftover state from previous runs
#   2. Installs nginx, certbot, and the DigitalOcean DNS plugin
#   3. Asks for the public hostname (must already point here)
#   4. Obtains a Let's Encrypt certificate via DNS-01
#   5. Writes an nginx vhost on the chosen port (default 8443)
#   6. Reloads nginx
#
# REQUIREMENTS:
#   - sudo access
#   - .env already configured (./install.sh run)
#   - A DNS A record pointing to this server's public IP
#   - The chosen HTTPS port free and reachable from the internet

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${GREEN}${BOLD}"
echo "============================================================"
echo "      Nginx + TLS (custom port) Setup for DDNS Server"
echo "============================================================"
echo -e "${NC}"
echo -e "This script sets up nginx as an HTTPS reverse proxy in front"
echo -e "of the DDNS server. It binds to a CUSTOM port (default 8443)"
echo -e "so it does not conflict with anything already on 80/443."
echo ""
echo -e "${YELLOW}Requirements:${NC}"
echo "  1. Public DNS A record already pointing to this server."
echo "  2. The chosen HTTPS port (8443 by default) open in the firewall."
echo "  3. Valid DigitalOcean API token in .env (used for DNS-01 cert"
echo "     validation; no port 80 required)."
echo "  4. sudo privileges."
echo ""
read -r -p "Press Enter to continue or Ctrl+C to abort..."

# =============================================
# Check for .env
# =============================================
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${RED}Error: .env not found. Run ./install.sh first.${NC}"
    exit 1
fi

# Read values from .env
INTERNAL_PORT=$(grep -E "^PORT=" "$SCRIPT_DIR/.env" | cut -d= -f2 | tr -d ' \r\n')
INTERNAL_PORT=${INTERNAL_PORT:-9876}

DO_TOKEN=$(grep -E "^TOKEN=" "$SCRIPT_DIR/.env" | cut -d= -f2- | tr -d ' \r\n')
if [ -z "$DO_TOKEN" ]; then
    echo -e "${RED}Error: TOKEN not set in .env.${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}${BOLD}── Step 1/6: Public hostname ──${NC}"
echo ""
echo -e "  ${CYAN}What is this?${NC}"
echo "  The hostname pointing to THIS server's static IP."
echo "  (Not the dynamic DDNS record — a fixed one for this server.)"
echo ""
while true; do
    read -r -p "  Public hostname (e.g. ddns.example.com): " PUBLIC_HOSTNAME
    if [[ "$PUBLIC_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then
        break
    fi
    echo -e "  ${RED}Invalid hostname. Try again.${NC}"
done

echo ""
echo -e "${BLUE}${BOLD}── Step 2/6: Email for Let's Encrypt ──${NC}"
echo ""
echo -e "  Used for cert expiration reminders. Required by Let's Encrypt."
echo ""
while true; do
    read -r -p "  Your email address: " LE_EMAIL
    if [[ "$LE_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        break
    fi
    echo -e "  ${RED}Invalid email. Try again.${NC}"
done

echo ""
echo -e "${BLUE}${BOLD}── Step 3/6: HTTPS port ──${NC}"
echo ""
echo -e "  ${CYAN}What is this?${NC}"
echo "  The public HTTPS port nginx will listen on. Default 8443."
echo "  This is the port the router will connect to."
echo ""
read -r -p "  HTTPS port [8443]: " HTTPS_PORT
HTTPS_PORT=${HTTPS_PORT:-8443}

if ! [[ "$HTTPS_PORT" =~ ^[0-9]+$ ]] || [ "$HTTPS_PORT" -lt 1 ] || [ "$HTTPS_PORT" -gt 65535 ]; then
    echo -e "${RED}Invalid port.${NC}"
    exit 1
fi

# Warn if port already in use by something else
if sudo ss -tlnp "sport = :$HTTPS_PORT" 2>/dev/null | grep -q LISTEN; then
    echo ""
    echo -e "  ${YELLOW}WARNING: Port ${HTTPS_PORT} already in use:${NC}"
    sudo ss -tlnp "sport = :$HTTPS_PORT" 2>/dev/null | tail -n +2
    echo ""
    read -r -p "  Continue anyway? [y/N]: " CONT
    CONT=${CONT:-N}
    [[ ! "$CONT" =~ ^[Yy]$ ]] && exit 1
fi

# =============================================
# Step 4: Clean up any previous broken state
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Step 4/6: Clean up previous state ──${NC}"
echo ""
if [ -f /etc/nginx/sites-enabled/ddns-server ] || [ -L /etc/nginx/sites-enabled/ddns-server ]; then
    echo -e "  ${YELLOW}Removing old /etc/nginx/sites-enabled/ddns-server${NC}"
    sudo rm -f /etc/nginx/sites-enabled/ddns-server
fi
if [ -f /etc/nginx/sites-available/ddns-server ]; then
    echo -e "  ${YELLOW}Removing old /etc/nginx/sites-available/ddns-server${NC}"
    sudo rm -f /etc/nginx/sites-available/ddns-server
fi
if [ -f /etc/nginx/conf.d/ddns-http.conf ]; then
    echo -e "  ${YELLOW}Removing old /etc/nginx/conf.d/ddns-http.conf${NC}"
    sudo rm -f /etc/nginx/conf.d/ddns-http.conf
fi
echo -e "  ${GREEN}Previous DDNS nginx configs cleared.${NC}"

# =============================================
# Step 5: Install packages
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Step 5/6: Install packages ──${NC}"
echo ""

NEEDED=""
command -v nginx     &>/dev/null || NEEDED="$NEEDED nginx"
command -v certbot   &>/dev/null || NEEDED="$NEEDED certbot"
dpkg -s python3-certbot-dns-digitalocean &>/dev/null || NEEDED="$NEEDED python3-certbot-dns-digitalocean"

if [ -n "$NEEDED" ]; then
    echo -e "  ${YELLOW}Installing:${NEEDED}${NC}"
    sudo apt update
    sudo apt install -y $NEEDED
else
    echo -e "  ${GREEN}All packages already installed.${NC}"
fi

# Verify DNS resolves
echo ""
echo -e "  ${YELLOW}Verifying DNS...${NC}"
SERVER_IP=$(curl -s -4 https://api.ipify.org || echo "")
RESOLVED_IP=$(getent ahosts "$PUBLIC_HOSTNAME" 2>/dev/null | awk 'NR==1{print $1}')

echo -e "  This server's public IP: ${BOLD}${SERVER_IP:-unknown}${NC}"
echo -e "  ${PUBLIC_HOSTNAME} resolves to: ${BOLD}${RESOLVED_IP:-unresolved}${NC}"

if [ -z "$RESOLVED_IP" ]; then
    echo -e "  ${RED}DNS does not resolve. Create the A record and wait for propagation.${NC}"
    exit 1
fi
if [ -n "$SERVER_IP" ] && [ "$RESOLVED_IP" != "$SERVER_IP" ]; then
    echo -e "  ${YELLOW}WARNING: DNS resolves to ${RESOLVED_IP} but server is ${SERVER_IP}.${NC}"
    read -r -p "  Continue anyway? [y/N]: " CONT
    CONT=${CONT:-N}
    [[ ! "$CONT" =~ ^[Yy]$ ]] && exit 1
else
    echo -e "  ${GREEN}DNS looks good.${NC}"
fi

# =============================================
# Step 6: DNS-01 cert + nginx vhost
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Step 6/6: Obtain cert (DNS-01) and configure nginx ──${NC}"
echo ""

# Write DO credentials file for certbot
DO_CREDS="/etc/letsencrypt/digitalocean.ini"
echo -e "  ${YELLOW}Writing DigitalOcean credentials for cert renewal...${NC}"
TMP_CREDS=$(mktemp)
cat > "$TMP_CREDS" << DOCREDS
# DigitalOcean API credentials used by certbot-dns-digitalocean
# Used only for DNS-01 challenge during cert issuance & renewal.
dns_digitalocean_token = ${DO_TOKEN}
DOCREDS
sudo mkdir -p /etc/letsencrypt
sudo mv "$TMP_CREDS" "$DO_CREDS"
sudo chmod 600 "$DO_CREDS"
sudo chown root:root "$DO_CREDS"

CERT_PATH="/etc/letsencrypt/live/${PUBLIC_HOSTNAME}/fullchain.pem"
if sudo test -f "$CERT_PATH"; then
    echo -e "  ${GREEN}Certificate already exists. Skipping issuance.${NC}"
else
    echo -e "  ${YELLOW}Requesting certificate via DNS-01...${NC}"
    echo -e "  ${CYAN}(This creates a temporary TXT record via DO API, waits for"
    echo -e "  propagation, then removes it. May take 30-60 seconds.)${NC}"
    sudo certbot certonly \
        --dns-digitalocean \
        --dns-digitalocean-credentials "$DO_CREDS" \
        --dns-digitalocean-propagation-seconds 60 \
        -d "$PUBLIC_HOSTNAME" \
        --email "$LE_EMAIL" \
        --agree-tos \
        --non-interactive

    if ! sudo test -f "$CERT_PATH"; then
        echo -e "  ${RED}Certbot did not produce a certificate at ${CERT_PATH}. Aborting.${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}Certificate obtained.${NC}"
fi

# Write http-context conf (rate limit zone + log format)
echo ""
echo -e "  ${YELLOW}Writing nginx configuration...${NC}"

TMP_HTTP=$(mktemp)
cat > "$TMP_HTTP" << 'NGINXHTTP'
# DDNS Server - http-context directives
# Rate limit: 10 req/min per client IP (burst handled in server block)
limit_req_zone $binary_remote_addr zone=ddns_limit:10m rate=10r/m;

# Access log format WITHOUT query string. DDNS credentials travel in the
# query string, so we must never log them.
log_format ddns_nolog '$remote_addr - $remote_user [$time_local] '
                     '"$request_method $uri $server_protocol" $status '
                     '$body_bytes_sent "$http_user_agent"';
NGINXHTTP
sudo mv "$TMP_HTTP" /etc/nginx/conf.d/ddns-http.conf
sudo chmod 644 /etc/nginx/conf.d/ddns-http.conf

# Write vhost
TMP_CONF=$(mktemp)
cat > "$TMP_CONF" << NGINXCONF
# DDNS Server - nginx vhost on custom HTTPS port ${HTTPS_PORT}
# Generated by setup_nginx.sh
# Note: log_format and limit_req_zone live in /etc/nginx/conf.d/ddns-http.conf
# This vhost does NOT bind to 80 or 443 — those are owned by other services.

server {
    listen ${HTTPS_PORT} ssl;
    listen [::]:${HTTPS_PORT} ssl;
    http2 on;
    server_name ${PUBLIC_HOSTNAME};

    ssl_certificate     /etc/letsencrypt/live/${PUBLIC_HOSTNAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${PUBLIC_HOSTNAME}/privkey.pem;

    # Hardened TLS
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer always;

    server_tokens off;
    access_log /var/log/nginx/ddns-access.log ddns_nolog;
    error_log  /var/log/nginx/ddns-error.log warn;

    client_max_body_size 4k;

    location = /ddns/update {
        limit_req zone=ddns_limit burst=5 nodelay;

        proxy_pass http://127.0.0.1:${INTERNAL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 15s;
        proxy_connect_timeout 5s;
    }

    location = /health {
        proxy_pass http://127.0.0.1:${INTERNAL_PORT};
        proxy_set_header Host \$host;
    }

    location / {
        return 404;
    }
}
NGINXCONF

sudo mv "$TMP_CONF" /etc/nginx/sites-available/ddns-server
sudo chmod 644 /etc/nginx/sites-available/ddns-server
sudo ln -sf /etc/nginx/sites-available/ddns-server /etc/nginx/sites-enabled/ddns-server

echo ""
echo -e "  ${YELLOW}Testing nginx config...${NC}"
if ! sudo nginx -t; then
    echo -e "  ${RED}Nginx config test failed. See error above.${NC}"
    exit 1
fi

# Start or reload nginx. If nginx was in a failed state from a previous
# broken config, systemctl reload may fail; try restart as fallback.
if sudo systemctl is-active --quiet nginx; then
    sudo systemctl reload nginx || sudo systemctl restart nginx
else
    sudo systemctl start nginx
fi

# =============================================
# Firewall
# =============================================
if command -v ufw &>/dev/null; then
    echo ""
    echo -e "  ${YELLOW}Opening port ${HTTPS_PORT} in ufw (if active)...${NC}"
    sudo ufw allow "$HTTPS_PORT"/tcp || true
fi

# =============================================
# Done
# =============================================
DDNS_USERNAME=$(grep -E "^DDNS_USERNAME=" "$SCRIPT_DIR/.env" | cut -d= -f2 | tr -d ' \r\n')
DDNS_PASSWORD=$(grep -E "^DDNS_PASSWORD=" "$SCRIPT_DIR/.env" | cut -d= -f2- | tr -d ' \r\n')
DOMAIN=$(grep -E "^DOMAIN=" "$SCRIPT_DIR/.env" | cut -d= -f2 | tr -d ' \r\n')

echo ""
echo -e "${GREEN}${BOLD}"
echo "============================================================"
echo "                 Nginx + TLS Setup Complete!"
echo "============================================================"
echo -e "${NC}"
echo -e "  ${BOLD}Your DDNS endpoint is now:${NC}"
echo -e "    ${BOLD}https://${PUBLIC_HOSTNAME}:${HTTPS_PORT}/ddns/update${NC}"
echo ""
echo -e "  ${BOLD}Test it manually:${NC}"
echo "    curl \"https://${PUBLIC_HOSTNAME}:${HTTPS_PORT}/ddns/update?username=${DDNS_USERNAME}&password=${DDNS_PASSWORD}&hostname=home.${DOMAIN}&ip=\$(curl -s https://api.ipify.org)\""
echo ""
echo -e "  ${BOLD}TP-Link ER605 DDNS settings (Network > Dynamic DNS > Custom):${NC}"
echo -e "    Service Provider: ${BOLD}Custom${NC}"
echo -e "    Server URL:       ${BOLD}https://${PUBLIC_HOSTNAME}:${HTTPS_PORT}/ddns/update?hostname=[DOMAIN]&myip=[IP]&username=[USERNAME]&password=[PASSWORD]${NC}"
echo -e "    Domain Name:      ${BOLD}home.${DOMAIN}${NC}"
echo -e "    Username:         ${BOLD}${DDNS_USERNAME}${NC}"
echo -e "    Password:         ${BOLD}${DDNS_PASSWORD}${NC}"
echo ""
echo -e "  ${YELLOW}Reminder:${NC} you must open port ${HTTPS_PORT}/tcp in your cloud"
echo -e "  firewall (DigitalOcean Networking > Firewalls, if you use one)."
echo ""
echo -e "  ${YELLOW}Cert auto-renewal:${NC} handled by certbot's systemd timer."
echo -e "  Check with: sudo systemctl status certbot.timer"
echo ""
