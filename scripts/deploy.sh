#!/bin/bash

# =====================================================================================
# Mycelium-Matrix Chat - Unified Deployment Script
# =====================================================================================
# This script provides a unified, automated deployment system for Mycelium-Matrix Chat
# It supports multiple environments (TFGrid, local development) with intelligent detection
#
# Usage:
#   ./deploy.sh                           # Auto-detect environment
#   ./deploy.sh --environment tfgrid     # Force TFGrid deployment
#   ./deploy.sh --environment local      # Force local deployment
#   ./deploy.sh --help                   # Show help
#
# =====================================================================================

set -o errexit   # Exit on error
set -o pipefail  # Exit on pipe error
set -o nounset   # Exit on undefined variable

# =====================================================================================
# Script Configuration
# =====================================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
CONFIG_DIR="$SCRIPT_DIR/config"

# Add lib to PATH for sourcing
export PATH="$LIB_DIR:$PATH"

# =====================================================================================
# Load Libraries
# =====================================================================================

# Source utility functions
if [ -f "$LIB_DIR/utils.sh" ]; then
    source "$LIB_DIR/utils.sh"
else
    echo "❌ Error: utils.sh not found in $LIB_DIR" >&2
    exit 1
fi

# Source configuration management
if [ -f "$LIB_DIR/config.sh" ]; then
    source "$LIB_DIR/config.sh"
else
    echo "❌ Error: config.sh not found in $LIB_DIR" >&2
    exit 1
fi

# Source validation functions
if [ -f "$LIB_DIR/validate.sh" ]; then
    source "$LIB_DIR/validate.sh"
else
    echo "❌ Error: validate.sh not found in $LIB_DIR" >&2
    exit 1
fi

# Source rollback functions
if [ -f "$LIB_DIR/rollback.sh" ]; then
    source "$LIB_DIR/rollback.sh"
else
    echo "❌ Error: rollback.sh not found in $LIB_DIR" >&2
    exit 1
fi

# =====================================================================================
# Global Variables
# =====================================================================================

# Deployment state
MYCELIUM_IP=""
DEPLOYMENT_START_TIME=""
ENVIRONMENT=""
DEPLOYMENT_ID=""

# =====================================================================================
# Environment Detection Functions
# =====================================================================================

detect_environment() {
    log "Detecting deployment environment..."

    local indicators=0
    local detected_env=""

    # Check for tfcmd (TFGrid indicator)
    if command -v tfcmd &>/dev/null; then
        debug "tfcmd found - TFGrid environment detected"
        ((indicators++))
        detected_env="tfgrid"
    fi

    # Check for mycelium connectivity
    if command -v mycelium &>/dev/null; then
        if mycelium status 2>/dev/null | grep -q "connected\|running"; then
            debug "Mycelium is connected - network environment detected"
            ((indicators++))
        fi
    fi

    # Check for Docker (local development indicator)
    if command -v docker &>/dev/null && command -v docker-compose &>/dev/null; then
        debug "Docker environment found - could be local development"
        if [ "$detected_env" = "" ]; then
            detected_env="local"
        fi
    fi

    # Check for existing deployment files
    if [ -f "$PROJECT_ROOT/docker-compose.yml" ] || [ -f "$PROJECT_ROOT/Makefile" ]; then
        debug "Project files found - local development likely"
        if [ "$detected_env" = "" ]; then
            detected_env="local"
        fi
    fi

    # Default to local if nothing detected
    if [ -z "$detected_env" ]; then
        warning "Could not auto-detect environment, defaulting to local"
        detected_env="local"
    fi

    log "Environment detected: $detected_env (confidence: $indicators indicators)"
    echo "$detected_env"
}

# =====================================================================================
# Validation Functions
# =====================================================================================

validate_prerequisites() {
    log "Validating deployment prerequisites..."

    local errors=0

    # Check required commands
    local required_commands=("curl" "git" "ssh")
    for cmd in "${required_commands[@]}"; do
        if ! check_command "$cmd"; then
            ((errors++))
        fi
    done

    # Environment-specific validation
    case "$ENVIRONMENT" in
        tfgrid)
            if ! check_command "tfcmd"; then
                error "tfcmd is required for TFGrid deployment"
                ((errors++))
            fi
            ;;
        local)
            if ! check_command "docker" || ! check_command "docker-compose"; then
                error "Docker and Docker Compose are required for local deployment"
                ((errors++))
            fi
            ;;
    esac

    # Check network connectivity
    if ! check_connectivity; then
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        error "$errors prerequisite checks failed"
        return 1
    fi

    success "All prerequisites validated"
}

