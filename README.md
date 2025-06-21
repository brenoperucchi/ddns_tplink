# DDNS TP-Link Server

Flask server for dynamic DNS updates using DigitalOcean API.

## Configuration

Before running the server, edit the settings at the beginning of the `ddns_server.py` file:

```python
# =============================================
# CONFIGURATION - EDIT HERE AS NEEDED
# =============================================

# Authentication credentials
DDNS_USERNAME = "ddns"
DDNS_PASSWORD = "senhaescondida"

# Server configuration
SERVER_HOST = "0.0.0.0"
SERVER_PORT = 8443
DEBUG_MODE = False  # True only for development

# DigitalOcean API configuration
TOKEN = "your_token_here"
DOMAIN = "your_domain.com"
RECORD_ID = "your_record_id"
```

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/ddns_tplink.git
cd ddns_tplink
```

2. Create a virtual environment (recommended):
```bash
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
```

3. Install dependencies:
```bash
pip install -r requirements.txt
```

## Execution

### Development (testing only)

```bash
python ddns_server.py
```

### Production (recommended)

```bash
# Start server in production mode with Gunicorn
./start_production.sh

# Stop server
./stop_server.sh
```

The server will run on the host and port configured in the `SERVER_HOST` and `SERVER_PORT` variables.

### Run as system service (Linux)

1. Edit the `ddns-server.service` file and adjust the paths:
```bash
sudo cp ddns-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ddns-server
sudo systemctl start ddns-server
```

2. Check status:
```bash
sudo systemctl status ddns-server
```

## Usage

Make a GET request to `/ap` with the following parameters:

- `username`: must match `DDNS_USERNAME` configured on the server
- `password`: must match `DDNS_PASSWORD` configured on the server
- `hostname`: host name
- `ip`: IP address to be updated

### Usage example:

```
GET http://localhost:8443/ap?username=ddns&password=senhaescondida&hostname=example&ip=192.168.1.100
```

**Note**: Replace `localhost:8443` with the host and port configured in the `SERVER_HOST` and `SERVER_PORT` variables.

## Possible responses:

- `IP unchanged` (200): IP hasn't changed since last update
- `DNS updated` (200): DNS was successfully updated
- `Unauthorized` (403): Incorrect credentials
- `Missing parameters` (400): Required parameters not provided
- Error 500: Failure communicating with DigitalOcean API

## Log file

IP change history is maintained in the `ips.log` file in the format:
```
timestamp,ip
```

## Logs and Monitoring

### Available logs:

1. **ddns_operations.log**: Detailed log of system operations
   - Received requests
   - IP change verifications
   - DNS updates
   - Authentication errors
   
2. **access.log**: Gunicorn HTTP access log
   - All HTTP requests
   - Status codes and response times
   
3. **error.log**: Gunicorn server error log
   - System errors and exceptions
   
4. **ips.log**: IP change history
   - Timestamp and IP of each change

### View logs in real time:
```bash
# Operations log (most useful for debugging)
tail -f ddns_operations.log

# HTTP access logs
tail -f access.log

# Server error logs
tail -f error.log

# System logs (if using systemd)
sudo journalctl -u ddns-server -f
```

### Example operation logs:
```
2025-06-21 01:11:13,028 - INFO - Request received - Host: teste-log, IP: 192.168.1.102, User: ddns
2025-06-21 01:11:13,029 - INFO - Checking IP change - Current: 192.168.1.102, Last: 192.168.1.101
2025-06-21 01:11:13,029 - INFO - IP changed from 192.168.1.101 to 192.168.1.102 - Starting DNS update
2025-06-21 01:11:13,030 - INFO - Sending request to DigitalOcean - Domain: imentore.com.br, Record ID: 327101812
2025-06-21 01:11:13,488 - INFO - DNS updated successfully! New IP: 192.168.1.102
```

## Production Security

### Recommendations:
1. **Use HTTPS**: Configure SSL/TLS in Gunicorn or use a reverse proxy (nginx/Apache)
2. **Firewall**: Block unnecessary ports
3. **Strong passwords**: Change default credentials
4. **Monitoring**: Configure alerts for failures
5. **Backup**: Regularly backup the `ips.log` file

### SSL Configuration (optional):
Uncomment and configure in `gunicorn.conf.py`:
```python
keyfile = "/path/to/your/private.key"
certfile = "/path/to/your/certificate.crt"
```
