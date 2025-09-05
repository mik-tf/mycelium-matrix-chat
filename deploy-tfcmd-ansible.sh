#!/bin/bash

# =====================================================================================
# MMC TFGrid Deployment with Ansible Orchestration
# =====================================================================================
# This script provides a complete deployment solution:
# 1. Deploy VM using tfcmd
# 2. Generate ansible inventory
# 3. Run ansible playbooks for preparation and deployment
# =====================================================================================

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR" && pwd)"

# VM Deployment Parameters (can be overridden)
VM_NAME="${VM_NAME:-myceliumchat}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519.pub}"
CPU_CORES="${CPU_CORES:-4}"
MEMORY_GB="${MEMORY_GB:-16}"
DISK_GB="${DISK_GB:-250}"
NODE_ID="${NODE_ID:-6883}"
ENABLE_MYCELIUM="${ENABLE_MYCELIUM:-true}"
FLIST="${FLIST:-https://hub.grid.tf/tf-official-vms/ubuntu-24.04-full.flist}"
ENTRYPOINT="${ENTRYPOINT:-/sbin/zinit init}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Utility functions
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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v tfcmd &>/dev/null; then
        die "tfcmd is not installed or not in PATH"
    fi

    if ! command -v ansible &>/dev/null; then
        die "ansible is not installed or not in PATH"
    fi

    if [ ! -f "$SSH_KEY_PATH" ]; then
        die "SSH key not found: $SSH_KEY_PATH"
    fi

    success "Prerequisites check passed"
}

# Deploy VM using tfcmd
deploy_vm() {
    log "🚀 Deploying VM using tfcmd..."

    local tfcmd_cmd="tfcmd deploy vm --flist $FLIST --entrypoint $ENTRYPOINT --name $VM_NAME --cpu $CPU_CORES --memory $MEMORY_GB --disk $DISK_GB --node $NODE_ID --ssh $SSH_KEY_PATH"
    if [ "$ENABLE_MYCELIUM" = true ]; then
        tfcmd_cmd="$tfcmd_cmd --mycelium true"
    fi

    log "Executing: $tfcmd_cmd"

    local deployment_output
    if ! deployment_output=$(eval "$tfcmd_cmd" 2>&1); then
        error "VM deployment failed"
        echo "$deployment_output" >&2
        exit 1
    fi

    echo "$deployment_output"

    # Extract mycelium IP
    MYCELIUM_IP=$(echo "$deployment_output" | grep -i "vm mycelium ip:" | sed 's/.*vm mycelium ip: *//' | tr -d '[:space:]' || true)

    if [ -z "$MYCELIUM_IP" ]; then
        # Try alternative patterns
        MYCELIUM_IP=$(echo "$deployment_output" | grep -oE '[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){7}' | head -1 || true)
    fi

    if [ -z "$MYCELIUM_IP" ]; then
        die "Could not extract mycelium IP from tfcmd output"
    fi

    success "VM deployed successfully"
    log "Mycelium IP: $MYCELIUM_IP"
}

# Generate ansible inventory
generate_inventory() {
    local ip="$1"
    log "📝 Generating ansible inventory..."

    local inventory_file="$PROJECT_ROOT/inventory/hosts.ini"

    # Backup existing inventory
    if [ -f "$inventory_file" ]; then
        cp "$inventory_file" "${inventory_file}.backup"
    fi

    # Create new inventory
    cat > "$inventory_file" << EOF
[mmc_servers]
mmc-node-1 ansible_host=$ip ansible_user=root

[mmc_servers:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3
EOF

    success "Ansible inventory generated: $inventory_file"
}

# Wait for VM to be ready
wait_for_vm() {
    local ip="$1"
    local timeout=300
    local check_interval=10

    log "⏳ Waiting for VM to be ready (timeout: ${timeout}s)..."

    local elapsed=0
    while [ $elapsed -lt "$timeout" ]; do
        if ssh -o ConnectTimeout=10 \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -o LogLevel=ERROR \
               -o BatchMode=yes \
               -i "$SSH_KEY_PATH" \
               "root@[$ip]" \
               "echo 'VM is ready'" 2>/dev/null; then
            success "VM is ready for ansible deployment"
            return 0
        fi

        log "SSH connection failed, waiting ${check_interval}s..."
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done

    die "Timeout waiting for VM to be ready"
}

# Run ansible playbooks
run_ansible() {
    log "🎭 Running ansible playbooks..."

    cd "$PROJECT_ROOT"

    # Run preparation playbooks
    log "Running preparation playbooks..."
    if ! ansible-playbook -i inventory/hosts.ini site.yml --tags preparation; then
        error "Ansible preparation failed"
        exit 1
    fi

    # Run deployment playbook
    log "Running deployment playbook..."
    if ! ansible-playbook -i inventory/hosts.ini site.yml --tags deploy,application; then
        error "Ansible deployment failed"
        exit 1
    fi

    # Run validation
    log "Running validation..."
    if ! ansible-playbook -i inventory/hosts.ini site.yml --tags validate,post-deploy; then
        warning "Validation had some issues, but deployment may still be functional"
    fi

    success "Ansible deployment completed"
}

# Main execution
main() {
    echo "🚀 MMC TFGrid + Ansible Deployment"
    echo "=================================="

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Deploy MMC to TFGrid using tfcmd + Ansible"
                echo ""
                echo "Options:"
                echo "  -h, --help              Show this help"
                echo "  -n, --name NAME         VM name (default: myceliumchat)"
                echo "  -s, --ssh-key PATH      SSH key path (default: ~/.ssh/id_ed25519.pub)"
                echo "  -c, --cpu CORES         CPU cores (default: 4)"
                echo "  -m, --memory GB         Memory in GB (default: 16)"
                echo "  -d, --disk GB           Disk size in GB (default: 250)"
                echo "  --node NODE_ID          Node ID (default: 6883)"
                echo "  --no-mycelium           Disable mycelium networking"
                echo ""
                exit 0
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
                exit 1
                ;;
        esac
    done

    # Show configuration
    log "Configuration:"
    echo "  VM Name: $VM_NAME" >&2
    echo "  SSH Key: $SSH_KEY_PATH" >&2
    echo "  CPU: $CPU_CORES cores" >&2
    echo "  Memory: $MEMORY_GB GB" >&2
    echo "  Disk: $DISK_GB GB" >&2
    echo "  Node: $NODE_ID" >&2
    echo "  Mycelium: $ENABLE_MYCELIUM" >&2
    echo "" >&2

    # Execute deployment steps
    check_prerequisites
    local deployment_output
    deployment_output=$(deploy_vm)
    MYCELIUM_IP=$(echo "$deployment_output" | grep -i "vm mycelium ip:" | sed 's/.*vm mycelium ip: *//' | tr -d '[:space:]' || echo "$deployment_output" | grep -oE '[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){7}' | head -1)
    generate_inventory "$MYCELIUM_IP"
    wait_for_vm "$MYCELIUM_IP"
    run_ansible

    echo ""
    echo "=================================================="
    success "🎉 MMC DEPLOYMENT COMPLETE!"
    echo "   🌐 VM IP: $MYCELIUM_IP" >&2
    echo "   🌐 Web Interface: http://$MYCELIUM_IP" >&2
    echo "   🔧 API: http://$MYCELIUM_IP/api" >&2
    echo "=================================================="
}

# Run main function
main "$@"