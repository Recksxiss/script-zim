#!/usr/bin/env bash

# Set strict error handling
set -euo pipefail

# Set text colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root (use sudo)${NC}"
    exit 1
fi

# Function to print header
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

# Install SSH based on distro
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

# Configure SSH
configure_ssh() {
    local service_name
    service_name=$(ssh_service_name)

    # Backup original config
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Ask user for PermitRootLogin preference
    echo "Select PermitRootLogin setting:"
    echo "1) yes            - Allows root login with password and key-based authentication"
    echo "2) without-password - Allows root login with key-based authentication only"
    echo "3) prohibit-password - Same as without-password (recommended for security)"
    read -p "Enter choice (1-3): " root_login_choice

    case $root_login_choice in
        1) root_login="yes";;
        2) root_login="without-password";;
        3) root_login="prohibit-password";;
        *) root_login="prohibit-password";;
    esac

    # Update SSH settings
    sed -i "s/^#*PermitRootLogin.*/PermitRootLogin ${root_login}/" /etc/ssh/sshd_config
    sed -i "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/" /etc/ssh/sshd_config

    # Create required directories in /DATA
    mkdir -p /DATA/coolify/ssh/keys
    mkdir -p ~/.ssh

    # Generate SSH key pair
    ssh-keygen -t ed25519 -a 100 -f /DATA/coolify/ssh/keys/id.root@host.docker.internal -q -N "" -C root@coolify

    # Set ownership and permissions
    chown 9999 /DATA/coolify/ssh/keys/id.root@host.docker.internal
    cat /DATA/coolify/ssh/keys/id.root@host.docker.internal.pub >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
    chmod 700 ~/.ssh

    # Restart SSH service
    systemctl restart "$service_name"
    systemctl enable "$service_name"
}

clear_cache() {
    echo "Clearing Coolify cache..."
    docker exec -it big-bear-coolify php artisan optimize
    echo "Cache cleared successfully!"
}

# Main execution
main() {
    # Create Docker network for Coolify if it doesn't exist
    if ! docker network inspect coolify >/dev/null 2>&1; then
        docker network create coolify
    fi

    echo "Installing SSH server..."
    install_ssh
    
    echo "Configuring SSH for Coolify..."
    configure_ssh
    
    echo "Verifying SSH service status..."
    systemctl status "$(ssh_service_name)"    
    
    echo "Setup complete! Your SSH key is located at /DATA/coolify/ssh/keys/id.root@host.docker.internal"
    
    read -p "Would you like to display the private key now? (y/n): " show_key
    if [[ $show_key =~ ^[Yy]$ ]]; then
        echo "Here's your private key to copy into Coolify's Keys & Tokens menu:"
        echo "----------------------------------------------------------------"
        cat /DATA/coolify/ssh/keys/id.root@host.docker.internal
        echo "----------------------------------------------------------------"
    fi
}

menu() {
    # Main menu
    clear
    print_header "BigBearCasaOS Coolify Setup V0.0.1"

    echo "Here are some links:"
    echo "https://community.bigbeartechworld.com"
    echo "https://github.com/BigBearTechWorld"
    echo ""
    echo "If you would like to support me, please consider buying me a tea:"
    echo "https://ko-fi.com/bigbeartechworld"
    echo ""
    echo "===================="
    echo "Please select an option:"
    echo "1) Setup SSH and configurations"
    echo "2) Clear cache"
    read -p "Enter choice (1-2): " menu_choice

    case $menu_choice in
        1) main;;
        2) clear_cache;;
        *) echo "Invalid option selected. Exiting.";;
    esac
}

# Run the menu
menu
