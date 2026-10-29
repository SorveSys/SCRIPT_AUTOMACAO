```bash
#!/bin/bash

set -Eeuo pipefail

# ==========================================================
# SORVESYS - INSTALACAO AUTOMATICA DOS AGENTES DE PEDAGIO
# ==========================================================

IP_ELASTICO="35.171.71.79"
DB_USER="agente_pedagio"
CONTAINER_NAME="sorvesys-captura"
IMAGE_NAME="sorvesys-captura:1.0"

REPO_URL="https://github.com/SorveSys/CODIGOS_SCRIPT.git"
BASE_DIR="/opt/sorvesys-captura"
SOURCE_DIR="${BASE_DIR}/src"

echo "======================================================="
echo "       INSTALACAO - SORVESYS CAPTURA                  "
echo "======================================================="

# Verifica permissao de administrador
if [ "$EUID" -ne 0 ]; then
    echo "ERRO: execute com sudo."
    echo "Exemplo: sudo env DB_PASS='SUA_SENHA' bash ./SCRIPT_PEDAGIO.sh"
    exit 1
fi

# Verifica se a senha foi informada
if [ -z "${DB_PASS:-}" ]; then
    echo "ERRO: a variavel DB_PASS nao foi informada."
    echo "Execute: sudo env DB_PASS='SUA_SENHA' bash ./SCRIPT_PEDAGIO.sh"
    exit 1
fi

trap 'echo "ERRO: falha na linha $LINENO. Verifique a mensagem acima."' ERR

echo
echo "[1/6] Atualizando lista de pacotes..."
export DEBIAN_FRONTEND=noninteractive
apt-get update

echo
echo "[2/6] Instalando dependencias..."
apt-get install -y docker.io git

echo
echo "[3/6] Iniciando Docker..."
systemctl enable --now docker

if ! docker info >/dev/null 2>&1; then
    echo "ERRO: o Docker nao iniciou corretamente."
    exit 1
fi

echo
echo "[4/6] Baixando os arquivos atualizados do GitHub..."

mkdir -p "$BASE_DIR"
rm -rf "$SOURCE_DIR"

git clone --depth 1 "$REPO_URL" "$SOURCE_DIR"

# Valida os arquivos necessarios
for arquivo in captura.py coletor.jar requirements.txt; do
    if [ ! -s "${SOURCE_DIR}/${arquivo}" ]; then
        echo "ERRO: arquivo ausente ou vazio: ${SOURCE_DIR}/${arquivo}"
        exit 1
    fi
done

# Atualiza o IP antigo caso esteja fixo no codigo Python
sed -i 's/98\.89\.118\.4/35.171.71.79/g' \
    "${SOURCE_DIR}/captura.py"

echo
echo "[5/6] Construindo a imagem Docker..."

cat > "${BASE_DIR}/Dockerfile.captura" <<'DOCKERFILE'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-17-jre-headless \
    python3 \
    python3-pip \
    ca-certificates \
    bash \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt /app/requirements.txt

RUN pip3 install --no-cache-dir -r /app/requirements.txt

COPY captura.py /app/captura.py
COPY coletor.jar /app/coletor.jar

CMD ["bash", "-lc", "python3 -u /app/captura.py & PID_PY=$!; java -jar /app/coletor.jar & PID_JAVA=$!; trap 'kill $PID_PY $PID_JAVA 2>/dev/null || true' TERM INT; wait -n $PID_PY $PID_JAVA; STATUS=$?; kill $PID_PY $PID_JAVA 2>/dev/null || true; wait 2>/dev/null || true; exit $STATUS"]
DOCKERFILE

docker build \
    --pull \
    --no-cache \
    -t "$IMAGE_NAME" \
    -f "${BASE_DIR}/Dockerfile.captura" \
    "$SOURCE_DIR"

echo
echo "[6/6] Removendo o container antigo e iniciando os agentes..."

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    docker rm -f "$CONTAINER_NAME"
fi

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -e DB_HOST="$IP_ELASTICO" \
    -e DB_USER="$DB_USER" \
    -e DB_PASS="$DB_PASS" \
    "$IMAGE_NAME"

sleep 5

if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" != "true" ]; then
    echo
    echo "ERRO: o container nao permaneceu em execucao."
    docker logs --tail 80 "$CONTAINER_NAME" || true
    exit 1
fi

echo
echo "======================================================="
echo "       SORVESYS INSTALADO COM SUCESSO                  "
echo "======================================================="
echo
echo "Container: $CONTAINER_NAME"
echo "Imagem:    $IMAGE_NAME"
echo "Banco:     $IP_ELASTICO"
echo
echo "Para acompanhar os logs:"
echo "sudo docker logs -f $CONTAINER_NAME"
echo
echo "Para verificar o estado:"
echo "sudo docker ps"
echo
```