# =====================================================================================
# VM Deployment Functions (TFGrid)
# =====================================================================================

deploy_tfgrid_vm() {
    log "🚀 Deploying VM on TFGrid..."

    # Get VM configuration
    local vm_name
    local cpu
    local memory
    local disk
    local node
    local enable_mycelium
    local flist
    local entrypoint

    vm_name=$(get_config "vm.name")
    cpu=$(get_config "vm.cpu")
    memory=$(get_config "vm.memory")
    disk=$(get_config "vm.disk")
    node=$(get_config "vm.node")
    enable_mycelium=$(get_config "vm.enable_mycelium")
    flist=$(get_config "vm.flist")
    entrypoint=$(get_config "vm.entrypoint")

    # Build tfcmd command
    local tfcmd_cmd="tfcmd deploy vm --flist $flist --entrypoint $entrypoint --name $vm_name --cpu $cpu --memory $memory --disk $disk --node $node"

    if [ "$enable_mycelium" = "true" ]; then
        tfcmd_cmd="$tfcmd_cmd --mycelium true"
    fi

    # Add SSH key
    local ssh_key_path
    ssh_key_path=$(get_config "deployment.ssh_key_path")
    ssh_key_path=$(eval echo "$ssh_key_path")

    if [ -f "$ssh_key_path" ]; then
        tfcmd_cmd="$tfcmd_cmd --ssh $ssh_key_path"
    else
        error "SSH key not found: $ssh_key_path"
        return 1
    fi

    log "Executing: $tfcmd_cmd"

    # Execute deployment
    local deployment_output
    if ! deployment_output=$(eval "$tfcmd_cmd" 2>&1); then
        error "VM deployment failed"
        echo "$deployment_output" >&2
        return 1
    fi

    # Extract mycelium IP
    MYCELIUM_IP=$(extract_mycelium_ip "$deployment_output")

    if [ -z "$MYCELIUM_IP" ]; then
        error "Could not extract mycelium IP from deployment output"
        echo "$deployment_output" >&2
        return 1
    fi

    success "VM deployed successfully"
    log "Mycelium IP: $MYCELIUM_IP"

    # Wait for VM to be ready
    wait_for_vm_ready "$MYCELIUM_IP"
}

extract_mycelium_ip() {
    local output="$1"

    # Look for mycelium IP in output
    local ip=""

    # Try different patterns
    ip=$(echo "$output" | grep -i "mycelium.*ip" | sed 's/.*ip[:]* *//' | tr -d '[:space:]' || true)
    if [ -z "$ip" ]; then
        ip=$(echo "$output" | grep -oE '[0-9a-fA-F]{1,4}(:[0-9a-fA-F]{1,4}){7}' | head -1 || true)
    fi

    echo "$ip"
}

wait_for_vm_ready() {
    local ip="$1"
    local timeout
    local check_interval

    timeout=$(get_config "remote.vm_ready_timeout" "300")
    check_interval=$(get_config "remote.vm_ready_check_interval" "10")

    log "⏳ Waiting for VM to be ready (timeout: ${timeout}s)..."

    local elapsed=0
    while [ $elapsed -lt "$timeout" ]; do
        local ssh_key_path
        ssh_key_path=$(get_config "deployment.ssh_key_path")
        ssh_key_path=$(eval echo "$ssh_key_path")

        # Handle IPv6 addresses by wrapping in brackets
        if [[ $ip =~ : ]]; then
            ssh_target="root@[$ip]"
        else
            ssh_target="root@$ip"
        fi

        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -i "$ssh_key_path" \
               "$ssh_target" "echo 'VM is ready'" 2>/dev/null; then
            success "VM is ready for deployment"
            return 0
        fi

        log "VM not ready yet, waiting ${check_interval}s..."
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done

    error "Timeout waiting for VM to be ready"
    return 1
}

