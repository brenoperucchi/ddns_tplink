# Security Configuration for DDNS Server
# Add these enhancements to improve security

from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
import ipaddress
import re
from functools import wraps
import hashlib
import hmac
import time

# Rate limiting setup
limiter = Limiter(
    app,
    key_func=get_remote_address,
    default_limits=["100 per hour"]
)

# IP validation function
def validate_ip_address(ip):
    """Validate IP address format and type"""
    try:
        ip_obj = ipaddress.ip_address(ip)
        # Reject private IPs for security (optional)
        if ip_obj.is_private:
            return False, "Private IP addresses not allowed"
        # Reject loopback and multicast
        if ip_obj.is_loopback or ip_obj.is_multicast:
            return False, "Invalid IP address type"
        return True, None
    except ValueError:
        return False, "Invalid IP address format"

# Hostname validation
def validate_hostname(hostname):
    """Validate hostname format"""
    if not hostname or len(hostname) > 255:
        return False
    
    # Basic hostname pattern
    pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'
    return bool(re.match(pattern, hostname))

# API key authentication (alternative to username/password)
def generate_api_key():
    """Generate secure API key"""
    return hashlib.sha256(f"{time.time()}{os.urandom(32)}".encode()).hexdigest()

# Request signing (HMAC)
def sign_request(params, secret):
    """Sign request parameters with HMAC"""
    sorted_params = sorted(params.items())
    message = "&".join([f"{k}={v}" for k, v in sorted_params])
    return hmac.new(secret.encode(), message.encode(), hashlib.sha256).hexdigest()

# Decorator for authentication
def require_auth(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Add timing attack protection
        start_time = time.time()
        
        username = request.args.get("username")
        password = request.args.get("password")
        
        # Constant time comparison
        valid_username = hmac.compare_digest(username or "", DDNS_USERNAME or "")
        valid_password = hmac.compare_digest(password or "", DDNS_PASSWORD or "")
        
        # Minimum processing time to prevent timing attacks
        elapsed = time.time() - start_time
        if elapsed < 0.1:
            time.sleep(0.1 - elapsed)
        
        if not (valid_username and valid_password):
            logger.warning(f"Authentication failed from {request.remote_addr}")
            return "Unauthorized", 403
            
        return f(*args, **kwargs)
    return decorated_function

# Enhanced route with security
@app.route("/ddns/update", methods=["GET"])
@limiter.limit("10 per minute")  # Rate limiting
@require_auth
def secure_ddns_update():
    """Secure DDNS update endpoint"""
    hostname = request.args.get("hostname")
    ip = request.args.get("ip") or request.args.get("myip")
    
    # Enhanced validation
    if not hostname or not ip:
        logger.warning(f"Missing parameters from {request.remote_addr}")
        return "Missing parameters", 400
    
    # Validate hostname
    if not validate_hostname(hostname):
        logger.warning(f"Invalid hostname '{hostname}' from {request.remote_addr}")
        return "Invalid hostname", 400
    
    # Validate IP
    is_valid, error_msg = validate_ip_address(ip)
    if not is_valid:
        logger.warning(f"Invalid IP '{ip}' from {request.remote_addr}: {error_msg}")
        return f"Invalid IP: {error_msg}", 400
    
    # Log with sanitized data (no credentials)
    logger.info(f"Valid request - Host: {hostname}, IP: {ip}, Source: {request.remote_addr}")
    
    # Continue with existing DNS update logic...
    return "Processing...", 200
