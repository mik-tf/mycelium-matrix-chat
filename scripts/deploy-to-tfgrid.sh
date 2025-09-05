#!/bin/bash

# =====================================================================================
# Local TFGrid Deployment Script
# =====================================================================================
# This script runs on your local machine and automatically deploys
# Mycelium-Matrix Chat to a TFGrid VM using its Mycelium IP address.
#
# Usage: ./deploy-to-tfgrid.sh [MYCELIUM_IP]
# Example: ./deploy-to-tfgrid.sh 400::abcd:1234:5678:9abc
# =====================================================================================

set -e  # Exit on any error

# =====================================================================================
# Configuration
# =====================================================================================

MYCELIUM_IP=""
SSH_USER="root"
SSH_KEY="$HOME/.ssh/id_ed25519"
PREPARATION_SCRIPT_URL="https://raw.githubusercontent.com/mik-tf/mycelium-matrix-chat/main/scripts/prepare-tfgrid-vm.sh"
DEPLOYMENT_SCRIPT_URL="https://raw.githubusercontent.com/mik-tf/mycelium-matrix-chat/main/scripts/deploy-mycelium-chat.sh"

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
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" >&2
}

success() {
    echo -e "${GREEN}✅ $*${NC}" >&2
}

warning() {
    echo -e "${YELLOW}⚠️  $*${NC}" >&2
}

error() {
    echo -e "${RED}❌ $*${NC}" >&2
}

die() {
    error "$*"
    exit 1
}

# =====================================================================================
# Validation Functions
# =====================================================================================

validate_mycelium_ip() {
    local ip="$1"

    # Basic IPv6 validation for Mycelium addresses
    if [[ ! "$ip" =~ ^[0-9a-f:]+$ ]]; then
        die "Invalid Mycelium IP format. Expected IPv6 format like: 400::abcd:1234:5678:9abc"
    fi

    # Check if it looks like a Mycelium address (starts with 4)
    if [[ ! "$ip" =~ ^4 ]]; then
        warning "IP doesn't start with '4' - this might not be a valid Mycelium address"
    fi
}

check_ssh_connectivity() {
    local ip="$1"
    local user="$2"
    local key="$3"

    log "Testing SSH connectivity to $user@$ip..."

    # Test SSH connection
    if ! ssh -i "$key" -o ConnectTimeout=30 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$user@$ip" "echo 'SSH connection successful'" 2>/dev/null; then
        die "Cannot connect to $user@$ip via SSH. Please ensure:
        1. SSH key is properly configured
        2. Mycelium network is connected on your local machine
        3. The VM is running and accessible"
    fi

    success "SSH connectivity confirmed"
}