# =====================================================================================
# Remote Operations Functions
# =====================================================================================

execute_remote() {
    local ip="$1"
    local user="$2"
    local command="$3"
    local timeout="${4:-300}"

    debug "Executing remotely on $user@$ip: $command"

    local ssh_key_path
    ssh_key_path=$(eval echo "$(get_config "deployment.ssh_key_path")")

    # Handle IPv6 addresses by wrapping in brackets
    if [[ $ip =~ : ]]; then
        ssh_target="$user@[$ip]"
    else
        ssh_target="$user@$ip"
    fi

    if ! ssh -i "$ssh_key_path" \
             -o ConnectTimeout=10 \
             -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             -o LogLevel=ERROR \
             "$ssh_target" \
             "timeout $timeout bash -c '$command'" 2>&1; then

        error "Remote command failed on $user@$ip"
        return 1
    fi
}

copy_to_remote() {
    local local_file="$1"
    local remote_path="$2"
    local ip="$3"
    local user="${4:-root}"

    debug "Copying $local_file to $user@$ip:$remote_path"

    local ssh_key_path
    ssh_key_path=$(eval echo "$(get_config "deployment.ssh_key_path")")

    # Handle IPv6 addresses by wrapping in brackets
    if [[ $ip =~ : ]]; then
        scp_target="$user@[$ip]:$remote_path"
    else
        scp_target="$user@$ip:$remote_path"
    fi

    if ! scp -i "$ssh_key_path" \
             -o StrictHostKeyChecking=no \
             -o UserKnownHostsFile=/dev/null \
             "$local_file" \
             "$scp_target" 2>&1; then

        error "File copy failed: $local_file -> $user@$ip:$remote_path"
        return 1
    fi
}

# =====================================================================================
# Deployment Functions
# =====================================================================================

prepare_remote_environment() {
    local ip="$1"

    log "📦 Preparing remote environment on $ip..."

    # Copy preparation script
    local prep_script="$SCRIPT_DIR/prepare-tfgrid-vm.sh"
    if [ ! -f "$prep_script" ]; then
        error "Preparation script not found: $prep_script"
        return 1
    fi

    copy_to_remote "$prep_script" "/tmp/prepare-tfgrid-vm.sh" "$ip"

    # Execute preparation
    if ! execute_remote "$ip" "root" "bash /tmp/prepare-tfgrid-vm.sh"; then
        error "Remote environment preparation failed"
        return 1
    fi

    success "Remote environment prepared successfully"
}

deploy_application() {
    local ip="$1"

    log "🚀 Deploying Mycelium-Matrix Chat application..."

    # Copy deployment script
    local deploy_script="$SCRIPT_DIR/deploy-mycelium-chat.sh"
    if [ ! -f "$deploy_script" ]; then
        error "Deployment script not found: $deploy_script"
        return 1
    fi

    copy_to_remote "$deploy_script" "/tmp/deploy-mycelium-chat.sh" "$ip"

    # Execute deployment as muser
    local deploy_user
    deploy_user=$(get_config "security.deploy_user")

    if ! execute_remote "$ip" "$deploy_user" "bash /tmp/deploy-mycelium-chat.sh"; then
        error "Application deployment failed"
        return 1
    fi

    success "Application deployed successfully"
}

# =====================================================================================
# Validation Functions
# =====================================================================================

validate_deployment() {
    local ip="$1"

    log "🔍 Validating deployment..."

    # Basic connectivity check
    if ! execute_remote "$ip" "root" "echo 'Connectivity test passed'"; then
        error "Cannot connect to deployed VM"
        return 1
    fi

    # Check if services are running
    local deploy_user
    deploy_user=$(get_config "security.deploy_user")

    # Check if muser exists and can run commands
    if ! execute_remote "$ip" "$deploy_user" "whoami"; then
        error "Deployment user $deploy_user is not properly configured"
        return 1
    fi

    # Check if application directory exists
    if ! execute_remote "$ip" "$deploy_user" "test -d ~/mycelium-matrix-chat"; then
        error "Application directory not found"
        return 1
    fi

    success "Deployment validation passed"
}

# =====================================================================================
# Local Deployment Functions
# =====================================================================================

