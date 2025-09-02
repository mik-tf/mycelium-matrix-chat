#!/bin/bash

# =====================================================================================
# Mycelium-Matrix Chat Production Deployment Script
# =====================================================================================
# This script automates the complete production deployment of Mycelium-Matrix Chat
# on Ubuntu 24.04 running on ThreeFold Grid with Mycelium P2P networking.
#
# Usage: ./scripts/deployment-prod.sh [options]
#
# Options:
#   --domain DOMAIN        Set the domain name (default: chat.projectmycelium.org)
#   --email EMAIL          Set admin email for SSL certificates
#   --dry-run             Show what would be done without executing
#   --help                Show this help message
#
# Example:
#   ./scripts/deployment-prod.sh --domain chat.projectmycelium.org --email admin@projectmycelium.org
# =====================================================================================

set -e  # Exit on any error

# =====================================================================================
# Configuration Variables
# =====================================================================================

DOMAIN="${DOMAIN:-chat.projectmycelium.org}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@projectmycelium.org}"
DRY_RUN=false
LOG_FILE="/var/log/mycelium-matrix-deployment.log"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

check_dependencies() {
    log "Checking system dependencies..."

    # Check if running on Ubuntu
    if ! grep -q "Ubuntu" /etc/os-release; then
        die "This script is designed for Ubuntu. Current OS: $(lsb_release -d | cut -f2)"
    fi

    # Check Ubuntu version
    UBUNTU_VERSION=$(lsb_release -r | cut -f2 | cut -d'.' -f1)
    if [ "$UBUNTU_VERSION" -lt 24 ]; then
        warning "Ubuntu $UBUNTU_VERSION detected. Ubuntu 24.04 recommended."
    fi

    # Check if running as root or with sudo
    if [ "$EUID" -eq 0 ]; then
        die "Please run this script as a regular user with sudo privileges, not as root."
    fi

    # Check sudo access
    if ! sudo -n true 2>/dev/null; then
        die "This script requires sudo privileges. Please run with a user that has sudo access."
    fi

    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        die "No internet connectivity detected."
    fi

    success "System dependencies check passed"
}

check_mycelium() {
    log "Checking Mycelium P2P network..."

    # Check if mycelium is installed
    if ! command -v mycelium &>/dev/null; then
        warning "Mycelium not found. Installing..."
        install_mycelium
    fi

    # Check if mycelium service is running
    if ! systemctl is-active --quiet myceliumd 2>/dev/null; then
        warning "Mycelium service not running. Starting..."
        sudo systemctl enable myceliumd
        sudo systemctl start myceliumd
        sleep 5
    fi

    # Get mycelium status
    if command -v mycelium &>/dev/null; then
        MYCELIUM_STATUS=$(mycelium --status 2>/dev/null || echo "unknown")
        success "Mycelium status: $MYCELIUM_STATUS"
    else
        warning "Could not determine Mycelium status"
    fi
}

# =====================================================================================
# Installation Functions
# =====================================================================================

install_system_dependencies() {
    log "Installing system dependencies..."

    # Update package list
    sudo apt update

    # Install essential packages
    sudo apt install -y \
        curl \
        wget \
        git \
        build-essential \
        pkg-config \
        libssl-dev \
        postgresql \
        postgresql-contrib \
        nginx \
        certbot \
        python3-certbot-nginx \
        ufw \
        htop \
        jq \
        net-tools \
        software-properties-common

    success "System dependencies installed"
}

install_rust() {
    log "Installing Rust..."

    if ! command -v cargo &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source "$HOME/.cargo/env"
        export PATH="$HOME/.cargo/bin:$PATH"
    fi

    # Verify installation
    cargo --version || die "Rust installation failed"

    success "Rust installed: $(cargo --version)"
}

install_nodejs() {
    log "Installing Node.js..."

    if ! command -v node &>/dev/null; then
        # Install Node.js 18.x LTS
        curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    # Verify installation
    node --version || die "Node.js installation failed"
    npm --version || die "npm installation failed"

    success "Node.js installed: $(node --version)"
}

install_mycelium() {
    log "Installing Mycelium..."

    # Install Mycelium using the official installer
    curl -fsSL https://mycelium.fly.dev/install | sh

    # Add to PATH
    export PATH="$HOME/.mycelium:$PATH"

    # Enable and start service
    sudo systemctl enable myceliumd
    sudo systemctl start myceliumd

    success "Mycelium installed and started"
}

