#!/bin/bash

# =====================================================================================
# Automated TFGrid Deployment Script for Mycelium-Matrix Chat
# =====================================================================================
# This script automates the complete deployment process:
# 1. Deploy VM using tfcmd
# 2. Extract mycelium IP from tfcmd output
# 3. Deploy Mycelium-Matrix Chat using the deployment script
# =====================================================================================

set -e  # Exit on any error

# =====================================================================================
# Configuration
# =====================================================================================

# VM Deployment Parameters
VM_NAME="myceliumchat"
SSH_KEY_PATH="$HOME/.ssh/id_ed25519.pub"
CPU_CORES=4
MEMORY_GB=16
DISK_GB=250
NODE_ID=6883
ENABLE_MYCELIUM=true

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
# VM Deployment Functions
# =====================================================================================

deploy_vm() {
    log "🚀 Deploying VM using tfcmd..."

    # Build the tfcmd command
    TFCMD_CMD="tfcmd deploy vm --name $VM_NAME --ssh $SSH_KEY_PATH --cpu $CPU_CORES --memory $MEMORY_GB --disk $DISK_GB --node $NODE_ID"
    if [ "$ENABLE_MYCELIUM" = true ]; then
        TFCMD_CMD="$TFCMD_CMD --mycelium true"
    fi

    log "Running: $TFCMD_CMD"

    # Execute the command and capture output
    TFCMD_OUTPUT=$(eval "$TFCMD_CMD" 2>&1)
    TFCMD_EXIT_CODE=$?

    echo "$TFCMD_OUTPUT" >&2

    if [ $TFCMD_EXIT_CODE -ne 0 ]; then
        die "VM deployment failed with exit code $TFCMD_EXIT_CODE"
    fi

    success "VM deployment initiated successfully"
    echo "$TFCMD_OUTPUT"
}

extract_mycelium_ip() {
    local output="$1"

    log "🔍 Extracting mycelium IP from tfcmd output..."

    # Look for the mycelium IP in the output
    # Expected format: "vm mycelium ip: 474:e774:f93d:ceaf:ff0f:c3b3:b901:4da3"
    MYCELIUM_IP=$(echo "$output" | grep -i "vm mycelium ip:" | sed 's/.*vm mycelium ip: *//' | tr -d '[:space:]' || true)

    if [ -z "$MYCELIUM_IP" ]; then
        # Try alternative patterns - look for IPv6-like patterns
        MYCELIUM_IP=$(echo "$output" | grep -oE '[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){7}' | head -1 || true)
    fi

    if [ -z "$MYCELIUM_IP" ]; then
        # Last resort: look for any pattern that looks like an IPv6 address
        MYCELIUM_IP=$(echo "$output" | grep -oE '[0-9a-fA-F:]{10,}' | grep -E '^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$' | head -1 || true)
    fi

    if [ -z "$MYCELIUM_IP" ]; then
        die "Could not extract mycelium IP from tfcmd output. Please check the output above."
    fi

    # Basic validation - just ensure we have something that looks like an IP
    MYCELIUM_IP=$(echo "$MYCELIUM_IP" | tr -d '[:space:]' | tr -d '\n' | tr -d '\r')

    # Simple validation: should not be empty and should contain colons
    if [ -z "$MYCELIUM_IP" ]; then
        die "No IP address extracted from tfcmd output"
    fi

    # Check if it contains at least some colons (basic IPv6-like check)
    if ! echo "$MYCELIUM_IP" | grep -q ':'; then
        die "Extracted value '$MYCELIUM_IP' doesn't contain colons - not an IPv6 address"
    fi

    # Count colons - should be reasonable for IPv6 (3-8 is acceptable)
    local colon_count=$(echo "$MYCELIUM_IP" | tr -cd ':' | wc -c)
    if [ "$colon_count" -lt 3 ] || [ "$colon_count" -gt 8 ]; then
        warning "IP '$MYCELIUM_IP' has $colon_count colons (expected 7 for standard IPv6)"
    fi

    log "Using mycelium IP: $MYCELIUM_IP"

    success "Mycelium IP extracted: $MYCELIUM_IP"
    echo "$MYCELIUM_IP"
}

wait_for_vm_ready() {
    local mycelium_ip="$1"

    log "⏳ Waiting 30 seconds for VM to fully initialize..."
    sleep 30

    success "VM should now be ready for deployment"
    return 0
}

# =====================================================================================
# Chat Deployment Functions
# =====================================================================================

deploy_chat() {
    local mycelium_ip="$1"

    log "🚀 Deploying Mycelium-Matrix Chat to $mycelium_ip..."

    # Use the local remote deployment script (modified version)
    DEPLOY_CMD="bash $(dirname "$0")/deploy-remote.sh $mycelium_ip"

    log "Running deployment command..."
    if eval "$DEPLOY_CMD"; then
        success "Chat deployment completed successfully"
    else
        die "Chat deployment failed"
    fi
}

