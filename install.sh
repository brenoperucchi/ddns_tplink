#!/bin/bash

# DDNS TP-Link Server - Interactive Installer
# This script configures the .env file and prepares the server to run.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
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
echo "         DDNS TP-Link Server - Interactive Installer"
echo "============================================================"
echo -e "${NC}"
echo -e "This script will guide you through the configuration of"
echo -e "the DDNS server that updates DNS records on DigitalOcean."
echo ""
echo -e "${YELLOW}You will need:${NC}"
echo "  - A DigitalOcean account with a domain configured"
echo "  - A DigitalOcean API token"
echo ""
echo -e "Press ${BOLD}Enter${NC} to continue or ${BOLD}Ctrl+C${NC} to cancel..."
read -r

# =============================================
# STEP 1: DigitalOcean API Token
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Step 1/6: DigitalOcean API Token ──${NC}"
echo ""
echo -e "  ${CYAN}Where to get it:${NC}"
echo "  1. Log in to https://cloud.digitalocean.com"
echo "  2. Go to API > Tokens > Generate New Token"
echo "  3. Give it a name (e.g. 'ddns-server')"
echo "  4. Select 'Read' and 'Write' permissions"
echo "  5. Copy the generated token"
echo ""
while true; do
    read -r -s -p "  Paste your API Token (input is hidden): " TOKEN
    echo ""
    if [ -z "$TOKEN" ]; then
        echo -e "  ${RED}Token cannot be empty. Try again.${NC}"
    elif [ ${#TOKEN} -lt 20 ]; then
        echo -e "  ${RED}Token seems too short. Try again.${NC}"
    else
        break
    fi
done
echo -e "  ${GREEN}Token saved.${NC}"

# =============================================
# STEP 2: Domain
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Step 2/6: Domain ──${NC}"
echo ""
echo -e "  ${CYAN}Where to get it:${NC}"
echo "  1. Go to https://cloud.digitalocean.com/networking/domains"
echo "  2. Your domain must be listed there (e.g. example.com)"
echo "  3. If it's not there, add it and point your domain's"
echo "     nameservers to DigitalOcean (ns1.digitalocean.com, etc.)"
echo ""
while true; do
    read -r -p "  Enter your domain (e.g. example.com): " DOMAIN
    if [ -z "$DOMAIN" ]; then
        echo -e "  ${RED}Domain cannot be empty. Try again.${NC}"
    else
        break
    fi
done

# =============================================
# STEP 3: Record ID (auto-detect or manual)
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Step 3/6: DNS Record ID ──${NC}"
echo ""
echo -e "  Fetching DNS records for ${BOLD}${DOMAIN}${NC} ..."
echo ""

RECORDS_JSON=$(curl -s -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://api.digitalocean.com/v2/domains/${DOMAIN}/records?type=A&per_page=100" 2>/dev/null)

# Check if API call succeeded
if echo "$RECORDS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'domain_records' in d" 2>/dev/null; then
    # Parse and display A records
    RECORD_COUNT=$(echo "$RECORDS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data.get('domain_records', [])
print(len(records))
")

    if [ "$RECORD_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}Found ${RECORD_COUNT} A record(s):${NC}"
        echo ""
        echo "$RECORDS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data.get('domain_records', [])
for i, r in enumerate(records, 1):
    name = r.get('name', '?')
    rid = r.get('id', '?')
    ip = r.get('data', '?')
    if name == '@':
        display = '${DOMAIN}'
    else:
        display = f\"{name}.${DOMAIN}\"
    print(f'    {i}) {display}  (ID: {rid}, IP: {ip})')
"
        echo ""
        echo -e "  ${CYAN}Which record should be updated by the DDNS server?${NC}"
        echo -e "  Enter the ${BOLD}number${NC} from the list above, or type a ${BOLD}Record ID${NC} manually."
        echo ""
        while true; do
            read -r -p "  Your choice: " CHOICE
            if [ -z "$CHOICE" ]; then
                echo -e "  ${RED}Cannot be empty. Try again.${NC}"
                continue
            fi
            # If it's a small number, treat as list index
            if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -le "$RECORD_COUNT" ] && [ "$CHOICE" -ge 1 ]; then
                RECORD_ID=$(echo "$RECORDS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data.get('domain_records', [])
print(records[${CHOICE}-1]['id'])
")
                RECORD_NAME=$(echo "$RECORDS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
records = data.get('domain_records', [])
r = records[${CHOICE}-1]
name = r.get('name', '?')
if name == '@':
    print('${DOMAIN}')
else:
    print(f\"{name}.${DOMAIN}\")
")
                echo -e "  ${GREEN}Selected: ${RECORD_NAME} (ID: ${RECORD_ID})${NC}"
                break
            elif [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -gt "$RECORD_COUNT" ]; then
                # Treat as manual Record ID
                RECORD_ID="$CHOICE"
                echo -e "  ${GREEN}Using Record ID: ${RECORD_ID}${NC}"
                break
            else
                echo -e "  ${RED}Invalid choice. Try again.${NC}"
            fi
        done
    else
        echo -e "  ${YELLOW}No A records found for ${DOMAIN}.${NC}"
        echo ""
        echo -e "  ${CYAN}How to create one:${NC}"
        echo "  1. Go to https://cloud.digitalocean.com/networking/domains/${DOMAIN}"
        echo "  2. Add an A record (e.g. 'home' -> any IP like 1.2.3.4)"
        echo "  3. Run this installer again, or enter the Record ID manually."
        echo ""
        while true; do
            read -r -p "  Enter Record ID manually (or press Ctrl+C to cancel): " RECORD_ID
            if [ -z "$RECORD_ID" ]; then
                echo -e "  ${RED}Record ID cannot be empty. Try again.${NC}"
            else
                break
            fi
        done
    fi
else
    echo -e "  ${RED}Could not fetch records from DigitalOcean API.${NC}"
    echo -e "  Possible causes: invalid token, domain not found, or network error."
    echo ""
    echo -e "  ${CYAN}How to find the Record ID manually:${NC}"
    echo "  1. Go to https://cloud.digitalocean.com/networking/domains/${DOMAIN}"
    echo "  2. Use the API directly:"
    echo "     curl -s -H 'Authorization: Bearer YOUR_TOKEN' \\"
    echo "       'https://api.digitalocean.com/v2/domains/${DOMAIN}/records?type=A'"
    echo "  3. Look for the 'id' field of the A record you want to update"
    echo ""
    while true; do
        read -r -p "  Enter Record ID manually: " RECORD_ID
        if [ -z "$RECORD_ID" ]; then
            echo -e "  ${RED}Record ID cannot be empty. Try again.${NC}"
        else
            break
        fi
    done
fi

# =============================================
# STEP 4: DDNS Username
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Step 4/6: DDNS Username ──${NC}"
echo ""
echo -e "  ${CYAN}What is this?${NC}"
echo "  This is the username your TP-Link router (or other DDNS client)"
echo "  will use to authenticate with this server."
echo "  Choose any username you like (e.g. 'ddns', 'admin', 'router')."
echo ""
while true; do
    read -r -p "  Choose a DDNS username: " DDNS_USERNAME
    if [ -z "$DDNS_USERNAME" ]; then
        echo -e "  ${RED}Username cannot be empty. Try again.${NC}"
    else
        break
    fi
done

# =============================================
# STEP 5: DDNS Password (auto-generated)
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Step 5/6: DDNS Password ──${NC}"
echo ""
echo -e "  ${CYAN}What is this?${NC}"
echo "  A strong password, auto-generated now, that your TP-Link router"
echo "  (ER605 or similar) will use to authenticate with this server."
echo "  Uses URL-safe characters so it works in the router's DDNS fields."
echo ""
DDNS_PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(24))")
echo -e "  ${GREEN}${BOLD}Generated password:${NC} ${BOLD}${DDNS_PASSWORD}${NC}"
echo -e "  ${YELLOW}IMPORTANT: Save this password now! You'll need it when"
echo -e "  configuring the DDNS client on your TP-Link ER605.${NC}"
echo ""
read -r -p "  Press Enter after saving the password..."

# =============================================
# STEP 6: Server Port
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Step 6/6: Server Port ──${NC}"
echo ""
echo -e "  ${CYAN}What is this?${NC}"
echo "  Internal port this server listens on (localhost only)."
echo "  If using nginx + TLS (recommended), the router will connect"
echo "  on port 443 and nginx forwards to this internal port."
echo ""
read -r -p "  Server port [9876]: " PORT
PORT=${PORT:-9876}

# =============================================
# SUMMARY
# =============================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "============================================================"
echo "                   Configuration Summary"
echo "============================================================"
echo -e "${NC}"
echo -e "  TOKEN          : ${BOLD}${TOKEN:0:8}...${TOKEN: -4}${NC}"
echo -e "  DOMAIN         : ${BOLD}${DOMAIN}${NC}"
echo -e "  RECORD_ID      : ${BOLD}${RECORD_ID}${NC}"
echo -e "  DDNS_USERNAME  : ${BOLD}${DDNS_USERNAME}${NC}"
echo -e "  DDNS_PASSWORD  : ${BOLD}${DDNS_PASSWORD}${NC}"
echo -e "  PORT           : ${BOLD}${PORT}${NC}"
echo ""
echo -e "${GREEN}============================================================${NC}"
echo ""
read -r -p "  Is this correct? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo -e "${RED}Installation cancelled. Run this script again to restart.${NC}"
    exit 1
fi

# =============================================
# WRITE .env FILE
# =============================================
echo ""
echo -e "${YELLOW}Writing .env file...${NC}"

cat > "$SCRIPT_DIR/.env" << ENVEOF
# DDNS Server Configuration
# Generated by install.sh on $(date '+%Y-%m-%d %H:%M:%S')

# DigitalOcean API Configuration
TOKEN=${TOKEN}
DOMAIN=${DOMAIN}
RECORD_ID=${RECORD_ID}

# DDNS Authentication
DDNS_USERNAME=${DDNS_USERNAME}
DDNS_PASSWORD=${DDNS_PASSWORD}

# Server Configuration
# HOST=127.0.0.1 keeps the app bound to loopback; nginx (port 443) is the
# only entry point from the internet. Change to 0.0.0.0 ONLY if you want
# gunicorn exposed directly (not recommended - no TLS).
HOST=127.0.0.1
PORT=${PORT}
DEBUG=false

# Set TRUST_PROXY=true when running behind nginx so rate limiting and logs
# use the real client IP from X-Forwarded-For.
TRUST_PROXY=true
ENVEOF

chmod 600 "$SCRIPT_DIR/.env"
echo -e "  ${GREEN}.env file created with restricted permissions (600).${NC}"

# =============================================
# INSTALL DEPENDENCIES
# =============================================
echo ""
echo -e "${YELLOW}Checking dependencies...${NC}"

if python3 -c "import flask, requests, dotenv, gunicorn" 2>/dev/null; then
    echo -e "  ${GREEN}All dependencies are already installed.${NC}"
else
    echo -e "  ${YELLOW}Installing dependencies...${NC}"
    if [ -d "$SCRIPT_DIR/.venv" ]; then
        source "$SCRIPT_DIR/.venv/bin/activate"
        pip install -r "$SCRIPT_DIR/requirements.txt"
    elif command -v pip3 &>/dev/null; then
        pip3 install --user -r "$SCRIPT_DIR/requirements.txt"
    elif python3 -m pip --version &>/dev/null; then
        python3 -m pip install --user --break-system-packages -r "$SCRIPT_DIR/requirements.txt"
    else
        echo -e "  ${RED}Could not install dependencies automatically.${NC}"
        echo -e "  Please install manually: pip install -r requirements.txt"
    fi
fi

# =============================================
# TEST CONNECTION
# =============================================
echo ""
echo -e "${YELLOW}Testing DigitalOcean API connection...${NC}"

TEST_RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://api.digitalocean.com/v2/domains/${DOMAIN}/records/${RECORD_ID}")

if [ "$TEST_RESULT" = "200" ]; then
    CURRENT_IP=$(curl -s \
        -H "Authorization: Bearer ${TOKEN}" \
        "https://api.digitalocean.com/v2/domains/${DOMAIN}/records/${RECORD_ID}" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['domain_record']['data'])" 2>/dev/null)
    echo -e "  ${GREEN}API connection successful!${NC}"
    echo -e "  Current IP in DNS: ${BOLD}${CURRENT_IP}${NC}"
elif [ "$TEST_RESULT" = "401" ]; then
    echo -e "  ${RED}Authentication failed. Check your API token.${NC}"
elif [ "$TEST_RESULT" = "404" ]; then
    echo -e "  ${RED}Record not found. Check your domain and record ID.${NC}"
else
    echo -e "  ${RED}Unexpected response (HTTP ${TEST_RESULT}). Check your settings.${NC}"
fi

# =============================================
# DONE
# =============================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "============================================================"
echo "                  Installation Complete!"
echo "============================================================"
echo -e "${NC}"
echo -e "  ${BOLD}To start the server:${NC}"
echo "    cd $SCRIPT_DIR"
echo "    python3 ddns_server.py"
echo ""
echo -e "  ${BOLD}To start in production (Gunicorn):${NC}"
echo "    ./start_production.sh"
echo ""
echo -e "  ${BOLD}To install as a systemd service:${NC}"
echo "    sudo cp ddns-server.service.example /etc/systemd/system/ddns-server.service"
echo "    sudo nano /etc/systemd/system/ddns-server.service  # adjust paths"
echo "    sudo systemctl daemon-reload"
echo "    sudo systemctl enable --now ddns-server"
echo ""
echo -e "  ${BOLD}Next step - set up nginx + TLS (recommended):${NC}"
echo "    ./setup_nginx.sh"
echo ""
echo -e "  ${BOLD}TP-Link ER605 DDNS config (after nginx is ready):${NC}"
echo -e "    Service Provider: ${BOLD}Custom${NC} (or 'Others')"
echo -e "    Server URL:       ${BOLD}https://ddns.YOUR_DOMAIN/ddns/update?hostname=[DOMAIN]&myip=[IP]&username=[USERNAME]&password=[PASSWORD]${NC}"
echo -e "    Domain Name:      ${BOLD}home.${DOMAIN}${NC}"
echo -e "    Username:         ${BOLD}${DDNS_USERNAME}${NC}"
echo -e "    Password:         ${BOLD}${DDNS_PASSWORD}${NC}"
echo -e "    ${YELLOW}([DOMAIN],[IP],[USERNAME],[PASSWORD] are literal placeholders)${NC}"
echo ""
echo -e "  ${BOLD}Local test:${NC}"
echo "    curl \"http://127.0.0.1:${PORT}/ddns/update?username=${DDNS_USERNAME}&password=${DDNS_PASSWORD}&hostname=home.${DOMAIN}&ip=$(curl -s https://api.ipify.org 2>/dev/null || echo 1.2.3.4)\""
echo ""
