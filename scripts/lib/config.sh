#!/bin/bash

# =====================================================================================
# Mycelium-Matrix Chat - Configuration Management Library
# =====================================================================================
# This library provides functions for loading and managing configuration files

# Global configuration variables
declare -A CONFIG

# =====================================================================================
# Configuration Loading Functions
# =====================================================================================

load_config() {
    local environment="$1"
    local config_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config" && pwd)"

    log "Loading configuration for environment: $environment"

    # Load defaults first
    load_config_file "$config_dir/defaults.conf"

    # Load environment-specific overrides
    case "$environment" in
        tfgrid)
            load_config_file "$config_dir/tfgrid.conf"
            ;;
        local)
            load_config_file "$config_dir/local.conf"
            ;;
        *)
            warning "Unknown environment '$environment', using defaults only"
            ;;
    esac

    # Apply environment variable overrides
    apply_env_overrides

    success "Configuration loaded successfully"
}

load_config_file() {
    local config_file="$1"

    if [ ! -f "$config_file" ]; then
        warning "Configuration file not found: $config_file"
        return 1
    fi

    log "Loading config file: $config_file"

    local current_section=""
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ $line =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue

        # Section headers
        if [[ $line =~ ^\[([^\]]+)\] ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi

        # Key-value pairs
        if [[ $line =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]// /}"
            local value="${BASH_REMATCH[2]// /}"

            # Remove quotes if present
            value="${value%\"}"
            value="${value#\"}"

            # Store with section prefix
            if [ -n "$current_section" ]; then
                CONFIG["$current_section.$key"]="$value"
            else
                CONFIG["$key"]="$value"
            fi
        fi
    done < "$config_file"
}

apply_env_overrides() {
    # Allow environment variables to override config values
    # Format: MYCELIUM_MATRIX_<SECTION>_<KEY>

    for key in "${!CONFIG[@]}"; do
        if [[ $key =~ ^([^.]+)\.(.+)$ ]]; then
            local section="${BASH_REMATCH[1]}"
            local config_key="${BASH_REMATCH[2]}"
            local env_var="MYCELIUM_MATRIX_${section^^}_${config_key^^}"

            # Check if environment variable exists before trying to expand it
            if [ -n "${!env_var+x}" ]; then
                local env_value="${!env_var}"
                if [ -n "$env_value" ]; then
                    log "Applying environment override: $key = $env_value"
                    CONFIG["$key"]="$env_value"
                fi
            fi
        fi
    done
}

# =====================================================================================
# Configuration Access Functions
# =====================================================================================

get_config() {
    local key="$1"
    local default_value="${2:-}"

    # Check if the key exists in the array
    if [ -n "${CONFIG[$key]+x}" ]; then
        local value="${CONFIG[$key]}"
        echo "$value"
    else
        # Return default value if provided
        echo "$default_value"
    fi
}

set_config() {
    local key="$1"
    local value="$2"

    CONFIG["$key"]="$value"
    log "Configuration updated: $key = $value"
}

# =====================================================================================
# Configuration Validation Functions
# =====================================================================================

validate_config() {
    log "Validating configuration..."

    local errors=0

    # Required configurations with validation
    if [ -z "$(get_config "vm.name" "")" ]; then
        error "Missing required configuration: vm.name"
        ((errors++))
    fi

    if [ -z "$(get_config "deployment.repo_url" "")" ]; then
        error "Missing required configuration: deployment.repo_url"
        ((errors++))
    fi

    if [ -z "$(get_config "software.mycelium_version" "")" ]; then
        error "Missing required configuration: software.mycelium_version"
        ((errors++))
    fi

    if [ -z "$(get_config "security.deploy_user" "")" ]; then
        error "Missing required configuration: security.deploy_user"
        ((errors++))
    fi

    # Validate VM configuration
    if [ "$(get_config "vm.cpu")" -lt 1 ] 2>/dev/null; then
        error "VM CPU must be at least 1"
        ((errors++))
    fi

    if [ "$(get_config "vm.memory")" -lt 1 ] 2>/dev/null; then
        error "VM memory must be at least 1 GB"
        ((errors++))
    fi

    # Validate SSH key exists
    local ssh_key_path
    ssh_key_path=$(get_config "deployment.ssh_key_path" "~/.ssh/id_ed25519.pub")
    ssh_key_path=$(eval echo "$ssh_key_path")

    if [ ! -f "$ssh_key_path" ]; then
        error "SSH key not found: $ssh_key_path"
        ((errors++))
    fi

    if [ $errors -eq 0 ]; then
        success "Configuration validation passed"
        return 0
    else
        error "$errors configuration errors found"
        return 1
    fi
}

# =====================================================================================
# Configuration Display Functions
# =====================================================================================

show_config() {
    local filter="$1"

    echo "📋 Current Configuration:"
    echo "========================"
    echo "Total config entries: ${#CONFIG[@]}"

    for key in "${!CONFIG[@]}"; do
        if [ -z "$filter" ] || [[ $key =~ $filter ]]; then
            printf "  %-30s = '%s'\n" "$key" "${CONFIG[$key]}"
        fi
    done
    echo ""
}

debug_config() {
    echo "🔍 CONFIG Array Debug:"
    echo "======================"
    echo "Array size: ${#CONFIG[@]}"

    if [ ${#CONFIG[@]} -eq 0 ]; then
        echo "CONFIG array is empty!"
        return 1
    fi

    echo "All keys:"
    for key in "${!CONFIG[@]}"; do
        echo "  '$key' = '${CONFIG[$key]}'"
    done
    echo ""
}

show_config_summary() {
    echo "📋 Configuration Summary:"
    echo "========================="
    echo "Environment: $(get_config "deployment.environment" "unknown")"
    echo "VM Name: $(get_config "vm.name" "unknown")"
    echo "VM Specs: $(get_config "vm.cpu" "unknown") CPU, $(get_config "vm.memory" "unknown") GB RAM, $(get_config "vm.disk" "unknown") GB disk"
    echo "Repository: $(get_config "deployment.repo_url" "unknown")"
    echo "Branch: $(get_config "deployment.branch" "unknown")"
    echo "Deploy User: $(get_config "security.deploy_user" "unknown")"
    echo "SSH Key: $(get_config "deployment.ssh_key_path" "unknown")"
    echo ""
}

# =====================================================================================
# Configuration Export Functions
# =====================================================================================

export_config_env() {
    # Export configuration as environment variables for subprocesses
    for key in "${!CONFIG[@]}"; do
        if [[ $key =~ ^([^.]+)\.(.+)$ ]]; then
            local section="${BASH_REMATCH[1]}"
            local config_key="${BASH_REMATCH[2]}"
            local env_var="MYCELIUM_MATRIX_${section^^}_${config_key^^}"
            export "$env_var"="${CONFIG[$key]}"
        fi
    done
}

save_config() {
    local output_file="$1"

    log "Saving configuration to: $output_file"

    echo "# Mycelium-Matrix Chat Configuration" > "$output_file"
    echo "# Generated on $(date)" >> "$output_file"
    echo "" >> "$output_file"

    local current_section=""
    for key in "${!CONFIG[@]}"; do
        if [[ $key =~ ^([^.]+)\.(.+)$ ]]; then
            local section="${BASH_REMATCH[1]}"
            local config_key="${BASH_REMATCH[2]}"
            local value="${CONFIG[$key]}"

            if [ "$section" != "$current_section" ]; then
                echo "[$section]" >> "$output_file"
                current_section="$section"
            fi

            echo "$config_key = \"$value\"" >> "$output_file"
        fi
    done

    success "Configuration saved to $output_file"
}