check_vm_requirements() {
    local ip="$1"
    local user="$2"
    local key="$3"

    log "Checking VM requirements..."

    # Check if running Ubuntu
    local os_info
    os_info=$(ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$user@$ip" "cat /etc/os-release | grep -i ubuntu || echo 'Not Ubuntu'" 2>/dev/null)

    if [[ "$os_info" == *"Not Ubuntu"* ]]; then
        die "VM is not running Ubuntu. This script requires Ubuntu 20.04 or higher."
    fi

    # Check Ubuntu version
    local ubuntu_version
    ubuntu_version=$(ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$user@$ip" "lsb_release -r | cut -f2 | cut -d'.' -f1" 2>/dev/null)

    if [ "$ubuntu_version" -lt 20 ]; then
        die "Ubuntu $ubuntu_version detected. Ubuntu 20.04 or higher required."
    fi

    success "VM requirements met (Ubuntu $ubuntu_version)"
}

# =====================================================================================
# Deployment Functions
# =====================================================================================

run_preparation() {
    local ip="$1"
    local user="$2"
    local key="$3"

    log "🚀 Starting VM preparation..."
    echo "" >&2

    # Run the preparation script on the remote VM
    ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$user@$ip" "bash -c 'curl -fsSL $PREPARATION_SCRIPT_URL | bash'" 2>&1

    success "VM preparation completed!"
}

monitor_deployment() {
    local ip="$1"
    local user="$2"
    local key="$3"

    log "📊 Monitoring deployment progress..."

    # Wait a bit for services to start
    sleep 5

    # Check if services are running
    local services_status
    services_status=$(ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "muser@$ip" "
        cd ~/mycelium-matrix-chat 2>/dev/null || echo 'Project directory not found'
        make ops-status 2>/dev/null || echo 'Status check failed'
    " 2>/dev/null || echo "Cannot check status yet")

    echo "$services_status" >&2
}

show_completion_info() {
    local ip="$1"

    echo "" >&2
    echo "==================================================" >&2
    success "🎉 DEPLOYMENT COMPLETE!"
    echo "" >&2
    echo "🌐 Access your Mycelium-Matrix Chat:" >&2
    echo "   📱 Web Interface: http://[$ip] (local access)" >&2
    echo "   🔧 API Health: http://[$ip]:8080/api/health" >&2
    echo "   📊 Matrix Bridge: http://[$ip]:8081/health" >&2
    echo "" >&2
    echo "🛠️  Management Commands (run on VM):" >&2
    echo "   📊 Check status: su - muser -c 'cd mycelium-matrix-chat && make ops-status'" >&2
    echo "   📋 View logs: su - muser -c 'cd mycelium-matrix-chat && make ops-logs'" >&2
    echo "   🔄 Restart: su - muser -c 'cd mycelium-matrix-chat && make ops-restart'" >&2
    echo "" >&2
    echo "🔐 SSH Access:" >&2
    echo "   ssh muser@$ip" >&2
    echo "" >&2
    echo "📝 Next Steps:" >&2
    echo "   1. Set up DNS for public access (optional)" >&2
    echo "   2. Configure SSL certificates" >&2
    echo "   3. Test the application" >&2
    echo "==================================================" >&2
}

# =====================================================================================
# Main Execution
# =====================================================================================

usage() {
    echo "Usage: $0 [MYCELIUM_IP]"
    echo ""
    echo "Deploy Mycelium-Matrix Chat to a TFGrid VM"
    echo ""
    echo "Arguments:"
    echo "  MYCELIUM_IP    The Mycelium IPv6 address of your TFGrid VM"
    echo "                 Example: 400::abcd:1234:5678:9abc"
    echo ""
    echo "Requirements:"
    echo "  - SSH key configured for passwordless access to the VM"
    echo "  - Mycelium network connected on your local machine"
    echo "  - TFGrid VM running Ubuntu 20.04 or higher"
    echo ""
    echo "Example:"
    echo "  $0 400::abcd:1234:5678:9abc"
    exit 1
}

main() {
    # Check arguments
    if [ $# -ne 1 ]; then
        usage
    fi

    MYCELIUM_IP="$1"

    echo "🚀 Mycelium-Matrix Chat TFGrid Deployment"
    echo "==========================================" >&2
    log "Target VM: $MYCELIUM_IP"
    echo "" >&2

    # Validate inputs
    validate_mycelium_ip "$MYCELIUM_IP"

    # Check SSH key exists
    if [ ! -f "$SSH_KEY" ]; then
        die "SSH key not found at $SSH_KEY. Please ensure your SSH key is set up for passwordless access to the VM."
    fi

    # Test connectivity and requirements
    check_ssh_connectivity "$MYCELIUM_IP" "$SSH_USER" "$SSH_KEY"
    check_vm_requirements "$MYCELIUM_IP" "$SSH_USER" "$SSH_KEY"

    # Run deployment
    run_preparation "$MYCELIUM_IP" "$SSH_USER" "$SSH_KEY"

    # Monitor and show results
    monitor_deployment "$MYCELIUM_IP" "muser" "$SSH_KEY"
    show_completion_info "$MYCELIUM_IP"

    success "Deployment completed successfully!"
}

# Run main function
main "$@"