install_docker() {
    log "Installing Docker..."

    if ! command -v docker &>/dev/null; then
        # Install Docker
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker "$USER"

        # Install Docker Compose
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi

    success "Docker installed"
}

# =====================================================================================
# Configuration Functions
# =====================================================================================

setup_firewall() {
    log "Configuring firewall..."

    # Enable UFW
    sudo ufw --force enable

    # Allow SSH (important for Mycelium access)
    sudo ufw allow ssh

    # Allow HTTP and HTTPS
    sudo ufw allow 80
    sudo ufw allow 443

    # Allow Matrix federation port
    sudo ufw allow 8448

    # Allow Mycelium ports
    sudo ufw allow 9651

    # Reload firewall
    sudo ufw reload

    success "Firewall configured"
}

setup_postgresql() {
    log "Setting up PostgreSQL database..."

    # Start PostgreSQL service
    sudo systemctl enable postgresql
    sudo systemctl start postgresql

    # Create database and user
    sudo -u postgres psql -c "CREATE USER mycelium_user WITH PASSWORD 'secure_password_$(openssl rand -hex 8)';" 2>/dev/null || true
    sudo -u postgres psql -c "CREATE DATABASE mycelium_matrix OWNER mycelium_user;" 2>/dev/null || true
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE mycelium_matrix TO mycelium_user;" 2>/dev/null || true

    success "PostgreSQL database configured"
}

