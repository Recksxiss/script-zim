#!/usr/bin/env bash

# =================================================
# BigBearCasaOS Coolify SSH Setup Script
# =================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Header
print_header() {
    echo "================================================"
    echo "$1"
    echo "================================================"
    echo
}

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
fi

# Install SSH
install_ssh() {
    case $OS in
        ubuntu|debian)
            apt update && apt install -y openssh-server
            ;;
        centos|rhel)
            yum install -y openssh-server
            ;;
        arch)
            pacman -S --noconfirm openssh
            ;;
        alpine)
            apk add openssh
            ;;
        opensuse*|sles)
            zypper install -y openssh
            ;;
    esac
}

# Determine SSH service name
ssh_service_name() {
    if systemctl list-units --all | grep -q sshd; then
        echo "sshd"
    else
        echo "ssh"
    fi
}

# Configure SSH to use /DATA/coolify/ssh/keys
configure_ssh_host() {
    local service_name
    service_name=$(ssh_service_name)

    mkdir -p /DATA/coolify/ssh/keys/root
    chmod 700 /DATA/coolify/ssh/keys/root

    # Generate key if not exists
    KEY_FILE="/DATA/coolify/ssh/keys/id.root@host.docker.internal"
    if [ ! -f "$KEY_FILE" ]; then
        ssh-keygen -t ed25519 -a 100 -f "$KEY_FILE" -q -N "" -C root@coolify
    fi

    # Copy public key to authorized_keys
    cat "${KEY_FILE}.pub" > /DATA/coolify/ssh/keys/root/authorized_keys
    chmod 600 /DATA/coolify/ssh/keys/root/authorized_keys

    # Update sshd_config
    SSHD_CONFIG="/etc/ssh/sshd_config"
    if [ -w "$SSHD_CONFIG" ]; then
        sed -i "s|^#*AuthorizedKeysFile.*|AuthorizedKeysFile /DATA/coolify/ssh/keys/%u/authorized_keys|" "$SSHD_CONFIG"
        sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/" "$SSHD_CONFIG"

        echo -e "${GREEN}Restarting SSH service...${NC}"
        systemctl restart "$service_name"
        systemctl enable "$service_name"
    else
        echo -e "${YELLOW}Warning: Cannot write to $SSHD_CONFIG, host SSH will not be modified.${NC}"
        echo -e "${YELLOW}Coolify will need to connect via SSH container.${NC}"
    fi
}

# Create SSH container as fallback
create_ssh_container() {
    mkdir -p /DATA/coolify/ssh/keys/root
    chmod 700 /DATA/coolify/ssh/keys/root

    KEY_FILE="/DATA/coolify/ssh/keys/id.root@host.docker.internal"
    if [ ! -f "$KEY_FILE" ]; then
        ssh-keygen -t ed25519 -a 100 -f "$KEY_FILE" -q -N "" -C root@coolify
    fi

    cat "${KEY_FILE}.pub" > /DATA/coolify/ssh/keys/root/authorized_keys
    chmod 600 /DATA/coolify/ssh/keys/root/authorized_keys

    docker run -d \
      --name ssh-server \
      -p 2222:22 \
      -v /DATA/coolify/ssh/keys:/root/.ssh \
      rastasheep/ubuntu-sshd:22.04 || echo "Container already exists"
    
    echo -e "${GREEN}SSH container created on port 2222${NC}"
}

# Clear Coolify cache
clear_cache() {
    echo "Clearing Coolify cache..."
    docker exec -it big-bear-coolify php artisan optimize || echo "Coolify container not running"
    echo "Cache cleared successfully!"
}

# Main
main() {
    echo "Installing SSH server..."
    install_ssh

    echo "Configuring SSH for Coolify..."
    configure_ssh_host

    echo -e "\nOptionally, you can run an SSH container as fallback..."
    read -p "Do you want to create SSH container? (y/n): " create_container
    if [[ $create_container =~ ^[Yy]$ ]]; then
        create_ssh_container
    fi

    echo -e "${GREEN}Setup complete!${NC}"
    echo "Your SSH private key is at: /DATA/coolify/ssh/keys/id.root@host.docker.internal"
}

# Menu
menu() {
    clear
    print_header "BigBearCasaOS Coolify SSH Setup V1.0"

    echo "1) Setup SSH for Coolify"
    echo "2) Clear Coolify cache"
    read -p "Enter choice (1-2): " menu_choice

    case $menu_choice in
        1) main;;
        2) clear_cache;;
        *) echo "Invalid option, exiting.";;
    esac
}

# Run
menu
