#!/bin/bash
# ==============================================================================
# Script de Deploy do Coletor SorveSys (Python + Java)
# Clona o código do GitHub e executa o container conectado ao MySQL.
#
# Uso:
#   chmod +x script_coleta.sh
#   sudo ./script_coleta.sh
# ==============================================================================

# --- 1. CONFIGURE AQUI O LINK DO SEU REPOSITÓRIO GITHUB ---
REPO_CAPTURA="https://github.com/SorveSys/CODIGOS_SCRIPT.git"

# --- Dados de Conexão com o Banco MySQL Existente ---
DB_HOST="${DB_HOST:-"98.89.118.4"}"     # IP ou Host do Banco MySQL
DB_USER="${DB_USER:-"agente_pedagio"}"          # Usuário do banco
DB_PASSWORD="${DB_PASSWORD:-"SenhaCaptura123"}" # Senha do banco
DB_NAME="${DB_NAME:-"sorvesys_db"}"      # Nome da base de dados

# --- Verificação de permissão Root ---
if [ "$EUID" -ne 0 ]; then 
    echo "[ERRO] Execute este script com sudo."
    exit 1
fi

echo "🚀 [1/3] Instalando dependências base e baixando o código do Git..."
export DEBIAN_FRONTEND=noninteractive
apt update -y && apt install -y git docker.io curl

systemctl enable --now docker

PASTA_CAPTURA="/opt/sorvesys-captura"

# Clona ou atualiza o repositório na pasta de build
if [ -d "$PASTA_CAPTURA/.git" ]; then
    echo "Atualizando código de captura via Git..."
    git -C "$PASTA_CAPTURA" pull
else
    echo "Clonando repositório de captura..."
    rm -rf "$PASTA_CAPTURA"
    git clone "$REPO_CAPTURA" "$PASTA_CAPTURA"
fi

cd "$PASTA_CAPTURA"

# Verifica se o arquivo captura.py foi realmente clonado
if [ ! -f "captura.py" ]; then
    echo "[ERRO CRÍTICO] O arquivo 'captura.py' não foi encontrado na raiz do repositório $REPO_CAPTURA."
    echo "Certifique-se de que o arquivo está na raiz do repositório e com o nome correto."
    exit 1
fi

# Cria um requirements.txt padrão caso não exista no repositório
if [ ! -f "requirements.txt" ]; then
cat > requirements.txt << 'EOF'
psutil==7.2.2
mysql-connector-python==26.7.0
python-dotenv==1.0.1
rich==15.0.0
speedtest-cli==2.1.3
EOF
fi

# --- 2. Geração do Dockerfile ---
echo "[2/3] Gerando o Dockerfile.captura..."
cat > Dockerfile.captura << 'EOF'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    default-jdk \
    python3 \
    python3-pip \
    wget \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copia os arquivos baixados pelo Git para dentro da imagem
COPY captura.py /app/captura.py
COPY requirements.txt /app/requirements.txt
COPY coletor.jar /app/coletor.jar

RUN pip3 install --no-cache-dir -r requirements.txt

CMD ["sh", "-c", "python3 captura.py & java -jar coletor.jar"]
EOF

# --- 3. Build e Execução do Container ---
echo "[3/3] Construindo imagem e iniciando o container..."
docker rm -f sorvesys-captura 2>/dev/null
docker build -t sorvesys-captura:1.0 -f Dockerfile.captura .

docker run -d \
  --name sorvesys-captura \
  --net=host \
  -e DB_HOST="$DB_HOST" \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e DB_NAME="$DB_NAME" \
  --restart always \
  sorvesys-captura:1.0

echo ""
echo "======================================================================"
echo "Container de Coleta (sorvesys-captura) implantado e rodando!"
echo "======================================================================"
