# DDNS TP-Link Server

Flask server that receives IP updates from a TP-Link router (ER605 and similar) and updates a DNS A record via a provider API. Runs behind nginx + Let's Encrypt so the router connects over HTTPS.

## Prerequisites

| Requirement | Notes |
|---|---|
| Linux host with `sudo` | Any distro (apt / dnf / pacman / zypper / apk) |
| Python 3.8+ | `curl` must also be installed |
| A DNS provider with API access | See options below |
| A public hostname for this server | A fixed A record pointing to this machine's IP |

### DNS provider options

| Provider | Cost | Own domain needed | Status |
|---|---|---|---|
| **DuckDNS** | Free | No — gets `*.duckdns.org` | Supported — **default** |
| **Cloudflare** | Free | Yes | Supported |
| **DigitalOcean** | Free tier / paid | Yes | Supported |

- **DuckDNS** — easiest start. Create a free account at duckdns.org, get a token and a free subdomain (e.g. `myhome.duckdns.org`). No domain purchase needed.
- **Cloudflare** — best option if you already have a domain. Free tier covers unlimited DNS updates and the API is very reliable.
- **DigitalOcean** — for users who already manage their domain through DigitalOcean DNS.

## Quick start

```bash
git clone https://github.com/yourusername/ddns_tplink.git
cd ddns_tplink
./setup.sh
```

`setup.sh` is a single interactive script that handles everything:

1. Collects your DNS provider credentials
2. Creates a virtual environment and installs Python dependencies
3. Tests the API connection before proceeding
4. *(Optional)* Configures nginx + Let's Encrypt TLS on a custom HTTPS port
5. *(Optional)* Installs and enables a systemd service

## What setup.sh does, step by step

### .env configuration

The script first asks which DNS provider you want to use, then collects:

**DuckDNS** (default)
- Token — shown at the top of duckdns.org after login
- Subdomain — the `*.duckdns.org` name you created (enter only the subdomain part)
- Token is validated live; no record ID needed

**Cloudflare**
- API token (dash.cloudflare.com → My Profile → API Tokens → "Edit zone DNS" template)
- Domain — Zone ID is auto-detected from the domain name
- Record ID — auto-fetched from the zone, pick from a numbered list

**DigitalOcean**
- API token (cloud.digitalocean.com → API → Tokens, Read + Write)
- Domain managed by DigitalOcean DNS
- Record ID — auto-fetched from the API, pick from a numbered list

**All providers:**
- **DDNS username / password** — credentials the router will send; password is auto-generated
- **Internal port** — gunicorn binds here on `127.0.0.1` (default `9876`)

The resulting `.env` is written with `chmod 600`.

### nginx + TLS (optional but recommended)

Credentials travel in the URL, so HTTPS is required end-to-end. The script:

- Installs `nginx`, `certbot`, and the DigitalOcean DNS plugin
- Obtains a Let's Encrypt certificate via **DNS-01** (no port 80 needed)
- Writes a hardened nginx vhost on a **custom port** (default `8443`) — safe if 80/443 are already used
- Opens the port in `ufw` or `firewalld` if active

> Remember to also open the chosen port in your **cloud firewall** (DigitalOcean Networking → Firewalls, etc.).

### systemd service (optional)

If selected, the script generates and enables a `ddns-server.service` unit with the correct paths for your current user, so the server starts on boot and restarts on failure.

```bash
sudo systemctl status  ddns-server
sudo systemctl restart ddns-server
sudo journalctl -u     ddns-server -f
```

## TP-Link ER605 — DDNS configuration

Go to **Network → Dynamic DNS → Add** and choose **Custom**.

The router shows an **Update URL** field with this hint:

> *Enter the URL in format of `http://[USERNAME]:[PASSWORD]@hostname/path?hostname=[DOMAIN]&myip=[IP]`*

**Ignore that example format.** Our server reads credentials as query parameters, not as Basic Auth in the URL. Use this URL instead:

```
https://<public-hostname>:<https-port>/ddns/update?hostname=[DOMAIN]&myip=[IP]&username=[USERNAME]&password=[PASSWORD]
```

Real example (replace with your hostname and port):
```
https://ddns.example.com:8443/ddns/update?hostname=[DOMAIN]&myip=[IP]&username=[USERNAME]&password=[PASSWORD]
```

| Field | Value |
|---|---|
| Service Provider | Custom |
| Update URL | the URL above |
| Domain Name | the A record to update, e.g. `home.example.com` |
| Username | value of `DDNS_USERNAME` from `.env` |
| Password | value of `DDNS_PASSWORD` from `.env` |

`[DOMAIN]`, `[IP]`, `[USERNAME]`, `[PASSWORD]` are **literal placeholders** — the router substitutes them with real values at update time. Do not replace them manually.

## Manual startup (without systemd)

```bash
./start_production.sh      # gunicorn in background
sudo journalctl -u ddns-server -f   # if using systemd
```

## API reference

### `GET /ddns/update`

| Parameter | Description |
|---|---|
| `username` | must match `DDNS_USERNAME` |
| `password` | must match `DDNS_PASSWORD` |
| `hostname` | RFC 1123 hostname |
| `ip` or `myip` | public IPv4 only |

| Response | Code | Meaning |
|---|---|---|
| `IP unchanged` | 200 | IP already matches the last recorded value |
| `DNS updated` | 200 | A record updated (DigitalOcean or Cloudflare) |
| `Unauthorized` | 403 | wrong credentials |
| `Missing parameters` | 400 | hostname or IP absent |
| `Invalid hostname` | 400 | hostname failed RFC 1123 validation |
| `Invalid IP` | 400 | private / reserved / non-public IPv4 |
| `Too many requests` | 429 | rate limit: 10 req/min per IP |
| `Failed to update DNS` | 502 | DNS provider API returned an error |
| `Upstream timeout` | 504 | provider API did not respond |

### `GET /health`

Returns `ok` (200). Rate-limit exempt.

## Security

- `.env` is `chmod 600` — never commit it
- Credentials compared with `hmac.compare_digest` (constant-time, no timing attacks)
- Gunicorn and nginx strip the query string from access logs (credentials never written to disk)
- Rate limiting at both nginx (10 req/min) and Flask (60/h default)
- `TRUST_PROXY=true` makes rate limiting use the real client IP behind nginx
- Only `/ddns/update` and `/health` are exposed; everything else returns 404

See [SECURITY.md](SECURITY.md) for details.

## Logs

| File | Content |
|---|---|
| `ddns_operations.log` | auth failures, IP changes, API errors |
| `access.log` | gunicorn access log (query string stripped) |
| `error.log` | gunicorn errors |
| `ips.log` | timestamped history of IP changes |
| `/var/log/nginx/ddns-*` | nginx access/error logs |

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `403 Unauthorized` | `DDNS_USERNAME` / `DDNS_PASSWORD` mismatch between `.env` and router |
| `Invalid IP` | Router sent a private address — only public IPv4 is accepted |
| `429 Too many requests` | Rate limit hit; wait or raise the limit in `ddns_server.py` |
| Cert issuance fails | API token missing write scope (DNS-01 needs to create a TXT record) |
| Record doesn't update | Check `ddns_operations.log` for the provider API response code |

## Project layout

```
ddns_tplink/
├── setup.sh                    # unified interactive setup (run this first)
├── start_production.sh         # manual start without systemd
├── ddns_server.py              # Flask app
├── gunicorn.conf.py            # production server config
├── ddns-server.service.example # reference systemd unit (setup.sh writes the real one)
├── requirements.txt
├── SECURITY.md
└── README.md
```
