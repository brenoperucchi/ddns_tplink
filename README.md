# DDNS TP-Link Server

Flask server for dynamic DNS updates using DigitalOcean API. Compatible with TP-Link routers and other DDNS clients.

## Features

- **DigitalOcean API Integration** - Updates DNS records automatically
- **TP-Link Router Compatible** - Works with TP-Link DDNS clients
- **Environment Configuration** - Secure `.env` file configuration
- **Production Ready** - Gunicorn WSGI server with PID management
- **Comprehensive Logging** - Multiple log files for monitoring
- **Visual Configuration Display** - Shows all settings on startup
- **Service Management** - Start/stop/status scripts included
- **Systemd Integration** - Linux service configuration

## Project Structure

```
ddns_tplink/
├── ddns_server.py              # Main Flask application
├── .env                        # Environment configuration (create from .env.example)
├── .env.example               # Configuration template
├── requirements.txt           # Python dependencies
├── SECURITY.md               # Security guide and best practices
├── gunicorn.conf.py          # Production server configuration
├── start_production.sh       # Start production server
├── stop_server.sh           # Stop server
├── status_server.sh         # Check server status
├── ddns-server.service.example # Systemd service template
├── test_server.py           # Test utilities
└── logs/
    ├── ddns_operations.log  # Application logs
    ├── access.log          # HTTP access logs
    ├── error.log          # Server error logs
    └── ips.log           # IP change history
```

## Configuration

The server uses environment variables loaded from a `.env` file for secure configuration.

### 1. Create Configuration File

```bash
# Copy the example configuration
cp .env.example .env

# Edit with your values
nano .env
```

### 2. Configure Environment Variables

Edit `.env` file with your settings:

```bash
# DigitalOcean API Configuration
TOKEN=your_digitalocean_token_here
DOMAIN=your_domain.com
RECORD_ID=your_record_id_here

# DDNS Authentication
DDNS_USERNAME=your_ddns_username
DDNS_PASSWORD=your_ddns_password

# Server Configuration
HOST=0.0.0.0
PORT=8443
DEBUG=false
```

### 3. DigitalOcean Setup

1. **Get API Token**: Go to DigitalOcean → API → Generate New Token
2. **Find Domain**: Your domain must be managed by DigitalOcean DNS
3. **Get Record ID**: Use DigitalOcean API or find in DNS management panel

### 4. Visual Configuration Check

When starting the server, you'll see a configuration summary:

```
============================================================
                    DDNS SERVER CONFIGURATION
============================================================

# DigitalOcean API Configuration
TOKEN        : ********************
DOMAIN       : example.com
RECORD_ID    : 123456789

# DDNS Authentication
DDNS_USERNAME: ddns_user
DDNS_PASSWORD: ********

# Server Configuration
HOST         : 0.0.0.0
PORT         : 8443
DEBUG        : False

============================================================
```

## Installation

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/ddns_tplink.git
cd ddns_tplink
```

### 2. Create Virtual Environment

```bash
# Create virtual environment
python -m venv .venv

# Activate (Linux/macOS)
source .venv/bin/activate

# Activate (Windows)
.venv\Scripts\activate
```

### 3. Install Dependencies

```bash
pip install -r requirements.txt
```

### 4. Configure Environment

```bash
# Copy configuration template
cp .env.example .env

# Edit configuration
nano .env
```

## Usage

### Development Mode (Testing)

```bash
# Run Flask development server
python ddns_server.py
```

### Production Mode (Recommended)

```bash
# Start production server
./start_production.sh

# Check server status
./status_server.sh

# Stop server
./stop_server.sh
```

### Server Management

#### Start Production Server
```bash
./start_production.sh
```
Output:
```
=== Starting DDNS server in production mode ===
Server started successfully!
Process PID: 12345
PID file: ddns_server.pid
Access logs: access.log
Error logs: error.log
```

#### Check Server Status
```bash
./status_server.sh
```
Output:
```
=== DDNS Server Status ===
PID file found: ddns_server.pid
Process PID: 12345
Status: RUNNING

Process details:
  PID  PPID CMD                          %CPU %MEM    ELAPSED
12345 12344 gunicorn: master [ddns_ser]  0.1  2.5   00:05:23
```

#### Stop Server
```bash
./stop_server.sh
```

### Linux System Service

#### 1. Install Service

```bash
# Copy service file and customize paths
sudo cp ddns-server.service.example /etc/systemd/system/ddns-server.service
sudo nano /etc/systemd/system/ddns-server.service

# Enable and start service
sudo systemctl daemon-reload
sudo systemctl enable ddns-server
sudo systemctl start ddns-server
```

#### 2. Service Management

```bash
# Check status
sudo systemctl status ddns-server

# View logs
sudo journalctl -u ddns-server -f

