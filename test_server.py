#!/usr/bin/env python3
"""
Script de teste para o servidor DDNS
"""
import requests

# =============================================
# CONFIGURAÇÕES DE TESTE - EDITE AQUI
# =============================================

# Configurações do servidor
SERVER_HOST = "localhost"
SERVER_PORT = 8443
SERVER_URL = f"http://{SERVER_HOST}:{SERVER_PORT}"

# Credenciais (devem coincidir com as do servidor)
USERNAME = "ddns"
PASSWORD = "senhaescondida"

# Dados de teste
HOSTNAME = "test-host"
TEST_IP = "203.0.113.1"  # IP de exemplo para teste

# =============================================

def test_ddns_server():
    """Testa o servidor DDNS"""
    
    print("=== Testando Servidor DDNS ===\n")
    
    # Teste 1: Requisição com parâmetros corretos
    print("1. Testando com credenciais corretas...")
    params = {
        "username": USERNAME,
        "password": PASSWORD,
        "hostname": HOSTNAME,
        "ip": TEST_IP
    }
    
    try:
        response = requests.get(f"{SERVER_URL}/ap", params=params)
        print(f"   Status: {response.status_code}")
        print(f"   Resposta: {response.text}")
    except requests.RequestException as e:
        print(f"   Erro: {e}")
    
    print()
    
    # Teste 2: Requisição com senha incorreta
    print("2. Testando com senha incorreta...")
    params_wrong = params.copy()
    params_wrong["password"] = "senha_errada"
    
    try:
        response = requests.get(f"{SERVER_URL}/ap", params=params_wrong)
        print(f"   Status: {response.status_code}")
        print(f"   Resposta: {response.text}")
    except requests.RequestException as e:
        print(f"   Erro: {e}")
    
    print()
    
    # Teste 3: Requisição com parâmetros faltando
    print("3. Testando com parâmetros faltando...")
    params_missing = {
        "username": USERNAME,
        "password": PASSWORD
        # hostname e ip faltando
    }
    
    try:
        response = requests.get(f"{SERVER_URL}/ap", params=params_missing)
        print(f"   Status: {response.status_code}")
        print(f"   Resposta: {response.text}")
    except requests.RequestException as e:
        print(f"   Erro: {e}")
    
    print()
    
    # Teste 4: Requisição com mesmo IP (para testar "IP unchanged")
    print("4. Testando novamente com mesmo IP...")
    try:
        response = requests.get(f"{SERVER_URL}/ap", params=params)
        print(f"   Status: {response.status_code}")
        print(f"   Resposta: {response.text}")
    except requests.RequestException as e:
        print(f"   Erro: {e}")

if __name__ == "__main__":
    test_ddns_server()
