# DDNS TP-Link Server

Flask server that updates a DigitalOcean DNS record from a DDNS client (TP-Link ER605 and similar routers). Designed to sit behind nginx with a Let's Encrypt certificate obtained via the DigitalOcean DNS-01 challenge — so the router can talk to it over HTTPS even on a host where ports 80/443 are already taken by another stack.

## Features

- **DigitalOcean API integration** — updates an A record when the IP changes
- **TP-Link ER605 compatible** — works with the "Custom" DDNS profile
- **Hardened by default** — rate limiting, constant-time credential check, hostname/IP validation, log sanitization, `X-Forwarded-For` support
- **Credentials never logged** — gunicorn and nginx access logs strip the query string
- **Interactive installer** — `install.sh` walks through the whole `.env` setup and auto-detects your DNS record
- **Nginx + TLS helper** — `setup_nginx.sh` obtains a cert via DNS-01 and configures an HTTPS vhost on a custom port
- **Systemd unit included** — runs unattended as the `app` user

## Requirements

- Linux host with `sudo`
- Python 3.10+
- A domain managed by DigitalOcean DNS
- A DigitalOcean API token with **read + write** scope
- A public DNS A record pointing to this server (separate from the DDNS record you plan to update)

## Quick start

```bash
git clone https://github.com/yourusername/ddns_tplink.git
cd ddns_tplink

# 1. Create venv and install dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 2. Interactive configuration (writes .env)
./install.sh

# 3. Nginx + Let's Encrypt in front (recommended)
./setup_nginx.sh

# 4. Run as a systemd service
sudo cp ddns-server.service /etc/systemd/system/ddns-server.service
sudo nano /etc/systemd/system/ddns-server.service   # adjust paths if needed
sudo systemctl daemon-reload
sudo systemctl enable --now ddns-server
```

## Installation in detail

### 1. Clone and install dependencies

```bash
git clone https://github.com/yourusername/ddns_tplink.git
cd ddns_tplink
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Run the interactive installer

`install.sh` writes a secure `.env` file (mode 600) and tests the DigitalOcean API for you. It asks for:

1. **DigitalOcean API token** — create at https://cloud.digitalocean.com/account/api/tokens (read + write)
2. **Domain** — must be listed under https://cloud.digitalocean.com/networking/domains
3. **Record ID** — the installer fetches all A records and lets you pick one from a numbered list; you can also paste an ID manually
4. **DDNS username** — any label the router will send (e.g. `ddns`)
5. **DDNS password** — auto-generated with `secrets.token_urlsafe(24)`; **copy it immediately**, you'll paste it into the router
6. **Server port** — internal port gunicorn binds to on `127.0.0.1` (default `9876`)

```bash
./install.sh
```

At the end the installer prints a summary and runs a live test against the DigitalOcean API so you know the token and record ID are valid before you start the server.

### 3. Put nginx + TLS in front (recommended)

The router will send credentials in the URL query string, so the connection **must** be HTTPS end-to-end. `setup_nginx.sh` handles everything:

```bash
./setup_nginx.sh
```

It will:

1. Clean up any previous DDNS nginx vhost
2. Install `nginx`, `certbot`, and `python3-certbot-dns-digitalocean` if missing
3. Ask for a **public hostname** (e.g. `ddns.example.com`) that already points at this server
4. Ask for an **email** for Let's Encrypt expiration notifications
5. Ask for an **HTTPS port** (default `8443` — useful when 443 is already taken by another stack)
6. Write `/etc/letsencrypt/digitalocean.ini` with your API token (mode 600, root-owned) and request a certificate via the **DNS-01** challenge — no port 80 required
7. Write an nginx vhost at `/etc/nginx/sites-available/ddns-server` with:
   - TLS 1.2/1.3, HSTS, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`
   - Rate limit: 10 req/min per client IP (`ddns_limit` zone)
   - Access log format **without** the query string (credentials are never written to disk)
   - Only `/ddns/update` and `/health` are exposed; everything else returns 404
8. Reload nginx and open the chosen port in `ufw` if active

After this, your endpoint is `https://<public-hostname>:<https-port>/ddns/update`.

> **Don't forget** to open the chosen HTTPS port on your cloud firewall (DigitalOcean Networking → Firewalls, AWS security groups, etc.) — `ufw` only covers the local firewall.

### 4. Install as a systemd service

The repo ships a ready-to-use unit file. Paths assume `/home/app/projects/ddns_tplink`; adjust if needed.

```bash
sudo cp ddns-server.service /etc/systemd/system/ddns-server.service
sudo nano /etc/systemd/system/ddns-server.service    # check WorkingDirectory / ExecStart
sudo systemctl daemon-reload
sudo systemctl enable --now ddns-server
sudo systemctl status ddns-server
```

Logs: `sudo journalctl -u ddns-server -f`

### 5. Configure the TP-Link ER605 (or compatible router)

**Network → Dynamic DNS → Add → Custom**

| Field            | Value                                                                                          |
|------------------|------------------------------------------------------------------------------------------------|
| Service Provider | Custom                                                                                         |
| Server URL       | `https://<public-hostname>:<https-port>/ddns/update?hostname=[DOMAIN]&myip=[IP]&username=[USERNAME]&password=[PASSWORD]` |
| Domain Name      | the record you want to update, e.g. `home.example.com`                                         |
| Username         | the value from `DDNS_USERNAME`                                                                 |
| Password         | the value from `DDNS_PASSWORD`                                                                 |

