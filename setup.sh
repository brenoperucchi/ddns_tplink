#!/bin/bash

# DDNS TP-Link Server — Unified Setup Script
# Configures .env, creates virtualenv, installs dependencies,
# optionally sets up nginx + TLS, and optionally installs a systemd service.
#
# DNS providers: DigitalOcean, Cloudflare
# Linux distros: Debian/Ubuntu (apt), RHEL/Fedora (dnf), Arch (pacman),
#                openSUSE (zypper), Alpine (apk)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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
echo "          DDNS TP-Link Server — Setup"
echo "============================================================"
echo -e "${NC}"
echo -e "This script will:"
echo -e "  1. Choose your DNS provider and collect credentials"
echo -e "  2. Create a virtual environment and install dependencies"
echo -e "  3. Optionally set up nginx + TLS"
echo -e "  4. Optionally install as a systemd service"
echo ""
echo -e "${YELLOW}Supported DNS providers:${NC}"
echo "  - DuckDNS      (free, no domain needed — recommended for new users)"
echo "  - Cloudflare   (free with your own domain)"
echo "  - DigitalOcean (for existing DigitalOcean users)"
echo ""
echo -e "Press ${BOLD}Enter${NC} to continue or ${BOLD}Ctrl+C${NC} to cancel..."
read -r

# =============================================
# DETECT PACKAGE MANAGER
# =============================================
detect_pkg_manager() {
    if command -v apt &>/dev/null; then echo "apt"
    elif command -v dnf &>/dev/null; then echo "dnf"
    elif command -v pacman &>/dev/null; then echo "pacman"
    elif command -v zypper &>/dev/null; then echo "zypper"
    elif command -v apk &>/dev/null; then echo "apk"
    else echo ""
    fi
}
PKG_MANAGER=$(detect_pkg_manager)

# =============================================
# CHECK REQUIRED TOOLS
# =============================================
echo -e "${YELLOW}Checking required tools...${NC}"

MISSING_TOOLS=""
for tool in python3 curl; do
    command -v "$tool" &>/dev/null || MISSING_TOOLS="$MISSING_TOOLS $tool"
done

if [ -n "$MISSING_TOOLS" ]; then
    echo -e "${RED}Missing required tools:${MISSING_TOOLS}${NC}"
    [ -n "$PKG_MANAGER" ] && echo -e "Install with: sudo $PKG_MANAGER install${MISSING_TOOLS}"
    exit 1
fi

PY_MAJOR=$(python3 -c "import sys; print(sys.version_info.major)")
PY_MINOR=$(python3 -c "import sys; print(sys.version_info.minor)")
PY_VERSION="${PY_MAJOR}.${PY_MINOR}"

if [ "$PY_MAJOR" -lt 3 ] || ([ "$PY_MAJOR" -eq 3 ] && [ "$PY_MINOR" -lt 8 ]); then
    echo -e "${RED}Python 3.8+ required. Found: ${PY_VERSION}${NC}"
    exit 1
fi
echo -e "  ${GREEN}python3 ${PY_VERSION} — OK${NC}"
echo -e "  ${GREEN}curl — OK${NC}"

# =============================================
# STEP 0: Choose DNS provider
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Provider selection ──${NC}"
echo ""
echo -e "  ${BOLD}1)${NC} DuckDNS      — free, no domain needed. Get a subdomain at duckdns.org ${GREEN}[default]${NC}"
echo -e "  ${BOLD}2)${NC} Cloudflare   — free with your own domain (most robust option)"
echo -e "  ${BOLD}3)${NC} DigitalOcean — for existing DigitalOcean DNS users"
echo ""
while true; do
    read -r -p "  Choose provider [1/2/3] (default: 1): " PROVIDER_CHOICE
    PROVIDER_CHOICE=${PROVIDER_CHOICE:-1}
    case "$PROVIDER_CHOICE" in
        1) PROVIDER="duckdns";      break ;;
        2) PROVIDER="cloudflare";   break ;;
        3) PROVIDER="digitalocean"; break ;;
        *) echo -e "  ${RED}Enter 1, 2 or 3.${NC}" ;;
    esac
done
echo -e "  ${GREEN}Provider: ${BOLD}${PROVIDER}${NC}"

# =============================================
# PROVIDER-SPECIFIC CREDENTIAL STEPS
# =============================================

