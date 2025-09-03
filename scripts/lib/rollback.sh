#!/bin/bash

# =====================================================================================
# Mycelium-Matrix Chat - Rollback and Recovery Library
# =====================================================================================
# This library provides functions for rolling back failed deployments and recovering from errors

# Global rollback state
declare -a ROLLBACK_STACK
ROLLBACK_LOG="/tmp/rollback-$(date +%Y%m%d-%H%M%S).log"

# =====================================================================================
# Rollback Stack Management
# =====================================================================================

push_rollback_action() {
    local action="$1"
    local description="$2"

    ROLLBACK_STACK+=("$action|$description")
    debug "Added rollback action: $description"
}

execute_rollback() {
    local reason="${1:-Unknown error}"

    error "Initiating rollback due to: $reason"
    log "Rollback started at $(date)" >> "$ROLLBACK_LOG"

    local rollback_count=0
    local success_count=0

    # Execute rollback actions in reverse order
    for ((i = ${#ROLLBACK_STACK[@]} - 1; i >= 0; i--)); do
        local action_desc="${ROLLBACK_STACK[$i]}"
        IFS='|' read -r action description <<< "$action_desc"

        ((rollback_count++))
        log "Executing rollback action $rollback_count: $description" | tee -a "$ROLLBACK_LOG"

        if eval "$action" 2>&1 | tee -a "$ROLLBACK_LOG"; then
            success "Rollback action completed: $description"
            ((success_count++))
        else
            error "Rollback action failed: $description"
        fi
    done

    if [ $success_count -eq $rollback_count ]; then
        success "Rollback completed successfully ($success_count/$rollback_count actions)"
    else
        error "Rollback completed with issues ($success_count/$rollback_count actions successful)"
    fi

    # Clear rollback stack
    ROLLBACK_STACK=()
}

# =====================================================================================
# VM Rollback Functions
# =====================================================================================

rollback_tfgrid_vm() {
    local vm_name="$1"

    log "Rolling back TFGrid VM: $vm_name"

    # Cancel the VM deployment
    if command -v tfcmd &>/dev/null; then
        if tfcmd cancel "$vm_name" 2>&1 | tee -a "$ROLLBACK_LOG"; then
            success "VM $vm_name cancelled successfully"
            return 0
        else
            error "Failed to cancel VM $vm_name"
            return 1
        fi
    else
        error "tfcmd not available for VM rollback"
        return 1
    fi
}

# =====================================================================================
# Remote System Rollback Functions
# =====================================================================================

rollback_remote_user() {
    local ip="$1"
    local user="$2"

    log "Rolling back user creation: $user@$ip"

    # Remove the created user
    if execute_remote "$ip" "root" "userdel -r '$user' 2>/dev/null || true"; then
        success "User $user removed successfully"
        return 0
    else
        error "Failed to remove user $user"
        return 1
    fi
}

rollback_remote_packages() {
    local ip="$1"
    local packages="$2"

    log "Rolling back package installation: $packages@$ip"

    # Remove installed packages
    if execute_remote "$ip" "root" "apt-get remove --purge -y $packages 2>/dev/null || true"; then
        success "Packages removed successfully"
        return 0
    else
        error "Failed to remove packages"
        return 1
    fi
}

rollback_remote_services() {
    local ip="$1"
    local services="$2"

    log "Rolling back services: $services@$ip"

    # Stop and disable services
    for service in $services; do
        execute_remote "$ip" "root" "systemctl stop $service 2>/dev/null || true"
        execute_remote "$ip" "root" "systemctl disable $service 2>/dev/null || true"
    done

    success "Services rolled back successfully"
}

rollback_remote_files() {
    local ip="$1"
    local files="$2"

    log "Rolling back files: $files@$ip"

    # Remove created files/directories
    if execute_remote "$ip" "root" "rm -rf $files 2>/dev/null || true"; then
        success "Files removed successfully"
        return 0
    else
        error "Failed to remove files"
        return 1
    fi
}

# =====================================================================================
# Application Rollback Functions
# =====================================================================================

rollback_application() {
    local ip="$1"
    local user="$2"

    log "Rolling back application deployment: $user@$ip"

    # Stop application services
    execute_remote "$ip" "$user" "cd ~/mycelium-matrix-chat && make down 2>/dev/null || true"

    # Remove application directory
    execute_remote "$ip" "$user" "rm -rf ~/mycelium-matrix-chat 2>/dev/null || true"

    # Remove systemd services
    execute_remote "$ip" "root" "rm -f /etc/systemd/system/matrix-bridge.service 2>/dev/null || true"
    execute_remote "$ip" "root" "rm -f /etc/systemd/system/web-gateway.service 2>/dev/null || true"
    execute_remote "$ip" "root" "rm -f /etc/systemd/system/mycelium-frontend.service 2>/dev/null || true"
    execute_remote "$ip" "root" "systemctl daemon-reload 2>/dev/null || true"

    success "Application rolled back successfully"
}

rollback_database() {
    local ip="$1"
    local user="$2"

    log "Rolling back database: $user@$ip"

    # Stop PostgreSQL
    execute_remote "$ip" "root" "systemctl stop postgresql 2>/dev/null || true"

    # Remove database files
    execute_remote "$ip" "root" "rm -rf /var/lib/postgresql 2>/dev/null || true"

    # Remove PostgreSQL package
    execute_remote "$ip" "root" "apt-get remove --purge -y postgresql postgresql-contrib 2>/dev/null || true"

    success "Database rolled back successfully"
}

# =====================================================================================
# Network Rollback Functions
# =====================================================================================

rollback_firewall() {
    local ip="$1"

    log "Rolling back firewall changes: $ip"

    # Reset UFW to defaults
    execute_remote "$ip" "root" "ufw --force reset 2>/dev/null || true"
    execute_remote "$ip" "root" "ufw --force enable 2>/dev/null || true"

    success "Firewall rolled back successfully"
}

rollback_mycelium() {
    local ip="$1"

    log "Rolling back Mycelium: $ip"

    # Stop Mycelium service
    execute_remote "$ip" "root" "systemctl stop myceliumd 2>/dev/null || true"
    execute_remote "$ip" "root" "systemctl disable myceliumd 2>/dev/null || true"

    # Remove Mycelium files
    execute_remote "$ip" "root" "rm -f /usr/local/bin/mycelium 2>/dev/null || true"
    execute_remote "$ip" "root" "rm -rf ~/.mycelium 2>/dev/null || true"

    success "Mycelium rolled back successfully"
}

# =====================================================================================
# Comprehensive Rollback Functions
# =====================================================================================

rollback_tfgrid_deployment() {
    local ip="$1"
    local vm_name="$2"

    log "Starting comprehensive TFGrid deployment rollback..."

    # Rollback in reverse order of deployment
    rollback_application "$ip" "$(get_config 'security.deploy_user')"
    rollback_database "$ip" "$(get_config 'security.deploy_user')"
    rollback_mycelium "$ip"
    rollback_firewall "$ip"
    rollback_remote_user "$ip" "$(get_config 'security.deploy_user')"
    rollback_tfgrid_vm "$vm_name"

    success "TFGrid deployment rollback completed"
}

rollback_local_deployment() {
    log "Starting local deployment rollback..."

    # Stop all services
    cd "$(get_config 'deployment.project_root')" || return 1
    make down 2>/dev/null || true

    # Remove containers and volumes
    docker-compose -f docker/docker-compose.yml down -v 2>/dev/null || true
    docker system prune -f 2>/dev/null || true

    # Remove built binaries
    rm -rf backend/matrix-bridge/target 2>/dev/null || true
    rm -rf backend/web-gateway/target 2>/dev/null || true
    rm -rf frontend/dist 2>/dev/null || true

    success "Local deployment rollback completed"
}

# =====================================================================================
# Recovery Functions
# =====================================================================================

attempt_recovery() {
    local ip="$1"
    local failed_step="$2"

    log "Attempting recovery from failed step: $failed_step"

    case "$failed_step" in
        "vm_deployment")
            log "Retrying VM deployment..."
            # VM deployment recovery would be handled by the main script
            return 1  # Let main script handle this
            ;;

        "remote_preparation")
            log "Retrying remote preparation..."
            # Clean up partial preparation and retry
            execute_remote "$ip" "root" "rm -rf /tmp/prepare-* 2>/dev/null || true"
            return 0  # Signal that retry is possible
            ;;

        "application_deployment")
            log "Retrying application deployment..."
            # Clean up partial application deployment
            execute_remote "$ip" "$(get_config 'security.deploy_user')" "rm -rf ~/mycelium-matrix-chat 2>/dev/null || true"
            return 0  # Signal that retry is possible
            ;;

        *)
            log "No specific recovery strategy for step: $failed_step"
            return 1  # No recovery possible
            ;;
    esac
}