# =====================================================================================
# Main Execution
# =====================================================================================

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Automated deployment of Mycelium-Matrix Chat to TFGrid"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -n, --name NAME         VM name (default: myceliumchat)"
    echo "  -s, --ssh-key PATH      SSH public key path (default: ~/.ssh/id_ed25519.pub)"
    echo "  -c, --cpu CORES         CPU cores (default: 4)"
    echo "  -m, --memory GB         Memory in GB (default: 16)"
    echo "  -d, --disk GB           Disk size in GB (default: 250)"
    echo "  --node NODE_ID          Node ID (default: 6883)"
    echo "  --no-mycelium           Disable mycelium networking"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use default settings"
    echo "  $0 --cpu 2 --memory 8 --disk 100     # Custom VM specs"
    echo "  $0 --name mychat --node 1234         # Custom name and node"
    echo ""
    echo "Requirements:"
    echo "  - tfcmd installed and configured"
    echo "  - SSH key pair exists"
    echo "  - Mycelium network connected (recommended)"
    exit 1
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                ;;
            -n|--name)
                VM_NAME="$2"
                shift 2
                ;;
            -s|--ssh-key)
                SSH_KEY_PATH="$2"
                shift 2
                ;;
            -c|--cpu)
                CPU_CORES="$2"
                shift 2
                ;;
            -m|--memory)
                MEMORY_GB="$2"
                shift 2
                ;;
            -d|--disk)
                DISK_GB="$2"
                shift 2
                ;;
            --node)
                NODE_ID="$2"
                shift 2
                ;;
            --no-mycelium)
                ENABLE_MYCELIUM=false
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

main() {
    echo "🚀 Automated Mycelium-Matrix Chat TFGrid Deployment"
    echo "==================================================" >&2

    # Parse command line arguments
    parse_args "$@"

    # Validate prerequisites
    if ! command -v tfcmd &> /dev/null; then
        die "tfcmd is not installed or not in PATH. Please install tfcmd first."
    fi

    if [ ! -f "$SSH_KEY_PATH" ]; then
        die "SSH public key not found at $SSH_KEY_PATH. Please generate SSH keys first."
    fi

    # Check mycelium status (don't try to auto-setup since it requires manual config)
    if command -v mycelium &> /dev/null; then
        log "Checking mycelium status..."
        if mycelium status >/dev/null 2>&1; then
            log "✅ Mycelium is running"
        else
            warning "⚠️  Mycelium is installed but not running"
            log "💡 Please ensure mycelium is running in your environment:"
            log "   sudo mycelium --peers tcp://188.40.132.242:9651 tcp://185.69.166.7:9651 --tun-name mycelium0"
            log "   (Run this in your terminal before executing the script)"
        fi
    else
        warning "⚠️  Mycelium client not found"
        log "💡 Please install and start mycelium before running this script"
        log "   Since you can SSH manually, mycelium is working in your environment"
    fi

    log "Configuration:"
    echo "  VM Name: $VM_NAME" >&2
    echo "  SSH Key: $SSH_KEY_PATH" >&2
    echo "  CPU: $CPU_CORES cores" >&2
    echo "  Memory: $MEMORY_GB GB" >&2
    echo "  Disk: $DISK_GB GB" >&2
    echo "  Node: $NODE_ID" >&2
    echo "  Mycelium: $ENABLE_MYCELIUM" >&2
    echo "" >&2

    # Step 1: Deploy VM
    log "Step 1: Deploying VM..."
    TFCMD_OUTPUT=$(deploy_vm)

    # Step 2: Extract mycelium IP
    log "Step 2: Extracting mycelium IP..."
    MYCELIUM_IP=$(extract_mycelium_ip "$TFCMD_OUTPUT")

    # Step 3: Wait for VM to be ready
    log "Step 3: Waiting for VM to be ready..."
    wait_for_vm_ready "$MYCELIUM_IP"

    # Step 4: Deploy chat application
    log "Step 4: Deploying Mycelium-Matrix Chat..."
    deploy_chat "$MYCELIUM_IP"

    # Success
    echo "" >&2
    echo "==================================================" >&2
    success "🎉 AUTOMATED DEPLOYMENT COMPLETE!"
    echo "" >&2
    echo "🌐 Your Mycelium-Matrix Chat is now running at:" >&2
    echo "   📱 Web Interface: http://[$MYCELIUM_IP]" >&2
    echo "   🔧 API Health: http://[$MYCELIUM_IP]:8080/api/health" >&2
    echo "   📊 Matrix Bridge: http://[$MYCELIUM_IP]:8081/health" >&2
    echo "" >&2
    echo "🔐 SSH Access: ssh root@$MYCELIUM_IP" >&2
    echo "   (or ssh muser@$MYCELIUM_IP after deployment)" >&2
    echo "" >&2
    echo "💡 To destroy the VM later: tfcmd cancel $VM_NAME" >&2
    echo "==================================================" >&2
}

# Run main function
main "$@"