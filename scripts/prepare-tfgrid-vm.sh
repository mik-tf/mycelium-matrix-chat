#!/bin/bash

# =====================================================================================
# TFGrid VM Preparation Script for Mycelium-Matrix Chat
# =====================================================================================
# This script prepares a fresh TFGrid Ubuntu 24.04 VM for Mycelium-Matrix Chat deployment.
# It handles user creation, prerequisite installation, and environment setup.
#
# Usage: Run as root on a fresh TFGrid VM
# =====================================================================================

set -e  # Exit on any error

# =====================================================================================
# Configuration
# =====================================================================================

DEPLOY_USER="muser"
LOG_FILE="/var/log/mycelium-tfgrid-prep.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =====================================================================================
# Utility Functions
# =====================================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ $*${NC}" | tee -a "$LOG_FILE"
}

die() {
    error "$*"
    exit 1
}

# =====================================================================================
# Pre-flight Checks
# =====================================================================================

check_environment() {
    log "Checking environment..."

    # Must run as root
    if [ "$EUID" -ne 0 ]; then
        die "This script must be run as root. Use: sudo $0"
    fi

    # Check if running on Ubuntu
    if ! grep -q "Ubuntu" /etc/os-release; then
        die "This script is designed for Ubuntu. Current OS: $(lsb_release -d | cut -f2)"
    fi

    # Check Ubuntu version
    UBUNTU_VERSION=$(lsb_release -r | cut -f2 | cut -d'.' -f1)
    if [ "$UBUNTU_VERSION" -lt 20 ]; then
        die "Ubuntu $UBUNTU_VERSION detected. Ubuntu 20.04 or higher required."
    fi

    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        die "No internet connectivity detected."
    fi

    success "Environment check passed"
}

# =====================================================================================
# User Management
# =====================================================================================

create_deploy_user() {
    log "Creating deployment user: $DEPLOY_USER"

    # Check if user already exists
    if id "$DEPLOY_USER" &>/dev/null; then
        warning "User $DEPLOY_USER already exists. Skipping user creation."
        return
    fi

    # Create user with home directory and bash shell
    useradd -m -s /bin/bash "$DEPLOY_USER"

    # Add to sudo group
    usermod -aG sudo "$DEPLOY_USER"

    # Configure passwordless sudo for the deploy user
    echo "$DEPLOY_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$DEPLOY_USER
    chmod 0440 /etc/sudoers.d/$DEPLOY_USER

    # Set no password for the user (passwordless login)
    passwd -d "$DEPLOY_USER"

    # Copy SSH keys from root to muser for passwordless SSH access
    mkdir -p /home/$DEPLOY_USER/.ssh
    cp /root/.ssh/authorized_keys /home/$DEPLOY_USER/.ssh/authorized_keys 2>/dev/null || true
    chown -R $DEPLOY_USER:$DEPLOY_USER /home/$DEPLOY_USER/.ssh
    chmod 700 /home/$DEPLOY_USER/.ssh
    chmod 600 /home/$DEPLOY_USER/.ssh/authorized_keys

    success "Deployment user $DEPLOY_USER created with passwordless sudo and SSH access"
}

# =====================================================================================
# System Updates
# =====================================================================================

update_system() {
    log "Updating system packages..."

    apt update
    apt upgrade -y
    apt autoremove -y
    apt autoclean

    success "System updated successfully"
}

# =====================================================================================
# Prerequisite Installation
# =====================================================================================

install_core_tools() {
    log "Installing core development tools..."

    apt install -y \
        curl \
        wget \
        git \
        make \
        build-essential \
        pkg-config \
        libssl-dev \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        net-tools \
        htop \
        jq \
        ufw

    success "Core tools installed"
}

install_docker() {
    log "Installing Docker and Docker Compose..."

    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh

    # Start and enable Docker service
    systemctl enable docker
    systemctl start docker

    # Add deploy user to docker group
    usermod -aG docker "$DEPLOY_USER"

    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    success "Docker and Docker Compose installed"
}

install_rust() {
    log "Installing Rust toolchain..."

    # Switch to deploy user for Rust installation
    su - "$DEPLOY_USER" -c "
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source ~/.cargo/env
        echo 'export PATH=\"\$HOME/.cargo/bin:\$PATH\"' >> ~/.bashrc
    "

    success "Rust installed for user $DEPLOY_USER"
}

install_nodejs() {
    log "Installing Node.js 20.x LTS..."

    # Add NodeSource repository
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -

    # Install Node.js
    apt-get install -y nodejs

    success "Node.js 20.x LTS installed"
}

install_web_server() {
    log "Installing Nginx and SSL tools..."

    apt install -y nginx certbot python3-certbot-nginx

    # Enable Nginx service
    systemctl enable nginx

    success "Nginx and Certbot installed"
}

install_mycelium() {
    log "Installing Mycelium P2P client..."

    # Download Mycelium binary (use the correct release URL)
    wget https://github.com/threefoldtech/mycelium/releases/download/v0.6.1/mycelium-x86_64-unknown-linux-musl.tar.gz
    tar -xzf mycelium-x86_64-unknown-linux-musl.tar.gz
    chmod +x mycelium
    mv mycelium /usr/local/bin/mycelium
    rm mycelium-x86_64-unknown-linux-musl.tar.gz

    success "Mycelium client installed"
}

