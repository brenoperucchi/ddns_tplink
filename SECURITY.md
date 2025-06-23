# SECURITY GUIDE - DDNS TP-Link Server

## MAIN SECURITY RISKS

### 1. **CREDENTIALS IN PLAIN TEXT**
**Risk:** Passwords transmitted without encryption via HTTP
**Impact:** Credential interception by attackers

**Solutions:**
```bash
# Use strong passwords
DDNS_PASSWORD=$(openssl rand -base64 32)

# Configure HTTPS (essential!)
# Option 1: Let's Encrypt Certificate
sudo apt install certbot
sudo certbot certonly --standalone -d your-domain.com

# Option 2: Nginx as HTTPS proxy
sudo apt install nginx
```

### 2. **LACK OF RATE LIMITING**
**Risk:** Brute force attacks and DoS
**Impact:** Credential compromise and service unavailability

**Quick Solution - Firewall:**
```bash
# Allow only your router
sudo ufw allow from YOUR_ROUTER_IP to any port 8443
sudo ufw deny 8443

# Rate limiting with iptables
sudo iptables -A INPUT -p tcp --dport 8443 -m limit --limit 25/minute --limit-burst 100 -j ACCEPT
```

### 3. **LOGS WITH SENSITIVE INFORMATION**
**Risk:** Credential exposure in logs
**Impact:** Data leak if logs are compromised

**Solution - Sanitization:**
```python
# Instead of:
logger.info(f"Request - User: {username}, Pass: {password}")

# Use:
logger.info(f"Request - User: {username[:3]}***, Source: {request.remote_addr}")
```

### 4. **INSUFFICIENT IP VALIDATION**
**Risk:** Malicious data injection
**Impact:** Potential data corruption

**Solution:**
```python
import ipaddress

def validate_ip(ip):
    try:
        ip_obj = ipaddress.ip_address(ip)
        # Reject private IPs if necessary
        if ip_obj.is_private:
            return False
        return True
    except ValueError:
        return False
```

### 5. **DEFAULT PORT EXPOSURE**
**Risk:** Port scanning and automated attacks
**Impact:** Easy service discovery

**Solution:**
```bash
# Use non-standard port
PORT=9876

# Configure port knocking (advanced)
sudo apt install knockd
```

## QUICK SECURITY IMPLEMENTATION

### **Level 1: Basic (5 minutes)**
```bash
# 1. Strong password
echo 'DDNS_PASSWORD='$(openssl rand -base64 32) >> .env

# 2. File permissions
chmod 600 .env

# 3. Basic firewall
sudo ufw enable
sudo ufw allow from YOUR_ROUTER_IP to any port 8443

# 4. Non-standard port
sed -i 's/PORT=8443/PORT=9876/' .env
```

### **Level 2: Intermediate (30 minutes)**
```bash
# 1. Free SSL certificate
sudo apt install certbot nginx
sudo certbot certonly --standalone -d your-domain.com

# 2. Configure Nginx as proxy
sudo nano /etc/nginx/sites-available/ddns
```

```nginx
server {
    listen 8443 ssl;
    server_name your-domain.com;
    
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000";
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    
    location / {
        proxy_pass http://localhost:8443;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### **Level 3: Advanced (1 hour)**
```bash
# 1. Security monitoring
sudo apt install fail2ban

# 2. Configure fail2ban for the service
sudo nano /etc/fail2ban/jail.local
```

```ini
[ddns-auth]
enabled = true
port = 8443
filter = ddns-auth
logpath = /path/to/ddns_operations.log
maxretry = 3
bantime = 3600
```

## MINIMUM SECURITY CHECKLIST

- [ ] **Strong password** (32+ random characters)
- [ ] **Protected .env file** (chmod 600)
- [ ] **Configured firewall** (router IP only)
- [ ] **Non-standard port** (don't use 8443)
- [ ] **HTTPS enabled** (SSL certificate)
- [ ] **Sanitized logs** (no credentials)
- [ ] **Secure backup** (important configurations)

## SIGNS OF COMPROMISE

**Monitor logs for:**
```bash
# Many failed authentication attempts
grep "Authentication failed" ddns_operations.log

# Requests from suspicious IPs
grep -v "YOUR_ROUTER_IP" access.log

# Attempts with malicious parameters
grep -E "(script|alert|drop|union)" ddns_operations.log
```

## IN CASE OF COMPROMISE

1. **Stop server immediately:**
   ```bash
   ./stop_server.sh
   sudo ufw deny 8443
   ```

2. **Change credentials:**
   ```bash
   # New DDNS password
   echo 'DDNS_PASSWORD='$(openssl rand -base64 32) >> .env
   
   # Regenerate DigitalOcean token
   # Access: https://cloud.digitalocean.com/account/api/tokens
   ```

3. **Analyze logs:**
   ```bash
   # Check suspicious activity
   grep -E "(40[0-9]|50[0-9])" access.log
   tail -100 ddns_operations.log
   ```

4. **Update everything:**
   ```bash
   pip install --upgrade -r requirements.txt
   sudo apt update && sudo apt upgrade
   ```

## FINAL RECOMMENDATION

**For home use:** Implement at least **Level 1** security.
**For commercial use:** Implement complete **Level 3**.

**Cost vs Benefit:** Level 2 offers excellent protection with moderate setup.
