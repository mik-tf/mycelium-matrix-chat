#!/bin/bash

# =====================================================================================
# Mycelium-Matrix Chat One-Command Deployment Script
# =====================================================================================
# This script handles the complete deployment process for muser
# Usage: Run as muser after preparation script completes
# =====================================================================================

set -e  # Exit on any error

# =====================================================================================
# Configuration
# =====================================================================================

REPO_URL="https://github.com/mik-tf/mycelium-matrix-chat"
PROJECT_DIR="$HOME/mycelium-matrix-chat"
LOG_FILE="$HOME/mycelium-deployment.log"

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
    log "Checking deployment environment..."

    # Check if running as muser
    if [ "$USER" != "muser" ]; then
        die "This script should be run as 'muser'. Current user: $USER"
    fi

    # Check sudo access (should be passwordless)
    if ! sudo -n true 2>/dev/null; then
        die "Passwordless sudo access required. Please run preparation script first."
    fi

    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        die "No internet connectivity detected."
    fi

    success "Environment check passed"
}

# =====================================================================================
# Repository Setup
# =====================================================================================

setup_repository() {
    log "Setting up Mycelium-Matrix Chat repository..."

    # Remove existing directory if it exists
    if [ -d "$PROJECT_DIR" ]; then
        warning "Removing existing project directory..."
        rm -rf "$PROJECT_DIR"
    fi

    # Clone the repository
    log "Cloning repository..."
    git clone "$REPO_URL" "$PROJECT_DIR"

    # Navigate to project directory
    cd "$PROJECT_DIR"

    success "Repository cloned to $PROJECT_DIR"
}

# =====================================================================================
# Deployment
# =====================================================================================

run_deployment() {
    log "Starting Mycelium-Matrix Chat deployment..."

    cd "$PROJECT_DIR"

    # Make sure we're in the right directory
    if [ ! -f "Makefile" ]; then
        die "Makefile not found. Are you in the correct directory?"
    fi

    # Run the production deployment
    log "Executing production deployment..."
    make ops-production

    success "Deployment completed successfully!"
}

# =====================================================================================
# Post-Deployment
# =====================================================================================

show_results() {
    log "Deployment Summary"

    echo ""
    echo "=================================================="
    success "🎉 Mycelium-Matrix Chat Deployment Complete!"
    echo ""
    echo "📋 What was accomplished:"
    echo "  ✅ Repository cloned"
    echo "  ✅ All prerequisites verified"
    echo "  ✅ Application built and deployed"
    echo "  ✅ Services configured and started"
    echo ""
    echo "🌐 Access your application:"
    echo "  📱 Web Interface: https://your-domain.com (after DNS setup)"
    echo "  🔧 API Health: curl http://localhost:8080/api/health"
    echo "  📊 Matrix Bridge: curl http://localhost:8081/health"
    echo ""
    echo "🛠️  Management Commands:"
    echo "  📊 Check status: make ops-status"
    echo "  📋 View logs: make ops-logs"
    echo "  🔄 Restart services: make ops-restart"
    echo "  💾 Create backup: make ops-backup"
    echo ""
    echo "📝 Next Steps:"
    echo "  1. Set up DNS (optional but recommended)"
    echo "  2. Configure SSL certificates"
    echo "  3. Test the application"
    echo "  4. Set up monitoring"
    echo ""
    echo "📚 Documentation: $PROJECT_DIR/docs/"
    echo "📊 Logs: $LOG_FILE"
    echo "=================================================="
}

# =====================================================================================
# Main Execution
# =====================================================================================

main() {
    echo "🚀 Mycelium-Matrix Chat One-Command Deployment"
    echo "=============================================="
    log "Starting deployment process..."

    check_environment
    setup_repository
    run_deployment
    show_results

    echo ""
    success "🎯 Deployment completed in $(($(date +%s) - $(grep "Starting deployment" $LOG_FILE | head -1 | cut -d'[' -f2 | cut -d']' -f1 | date -f- +%s))) seconds!"
}

# Run main function
main "$@" 2>&1 | tee -a "$LOG_FILE"