deploy_local() {
    log "🏠 Starting local deployment..."

    # Check if we're in the right directory
    if [ ! -f "$PROJECT_ROOT/Makefile" ]; then
        error "Makefile not found. Are you in the project root?"
        return 1
    fi

    cd "$PROJECT_ROOT"

    # Run local deployment
    if ! make ops-production; then
        error "Local deployment failed"
        return 1
    fi

    success "Local deployment completed"
}

# =====================================================================================
# Main Deployment Flow
# =====================================================================================

main_deployment() {
    local environment="$1"

    DEPLOYMENT_START_TIME=$(date +%s)
    DEPLOYMENT_ID="deploy-$(date +%Y%m%d-%H%M%S)-$(printf '%04x' $((RANDOM * RANDOM)))"

    log "🚀 Starting Mycelium-Matrix Chat deployment"
    log "Deployment ID: $DEPLOYMENT_ID"
    log "Environment: $environment"
    log "Project Root: $PROJECT_ROOT"

    # Load configuration
    load_config "$environment"
    validate_config

    # Show configuration summary
    show_config_summary

    # Validate prerequisites
    validate_prerequisites

    # Check for dry-run mode
    if [ "${DRY_RUN:-false}" = "true" ]; then
        warning "DRY RUN MODE - No actual deployment will be performed"
        log "Showing what would be executed..."

        case "$environment" in
            tfgrid)
                log "Would deploy TFGrid VM with configuration:"
                log "  Name: $(get_config 'vm.name' 'unknown')"
                log "  CPU: $(get_config 'vm.cpu' 'unknown')"
                log "  Memory: $(get_config 'vm.memory' 'unknown') GB"
                log "  Disk: $(get_config 'vm.disk' 'unknown') GB"
                log "  Node: $(get_config 'vm.node' 'unknown')"
                log "  Mycelium: $(get_config 'vm.enable_mycelium' 'unknown')"
                log "Would prepare remote environment and deploy application"
                log "Would validate deployment and show results"
                ;;

            local)
                log "Would run local deployment:"
                log "  Command: cd $PROJECT_ROOT && make ops-production"
                log "Would validate local deployment"
                ;;

            *)
                error "Unsupported environment: $environment"
                return 1
                ;;
        esac

        success "Dry run completed - no changes made"
        return 0
    fi

    case "$environment" in
        tfgrid)
            # TFGrid deployment flow with rollback support
            push_rollback_action "rollback_tfgrid_deployment '$MYCELIUM_IP' '$(get_config 'vm.name')'" "Complete TFGrid deployment rollback"

            deploy_tfgrid_vm
            push_rollback_action "rollback_tfgrid_vm '$(get_config 'vm.name')'" "Cancel TFGrid VM"

            prepare_remote_environment "$MYCELIUM_IP"
            push_rollback_action "rollback_remote_user '$MYCELIUM_IP' '$(get_config 'security.deploy_user')'" "Remove deployment user"

            deploy_application "$MYCELIUM_IP"
            push_rollback_action "rollback_application '$MYCELIUM_IP' '$(get_config 'security.deploy_user')'" "Remove application deployment"

            # Comprehensive validation
            if ! run_full_validation "$MYCELIUM_IP" "$environment"; then
                error "Deployment validation failed"
                execute_rollback "Validation failure"
                return 1
            fi

            show_deployment_results "$MYCELIUM_IP"
            ;;

        local)
            # Local deployment flow with rollback support
            push_rollback_action "rollback_local_deployment" "Complete local deployment rollback"

            deploy_local
            push_rollback_action "cd '$PROJECT_ROOT' && make down" "Stop local services"

            # Local validation
            if ! validate_local_deployment; then
                error "Local deployment validation failed"
                execute_rollback "Local validation failure"
                return 1
            fi

            show_local_results
            ;;

        *)
            error "Unsupported environment: $environment"
            return 1
            ;;
    esac
}

# =====================================================================================
# Results Display Functions
# =====================================================================================