if [ "$PROVIDER" = "duckdns" ]; then

    # --- Step 1: DuckDNS Token ---
    echo ""
    echo -e "${BLUE}${BOLD}── Step 1/6: DuckDNS Token ──${NC}"
    echo ""
    echo -e "  ${CYAN}Where to get it:${NC}"
    echo "  1. Create a free account at https://www.duckdns.org"
    echo "  2. Your token is shown at the top of the page after login"
    echo ""
    while true; do
        read -r -s -p "  Paste your DuckDNS token (input is hidden): " DUCK_TOKEN
        echo ""
        if [ -z "$DUCK_TOKEN" ]; then
            echo -e "  ${RED}Token cannot be empty.${NC}"
        elif [ ${#DUCK_TOKEN} -lt 10 ]; then
            echo -e "  ${RED}Token seems too short.${NC}"
        else
            break
        fi
    done
    echo -e "  ${GREEN}Token saved.${NC}"

    # --- Step 2: DuckDNS subdomain ---
    echo ""
    echo -e "${BLUE}${BOLD}── Step 2/6: DuckDNS subdomain ──${NC}"
    echo ""
    echo -e "  ${CYAN}What is this?${NC}"
    echo "  The subdomain you created on duckdns.org (e.g. 'myhome' → myhome.duckdns.org)."
    echo "  This is the record your router will keep updated."
    echo "  Enter only the subdomain part, without '.duckdns.org'."
    echo ""
    while true; do
        read -r -p "  DuckDNS subdomain: " DUCK_SUBDOMAIN
        if [ -z "$DUCK_SUBDOMAIN" ]; then
            echo -e "  ${RED}Subdomain cannot be empty.${NC}"
        elif [[ "$DUCK_SUBDOMAIN" =~ \. ]]; then
            echo -e "  ${RED}Enter only the subdomain part (e.g. 'myhome', not 'myhome.duckdns.org').${NC}"
        else
            break
        fi
    done
    DOMAIN="${DUCK_SUBDOMAIN}.duckdns.org"
    echo -e "  ${GREEN}Full hostname: ${BOLD}${DOMAIN}${NC}"

    # --- Step 3: Validate token via API ---
    echo ""
    echo -e "  ${YELLOW}Validating DuckDNS token...${NC}"
    DUCK_TEST=$(curl -s "https://www.duckdns.org/update?domains=${DUCK_SUBDOMAIN}&token=${DUCK_TOKEN}&ip=" 2>/dev/null)
    if [ "$DUCK_TEST" = "OK" ]; then
        echo -e "  ${GREEN}Token is valid.${NC}"
    else
        echo -e "  ${YELLOW}Could not validate token (response: '${DUCK_TEST}'). Check your token and subdomain.${NC}"
    fi
    # No separate record ID needed for DuckDNS
    RECORD_ID=""

elif [ "$PROVIDER" = "digitalocean" ]; then

    # --- Step 1: DigitalOcean API Token ---
    echo ""
    echo -e "${BLUE}${BOLD}── Step 1/6: DigitalOcean API Token ──${NC}"
    echo ""
    echo -e "  ${CYAN}Where to get it:${NC}"
    echo "  1. Log in to https://cloud.digitalocean.com"
    echo "  2. Go to API > Tokens > Generate New Token"
    echo "  3. Enable Read + Write permissions"
    echo ""
    while true; do
        read -r -s -p "  Paste your API Token (input is hidden): " DO_TOKEN
        echo ""
        if [ -z "$DO_TOKEN" ]; then
            echo -e "  ${RED}Token cannot be empty.${NC}"
        elif [ ${#DO_TOKEN} -lt 20 ]; then
            echo -e "  ${RED}Token seems too short.${NC}"
        else
            break
        fi
    done
    echo -e "  ${GREEN}Token saved.${NC}"

    # --- Step 2: Domain ---
    echo ""
    echo -e "${BLUE}${BOLD}── Step 2/6: Domain ──${NC}"
    echo ""
    echo -e "  The root domain managed by DigitalOcean DNS (e.g. example.com)."
    echo "  Check: https://cloud.digitalocean.com/networking/domains"
    echo ""
    while true; do
        read -r -p "  Enter your domain: " DOMAIN
        [ -n "$DOMAIN" ] && break
        echo -e "  ${RED}Domain cannot be empty.${NC}"
    done

    # --- Step 3: Record ID (auto-detect) ---
    echo ""
    echo -e "${BLUE}${BOLD}── Step 3/6: DNS Record ID ──${NC}"
    echo ""
    echo -e "  Fetching A records for ${BOLD}${DOMAIN}${NC} ..."
    echo ""

    RECORDS_JSON=$(curl -s -X GET \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${DO_TOKEN}" \
        "https://api.digitalocean.com/v2/domains/${DOMAIN}/records?type=A&per_page=100" 2>/dev/null)

    if echo "$RECORDS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'domain_records' in d" 2>/dev/null; then
        RECORD_COUNT=$(echo "$RECORDS_JSON" | python3 -c "
import sys,json; print(len(json.load(sys.stdin).get('domain_records',[])))
")
        if [ "$RECORD_COUNT" -gt 0 ]; then
            echo -e "  ${GREEN}Found ${RECORD_COUNT} A record(s):${NC}"
            echo ""
            echo "$RECORDS_JSON" | python3 -c "
import sys,json
domain='${DOMAIN}'
data=json.load(sys.stdin)
for i,r in enumerate(data.get('domain_records',[]),1):
    name=r.get('name','?')
    display=domain if name=='@' else f'{name}.{domain}'
    print(f'    {i}) {display}  (ID: {r[\"id\"]}, IP: {r[\"data\"]})')
"
            echo ""
            echo -e "  ${CYAN}Enter the number or a Record ID manually:${NC}"
            while true; do
                read -r -p "  Your choice: " CHOICE
                [ -z "$CHOICE" ] && { echo -e "  ${RED}Cannot be empty.${NC}"; continue; }
                if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$RECORD_COUNT" ]; then
                    RECORD_ID=$(echo "$RECORDS_JSON" | python3 -c "
import sys,json; print(json.load(sys.stdin)['domain_records'][${CHOICE}-1]['id'])
")
                    RECORD_NAME=$(echo "$RECORDS_JSON" | python3 -c "
import sys,json
domain='${DOMAIN}'
r=json.load(sys.stdin)['domain_records'][${CHOICE}-1]
name=r.get('name','?')
print(domain if name=='@' else f'{name}.{domain}')
")
                    echo -e "  ${GREEN}Selected: ${RECORD_NAME} (ID: ${RECORD_ID})${NC}"
                    break
                elif [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
                    RECORD_ID="$CHOICE"
                    echo -e "  ${GREEN}Using Record ID: ${RECORD_ID}${NC}"
                    break
                else
                    echo -e "  ${RED}Invalid choice.${NC}"
                fi
            done
        else
            echo -e "  ${YELLOW}No A records found. Enter Record ID manually.${NC}"
            while true; do
                read -r -p "  Record ID: " RECORD_ID
                [ -n "$RECORD_ID" ] && break
                echo -e "  ${RED}Cannot be empty.${NC}"
            done
        fi
    else
        echo -e "  ${RED}Could not fetch records (invalid token, domain not found, or network error).${NC}"
        while true; do
            read -r -p "  Enter Record ID manually: " RECORD_ID
            [ -n "$RECORD_ID" ] && break
            echo -e "  ${RED}Cannot be empty.${NC}"
        done
    fi

else  # cloudflare

    # --- Step 1: Cloudflare API Token ---
    echo ""
    echo -e "${BLUE}${BOLD}── Step 1/6: Cloudflare API Token ──${NC}"
    echo ""
    echo -e "  ${CYAN}Where to get it:${NC}"
    echo "  1. Log in to https://dash.cloudflare.com"
    echo "  2. Go to My Profile > API Tokens > Create Token"
    echo "  3. Use the 'Edit zone DNS' template"
    echo "  4. Scope: Zone > DNS > Edit  (for your domain)"
    echo ""
    while true; do
        read -r -s -p "  Paste your API Token (input is hidden): " CF_TOKEN
        echo ""
        if [ -z "$CF_TOKEN" ]; then
            echo -e "  ${RED}Token cannot be empty.${NC}"
        elif [ ${#CF_TOKEN} -lt 20 ]; then
            echo -e "  ${RED}Token seems too short.${NC}"
        else
            break
        fi
    done
    echo -e "  ${GREEN}Token saved.${NC}"

    # --- Step 2: Domain → auto-detect Zone ID ---
    echo ""
    echo -e "${BLUE}${BOLD}── Step 2/6: Domain ──${NC}"
    echo ""
    echo -e "  The root domain on Cloudflare (e.g. example.com)."
    echo ""
    while true; do
        read -r -p "  Enter your domain: " DOMAIN
        [ -n "$DOMAIN" ] && break
        echo -e "  ${RED}Domain cannot be empty.${NC}"
    done

    echo ""
    echo -e "  Fetching Zone ID for ${BOLD}${DOMAIN}${NC} ..."
    ZONE_JSON=$(curl -s -X GET \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}&status=active" 2>/dev/null)

    CF_ZONE_ID=$(echo "$ZONE_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
zones=data.get('result',[])
print(zones[0]['id'] if zones else '')
" 2>/dev/null)

    if [ -z "$CF_ZONE_ID" ]; then
        echo -e "  ${RED}Could not find zone for '${DOMAIN}' (check token permissions or domain name).${NC}"
        while true; do
            read -r -p "  Enter Zone ID manually: " CF_ZONE_ID
            [ -n "$CF_ZONE_ID" ] && break
            echo -e "  ${RED}Cannot be empty.${NC}"
        done
    else
        echo -e "  ${GREEN}Zone ID: ${BOLD}${CF_ZONE_ID}${NC}"
    fi

    # --- Step 3: Record ID (auto-detect from zone) ---
    echo ""
    echo -e "${BLUE}${BOLD}── Step 3/6: DNS Record ID ──${NC}"
    echo ""
    echo -e "  Fetching A records for ${BOLD}${DOMAIN}${NC} ..."
    echo ""

    RECORDS_JSON=$(curl -s -X GET \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A&per_page=100" 2>/dev/null)

    RECORD_COUNT=$(echo "$RECORDS_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
print(len(data.get('result',[])))
" 2>/dev/null || echo "0")

    if [ "$RECORD_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}Found ${RECORD_COUNT} A record(s):${NC}"
        echo ""
        echo "$RECORDS_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
for i,r in enumerate(data.get('result',[]),1):
    print(f'    {i}) {r[\"name\"]}  (ID: {r[\"id\"]}, IP: {r[\"content\"]})')
"
        echo ""
        echo -e "  ${CYAN}Enter the number or a Record ID manually:${NC}"
        while true; do
            read -r -p "  Your choice: " CHOICE
            [ -z "$CHOICE" ] && { echo -e "  ${RED}Cannot be empty.${NC}"; continue; }
            if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$RECORD_COUNT" ]; then
                RECORD_ID=$(echo "$RECORDS_JSON" | python3 -c "
import sys,json; print(json.load(sys.stdin)['result'][${CHOICE}-1]['id'])
")
                RECORD_NAME=$(echo "$RECORDS_JSON" | python3 -c "
import sys,json; print(json.load(sys.stdin)['result'][${CHOICE}-1]['name'])
")
                echo -e "  ${GREEN}Selected: ${RECORD_NAME} (ID: ${RECORD_ID})${NC}"
                break
            else
                RECORD_ID="$CHOICE"
                echo -e "  ${GREEN}Using Record ID: ${RECORD_ID}${NC}"
                break
            fi
        done
    else
        echo -e "  ${YELLOW}No A records found. Enter Record ID manually.${NC}"
        while true; do
            read -r -p "  Record ID: " RECORD_ID
            [ -n "$RECORD_ID" ] && break
            echo -e "  ${RED}Cannot be empty.${NC}"
        done
    fi

fi  # end provider-specific steps

# Derive WAN1 hostname (what the router sends as the hostname= parameter)
if [ "$PROVIDER" = "duckdns" ]; then
    WAN1_HOSTNAME="${DUCK_SUBDOMAIN}.duckdns.org"
elif [ -n "${RECORD_NAME:-}" ]; then
    WAN1_HOSTNAME="$RECORD_NAME"
else
    WAN1_HOSTNAME="$DOMAIN"
fi

# =============================================
# STEPS 4-6: DDNS credentials + port (shared)
# =============================================

# --- Step 4: DDNS Username ---
echo ""
echo -e "${BLUE}${BOLD}── Step 4/6: DDNS Username ──${NC}"
echo ""
echo -e "  The username your TP-Link router will send to authenticate."
echo "  Choose any name (e.g. 'ddns', 'router')."
echo ""
while true; do
    read -r -p "  Choose a DDNS username: " DDNS_USERNAME
    [ -n "$DDNS_USERNAME" ] && break
    echo -e "  ${RED}Username cannot be empty.${NC}"
done

# --- Step 5: DDNS Password (auto-generated) ---
echo ""
echo -e "${BLUE}${BOLD}── Step 5/6: DDNS Password ──${NC}"
echo ""
DDNS_PASSWORD=$(python3 -c "import secrets; print(secrets.token_urlsafe(24))")
echo -e "  ${GREEN}${BOLD}Generated password:${NC} ${BOLD}${DDNS_PASSWORD}${NC}"
echo -e "  ${YELLOW}IMPORTANT: Save this now — you will need it in the router.${NC}"
echo ""
read -r -p "  Press Enter after saving the password..."

# --- Step 6: Server Port ---
echo ""
echo -e "${BLUE}${BOLD}── Step 6/6: Server Port ──${NC}"
echo ""
echo -e "  Internal port gunicorn binds to on 127.0.0.1."
echo ""
read -r -p "  Server port [9876]: " PORT
PORT=${PORT:-9876}

# =============================================
# SECOND WAN (optional)
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Optional: Second WAN interface ──${NC}"
echo ""
echo -e "  If your router has two internet connections (WAN + WAN/LAN1),"
echo -e "  each can update a different DNS record independently."
echo ""
read -r -p "  Add a second WAN interface? [y/N]: " SECOND_WAN
SECOND_WAN=${SECOND_WAN:-N}

MULTI_WAN=false
WAN2_PROVIDER=""
WAN2_HOSTNAME=""

if [[ "$SECOND_WAN" =~ ^[Yy]$ ]]; then
    MULTI_WAN=true

    echo ""
    echo -e "${BLUE}${BOLD}── WAN2: Provider ──${NC}"
    echo ""
    echo -e "  ${BOLD}1)${NC} DuckDNS"
    echo -e "  ${BOLD}2)${NC} Cloudflare"
    echo -e "  ${BOLD}3)${NC} DigitalOcean"
    echo ""
    while true; do
        read -r -p "  Provider for WAN2 [1/2/3]: " WAN2_CHOICE
        case "$WAN2_CHOICE" in
            1) WAN2_PROVIDER="duckdns";      break ;;
            2) WAN2_PROVIDER="cloudflare";   break ;;
            3) WAN2_PROVIDER="digitalocean"; break ;;
            *) echo -e "  ${RED}Enter 1, 2 or 3.${NC}" ;;
        esac
    done
    echo -e "  ${GREEN}WAN2 provider: ${BOLD}${WAN2_PROVIDER}${NC}"

    if [ "$WAN2_PROVIDER" = "duckdns" ]; then
        echo ""
        echo -e "${BLUE}${BOLD}── WAN2: DuckDNS credentials ──${NC}"
        echo ""
        while true; do
            read -r -s -p "  DuckDNS token for WAN2 (input hidden): " WAN2_DUCK_TOKEN
            echo ""
            [ ${#WAN2_DUCK_TOKEN} -ge 10 ] && break
            echo -e "  ${RED}Token too short.${NC}"
        done
        while true; do
            read -r -p "  DuckDNS subdomain for WAN2 (e.g. myhome2): " WAN2_DUCK_SUBDOMAIN
            if [ -z "$WAN2_DUCK_SUBDOMAIN" ]; then
                echo -e "  ${RED}Cannot be empty.${NC}"
            elif [[ "$WAN2_DUCK_SUBDOMAIN" =~ \. ]]; then
                echo -e "  ${RED}Enter only the subdomain part (e.g. 'myhome2', not 'myhome2.duckdns.org').${NC}"
            else
                break
            fi
        done
        WAN2_HOSTNAME="${WAN2_DUCK_SUBDOMAIN}.duckdns.org"
        echo -e "  ${GREEN}WAN2 hostname: ${BOLD}${WAN2_HOSTNAME}${NC}"

    elif [ "$WAN2_PROVIDER" = "digitalocean" ]; then
        echo ""
        echo -e "${BLUE}${BOLD}── WAN2: DigitalOcean credentials ──${NC}"
        echo ""
        while true; do
            read -r -s -p "  DigitalOcean API token for WAN2 (input hidden): " WAN2_DO_TOKEN
            echo ""
            [ ${#WAN2_DO_TOKEN} -ge 20 ] && break
            echo -e "  ${RED}Token too short.${NC}"
        done
        while true; do
            read -r -p "  Domain for WAN2 (e.g. example.com): " WAN2_DO_DOMAIN
            [ -n "$WAN2_DO_DOMAIN" ] && break
            echo -e "  ${RED}Cannot be empty.${NC}"
        done
        echo ""
        echo -e "  Fetching A records for ${BOLD}${WAN2_DO_DOMAIN}${NC} ..."
        WAN2_RECORDS=$(curl -s -X GET \
            -H "Authorization: Bearer ${WAN2_DO_TOKEN}" \
            "https://api.digitalocean.com/v2/domains/${WAN2_DO_DOMAIN}/records?type=A&per_page=100" 2>/dev/null)

        if echo "$WAN2_RECORDS" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'domain_records' in d" 2>/dev/null; then
            WAN2_RCOUNT=$(echo "$WAN2_RECORDS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('domain_records',[])))")
            if [ "$WAN2_RCOUNT" -gt 0 ]; then
                echo -e "  ${GREEN}Found ${WAN2_RCOUNT} record(s):${NC}"
                echo ""
                echo "$WAN2_RECORDS" | python3 -c "
import sys,json
domain='${WAN2_DO_DOMAIN}'
data=json.load(sys.stdin)
for i,r in enumerate(data.get('domain_records',[]),1):
    name=r.get('name','?')
    display=domain if name=='@' else f'{name}.{domain}'
    print(f'    {i}) {display}  (ID: {r[\"id\"]}, IP: {r[\"data\"]})')
"
                while true; do
                    read -r -p "  Choose record for WAN2: " WAN2_SEL
                    [ -z "$WAN2_SEL" ] && continue
                    if [[ "$WAN2_SEL" =~ ^[0-9]+$ ]] && [ "$WAN2_SEL" -ge 1 ] && [ "$WAN2_SEL" -le "$WAN2_RCOUNT" ]; then
                        WAN2_RECORD_ID=$(echo "$WAN2_RECORDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['domain_records'][${WAN2_SEL}-1]['id'])")
                        WAN2_HOSTNAME=$(echo "$WAN2_RECORDS" | python3 -c "
import sys,json
domain='${WAN2_DO_DOMAIN}'
r=json.load(sys.stdin)['domain_records'][${WAN2_SEL}-1]
name=r.get('name','?')
print(domain if name=='@' else f'{name}.{domain}')
")
                        echo -e "  ${GREEN}Selected: ${WAN2_HOSTNAME} (ID: ${WAN2_RECORD_ID})${NC}"
                        break
                    else
                        WAN2_RECORD_ID="$WAN2_SEL"
                        read -r -p "  Hostname the router sends for WAN2: " WAN2_HOSTNAME
                        break
                    fi
                done
            else
                echo -e "  ${YELLOW}No A records found.${NC}"
                read -r -p "  Record ID for WAN2: " WAN2_RECORD_ID
                read -r -p "  Hostname the router sends for WAN2: " WAN2_HOSTNAME
            fi
        else
            echo -e "  ${YELLOW}Could not fetch records.${NC}"
            read -r -p "  Record ID for WAN2: " WAN2_RECORD_ID
            read -r -p "  Hostname the router sends for WAN2: " WAN2_HOSTNAME
        fi

    else  # cloudflare WAN2
        echo ""
        echo -e "${BLUE}${BOLD}── WAN2: Cloudflare credentials ──${NC}"
        echo ""
        while true; do
            read -r -s -p "  Cloudflare API token for WAN2 (input hidden): " WAN2_CF_TOKEN
            echo ""
            [ ${#WAN2_CF_TOKEN} -ge 20 ] && break
            echo -e "  ${RED}Token too short.${NC}"
        done
        while true; do
            read -r -p "  Domain for WAN2 (e.g. example.com): " WAN2_CF_DOMAIN
            [ -n "$WAN2_CF_DOMAIN" ] && break
            echo -e "  ${RED}Cannot be empty.${NC}"
        done
        WAN2_ZONE_JSON=$(curl -s -H "Authorization: Bearer ${WAN2_CF_TOKEN}" \
            "https://api.cloudflare.com/client/v4/zones?name=${WAN2_CF_DOMAIN}&status=active" 2>/dev/null)
        WAN2_CF_ZONE_ID=$(echo "$WAN2_ZONE_JSON" | python3 -c "
import sys,json
data=json.load(sys.stdin)
zones=data.get('result',[])
print(zones[0]['id'] if zones else '')
" 2>/dev/null)
        if [ -z "$WAN2_CF_ZONE_ID" ]; then
            read -r -p "  Zone ID for WAN2: " WAN2_CF_ZONE_ID
        else
            echo -e "  ${GREEN}Zone ID: ${BOLD}${WAN2_CF_ZONE_ID}${NC}"
        fi
        WAN2_CF_RECORDS=$(curl -s -H "Authorization: Bearer ${WAN2_CF_TOKEN}" \
            "https://api.cloudflare.com/client/v4/zones/${WAN2_CF_ZONE_ID}/dns_records?type=A&per_page=100" 2>/dev/null)
        WAN2_RCOUNT=$(echo "$WAN2_CF_RECORDS" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('result',[])))" 2>/dev/null || echo "0")
        if [ "$WAN2_RCOUNT" -gt 0 ]; then
            echo "$WAN2_CF_RECORDS" | python3 -c "
import sys,json
for i,r in enumerate(json.load(sys.stdin).get('result',[]),1):
    print(f'    {i}) {r[\"name\"]}  (ID: {r[\"id\"]}, IP: {r[\"content\"]})')
"
            while true; do
                read -r -p "  Choose record for WAN2: " WAN2_SEL
                [ -z "$WAN2_SEL" ] && continue
                if [[ "$WAN2_SEL" =~ ^[0-9]+$ ]] && [ "$WAN2_SEL" -ge 1 ] && [ "$WAN2_SEL" -le "$WAN2_RCOUNT" ]; then
                    WAN2_CF_RECORD_ID=$(echo "$WAN2_CF_RECORDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][${WAN2_SEL}-1]['id'])")
                    WAN2_HOSTNAME=$(echo "$WAN2_CF_RECORDS" | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][${WAN2_SEL}-1]['name'])")
                    echo -e "  ${GREEN}Selected: ${WAN2_HOSTNAME} (ID: ${WAN2_CF_RECORD_ID})${NC}"
                    break
                else
                    WAN2_CF_RECORD_ID="$WAN2_SEL"
                    read -r -p "  Hostname the router sends for WAN2: " WAN2_HOSTNAME
                    break
                fi
            done
        else
            read -r -p "  Record ID for WAN2: " WAN2_CF_RECORD_ID
            read -r -p "  Hostname the router sends for WAN2: " WAN2_HOSTNAME
        fi
    fi
fi  # end second WAN

# =============================================
# SUMMARY
# =============================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "============================================================"
echo "                   Configuration Summary"
echo "============================================================"
echo -e "${NC}"
if [ "$MULTI_WAN" = "true" ]; then
    echo -e "  MODE           : ${BOLD}multi-WAN${NC}"
    echo -e "  WAN1           : ${BOLD}${WAN1_HOSTNAME}${NC}  (${PROVIDER})"
    echo -e "  WAN2           : ${BOLD}${WAN2_HOSTNAME}${NC}  (${WAN2_PROVIDER})"
else
    echo -e "  PROVIDER       : ${BOLD}${PROVIDER}${NC}"
    if [ "$PROVIDER" = "duckdns" ]; then
        echo -e "  DUCK_TOKEN     : ${BOLD}${DUCK_TOKEN:0:8}...${DUCK_TOKEN: -4}${NC}"
        echo -e "  DUCK_DOMAIN    : ${BOLD}${DUCK_SUBDOMAIN}${NC}  (→ ${DOMAIN})"
    elif [ "$PROVIDER" = "digitalocean" ]; then
        echo -e "  TOKEN          : ${BOLD}${DO_TOKEN:0:8}...${DO_TOKEN: -4}${NC}"
        echo -e "  DOMAIN         : ${BOLD}${DOMAIN}${NC}"
        echo -e "  RECORD_ID      : ${BOLD}${RECORD_ID}${NC}"
    else
        echo -e "  CF_TOKEN       : ${BOLD}${CF_TOKEN:0:8}...${CF_TOKEN: -4}${NC}"
        echo -e "  CF_ZONE_ID     : ${BOLD}${CF_ZONE_ID}${NC}"
        echo -e "  CF_RECORD_ID   : ${BOLD}${RECORD_ID}${NC}"
        echo -e "  DOMAIN         : ${BOLD}${DOMAIN}${NC}"
    fi
fi
echo -e "  DDNS_USERNAME  : ${BOLD}${DDNS_USERNAME}${NC}"
echo -e "  DDNS_PASSWORD  : ${BOLD}${DDNS_PASSWORD}${NC}"
echo -e "  PORT           : ${BOLD}${PORT}${NC}"
echo ""
echo -e "${GREEN}============================================================${NC}"
echo ""
read -r -p "  Is this correct? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo -e "${RED}Setup cancelled. Run this script again to restart.${NC}"
    exit 1
fi

# =============================================
# WRITE .env FILE
# =============================================
echo ""
echo -e "${YELLOW}Writing .env file...${NC}"

if [ "$MULTI_WAN" = "true" ]; then
    # ── Write endpoints.json ──────────────────────────────────────
    echo -e "${YELLOW}Writing endpoints.json...${NC}"

    # Build WAN1 entry
    if [ "$PROVIDER" = "duckdns" ]; then
        WAN1_JSON="\"duck_token\": \"${DUCK_TOKEN}\", \"duck_domain\": \"${DUCK_SUBDOMAIN}\""
    elif [ "$PROVIDER" = "digitalocean" ]; then
        WAN1_JSON="\"token\": \"${DO_TOKEN}\", \"domain\": \"${DOMAIN}\", \"record_id\": \"${RECORD_ID}\""
    else
        WAN1_JSON="\"cf_token\": \"${CF_TOKEN}\", \"zone_id\": \"${CF_ZONE_ID}\", \"record_id\": \"${RECORD_ID}\""
    fi

    # Build WAN2 entry
    if [ "$WAN2_PROVIDER" = "duckdns" ]; then
        WAN2_JSON="\"duck_token\": \"${WAN2_DUCK_TOKEN}\", \"duck_domain\": \"${WAN2_DUCK_SUBDOMAIN}\""
    elif [ "$WAN2_PROVIDER" = "digitalocean" ]; then
        WAN2_JSON="\"token\": \"${WAN2_DO_TOKEN}\", \"domain\": \"${WAN2_DO_DOMAIN}\", \"record_id\": \"${WAN2_RECORD_ID}\""
    else
        WAN2_JSON="\"cf_token\": \"${WAN2_CF_TOKEN}\", \"zone_id\": \"${WAN2_CF_ZONE_ID}\", \"record_id\": \"${WAN2_CF_RECORD_ID}\""
    fi

    cat > "$SCRIPT_DIR/endpoints.json" << EPEOF
{
  "${WAN1_HOSTNAME}": {
    "provider": "${PROVIDER}",
    ${WAN1_JSON}
  },
  "${WAN2_HOSTNAME}": {
    "provider": "${WAN2_PROVIDER}",
    ${WAN2_JSON}
  }
}
EPEOF
    chmod 600 "$SCRIPT_DIR/endpoints.json"
    echo -e "  ${GREEN}endpoints.json created (600).${NC}"

    # ── Write .env for multi mode ─────────────────────────────────
    cat > "$SCRIPT_DIR/.env" << ENVEOF
# DDNS Server Configuration
# Generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')

PROVIDER=multi
ENDPOINTS_FILE=endpoints.json

# DDNS Authentication
DDNS_USERNAME=${DDNS_USERNAME}
DDNS_PASSWORD=${DDNS_PASSWORD}

# Server
HOST=127.0.0.1
PORT=${PORT}
DEBUG=false
TRUST_PROXY=true
ENVEOF

elif [ "$PROVIDER" = "duckdns" ]; then
    cat > "$SCRIPT_DIR/.env" << ENVEOF
# DDNS Server Configuration
# Generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')

PROVIDER=duckdns
ALLOWED_HOSTNAME=${WAN1_HOSTNAME}

# DuckDNS
DUCK_TOKEN=${DUCK_TOKEN}
DUCK_DOMAIN=${DUCK_SUBDOMAIN}

# DDNS Authentication
DDNS_USERNAME=${DDNS_USERNAME}
DDNS_PASSWORD=${DDNS_PASSWORD}

# Server
HOST=127.0.0.1
PORT=${PORT}
DEBUG=false
TRUST_PROXY=true
ENVEOF
elif [ "$PROVIDER" = "digitalocean" ]; then
    cat > "$SCRIPT_DIR/.env" << ENVEOF
# DDNS Server Configuration
# Generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')

PROVIDER=digitalocean
ALLOWED_HOSTNAME=${WAN1_HOSTNAME}

# DigitalOcean API
TOKEN=${DO_TOKEN}
DOMAIN=${DOMAIN}
RECORD_ID=${RECORD_ID}

# DDNS Authentication
DDNS_USERNAME=${DDNS_USERNAME}
DDNS_PASSWORD=${DDNS_PASSWORD}

# Server
HOST=127.0.0.1
PORT=${PORT}
DEBUG=false
TRUST_PROXY=true
ENVEOF
else
    cat > "$SCRIPT_DIR/.env" << ENVEOF
# DDNS Server Configuration
# Generated by setup.sh on $(date '+%Y-%m-%d %H:%M:%S')

PROVIDER=cloudflare
ALLOWED_HOSTNAME=${WAN1_HOSTNAME}

# Cloudflare API
CF_TOKEN=${CF_TOKEN}
CF_ZONE_ID=${CF_ZONE_ID}
CF_RECORD_ID=${RECORD_ID}

# DDNS Authentication
DDNS_USERNAME=${DDNS_USERNAME}
DDNS_PASSWORD=${DDNS_PASSWORD}

# Server
HOST=127.0.0.1
PORT=${PORT}
DEBUG=false
TRUST_PROXY=true
ENVEOF
fi

chmod 600 "$SCRIPT_DIR/.env"
echo -e "  ${GREEN}.env created with restricted permissions (600).${NC}"

# =============================================
# CREATE VIRTUAL ENVIRONMENT
# =============================================
echo ""
echo -e "${YELLOW}Setting up virtual environment...${NC}"

if [ ! -d "$SCRIPT_DIR/.venv" ]; then
    if ! python3 -m venv --help &>/dev/null 2>&1; then
        echo -e "  ${YELLOW}python3-venv not found. Attempting to install...${NC}"
        case "$PKG_MANAGER" in
            apt)    sudo apt install -y python3-venv ;;
            dnf)    sudo dnf install -y python3-venv ;;
            pacman) sudo pacman -S --noconfirm python ;;
            *)      echo -e "  ${RED}Install python3-venv manually and re-run.${NC}"; exit 1 ;;
        esac
    fi
    python3 -m venv "$SCRIPT_DIR/.venv"
    echo -e "  ${GREEN}Virtual environment created.${NC}"
else
    echo -e "  ${GREEN}Virtual environment already exists — reusing.${NC}"
fi

source "$SCRIPT_DIR/.venv/bin/activate"
echo -e "  ${YELLOW}Installing Python dependencies...${NC}"
pip install --quiet --upgrade pip
pip install --quiet -r "$SCRIPT_DIR/requirements.txt"
echo -e "  ${GREEN}Dependencies installed.${NC}"

# =============================================
# TEST API CONNECTION
# =============================================
echo ""
echo -e "${YELLOW}Testing DNS provider API connection...${NC}"

if [ "$PROVIDER" = "duckdns" ]; then
    DUCK_TEST=$(curl -s "https://www.duckdns.org/update?domains=${DUCK_SUBDOMAIN}&token=${DUCK_TOKEN}&ip=" 2>/dev/null)
    if [ "$DUCK_TEST" = "OK" ]; then
        CURRENT_IP=$(curl -s "https://www.duckdns.org/update?domains=${DUCK_SUBDOMAIN}&token=${DUCK_TOKEN}&verbose=true" \
            | head -1 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}DuckDNS API OK — current IP: ${BOLD}${CURRENT_IP}${NC}"
    else
        echo -e "  ${YELLOW}Unexpected DuckDNS response: '${DUCK_TEST}'. Check token and subdomain.${NC}"
    fi
elif [ "$PROVIDER" = "digitalocean" ]; then
    TEST_RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${DO_TOKEN}" \
        "https://api.digitalocean.com/v2/domains/${DOMAIN}/records/${RECORD_ID}")
    if [ "$TEST_RESULT" = "200" ]; then
        CURRENT_IP=$(curl -s -H "Authorization: Bearer ${DO_TOKEN}" \
            "https://api.digitalocean.com/v2/domains/${DOMAIN}/records/${RECORD_ID}" \
            | python3 -c "import sys,json; print(json.load(sys.stdin)['domain_record']['data'])" 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}DigitalOcean API OK — current IP: ${BOLD}${CURRENT_IP}${NC}"
    elif [ "$TEST_RESULT" = "401" ]; then
        echo -e "  ${YELLOW}Auth failed (401). Check your token.${NC}"
    elif [ "$TEST_RESULT" = "404" ]; then
        echo -e "  ${YELLOW}Record not found (404). Check domain and record ID.${NC}"
    else
        echo -e "  ${YELLOW}Unexpected response: HTTP ${TEST_RESULT}.${NC}"
    fi
else
    TEST_RESULT=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${CF_TOKEN}" \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}")
    if [ "$TEST_RESULT" = "200" ]; then
        CURRENT_IP=$(curl -s \
            -H "Authorization: Bearer ${CF_TOKEN}" \
            "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
            | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['content'])" 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}Cloudflare API OK — current IP: ${BOLD}${CURRENT_IP}${NC}"
    elif [ "$TEST_RESULT" = "400" ] || [ "$TEST_RESULT" = "401" ]; then
        echo -e "  ${YELLOW}Auth failed (${TEST_RESULT}). Check your token and permissions.${NC}"
    elif [ "$TEST_RESULT" = "404" ]; then
        echo -e "  ${YELLOW}Record not found (404). Check Zone ID and Record ID.${NC}"
    else
        echo -e "  ${YELLOW}Unexpected response: HTTP ${TEST_RESULT}.${NC}"
    fi
fi

# =============================================
# NGINX + TLS (optional)
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Optional: nginx + TLS ──${NC}"
echo ""
echo -e "  Nginx acts as an HTTPS reverse proxy on a custom port (default 8443)."
echo ""
echo -e "  ${CYAN}Requirements:${NC}"
echo "    - A public DNS A record already pointing to this server"
echo "    - The chosen HTTPS port open in your firewall"
echo "    - sudo access"
echo ""
read -r -p "  Set up nginx + TLS now? [y/N]: " SETUP_NGINX
SETUP_NGINX=${SETUP_NGINX:-N}

if [[ "$SETUP_NGINX" =~ ^[Yy]$ ]]; then

    echo ""
    echo -e "${BLUE}${BOLD}── nginx: Public hostname ──${NC}"
    echo ""
    echo -e "  Hostname pointing to THIS server's static IP (not the DDNS record)."
    echo ""
    while true; do
        read -r -p "  Public hostname (e.g. ddns.example.com): " PUBLIC_HOSTNAME
        [[ "$PUBLIC_HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]] && break
        echo -e "  ${RED}Invalid hostname.${NC}"
    done

    echo ""
    echo -e "${BLUE}${BOLD}── nginx: Email for Let's Encrypt ──${NC}"
    echo ""
    while true; do
        read -r -p "  Your email address: " LE_EMAIL
        [[ "$LE_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
        echo -e "  ${RED}Invalid email.${NC}"
    done

    echo ""
    echo -e "${BLUE}${BOLD}── nginx: HTTPS port ──${NC}"
    echo ""
    echo -e "  Port nginx listens on (default 8443, avoids conflict with 443)."
    echo ""
    read -r -p "  HTTPS port [8443]: " HTTPS_PORT
    HTTPS_PORT=${HTTPS_PORT:-8443}

    if ! [[ "$HTTPS_PORT" =~ ^[0-9]+$ ]] || [ "$HTTPS_PORT" -lt 1 ] || [ "$HTTPS_PORT" -gt 65535 ]; then
        echo -e "${RED}Invalid port.${NC}"; exit 1
    fi

    if sudo ss -tlnp "sport = :$HTTPS_PORT" 2>/dev/null | grep -q LISTEN; then
        echo -e "  ${YELLOW}WARNING: Port ${HTTPS_PORT} already in use.${NC}"
        read -r -p "  Continue anyway? [y/N]: " CONT
        [[ ! "${CONT:-N}" =~ ^[Yy]$ ]] && exit 1
    fi

    # ---- Install packages ----
    echo ""
    echo -e "${YELLOW}Installing nginx and certbot...${NC}"

    pkg_install() {
        case "$PKG_MANAGER" in
            apt)    sudo apt update -qq && sudo apt install -y "$@" ;;
            dnf)
                if ! sudo dnf repolist enabled 2>/dev/null | grep -qi epel; then
                    sudo dnf install -y epel-release
                fi
                sudo dnf install -y "$@"
                ;;
            pacman) sudo pacman -Sy --noconfirm "$@" ;;
            zypper) sudo zypper install -y "$@" ;;
            apk)    sudo apk add "$@" ;;
            *)      echo -e "  ${RED}No supported package manager. Install manually: $*${NC}"; return 1 ;;
        esac
    }

    command -v nginx   &>/dev/null || pkg_install nginx
    command -v certbot &>/dev/null || pkg_install certbot

    # certbot DNS plugin depends on provider
    if [ "$PROVIDER" = "duckdns" ]; then
        # certbot-dns-duckdns is pip-only (no distro packages)
        if ! python3 -c "import certbot_dns_duckdns" 2>/dev/null; then
            echo -e "  ${YELLOW}Installing certbot-dns-duckdns via pip...${NC}"
            sudo python3 -m pip install certbot-dns-duckdns --break-system-packages
        fi
        CERTBOT_DNS_PLUGIN="--dns-duckdns"
        CERTBOT_CREDS_FILE="/etc/letsencrypt/duckdns.ini"
        TMP_CREDS=$(mktemp)
        printf 'dns_duckdns_token = %s\n' "${DUCK_TOKEN}" > "$TMP_CREDS"
    elif [ "$PROVIDER" = "digitalocean" ]; then
        if ! python3 -c "import certbot_dns_digitalocean" 2>/dev/null; then
            case "$PKG_MANAGER" in
                apt)    pkg_install python3-certbot-dns-digitalocean || true ;;
                dnf)    pkg_install python3-certbot-dns-digitalocean || true ;;
                pacman) pkg_install certbot-dns-digitalocean || true ;;
            esac
            if ! python3 -c "import certbot_dns_digitalocean" 2>/dev/null; then
                echo -e "  ${YELLOW}Installing certbot-dns-digitalocean via pip...${NC}"
                sudo python3 -m pip install certbot-dns-digitalocean --break-system-packages
            fi
        fi
        CERTBOT_DNS_PLUGIN="--dns-digitalocean"
        CERTBOT_CREDS_FILE="/etc/letsencrypt/digitalocean.ini"
        TMP_CREDS=$(mktemp)
        printf 'dns_digitalocean_token = %s\n' "${DO_TOKEN}" > "$TMP_CREDS"
    else
        if ! python3 -c "import certbot_dns_cloudflare" 2>/dev/null; then
            case "$PKG_MANAGER" in
                apt)    pkg_install python3-certbot-dns-cloudflare || true ;;
                dnf)    pkg_install python3-certbot-dns-cloudflare || true ;;
                pacman) pkg_install certbot-dns-cloudflare || true ;;
            esac
            if ! python3 -c "import certbot_dns_cloudflare" 2>/dev/null; then
                echo -e "  ${YELLOW}Installing certbot-dns-cloudflare via pip...${NC}"
                sudo python3 -m pip install certbot-dns-cloudflare --break-system-packages
            fi
        fi
        CERTBOT_DNS_PLUGIN="--dns-cloudflare"
        CERTBOT_CREDS_FILE="/etc/letsencrypt/cloudflare.ini"
        TMP_CREDS=$(mktemp)
        printf 'dns_cloudflare_api_token = %s\n' "${CF_TOKEN}" > "$TMP_CREDS"
    fi

    echo -e "  ${YELLOW}Writing provider credentials for certbot...${NC}"
    sudo mkdir -p /etc/letsencrypt
    sudo mv "$TMP_CREDS" "$CERTBOT_CREDS_FILE"
    sudo chmod 600 "$CERTBOT_CREDS_FILE"
    sudo chown root:root "$CERTBOT_CREDS_FILE"

    # ---- Verify DNS ----
    echo ""
    echo -e "  ${YELLOW}Verifying DNS resolution...${NC}"
    SERVER_IP=$(curl -s -4 https://api.ipify.org 2>/dev/null || echo "")
    RESOLVED_IP=$(getent ahosts "$PUBLIC_HOSTNAME" 2>/dev/null | awk 'NR==1{print $1}')
    echo -e "  This server's public IP : ${BOLD}${SERVER_IP:-unknown}${NC}"
    echo -e "  ${PUBLIC_HOSTNAME} resolves to: ${BOLD}${RESOLVED_IP:-unresolved}${NC}"

    if [ -z "$RESOLVED_IP" ]; then
        echo -e "  ${RED}DNS does not resolve. Create the A record, wait for propagation, then re-run.${NC}"
        exit 1
    fi
    if [ -n "$SERVER_IP" ] && [ "$RESOLVED_IP" != "$SERVER_IP" ]; then
        echo -e "  ${YELLOW}WARNING: DNS points to ${RESOLVED_IP} but server is ${SERVER_IP}.${NC}"
        read -r -p "  Continue anyway? [y/N]: " CONT
        [[ ! "${CONT:-N}" =~ ^[Yy]$ ]] && exit 1
    else
        echo -e "  ${GREEN}DNS looks good.${NC}"
    fi

    # ---- Obtain certificate ----
    CERT_PATH="/etc/letsencrypt/live/${PUBLIC_HOSTNAME}/fullchain.pem"
    if sudo test -f "$CERT_PATH"; then
        echo -e "  ${GREEN}Certificate already exists. Skipping issuance.${NC}"
    else
        echo ""
        echo -e "  ${YELLOW}Requesting TLS certificate via DNS-01 challenge...${NC}"
        echo -e "  ${CYAN}(Creates a temporary DNS TXT record — may take ~60s)${NC}"
        sudo certbot certonly \
            $CERTBOT_DNS_PLUGIN \
            "${CERTBOT_DNS_PLUGIN}-credentials" "$CERTBOT_CREDS_FILE" \
            "${CERTBOT_DNS_PLUGIN}-propagation-seconds" 60 \
            -d "$PUBLIC_HOSTNAME" \
            --email "$LE_EMAIL" \
            --agree-tos \
            --non-interactive

        if ! sudo test -f "$CERT_PATH"; then
            echo -e "  ${RED}Certificate not found after certbot run. Aborting.${NC}"
            exit 1
        fi
        echo -e "  ${GREEN}Certificate obtained.${NC}"
    fi

    # ---- Clean up previous nginx config ----
    sudo rm -f \
        /etc/nginx/sites-enabled/ddns-server \
        /etc/nginx/sites-available/ddns-server \
        /etc/nginx/conf.d/ddns-server.conf \
        /etc/nginx/conf.d/ddns-http.conf

    # ---- Detect nginx config layout ----
    if [ -d /etc/nginx/sites-available ]; then
        NGINX_VHOST_FILE="/etc/nginx/sites-available/ddns-server"
        NGINX_VHOST_LINK="/etc/nginx/sites-enabled/ddns-server"
    else
        NGINX_VHOST_FILE="/etc/nginx/conf.d/ddns-server.conf"
        NGINX_VHOST_LINK=""
    fi
    HTTP_CONF="/etc/nginx/conf.d/ddns-http.conf"

    echo ""
    echo -e "  ${YELLOW}Writing nginx configuration...${NC}"

    TMP_HTTP=$(mktemp)
    cat > "$TMP_HTTP" << 'NGINXHTTP'
# DDNS Server — http-context directives
limit_req_zone $binary_remote_addr zone=ddns_limit:10m rate=10r/m;

# Access log format WITHOUT query string (credentials travel in the query string)
log_format ddns_nolog '$remote_addr - $remote_user [$time_local] '
                     '"$request_method $uri $server_protocol" $status '
                     '$body_bytes_sent "$http_user_agent"';
NGINXHTTP
    sudo mv "$TMP_HTTP" "$HTTP_CONF"
    sudo chmod 644 "$HTTP_CONF"

    TMP_CONF=$(mktemp)
    cat > "$TMP_CONF" << NGINXCONF
# DDNS Server — nginx vhost on HTTPS port ${HTTPS_PORT}
server {
    listen ${HTTPS_PORT} ssl;
    listen [::]:${HTTPS_PORT} ssl;
    http2 on;
    server_name ${PUBLIC_HOSTNAME};

    ssl_certificate     /etc/letsencrypt/live/${PUBLIC_HOSTNAME}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${PUBLIC_HOSTNAME}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

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
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 15s;
        proxy_connect_timeout 5s;
    }

    location = /health {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_set_header Host \$host;
    }

    location / { return 404; }
}
NGINXCONF
    sudo mv "$TMP_CONF" "$NGINX_VHOST_FILE"
    sudo chmod 644 "$NGINX_VHOST_FILE"
    [ -n "$NGINX_VHOST_LINK" ] && sudo ln -sf "$NGINX_VHOST_FILE" "$NGINX_VHOST_LINK"

    echo -e "  ${YELLOW}Testing nginx config...${NC}"
    if ! sudo nginx -t; then
        echo -e "  ${RED}Nginx config test failed.${NC}"; exit 1
    fi

    if sudo systemctl is-active --quiet nginx; then
        sudo systemctl reload nginx || sudo systemctl restart nginx
    else
        sudo systemctl start nginx
    fi

    # Open firewall
    if command -v ufw &>/dev/null; then
        sudo ufw allow "$HTTPS_PORT"/tcp || true
    elif command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --permanent --add-port="${HTTPS_PORT}/tcp" || true
        sudo firewall-cmd --reload || true
    fi

    echo -e "  ${GREEN}Nginx running on port ${HTTPS_PORT}.${NC}"

fi  # end nginx setup

# =============================================
# SYSTEMD SERVICE (optional)
# =============================================
echo ""
echo -e "${BLUE}${BOLD}── Optional: systemd service ──${NC}"
echo ""
echo -e "  Installs ddns-server as a systemd service (starts on boot, restarts on failure)."
echo ""
read -r -p "  Install systemd service? [y/N]: " SETUP_SYSTEMD
SETUP_SYSTEMD=${SETUP_SYSTEMD:-N}

if [[ "$SETUP_SYSTEMD" =~ ^[Yy]$ ]]; then
    SERVICE_FILE="/etc/systemd/system/ddns-server.service"
    CURRENT_USER=$(whoami)
    CURRENT_GROUP=$(id -gn)

    TMP_SERVICE=$(mktemp)
    cat > "$TMP_SERVICE" << SERVICEEOF
[Unit]
Description=DDNS TP-Link Server
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
Group=${CURRENT_GROUP}
WorkingDirectory=${SCRIPT_DIR}
EnvironmentFile=${SCRIPT_DIR}/.env
Environment=PATH=${SCRIPT_DIR}/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=${SCRIPT_DIR}/.venv/bin/gunicorn --config gunicorn.conf.py ddns_server:app
ExecReload=/bin/kill -s HUP \$MAINPID
KillMode=mixed
TimeoutStopSec=5
PrivateTmp=true
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICEEOF

    sudo mv "$TMP_SERVICE" "$SERVICE_FILE"
    sudo chmod 644 "$SERVICE_FILE"
    sudo systemctl daemon-reload
    sudo systemctl enable --now ddns-server

    echo -e "  ${GREEN}Service installed and started.${NC}"
    echo ""
    echo -e "  Useful commands:"
    echo -e "    sudo systemctl status  ddns-server"
    echo -e "    sudo systemctl restart ddns-server"
    echo -e "    sudo journalctl -u ddns-server -f"
fi

# =============================================
# DONE
# =============================================
echo ""
echo -e "${GREEN}${BOLD}"
echo "============================================================"
echo "                    Setup Complete!"
echo "============================================================"
echo -e "${NC}"

if [[ "$SETUP_SYSTEMD" =~ ^[Yy]$ ]]; then
    echo -e "  ${BOLD}Server is running via systemd.${NC}"
    echo -e "    sudo systemctl status ddns-server"
else
    echo -e "  ${BOLD}To start the server manually:${NC}"
    echo "    ./start_production.sh"
fi

echo ""

if [[ "$SETUP_NGINX" =~ ^[Yy]$ ]]; then
    echo -e "  ${BOLD}DDNS endpoint:${NC}"
    echo -e "    https://${PUBLIC_HOSTNAME}:${HTTPS_PORT}/ddns/update"
    echo ""
    echo -e "  ${BOLD}TP-Link ER605 — Update URL field:${NC}"
    echo -e "    ${BOLD}https://${PUBLIC_HOSTNAME}:${HTTPS_PORT}/ddns/update?hostname=[DOMAIN]&myip=[IP]&username=[USERNAME]&password=[PASSWORD]${NC}"
    echo ""
    echo -e "  ${BOLD}Other fields:${NC}"
    echo -e "    Domain Name : home.${DOMAIN}"
    echo -e "    Username    : ${DDNS_USERNAME}"
    echo -e "    Password    : ${DDNS_PASSWORD}"
    echo ""
    echo -e "  ${YELLOW}Note:${NC} [DOMAIN],[IP],[USERNAME],[PASSWORD] are literal TP-Link placeholders."
    echo -e "  ${YELLOW}Reminder:${NC} open port ${HTTPS_PORT}/tcp in your cloud firewall."
    echo -e "  ${YELLOW}Cert renewal:${NC} handled by certbot's systemd timer."
    echo -e "    sudo systemctl status certbot.timer"
else
    echo -e "  ${BOLD}Local test:${NC}"
    echo "    curl \"http://127.0.0.1:${PORT}/ddns/update?username=${DDNS_USERNAME}&password=${DDNS_PASSWORD}&hostname=home.${DOMAIN}&ip=\$(curl -s https://api.ipify.org 2>/dev/null || echo 1.2.3.4)\""
fi

echo ""
