import os

# Bind to loopback by default; nginx terminates TLS and proxies here.
# To bind publicly, set HOST=0.0.0.0 in .env.
_host = os.getenv("HOST", "127.0.0.1")
_port = os.getenv("PORT", "9876")
bind = f"{_host}:{_port}"
backlog = 2048

# Workers
workers = 2
worker_class = "sync"
worker_connections = 1000
timeout = 30
keepalive = 2

# Logging - access_log_format intentionally omits the query string (%(q)s)
# because DDNS credentials are passed as GET parameters. The default
# format uses %(r)s which would log the full request line with password.
loglevel = "info"
accesslog = "access.log"
errorlog = "error.log"
access_log_format = (
    '%(h)s %(l)s %(u)s %(t)s "%(m)s %(U)s %(H)s" %(s)s %(b)s '
    '"%(f)s" "%(a)s" %(D)s'
)

# Process
daemon = False
pidfile = "ddns_server.pid"
user = None
group = None
tmp_upload_dir = None

# TLS is handled by nginx in front. If running gunicorn directly with TLS,
# uncomment and point to your certificate files:
# keyfile = "/path/to/privkey.pem"
# certfile = "/path/to/fullchain.pem"

# Restart workers periodically to mitigate memory leaks
max_requests = 1000
max_requests_jitter = 50

# Timeout for graceful worker restart
graceful_timeout = 30

# Keep-alive connection timeout
keepalive_timeout = 2