# Restart service
sudo systemctl restart ddns-server
```

## API Endpoints

### DDNS Update Endpoint

**Endpoint:** `GET /ddns/update`

**Parameters:**
- `username` - Must match `DDNS_USERNAME` from `.env`
- `password` - Must match `DDNS_PASSWORD` from `.env` 
- `hostname` - Hostname to update (can use `[DOMAIN]` placeholder)
- `ip` or `myip` - New IP address (can use `[IP]` placeholder)

### Usage Examples

#### Basic Request
```bash
curl "http://localhost:8443/ddns/update?username=ddns&password=secret&hostname=example.com&ip=192.168.1.100"
```

#### TP-Link Router Format
```bash
http://your-server:8443/ddns/update?hostname=[DOMAIN]&myip=[IP]&username=[USERNAME]&password=[PASSWORD]
```

#### Real Example
```bash
curl "http://example.com:8443/ddns/update?hostname=subdomain.example.com&myip=203.0.113.1&username=ddns&password=mypassword"
```

### API Responses

| Response | Code | Description |
|----------|------|-------------|
| `IP unchanged` | 200 | IP hasn't changed since last update |
| `DNS updated` | 200 | DNS record successfully updated |
| `Missing parameters` | 400 | Required parameters not provided |
| `Unauthorized` | 403 | Invalid username/password |
| `Failed to update DNS` | 500 | DigitalOcean API error |

### TP-Link Router Configuration

1. **Login to Router** → Advanced → Dynamic DNS
2. **Service Provider:** Custom
3. **Server Address:** `your-server-ip:8443`
4. **Domain Name:** `[DOMAIN]` (literal text)
5. **Username/Password:** From your `.env` file
6. **Update URL:** `/ddns/update?hostname=[DOMAIN]&myip=[IP]&username=[USERNAME]&password=[PASSWORD]`

## Logs and Monitoring

### Log Files

| File                  | Purpose                | Content                                   |
|-----------------------|------------------------|-------------------------------------------|
| `ddns_operations.log` | Application operations | Requests, IP changes, DNS updates, errors |
| `access.log`          | HTTP access logs       | All HTTP requests with status codes       |
| `error.log`           | Server errors          | Gunicorn and system errors                |
| `ips.log`             | IP change history      | Timestamp and IP for each change          |

### Log Examples

#### Operations Log (`ddns_operations.log`)
```
2025-06-23 14:30:15,123 - INFO - Request received - Host: example.com, IP: 203.0.113.1, User: ddns
2025-06-23 14:30:15,124 - INFO - Checking IP change - Current: 203.0.113.1, Last: 203.0.113.2
2025-06-23 14:30:15,124 - INFO - IP changed from 203.0.113.2 to 203.0.113.1 - Starting DNS update
2025-06-23 14:30:15,125 - INFO - Sending request to DigitalOcean - Domain: example.com, Record ID: 123456
2025-06-23 14:30:15,456 - INFO - DNS updated successfully! New IP: 203.0.113.1
```

#### IP History (`ips.log`)
```
2025-06-23 14:25:10.123456,203.0.113.2
2025-06-23 14:30:15.124578,203.0.113.1
2025-06-23 14:35:20.987654,203.0.113.3
```

### Real-time Monitoring

```bash
# Monitor operations (most useful)
tail -f ddns_operations.log

# Monitor HTTP requests
tail -f access.log

# Monitor server errors
tail -f error.log

# Monitor system service logs
sudo journalctl -u ddns-server -f

# Check last IP changes
tail -10 ips.log
```

### Server Status Monitoring

```bash
# Comprehensive status check
./status_server.sh

# Quick process check
ps aux | grep ddns_server

# Check if port is listening
lsof -i :8443

# Monitor server resources
top -p $(cat ddns_server.pid)
```

## Security and Production

**IMPORTANT: This server handles authentication credentials and DNS management. Please review the [SECURITY.md](SECURITY.md) guide for detailed security recommendations.**

### Critical Security Considerations

#### **1. Credential Security**
```bash
# NEVER commit .env to version control
echo ".env" >> .gitignore

# Secure file permissions (owner read/write only)
chmod 600 .env

# Use strong, unique passwords
DDNS_PASSWORD=$(openssl rand -base64 32)
```

#### **2. Network Security Risks**
- **Unencrypted Traffic**: Credentials sent in plain text over HTTP
- **Man-in-the-Middle**: Attackers can intercept DDNS requests  
- **Credential Sniffing**: Network monitoring can capture passwords

#### **3. Rate Limiting (Important!)**
Without rate limiting, attackers can:
- Brute force your credentials
- Perform DoS attacks
- Abuse your DigitalOcean API quota

#### **4. Input Validation**
- IP address validation is minimal
- No validation of hostname format
- Potential for injection attacks

### Quick Security Setup (5 minutes)

```bash
# 1. Generate strong password
echo 'DDNS_PASSWORD='$(openssl rand -base64 32) >> .env

# 2. Secure file permissions
chmod 600 .env

# 3. Use non-standard port
sed -i 's/PORT=8443/PORT=9876/' .env

# 4. Firewall protection (replace YOUR_ROUTER_IP)
sudo ufw allow from YOUR_ROUTER_IP to any port 9876
sudo ufw deny 9876
```

### Production Security (Recommended)

For production use, see **[SECURITY.md](SECURITY.md)** for:
- HTTPS/SSL configuration
- Rate limiting implementation
- Advanced firewall rules
- Monitoring and intrusion detection
- Log sanitization
- Backup strategies