# =====================================================================================
# Error Recovery Integration
# =====================================================================================

cleanup_on_error() {
    log "Running error cleanup..."

    # Clean up temporary files
    rm -f /tmp/deploy-* 2>/dev/null || true
    rm -f /tmp/prepare-* 2>/dev/null || true
    rm -f /tmp/mycelium-matrix-* 2>/dev/null || true

    # Clean up log files older than 7 days
    find /tmp -name "mycelium-matrix-*.log" -mtime +7 -delete 2>/dev/null || true
}

# =====================================================================================
# Backup and Restore Functions
# =====================================================================================

create_backup() {
    local ip="$1"
    local user="$2"
    local backup_dir="${3:-/tmp/backup-$(date +%Y%m%d-%H%M%S)}"

    log "Creating backup: $backup_dir"

    # Create backup directory
    execute_remote "$ip" "$user" "mkdir -p $backup_dir"

    # Backup application data
    execute_remote "$ip" "$user" "cp -r ~/mycelium-matrix-chat $backup_dir/ 2>/dev/null || true"

    # Backup database (if running)
    execute_remote "$ip" "$user" "pg_dump -U $(get_config 'database.user') $(get_config 'database.name') > $backup_dir/database.sql 2>/dev/null || true"

    # Backup configuration files
    execute_remote "$ip" "root" "cp -r /etc/systemd/system/matrix-* $backup_dir/systemd/ 2>/dev/null || true"
    execute_remote "$ip" "root" "cp /etc/nginx/sites-available/* $backup_dir/nginx/ 2>/dev/null || true"

    success "Backup created: $backup_dir"
    echo "$backup_dir"
}