`[DOMAIN]`, `[IP]`, `[USERNAME]`, `[PASSWORD]` are **literal placeholders** — the router substitutes them at request time.

## Manual configuration (if you skip `install.sh`)

Create `.env` at the project root:

```bash
# DigitalOcean API
TOKEN=dop_v1_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
DOMAIN=example.com
RECORD_ID=123456789

# DDNS credentials (used by the router)
DDNS_USERNAME=ddns
DDNS_PASSWORD=change-me-strong-password

# Server
HOST=127.0.0.1    # bind to loopback; nginx proxies in front
PORT=9876
DEBUG=false

# Honor X-Forwarded-For from nginx (for rate limiting and logging)
TRUST_PROXY=true
```

```bash
chmod 600 .env
```

## Running manually (no systemd)

```bash
# Development (Flask dev server)
python3 ddns_server.py

# Production (gunicorn, foreground)
gunicorn --config gunicorn.conf.py ddns_server:app

# Production (detached with PID file)
./start_production.sh
./status_server.sh
./stop_server.sh
```

## API

### `GET /ddns/update`

| Parameter          | Description                                        |
|--------------------|----------------------------------------------------|
| `username`         | must match `DDNS_USERNAME`                         |
| `password`         | must match `DDNS_PASSWORD`                         |
| `hostname`         | RFC 1123 hostname (validated)                      |
| `ip` or `myip`     | public IPv4 (private/reserved/loopback rejected)   |

| Response              | Code | Meaning                                |
|-----------------------|------|----------------------------------------|
| `IP unchanged`        | 200  | current IP matches the last recorded   |
| `DNS updated`         | 200  | record updated on DigitalOcean         |
| `Missing parameters`  | 400  | hostname or IP missing (after auth)    |
| `Invalid hostname`    | 400  | hostname failed validation             |
| `Invalid IP`          | 400  | IP not a routable public IPv4          |
| `Unauthorized`        | 403  | bad credentials                        |
| `Too many requests`   | 429  | rate limit tripped                     |
| `Failed to update DNS`| 502  | DigitalOcean API returned an error     |
| `Upstream timeout`    | 504  | DigitalOcean API did not respond       |

### `GET /health`

Returns `ok` (200). Exempt from rate limiting.

### Quick manual test

```bash
curl "https://ddns.example.com:8443/ddns/update?username=ddns&password=SECRET&hostname=home.example.com&myip=$(curl -s https://api.ipify.org)"
```

## Security notes

- `.env` is chmod 600 and must never be committed
- DDNS password is auto-generated (URL-safe, 24 bytes) and stored only in `.env` and your router
- Credentials are compared with `hmac.compare_digest` (constant-time)
- Flask: `MAX_CONTENT_LENGTH=4KB`; non-DDNS routes return 404
- Gunicorn and nginx strip the query string from access logs
- Rate limiting: 10 req/min per IP at nginx + 10 req/min at Flask (`60/h` default)
- When running behind nginx, set `TRUST_PROXY=true` so rate limiting and logs see the real client IP
- Hostnames are validated (RFC 1123); IPs must be public IPv4

See [SECURITY.md](SECURITY.md) for further hardening.

## Logs

| File                   | Content                                                |
|------------------------|--------------------------------------------------------|
| `ddns_operations.log`  | app events: auth failures, IP changes, DO API errors   |
| `access.log`           | gunicorn access log (query string stripped)            |
| `error.log`            | gunicorn worker errors                                 |
| `ips.log`              | timestamped history of every accepted IP change        |
| `/var/log/nginx/ddns-*`| nginx access/error when using `setup_nginx.sh`         |

```bash
tail -f ddns_operations.log
tail -f /var/log/nginx/ddns-access.log
sudo journalctl -u ddns-server -f
```

## Troubleshooting

- **`403 Unauthorized`** — `DDNS_USERNAME` / `DDNS_PASSWORD` mismatch. Check `.env` and the router.
- **`Invalid IP`** — router sent a private/reserved address. The service only accepts routable public IPv4.
- **`429 Too many requests`** — rate limit hit (nginx 10/min or Flask 10/min). Wait or raise the limit in `setup_nginx.sh` / `ddns_server.py`.
- **Cert issuance fails in `setup_nginx.sh`** — check the DigitalOcean token has write scope; the DNS-01 challenge needs to create a temporary TXT record.
- **Router reports success but the record does not change** — check `ddns_operations.log`; the upstream DigitalOcean API response is logged with the error code.
- **Systemd unit fails with `EnvironmentFile` error** — the unit file reads `.env` directly; make sure the path in the unit matches your install location.

## Project layout

```
ddns_tplink/
├── install.sh                  # interactive .env setup
├── setup_nginx.sh              # nginx + Let's Encrypt DNS-01 setup
├── ddns_server.py              # Flask app (auth, validation, rate limit, DO API call)
├── config.py                   # environment-based config object
├── gunicorn.conf.py            # production server config (logs strip query string)
├── ddns-server.service         # systemd unit
├── start_production.sh         # start gunicorn detached
├── stop_server.sh              # stop via PID file
├── status_server.sh            # status via PID file
├── test_server.py              # manual test helper
├── requirements.txt
├── SECURITY.md
├── README.md
└── logs: ddns_operations.log, access.log, error.log, ips.log
```
