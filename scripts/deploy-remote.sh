#!/bin/bash

# =====================================================================================
# Remote TFGrid Deployment Script (One-Liner Version)
# =====================================================================================
# This script can be downloaded and run directly from GitHub without cloning the repo
# Usage: curl -fsSL <url> | bash -s <MYCELIUM_IP>
# =====================================================================================

set -e  # Exit on any error

# =====================================================================================
# Configuration
# =====================================================================================

MYCELIUM_IP=""
SSH_USER="root"
SSH_KEY="$HOME/.ssh/id_ed25519"
REPO_URL="https://github.com/mik-tf/mycelium-matrix-chat"
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

    # Basic IPv6 validation for Mycelium addresses (case insensitive)
    if [[ ! "$ip" =~ ^[0-9a-fA-F:]+$ ]]; then
        die "Invalid Mycelium IP format. Expected IPv6 format like: 400::abcd:1234:5678:9abc"
    fi

    # Count colons - should be 7 for full IPv6
    local colon_count=$(echo "$ip" | tr -cd ':' | wc -c)
    if [ "$colon_count" -ne 7 ]; then
        die "Invalid IPv6 format: should have 7 colons, found $colon_count"
    fi

    # Basic check that it contains hex-like characters
    if ! echo "$ip" | grep -q '[0-9a-fA-F]'; then
        die "IP doesn't contain valid hex digits"
    fi

    log "IP validation passed: $ip"
}

check_ssh_connectivity() {
    local ip="$1"
    local user="$2"
    local key="$3"

    log "Testing SSH connectivity to $user@$ip..."

    # Test SSH connection with timeout (TFGrid provides SSH keys automatically)
    if ! timeout 30 ssh -i "$key" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$user@$ip" "echo 'SSH connection successful'" 2>/dev/null; then
        die "Cannot connect to $user@$ip via SSH.

Troubleshooting for TFGrid VMs:
1. Verify Mycelium network is connected on your local machine
2. Ensure you're using the correct Mycelium IP from TFGrid dashboard
3. Check that the VM is running and accessible
4. TFGrid provides SSH keys automatically - no manual setup needed

If connection fails, try:
  ssh root@$ip  # Test basic connectivity"
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
    os_info=$(timeout 30 ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$user@$ip" "cat /etc/os-release | grep -i ubuntu || echo 'Not Ubuntu'" 2>/dev/null)

    if [[ "$os_info" == *"Not Ubuntu"* ]]; then
        die "VM is not running Ubuntu. This script requires Ubuntu 20.04 or higher."
    fi

    # Check Ubuntu version
    local ubuntu_version
    ubuntu_version=$(timeout 30 ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$user@$ip" "lsb_release -r | cut -f2 | cut -d'.' -f1" 2>/dev/null)

    if [ "$ubuntu_version" -lt 20 ]; then
        die "Ubuntu $ubuntu_version detected. Ubuntu 20.04 or higher required."
    fi

    success "VM requirements met (Ubuntu $ubuntu_version)"
}

# =====================================================================================
# Deployment Functions
# =====================================================================================

run_remote_deployment() {
    local ip="$1"
    local user="$2"
    local key="$3"

    log "🚀 Starting remote deployment to $ip..."
    echo "" >&2

    # Run the preparation script on the remote VM
    log "Running preparation script on remote VM..."
    if ! timeout 1800 ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$user@$ip" "bash -c 'curl -fsSL $PREPARATION_SCRIPT_URL | bash'" 2>&1; then
        die "Remote preparation failed. Check the output above for details."
    fi

    success "Remote deployment completed successfully!"
}

show_completion_info() {
    local ip="$1"

    echo "" >&2
    echo "==================================================" >&2
    success "🎉 MYCELIUM-MATRIX CHAT DEPLOYMENT COMPLETE!"
    echo "" >&2
    echo "🌐 Access your application:" >&2
    echo "   📱 Web Interface: http://[$ip] (local access)" >&2
    echo "   🔧 API Health: http://[$ip]:8080/api/health" >&2
    echo "   📊 Matrix Bridge: http://[$ip]:8081/health" >&2
    echo "" >&2
    echo "🛠️  Management Commands (run on VM):" >&2
    echo "   📊 Check status: ssh muser@$ip 'cd mycelium-matrix-chat && make ops-status'" >&2
    echo "   📋 View logs: ssh muser@$ip 'cd mycelium-matrix-chat && make ops-logs'" >&2
    echo "   🔄 Restart: ssh muser@$ip 'cd mycelium-matrix-chat && make ops-restart'" >&2
    echo "" >&2
    echo "🔐 SSH Access:" >&2
    echo "   ssh muser@$ip" >&2
    echo "" >&2
    echo "📝 Next Steps:" >&2
    echo "   1. Set up DNS for public access (optional)" >&2
    echo "   2. Configure SSL certificates" >&2
    echo "   3. Test the application" >&2
    echo "" >&2
    echo "==================================================" >&2
}

# =====================================================================================
# Main Execution
# =====================================================================================

usage() {
    echo "Usage: $0 <MYCELIUM_IP>"
    echo ""
    echo "Deploy Mycelium-Matrix Chat to a TFGrid VM"
    echo ""
    echo "Arguments:"
    echo "  MYCELIUM_IP    The Mycelium IPv6 address of your TFGrid VM"
    echo "                 Example: 400::abcd:1234:5678:9abc"
    echo ""
    echo "One-liner usage:"
    echo "  curl -fsSL https://raw.githubusercontent.com/mik-tf/mycelium-matrix-chat/main/scripts/deploy-remote.sh | bash -s 400::abcd:1234:5678:9abc"
    echo ""
    echo "Requirements:"
    echo "  - Mycelium network connected on your local machine"
    echo "  - TFGrid VM running Ubuntu 20.04 or higher"
    echo "  - SSH key (provided automatically by TFGrid)"
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

    echo "🚀 Mycelium-Matrix Chat Remote Deployment"
    echo "========================================" >&2
    log "Target VM: $MYCELIUM_IP"
    echo "" >&2

    # Validate inputs
    validate_mycelium_ip "$MYCELIUM_IP"

    # Check SSH key exists (TFGrid provides SSH keys automatically)
    if [ ! -f "$SSH_KEY" ]; then
        die "SSH key not found at $SSH_KEY.

For TFGrid VMs, SSH keys are provided automatically. If missing:
  ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519

TFGrid handles SSH key distribution automatically - no manual copying needed."
    fi

    # Test connectivity and requirements
    check_ssh_connectivity "$MYCELIUM_IP" "$SSH_USER" "$SSH_KEY"
    check_vm_requirements "$MYCELIUM_IP" "$SSH_USER" "$SSH_KEY"

    # Run deployment
    run_remote_deployment "$MYCELIUM_IP" "$SSH_USER" "$SSH_KEY"

    # Show results
    show_completion_info "$MYCELIUM_IP"

    success "🎯 Deployment completed successfully!"
    log "Total deployment time: $(($(date +%s) - $(grep "Starting remote deployment" /tmp/deploy-remote.log 2>/dev/null | head -1 | cut -d'[' -f2 | cut -d']' -f1 | date -f- +%s 2>/dev/null || echo $(date +%s)))) seconds"
}

# Run main function
main "$@" 2>&1 | tee /tmp/deploy-remote.log