restore_from_backup() {
    local ip="$1"
    local user="$2"
    local backup_dir="$3"

    log "Restoring from backup: $backup_dir"

    # Check if backup exists
    if ! execute_remote "$ip" "$user" "test -d $backup_dir"; then
        error "Backup directory not found: $backup_dir"
        return 1
    fi

    # Restore application data
    execute_remote "$ip" "$user" "cp -r $backup_dir/mycelium-matrix-chat ~/ 2>/dev/null || true"

    # Restore database
    execute_remote "$ip" "$user" "psql -U $(get_config 'database.user') $(get_config 'database.name') < $backup_dir/database.sql 2>/dev/null || true"

    # Restore configuration files
    execute_remote "$ip" "root" "cp $backup_dir/systemd/* /etc/systemd/system/ 2>/dev/null || true"
    execute_remote "$ip" "root" "cp $backup_dir/nginx/* /etc/nginx/sites-available/ 2>/dev/null || true"
    execute_remote "$ip" "root" "systemctl daemon-reload 2>/dev/null || true"

    success "Restored from backup: $backup_dir"
}

# =====================================================================================
# Monitoring and Alerting Functions
# =====================================================================================

monitor_deployment() {
    local ip="$1"
    local timeout="${2:-300}"
    local check_interval="${3:-30}"

    log "Monitoring deployment for $timeout seconds..."

    local start_time
    start_time=$(date +%s)
    local last_check=0

    while [ $(( $(date +%s) - start_time )) -lt "$timeout" ]; do
        local current_time
        current_time=$(date +%s)

        if [ $((current_time - last_check)) -ge "$check_interval" ]; then
            debug "Deployment status check..."

            # Check if basic services are running
            if execute_remote "$ip" "$(get_config 'security.deploy_user')" "curl -s http://localhost:8080/api/health > /dev/null"; then
                success "Deployment appears healthy"
                return 0
            fi

            last_check="$current_time"
        fi

        sleep 5
    done

    warning "Deployment monitoring timeout reached"
    return 1
}

# =====================================================================================
# Utility Functions
# =====================================================================================

is_rollback_needed() {
    # Check if there are any rollback actions pending
    [ ${#ROLLBACK_STACK[@]} -gt 0 ]
}

get_rollback_summary() {
    echo "Pending rollback actions: ${#ROLLBACK_STACK[@]}"
    for ((i = 0; i < ${#ROLLBACK_STACK[@]}; i++)); do
        local action_desc="${ROLLBACK_STACK[$i]}"
        IFS='|' read -r action description <<< "$action_desc"
        echo "  $((i + 1)). $description"
    done
}

clear_rollback_stack() {
    log "Clearing rollback stack (${#ROLLBACK_STACK[@]} actions)"
    ROLLBACK_STACK=()
}