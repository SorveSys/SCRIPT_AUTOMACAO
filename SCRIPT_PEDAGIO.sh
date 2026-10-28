#!/bin/bash
# ==============================================================================
# Script do Coletor SorveSys (Python para Hardware + Java para Rede)
# Apenas constrói e roda o container de captura, conectando ao banco existente.
#
# Uso:
#   chmod +x script_coleta.sh
#   sudo ./script_coleta.sh
# ==============================================================================

# --- Configurações do Banco de Dados Existente ---
# Altere os valores abaixo ou passe as variáveis antes de rodar o script
DB_HOST="${DB_HOST:-"98.89.118.4"}"     # IP ou Host do Servidor MySQL
DB_USER="${DB_USER:-"agente_pedagio"}"          # Usuário do banco
DB_PASSWORD="${DB_PASSWORD:-"senha"}" # Senha do banco
DB_NAME="${DB_NAME:-"sorvesys_db"}"      # Nome da base de dados

# --- 1. Verificação de permissão de Superusuário ---
if [ "$EUID" -ne 0 ]; then 
    echo "[ERRO] Execute este script com permissão de sudo."
    echo "Uso: sudo ./script_coleta.sh"
    exit 1
fi

echo "[1/2] Verificando ambiente Docker e preparando diretórios..."
export DEBIAN_FRONTEND=noninteractive
apt update -y && apt install -y curl docker.io

# Garante que o serviço do Docker está rodando
systemctl enable --now docker

PASTA_CAPTURA="/opt/sorvesys-captura"
mkdir -p "$PASTA_CAPTURA"

# Copia os arquivos do diretório atual para a pasta de build
[ -f "$PWD/captura.py" ] && cp "$PWD/captura.py" "$PASTA_CAPTURA/"
[ -f "$PWD/requirements.txt" ] && cp "$PWD/requirements.txt" "$PASTA_CAPTURA/"
[ -f "$PWD/coletor.jar" ] && cp "$PWD/coletor.jar" "$PASTA_CAPTURA/"

cd "$PASTA_CAPTURA"

# Garante o arquivo requirements.txt caso não exista localmente
if [ ! -f "requirements.txt" ]; then
cat > requirements.txt << 'EOF'
psutil==7.2.2
mysql-connector-python==26.7.0
python-dotenv==1.0.1
rich==15.0.0
speedtest-cli==2.1.3
EOF
fi

# --- 2. Geração do Dockerfile Híbrido ---
cat > Dockerfile.captura << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Instala Java JDK (Rede), Python 3 e PIP (Hardware)
RUN apt-get update && apt-get install -y \
    default-jdk \
    python3 \
    python3-pip \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copia os executáveis e dependências para o container
COPY captura.py /app/captura.py
COPY requirements.txt /app/requirements.txt
COPY coletor.jar /app/coletor.jar

# Instala as bibliotecas do Python
RUN pip3 install --no-cache-dir -r requirements.txt

# Executa o script Python em background (&) e o JAR do Java em foreground
CMD ["sh", "-c", "python3 captura.py & java -jar coletor.jar"]
EOF

# --- 3. Build e Execução do Container ---
echo "[2/2] Construindo imagem e subindo container de captura..."
docker rm -f sorvesys-captura 2>/dev/null
docker build -t sorvesys-captura:1.0 -f Dockerfile.captura .

# O modo --net=host permite ao container acessar facilmentes o MySQL em 127.0.0.1 ou IPs da rede
docker run -d \
  --name sorvesys-captura \
  --net=host \
  -e DB_HOST="$DB_HOST" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e DB_NAME="$DB_NAME" \
  --restart always \
  sorvesys-captura:1.0

# --- Resumo da Execução ---
echo ""
echo "======================================================================"
echo "Container de Coleta (Python + Java) iniciado com sucesso!"
echo "Apontando para o Banco MySQL em: $DB_HOST (Base: $DB_NAME)"
echo "======================================================================"
