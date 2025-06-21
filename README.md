# DDNS TP-Link Server

Servidor Flask para atualização dinâmica de DNS usando a API da DigitalOcean.

## Configuração

Antes de executar o servidor, edite as configurações no início do arquivo `ddns_server.py`:

```python
# =============================================
# CONFIGURAÇÕES - EDITE AQUI CONFORME NECESSÁRIO
# =============================================

# Credenciais de autenticação
DDNS_USERNAME = "ddns"
DDNS_PASSWORD = "senhaescondida"

# Configurações do servidor
SERVER_HOST = "0.0.0.0"
SERVER_PORT = 8443
DEBUG_MODE = False  # True apenas para desenvolvimento

# Configurações da DigitalOcean API
TOKEN = "seu_token_aqui"
DOMAIN = "seu_dominio.com"
RECORD_ID = "seu_record_id"
```

## Instalação

1. Instale as dependências:
```bash
pip install -r requirements.txt
```

## Execução

### Desenvolvimento (apenas para testes)

```bash
python ddns_server.py
```

### Produção (recomendado)

```bash
# Inicia o servidor em modo de produção com Gunicorn
./start_production.sh

# Para parar o servidor
./stop_server.sh
```

O servidor será executado no host e porta configurados nas variáveis `SERVER_HOST` e `SERVER_PORT`.

### Execução como serviço do sistema (Linux)

1. Edite o arquivo `ddns-server.service` e ajuste os caminhos:
```bash
sudo cp ddns-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable ddns-server
sudo systemctl start ddns-server
```

2. Verificar status:
```bash
sudo systemctl status ddns-server
```

## Uso

Faça uma requisição GET para `/ap` com os seguintes parâmetros:

- `username`: deve coincidir com `DDNS_USERNAME` configurado no servidor
- `password`: deve coincidir com `DDNS_PASSWORD` configurado no servidor
- `hostname`: nome do host
- `ip`: endereço IP a ser atualizado

### Exemplo de uso:

```
GET http://localhost:8443/ap?username=ddns&password=senhaescondida&hostname=example&ip=192.168.1.100
```

**Nota**: Substitua `localhost:8443` pelo host e porta configurados nas variáveis `SERVER_HOST` e `SERVER_PORT`.

## Respostas possíveis:

- `IP unchanged` (200): O IP não mudou desde a última atualização
- `DNS updated` (200): DNS foi atualizado com sucesso
- `Unauthorized` (403): Credenciais incorretas
- `Missing parameters` (400): Parâmetros obrigatórios não fornecidos
- Erro 500: Falha na comunicação com a API da DigitalOcean

## Arquivo de log

O histórico de IPs é mantido no arquivo `ips.log` no formato:
```
timestamp,ip
```

## Logs e Monitoramento

### Logs disponíveis:

1. **ddns_operations.log**: Log detalhado das operações do sistema
   - Requisições recebidas
   - Verificações de mudança de IP
   - Atualizações de DNS
   - Erros de autenticação
   
2. **access.log**: Log de acesso HTTP do Gunicorn
   - Todas as requisições HTTP
   - Status codes e tempos de resposta
   
3. **error.log**: Log de erros do servidor Gunicorn
   - Erros de sistema e exceções
   
4. **ips.log**: Histórico de mudanças de IP
   - Timestamp e IP de cada mudança

### Visualizar logs em tempo real:
```bash
# Log de operações (mais útil para debug)
tail -f ddns_operations.log

# Logs de acesso HTTP
tail -f access.log

# Logs de erro do servidor
tail -f error.log

# Logs do sistema (se usando systemd)
sudo journalctl -u ddns-server -f
```

### Exemplo de logs de operação:
```
2025-06-21 01:11:13,028 - INFO - Requisição recebida - Host: teste-log, IP: 192.168.1.102, User: ddns
2025-06-21 01:11:13,029 - INFO - Verificando mudança de IP - Atual: 192.168.1.102, Último: 192.168.1.101
2025-06-21 01:11:13,029 - INFO - IP mudou de 192.168.1.101 para 192.168.1.102 - Iniciando atualização DNS
2025-06-21 01:11:13,030 - INFO - Enviando requisição para DigitalOcean - Domínio: imentore.com.br, Record ID: 327101812
2025-06-21 01:11:13,488 - INFO - DNS atualizado com sucesso! Novo IP: 192.168.1.102
```

## Segurança em Produção

### Recomendações:
1. **Use HTTPS**: Configure SSL/TLS no Gunicorn ou use um proxy reverso (nginx/Apache)
2. **Firewall**: Bloqueie portas desnecessárias
3. **Senhas fortes**: Altere as credenciais padrão
4. **Monitoramento**: Configure alertas para falhas
5. **Backup**: Faça backup do arquivo `ips.log` regularmente

### Configuração SSL (opcional):
Descomente e configure no `gunicorn.conf.py`:
```python
keyfile = "/path/to/your/private.key"
certfile = "/path/to/your/certificate.crt"
```
