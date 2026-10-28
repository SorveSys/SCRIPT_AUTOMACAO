#!/bin/bash
### Deploy Automático - Praça de Pedágio SorveSys (Captura) ###

# Limpa a tela para visual profissional
clear

echo "======================================================="
echo "       INICIANDO INSTALAÇÃO - SORVESYS CAPTURA         "
echo "======================================================="
echo "Configurando ambiente de monitoramento de hardware..."

# Variáveis configuradas automaticamente (Sem interação do usuário)
IP_ELASTICO="IP_ELASTICO_SERVER"
DB_USER="agente_pedagio"
DB_PASS="SenhaCaptura123"

if [ "$EUID" -ne 0 ]; then 
    echo "Por favor, execute com permissão de administrador: sudo ./setup_pedagio.sh"
    exit 1
fi

echo "[1/4] Atualizando sistema e instalando dependências base..."
apt update && apt upgrade -y > /dev/null 2>&1

if ! command -v docker &> /dev/null; then
    echo "[2/4] Instalando motor de virtualização (Docker)..."
    apt install docker.io -y > /dev/null 2>&1
    systemctl enable --now docker
else
    echo "[2/4] Docker já instalado. Pulando etapa..."
fi

echo "[3/4] Baixando os agentes de captura (Java e Python)..."
mkdir -p /opt/sorvesys-captura
cd /opt/sorvesys-captura

cat > Dockerfile.captura << 'EOF'
FROM ubuntu:22.04
RUN apt-get update && apt-get install -y default-jdk python3 python3-pip python3-psutil wget
WORKDIR /app

# Substitua pelas URLs RAW originais dos executáveis
RUN wget -q -O captura_python.py "https://github.com/SorveSys/Script_Automacao/raw/refs/heads/main/scripty"
RUN wget -q -O captura_java.jar "https://github.com/SorveSys/Script_Automacao/raw/refs/heads/main/coletor.jar"

CMD ["sh", "-c", "python3 captura_python.py & java -jar captura_java.jar"]
EOF

echo "[4/4] Iniciando os agentes de monitoramento..."
docker rm -f sorvesys-captura 2>/dev/null
docker build -t sorvesys-captura:1.0 -f Dockerfile.captura . > /dev/null 2>&1

# O container agora sobe utilizando as credenciais do usuário restrito, 
# que nós "chumbamos" nas variáveis lá em cima de forma segura.
docker run -d --name sorvesys-captura --restart unless-stopped \
    -e DB_HOST=$IP_ELASTICO \
    -e DB_USER=$DB_USER \
    -e DB_PASS=$DB_PASS \
    sorvesys-captura:1.0
    
echo "======================================================="
echo "INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo "Os agentes já estão rodando em segundo plano e enviando"
echo "os dados de consumo desta máquina para a central."
echo "======================================================="
