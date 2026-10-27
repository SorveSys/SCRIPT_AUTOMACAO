#!/bin/bash
### Deploy - Servidor Central SorveSys (Empresa) ###

# Limpa a tela para um visual mais limpo
clear

echo "======================================================="
echo "       DEPLOY SORVESYS - SERVIDOR CENTRAL (AWS EC2)    "
echo "======================================================="

IP_ELASTICO="52.203.195.74"
DISCO_NOME="nvme1n1"
REPO_SITE="https://github.com/SorveSys/site-instituicional.git"
PASTA_SITE="$PWD/site-instituicional"

if [ "$EUID" -ne 0 ]; then 
    echo "Por favor, execute com permissão de administrador: sudo ./setup_empresa.sh"
    exit 1
fi

# Solicita a senha de forma segura (os caracteres não aparecem enquanto digita)
read -s -p "Defina a senha para o Banco de Dados (MySQL): " SENHA_BANCO
echo "" # Quebra de linha após o usuário digitar a senha escondida
echo "======================================================="

echo "Atualizando sistema e instalando dependências base..."
apt update && apt upgrade -y > /dev/null 2>&1
apt install git wget curl -y > /dev/null 2>&1

if ! command -v docker &> /dev/null; then
    echo "Instalando Docker..."
    apt install docker.io -y > /dev/null 2>&1
    systemctl enable --now docker
fi

echo ""
read -p "Agora será instalado o Banco de Dados. Deseja prosseguir? (S/N) " RESP_DB
if [[ "$RESP_DB" =~ ^[Ss]$ ]]; then
    echo "Configurando o disco /dev/$DISCO_NOME para o Banco de Dados..."
    if lsblk | grep -q "$DISCO_NOME"; then
        if ! blkid /dev/$DISCO_NOME | grep -q "ext4"; then
            mkfs.ext4 /dev/$DISCO_NOME
        fi
        mkdir -p /mnt/dados_banco
        if ! mount | grep -q "/mnt/dados_banco"; then
            mount /dev/$DISCO_NOME /mnt/dados_banco
            echo "/dev/$DISCO_NOME /mnt/dados_banco ext4 defaults 0 0" >> /etc/fstab
        fi
    else
        mkdir -p /mnt/dados_banco
    fi

    docker rm -f sorvesys-db 2>/dev/null
    docker run -d --name sorvesys-db --restart unless-stopped \
        -e MYSQL_ROOT_PASSWORD=$SENHA_BANCO \
        -e MYSQL_DATABASE=sorvesys_db \
        -p 3306:3306 -v /mnt/dados_banco:/var/lib/mysql mysql:8.0
    echo "Banco de dados MySQL operando na porta 3306."
fi

echo ""
read -p "Agora será instalado o Site Institucional e Dashboard. Deseja prosseguir? (S/N) " RESP_SITE
if [[ "$RESP_SITE" =~ ^[Ss]$ ]]; then
    echo "Baixando e configurando o Site..."
    if [ -d "$PASTA_SITE" ]; then
        git -C "$PASTA_SITE" pull
    else
        git clone "$REPO_SITE" "$PASTA_SITE"
    fi
    
    cd "$PASTA_SITE"
    cat > Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY . .
RUN npm install
EXPOSE 3333
CMD ["npm", "start"]
EOF
    echo "node_modules" > .dockerignore
    docker rm -f sorvesys-site 2>/dev/null
    docker build -t site-instituicional:1.0 . > /dev/null 2>&1
    docker run -d --name sorvesys-site --restart unless-stopped -p 80:3333 site-instituicional:1.0
    echo "Site acessível em: http://$IP_ELASTICO"
fi

echo ""
echo "Instalação do Servidor Central finalizada!"