setup_nginx() {
    log "Configuring Nginx..."

    # Create Nginx configuration
    sudo tee /etc/nginx/sites-available/$DOMAIN > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    # Redirect HTTP to HTTPS
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;

    # SSL configuration (will be updated by Certbot)
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    # Frontend (React app)
    location / {
        proxy_pass http://localhost:5173;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }

    # API Gateway
    location /api/ {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;
    }

    # Matrix Federation API
    location /_matrix/ {
        proxy_pass http://localhost:8081;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 86400;

        # Federation-specific headers
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Server \$host;
    }

    # Mycelium API
    location /mycelium/ {
        proxy_pass http://localhost:8989;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Static files caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

    # Enable site
    sudo ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default

    # Test configuration
    sudo nginx -t || die "Nginx configuration test failed"

    # Reload Nginx
    sudo systemctl reload nginx

    success "Nginx configured for $DOMAIN"
}

setup_ssl() {
    log "Setting up SSL certificates..."

    # Use Certbot to get SSL certificate
    sudo certbot --nginx \
        --non-interactive \
        --agree-tos \
        --email "$ADMIN_EMAIL" \
        -d "$DOMAIN" \
        -d "www.$DOMAIN"

    success "SSL certificates obtained and configured"
}

# =====================================================================================
# Application Deployment
# =====================================================================================

build_application() {
    log "Building Mycelium-Matrix Chat application..."

    cd "$PROJECT_ROOT"

    # Build Rust services
    log "Building Matrix Bridge..."
    cd backend/matrix-bridge
    cargo build --release

    log "Building Web Gateway..."
    cd ../web-gateway
    cargo build --release

    # Build frontend
    log "Building React frontend..."
    cd ../../frontend
    npm install
    npm run build

    success "Application built successfully"
}

deploy_services() {
    log "Deploying application services..."

    cd "$PROJECT_ROOT"

    # Create systemd service for Matrix Bridge
    sudo tee /etc/systemd/system/matrix-bridge.service > /dev/null <<EOF
[Unit]
Description=Mycelium Matrix Bridge Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_ROOT/backend/matrix-bridge
ExecStart=$PROJECT_ROOT/backend/matrix-bridge/target/release/matrix-bridge
Restart=always
RestartSec=5
Environment=RUST_LOG=info
Environment=DATABASE_URL=postgresql://mycelium_user:secure_password@localhost/mycelium_matrix

[Install]
WantedBy=multi-user.target
EOF

    # Create systemd service for Web Gateway
    sudo tee /etc/systemd/system/web-gateway.service > /dev/null <<EOF
[Unit]
Description=Mycelium Web Gateway Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_ROOT/backend/web-gateway
ExecStart=$PROJECT_ROOT/backend/web-gateway/target/release/web-gateway
Restart=always
RestartSec=5
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start services
    sudo systemctl daemon-reload
    sudo systemctl enable matrix-bridge
    sudo systemctl enable web-gateway
    sudo systemctl start matrix-bridge
    sudo systemctl start web-gateway

    success "Application services deployed and started"
}

deploy_frontend() {
    log "Deploying frontend application..."

    cd "$PROJECT_ROOT/frontend"

    # Install serve for production serving
    npm install -g serve

    # Create systemd service for frontend
    sudo tee /etc/systemd/system/mycelium-frontend.service > /dev/null <<EOF
[Unit]
Description=Mycelium Frontend Service
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PROJECT_ROOT/frontend
ExecStart=serve -s dist -l 5173
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start frontend service
    sudo systemctl enable mycelium-frontend
    sudo systemctl start mycelium-frontend

    success "Frontend deployed and started"
}

# =====================================================================================
# Validation Functions
# =====================================================================================

validate_deployment() {
    log "Validating deployment..."

    # Wait for services to start
    sleep 10

    # Check service status
    if ! systemctl is-active --quiet matrix-bridge; then
        error "Matrix Bridge service failed to start"
        return 1
    fi

    if ! systemctl is-active --quiet web-gateway; then
        error "Web Gateway service failed to start"
        return 1
    fi

    if ! systemctl is-active --quiet mycelium-frontend; then
        error "Frontend service failed to start"
        return 1
    fi

    # Check HTTP endpoints
    if ! curl -s -k https://$DOMAIN/api/health > /dev/null; then
        error "API health check failed"
        return 1
    fi

    if ! curl -s -k https://$DOMAIN/_matrix/federation/v1/version > /dev/null; then
        error "Matrix federation check failed"
        return 1
    fi

    if ! curl -s -k https://$DOMAIN/ | grep -q "html"; then
        error "Frontend check failed"
        return 1
    fi

    success "Deployment validation passed"
}

# =====================================================================================
# Main Deployment Function
# =====================================================================================

main() {
    log "Starting Mycelium-Matrix Chat production deployment..."
    log "Domain: $DOMAIN"
    log "Admin Email: $ADMIN_EMAIL"
    log "Project Root: $PROJECT_ROOT"

    # Create log file
    sudo touch "$LOG_FILE"
    sudo chown "$USER:$USER" "$LOG_FILE"

    # Phase 1: Pre-flight checks
    check_dependencies
    check_mycelium

    # Phase 2: System setup
    install_system_dependencies
    install_rust
    install_nodejs
    install_docker

    # Phase 3: Security and networking
    setup_firewall

    # Phase 4: Database setup
    setup_postgresql

    # Phase 5: Web server configuration
    setup_nginx

    # Phase 6: SSL setup
    setup_ssl

    # Phase 7: Application deployment
    build_application
    deploy_services
    deploy_frontend

    # Phase 8: Validation
    validate_deployment

    # Success message
    echo ""
    echo "=================================================================================="
    success "🎉 DEPLOYMENT COMPLETE!"
    echo ""
    echo "🌐 Website: https://$DOMAIN"
    echo "🔧 API: https://$DOMAIN/api"
    echo "📊 Matrix Bridge: https://$DOMAIN/_matrix/federation/v1/version"
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Configure DNS A record: $DOMAIN → $(curl -s ifconfig.me)"
    echo "  2. Test the application in your browser"
    echo "  3. Monitor logs: sudo journalctl -u matrix-bridge -f"
    echo "  4. Set up monitoring and backups"
    echo ""
    echo "📚 Documentation:"
    echo "  - Deployment logs: $LOG_FILE"
    echo "  - Service status: sudo systemctl status matrix-bridge"
    echo "  - DNS Setup: ./docs/ops/dns-setup.md"
    echo "=================================================================================="
}

# =====================================================================================
# Command Line Argument Processing
# =====================================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            DOMAIN="$2"
            shift 2
            ;;
        --email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            echo "Mycelium-Matrix Chat Production Deployment Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --domain DOMAIN        Set the domain name (default: chat.projectmycelium.org)"
            echo "  --email EMAIL          Set admin email for SSL certificates"
            echo "  --dry-run             Show what would be done without executing"
            echo "  --help                Show this help message"
            echo ""
            echo "Example:"
            echo "  $0 --domain chat.projectmycelium.org --email admin@projectmycelium.org"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
if [ "$DRY_RUN" = true ]; then
    warning "DRY RUN MODE - No changes will be made"
    echo "Would execute: main()"
else
    main
fi