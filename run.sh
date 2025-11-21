#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SSH_VOLUME="/DATA/AppData/big-bear-coolify/ssh/mux"
SSH_KEY="$SSH_VOLUME/id.root@host.docker.internal"

echo "================================================"
echo "BigBearCasaOS Coolify SSH Setup v3.0"
echo "================================================"
echo

# Criar pasta de SSH se não existir
mkdir -p "$SSH_VOLUME"

# Gerar chave SSH se não existir
if [ ! -f "$SSH_KEY" ]; then
    echo -e "${YELLOW}Generating SSH key for Coolify...${NC}"
    ssh-keygen -t ed25519 -a 100 -f "$SSH_KEY" -N "" -C "root@coolify"
    echo -e "${GREEN}SSH key generated at $SSH_KEY${NC}"
else
    echo -e "${YELLOW}SSH key already exists at $SSH_KEY${NC}"
fi

echo
echo "Coolify will use the SSH key in $SSH_VOLUME."
echo

# Perguntar se quer criar container SSH de fallback
read -p "Do you want to create an SSH fallback container? (y/n): " CREATE_CONTAINER

if [[ $CREATE_CONTAINER =~ ^[Yy]$ ]]; then
    if docker ps -a --format '{{.Names}}' | grep -q "^coolify-ssh\$"; then
        echo -e "${YELLOW}SSH container already exists. Starting it...${NC}"
        docker start coolify-ssh
    else
        echo -e "${YELLOW}Creating SSH container on port 2222...${NC}"
        docker run -d \
            --name coolify-ssh \
            -p 2222:22 \
            -v "$SSH_VOLUME":/config/ssh \
            -e PUID=1000 \
            -e PGID=1000 \
            -e TZ=Etc/UTC \
            -e PASSWORD_ACCESS=false \
            linuxserver/openssh-server || {
                echo -e "${RED}Failed to create SSH container.${NC}"
                exit 1
            }
    fi
    echo -e "${GREEN}SSH container is running on port 2222.${NC}"
fi

echo
echo -e "${GREEN}Setup complete!${NC}"
echo "Use the private key at: $SSH_KEY"
echo "Add the public key (.pub) to the servers Coolify should manage."