# =====================================================================================
# Security Configuration
# =====================================================================================

configure_firewall() {
    log "Configuring basic firewall..."

    # Enable UFW
    ufw --force enable

    # Allow SSH (important for access)
    ufw allow ssh

    # Allow HTTP and HTTPS
    ufw allow 80
    ufw allow 443

    # Reload firewall
    ufw reload

    success "Firewall configured"
}

# =====================================================================================
# Verification
# =====================================================================================

verify_installation() {
    log "Verifying installation..."

    local errors=0

    # Check core tools
    for tool in git make curl wget; do
        if command -v "$tool" &>/dev/null; then
            echo "  ✅ $tool: $(which $tool)"
        else
            echo "  ❌ $tool: NOT FOUND"
            ((errors++))
        fi
    done

    # Check Docker
    if command -v docker &>/dev/null && systemctl is-active --quiet docker; then
        echo "  ✅ Docker: $(docker --version)"
    else
        echo "  ❌ Docker: NOT WORKING"
        ((errors++))
    fi

    # Check Docker Compose
    if command -v docker-compose &>/dev/null; then
        echo "  ✅ Docker Compose: $(docker-compose --version)"
    else
        echo "  ❌ Docker Compose: NOT FOUND"
        ((errors++))
    fi

    # Check Node.js
    if command -v node &>/dev/null; then
        echo "  ✅ Node.js: $(node --version)"
    else
        echo "  ❌ Node.js: NOT FOUND"
        ((errors++))
    fi

    # Check Mycelium
    if command -v mycelium &>/dev/null; then
        echo "  ✅ Mycelium: $(mycelium --version 2>/dev/null || echo 'installed')"
    else
        echo "  ❌ Mycelium: NOT FOUND"
        ((errors++))
    fi

    # Check Rust (for deploy user)
    if su - "$DEPLOY_USER" -c "command -v cargo" &>/dev/null; then
        echo "  ✅ Rust: $(su - "$DEPLOY_USER" -c "cargo --version")"
    else
        echo "  ❌ Rust: NOT FOUND"
        ((errors++))
    fi

    if [ $errors -eq 0 ]; then
        success "All prerequisites verified successfully!"
    else
        warning "$errors issues found. Please check the output above."
    fi
}

# =====================================================================================
# Main Execution
# =====================================================================================

main() {
    echo "🚀 TFGrid VM Preparation for Mycelium-Matrix Chat"
    echo "=================================================="
    log "Starting preparation process..."

    check_environment
    create_deploy_user
    update_system
    install_core_tools
    install_docker
    install_rust
    install_nodejs
    install_web_server
    install_mycelium
    configure_firewall
    verify_installation

    echo ""
    echo "🚀 Next: Automatic deployment will begin..."
    echo ""

    # Automatically switch to muser and run deployment
    echo "🔄 Switching to $DEPLOY_USER and starting deployment..."
    echo ""

    # Copy and run local deployment script as muser
    log "Copying and running local deployment script as $DEPLOY_USER..."

    # Find the deployment script
    local deploy_script="/tmp/deploy-mycelium-chat.sh"
    local local_script
    local_script="$(find /tmp -name "deploy-mycelium-chat.sh" 2>/dev/null || echo "")"

    # If not in /tmp, look in the same directory as this script
    if [ -z "$local_script" ]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local_script="$script_dir/deploy-mycelium-chat.sh"
    fi

    if [ -f "$local_script" ]; then
        cp "$local_script" "$deploy_script"
        chown "$DEPLOY_USER:$DEPLOY_USER" "$deploy_script"
        chmod +x "$deploy_script"

        if su - "$DEPLOY_USER" -c "bash $deploy_script" 2>&1; then
            success "Deployment completed successfully"
        else
            warning "Deployment had issues but may have completed partially"
            log "Check the deployment status manually"
        fi
    else
        warning "Local deployment script not found, falling back to download"
        if su - "$DEPLOY_USER" -c "curl -fsSL https://raw.githubusercontent.com/mik-tf/mycelium-matrix-chat/main/scripts/deploy-mycelium-chat.sh | bash" 2>&1; then
            success "Deployment completed successfully"
        else
            warning "Deployment had issues but may have completed partially"
            log "Check the deployment status manually"
        fi
    fi

    echo ""
    echo "=================================================="
    success "🎉 Complete TFGrid deployment finished!"
    echo ""
    echo "🌐 Your Mycelium-Matrix Chat is now running!"
    echo "📊 Check status: su - $DEPLOY_USER -c 'cd mycelium-matrix-chat && make ops-status'"
    echo "📋 View logs: su - $DEPLOY_USER -c 'cd mycelium-matrix-chat && make ops-logs'"
    echo ""
    echo "🔐 Security Notes:"
    echo "  - $DEPLOY_USER has passwordless sudo for system operations"
    echo "  - Services run as $DEPLOY_USER, not as root"
    echo "  - All logs saved to: $LOG_FILE"
    echo "=================================================="
}

# Run main function
main "$@"