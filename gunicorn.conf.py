# Configuração do Gunicorn para produção

# Rede
bind = "0.0.0.0:8443"
backlog = 2048

# Trabalhadores
workers = 2
worker_class = "sync"
worker_connections = 1000
timeout = 30
keepalive = 2

# Logging
loglevel = "info"
accesslog = "access.log"
errorlog = "error.log"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Processo
daemon = False
pidfile = "ddns_server.pid"
user = None
group = None
tmp_upload_dir = None

# SSL/HTTPS (descomente e configure se necessário)
# keyfile = "/path/to/keyfile"
# certfile = "/path/to/certfile"

# Restart workers after this many requests, to help prevent memory leaks
max_requests = 1000
max_requests_jitter = 50

# Timeout for graceful workers restart
graceful_timeout = 30

# The number of seconds to wait for requests on a Keep-Alive connection
keepalive_timeout = 2