show_deployment_results() {
    local ip="$1"
    local duration=$(( $(date +%s) - DEPLOYMENT_START_TIME ))

    echo ""
    echo "=================================================="
    success "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo ""
    echo "📊 Deployment Summary:"
    echo "  Deployment ID: $DEPLOYMENT_ID"
    echo "  Environment: $ENVIRONMENT"
    echo "  Duration: ${duration}s"
    echo "  VM IP: $ip"
    echo ""
    echo "🌐 Access your application:"
    echo "  📱 Web Interface: http://[$ip]"
    echo "  🔧 API Health: http://[$ip]:8080/api/health"
    echo "  📊 Matrix Bridge: http://[$ip]:8081/health"
    echo ""
    echo "🛠️  Management Commands:"
    local deploy_user
    deploy_user=$(get_config "security.deploy_user")
    echo "  📊 Check status: ssh $deploy_user@$ip 'cd mycelium-matrix-chat && make ops-status'"
    echo "  📋 View logs: ssh $deploy_user@$ip 'cd mycelium-matrix-chat && make ops-logs'"
    echo "  🔄 Restart: ssh $deploy_user@$ip 'cd mycelium-matrix-chat && make ops-restart'"
    echo ""
    echo "🔐 SSH Access:"
    echo "  ssh $deploy_user@$ip"
    echo ""
    echo "💡 To destroy the VM later:"
    echo "  tfcmd cancel $(get_config "vm.name")"
    echo "=================================================="
}

show_local_results() {
    local duration=$(( $(date +%s) - DEPLOYMENT_START_TIME ))

    echo ""
    echo "=================================================="
    success "🎉 LOCAL DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo ""
    echo "📊 Deployment Summary:"
    echo "  Deployment ID: $DEPLOYMENT_ID"
    echo "  Environment: local"
    echo "  Duration: ${duration}s"
    echo ""
    echo "🌐 Access your application:"
    echo "  📱 Frontend: http://localhost:5173"
    echo "  🔧 API Gateway: http://localhost:8080"
    echo "  📊 Matrix Bridge: http://localhost:8081"
    echo ""
    echo "🛠️  Management Commands:"
    echo "  📊 Check status: make status"
    echo "  📋 View logs: make logs"
    echo "  🔄 Restart: make down && make setup-full"
    echo "=================================================="
}

# =====================================================================================
# Command Line Interface
# =====================================================================================

usage() {
    cat << EOF
Mycelium-Matrix Chat - Unified Deployment Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -e, --environment ENV    Deployment environment (tfgrid, local, auto)
                             Default: auto (detect automatically)
    -c, --config FILE        Custom configuration file
    -v, --verbose           Enable verbose logging
    -d, --dry-run           Show what would be done without executing
    -h, --help              Show this help message

ENVIRONMENTS:
    tfgrid                  Deploy to ThreeFold Grid (creates VM automatically)
    local                   Deploy locally for development
    auto                    Auto-detect environment (default)

EXAMPLES:
    $0                           # Auto-detect and deploy
    $0 --environment tfgrid     # Deploy to TFGrid
    $0 --environment local      # Deploy locally
    $0 --verbose                # Verbose output
    $0 --dry-run                # Show plan without executing

CONFIGURATION:
    Configuration files are loaded from scripts/config/
    - defaults.conf: Default values
    - tfgrid.conf: TFGrid-specific overrides
    - local.conf: Local development overrides

    Environment variables can override config:
    MYCELIUM_MATRIX_VM_NAME=myvm ./deploy.sh

For more information, see docs/ops/deployment.md
EOF
}

parse_arguments() {
    ENVIRONMENT="auto"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -c|--config)
                CUSTOM_CONFIG="$2"
                shift 2
                ;;
            -v|--verbose)
                LOG_LEVEL="debug"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Handle auto-detection
    if [ "$ENVIRONMENT" = "auto" ]; then
        ENVIRONMENT=$(detect_environment)
    fi
}

# =====================================================================================
# Main Entry Point
# =====================================================================================

main() {
    # Parse command line arguments
    parse_arguments "$@"

    # Validate environment
    case "$ENVIRONMENT" in
        tfgrid|local)
            ;;
        *)
            error "Invalid environment: $ENVIRONMENT"
            usage
            exit 1
            ;;
    esac

    # Start deployment
    if main_deployment "$ENVIRONMENT"; then
        success "🎯 Deployment completed successfully!"
        exit 0
    else
        error "💥 Deployment failed!"
        exit 1
    fi
}

# Run main function
main "$@"