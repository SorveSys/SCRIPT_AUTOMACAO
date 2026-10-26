```bash
#!/bin/bash
set -Eeuo pipefail
### Instalação e Deploy Automático - SorveSys ###
### Uso: sudo ./setup_sorvesys.sh ###

# Variáveis Globais
IP_ELASTICO="52.203.195.74"
DISCO_NOME="nvme1n1"
REPO_SITE="https://github.com/SorveSys/site-instituicional.git"
PASTA_SITE="$PWD/site-instituicional"

# Verifica se é root
if [ "$EUID" -ne 0 ]; then
    echo "Execute com sudo: sudo ./setup_sorvesys.sh"
    exit 1
fi

# Solicita a senha do banco de dados
echo "Configuração do banco de dados MySQL"
read -rsp "Digite a senha do MySQL: " SENHA_BANCO
echo ""

# Verifica se a senha foi informada
if [ -z "$SENHA_BANCO" ]; then
    echo "Erro: a senha do MySQL não pode estar vazia."
    exit 1
fi

echo "===================================================="
echo "       BEM-VINDO AO INSTALADOR SORVESYS             "
echo "===================================================="

# Atualiza os pacotes e instala dependências básicas
echo "Atualizando pacotes e instalando dependências básicas..."

apt update && apt upgrade -y > /dev/null 2>&1
apt install git wget curl -y > /dev/null 2>&1

# Instala e habilita o Docker caso não exista
if ! command -v docker &> /dev/null; then
    echo "Instalando Docker..."
    apt install docker.io -y
    systemctl enable --now docker
fi

echo "Iniciando configuração do Servidor Central (Empresa)..."

# 1. Configuração do volume de 30 GB para o banco de dados
echo "Configurando o disco /dev/$DISCO_NOME para o Banco de Dados..."

if lsblk | grep -q "$DISCO_NOME"; then

    # Verifica se o disco já está formatado em ext4
    if ! blkid "/dev/$DISCO_NOME" | grep -q "ext4"; then
        echo "Formatando o disco /dev/$DISCO_NOME..."
        mkfs.ext4 "/dev/$DISCO_NOME"
    fi

    # Cria a pasta de montagem e monta o disco
    mkdir -p /mnt/dados_banco

    if ! mount | grep -q "/mnt/dados_banco"; then
        mount "/dev/$DISCO_NOME" /mnt/dados_banco

        # Adiciona ao fstab para montagem automática
        if ! grep -q "/mnt/dados_banco" /etc/fstab; then
            echo "/dev/$DISCO_NOME /mnt/dados_banco ext4 defaults 0 0" >> /etc/fstab
        fi
    fi

    echo "Disco montado com sucesso em /mnt/dados_banco"

else
    echo "Aviso: Disco $DISCO_NOME não encontrado."
    echo "O banco usará o armazenamento padrão."
    mkdir -p /mnt/dados_banco
fi

# 2. Inicialização do banco de dados MySQL
echo "Subindo container do MySQL..."

docker rm -f sorvesys-db 2>/dev/null

docker run -d \
    --name sorvesys-db \
    --restart unless-stopped \
    -e MYSQL_ROOT_PASSWORD="$SENHA_BANCO" \
    -e MYSQL_DATABASE=sorvesys_db \
    -p 3306:3306 \
    -v /mnt/dados_banco:/var/lib/mysql \
    mysql:8.0

# 3. Configuração do site institucional / Dashboard
echo "Configurando o Site Institucional..."

if [ -d "$PASTA_SITE" ]; then
    git -C "$PASTA_SITE" pull
else
    git clone "$REPO_SITE" "$PASTA_SITE"
fi

cd "$PASTA_SITE" || exit 1

# Cria o Dockerfile para o site
cat > Dockerfile << 'EOF'
FROM node:20-alpine

WORKDIR /app

COPY . .

RUN npm install

EXPOSE 3333

CMD ["npm", "start"]
EOF

# Configura o .dockerignore
echo "node_modules" > .dockerignore

# Recria o container do site
docker rm -f sorvesys-site 2>/dev/null

docker build -t site-instituicional:1.0 .

docker run -d \
    --name sorvesys-site \
    --restart unless-stopped \
    -p 80:3333 \
    site-instituicional:1.0

# 4. Finalização
echo "===================================================="
echo "DEPLOY DA EMPRESA CONCLUÍDO COM SUCESSO!"
echo "Site / Dashboard acessível em: http://$IP_ELASTICO"
echo "Banco de Dados operando na porta 3306."
echo "===================================================="
```
