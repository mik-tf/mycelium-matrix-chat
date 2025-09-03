#!/bin/bash

# =====================================================================================
# Mycelium-Matrix Chat - Utility Functions Library
# =====================================================================================
# This library provides common utility functions for logging, error handling, and system operations

# =====================================================================================
# Logging Functions
# =====================================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging level (can be overridden by config)
LOG_LEVEL="${LOG_LEVEL:-info}"
LOG_FILE="${LOG_FILE:-/tmp/mycelium-matrix-deploy.log}"

# Log levels (in order of verbosity)
declare -A LOG_LEVELS=(
    [error]=0
    [warn]=1
    [info]=2
    [debug]=3
)

log() {
    local level="${1:-info}"
    local message="$2"
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')

    # Check if we should log this level
    if [ "${LOG_LEVELS[$level]}" -gt "${LOG_LEVELS[$LOG_LEVEL]}" ]; then
        return
    fi

    # Format message with color
    local color="$NC"
    case "$level" in
        error) color="$RED" ;;
        warn) color="$YELLOW" ;;
        info) color="$BLUE" ;;
        debug) color="$PURPLE" ;;
        success) color="$GREEN" ;;
    esac

    # Log to file (without colors)
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"

    # Log to console (with colors)
    echo -e "${color}[$timestamp]${NC} $message" >&2
}

success() {
    log "success" "✅ $*"
}

warning() {
    log "warn" "⚠️  $*"
}

error() {
    log "error" "❌ $*"
}

debug() {
    log "debug" "🔍 $*"
}

info() {
    log "info" "ℹ️  $*"
}

# =====================================================================================
# Error Handling Functions
# =====================================================================================

# Global error handling
set -o errtrace  # Enable error tracing
trap 'handle_error $? $LINENO $BASH_COMMAND' ERR

handle_error() {
    local exit_code="$1"
    local line_number="$2"
    local command="$3"

    error "Command failed (exit code: $exit_code) at line $line_number:"
    error "  Command: $command"
    error "  Working directory: $(pwd)"
    error "  User: $(whoami)"

    # Show recent log entries
    if [ -f "$LOG_FILE" ]; then
        error "Recent log entries:"
        tail -10 "$LOG_FILE" | while read -r line; do
            error "  $line"
        done
    fi

    # Call cleanup if defined
    if declare -f cleanup_on_error > /dev/null; then
        warning "Running error cleanup..."
        cleanup_on_error
    fi

    exit "$exit_code"
}

# Execute command with retry logic
execute_with_retry() {
    local command="$1"
    local max_attempts="${2:-3}"
    local delay="${3:-5}"
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        debug "Executing (attempt $attempt/$max_attempts): $command"

        if eval "$command"; then
            return 0
        fi

        if [ $attempt -lt $max_attempts ]; then
            warning "Command failed, retrying in $delay seconds..."
            sleep "$delay"
        fi

        ((attempt++))
    done

    error "Command failed after $max_attempts attempts"
    return 1
}

# Execute command with timeout
execute_with_timeout() {
    local timeout="$1"
    local command="$2"

    debug "Executing with ${timeout}s timeout: $command"

    if timeout "$timeout" bash -c "$command"; then
        return 0
    else
        local exit_code="$?"
        if [ "$exit_code" -eq 124 ]; then
            error "Command timed out after ${timeout} seconds"
        else
            error "Command failed with exit code $exit_code"
        fi
        return "$exit_code"
    fi
}

# =====================================================================================
# System Validation Functions
# =====================================================================================

check_command() {
    local command="$1"
    local description="${2:-$command}"

    if command -v "$command" &>/dev/null; then
        debug "$description found: $(command -v "$command")"
        return 0
    else
        error "$description not found in PATH"
        return 1
    fi
}

check_file() {
    local file="$1"
    local description="${2:-file}"

    if [ -f "$file" ]; then
        debug "$description found: $file"
        return 0
    else
        error "$description not found: $file"
        return 1
    fi
}

check_directory() {
    local dir="$1"
    local description="${2:-directory}"

    if [ -d "$dir" ]; then
        debug "$description found: $dir"
        return 0
    else
        error "$description not found: $dir"
        return 1
    fi
}

# =====================================================================================
# Network Functions
# =====================================================================================

check_connectivity() {
    local host="${1:-8.8.8.8}"
    local timeout="${2:-10}"

    debug "Checking connectivity to $host..."

    if ping -c 1 -W "$timeout" "$host" &>/dev/null; then
        debug "Network connectivity confirmed"
        return 0
    else
        error "No network connectivity to $host"
        return 1
    fi
}

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    local interval="${4:-2}"

    debug "Waiting for $host:$port (timeout: ${timeout}s)"

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if nc -z "$host" "$port" 2>/dev/null; then
            debug "Port $port is now open"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    error "Timeout waiting for $host:$port"
    return 1
}

# =====================================================================================
# File System Functions
# =====================================================================================

ensure_directory() {
    local dir="$1"

    if [ ! -d "$dir" ]; then
        debug "Creating directory: $dir"
        mkdir -p "$dir" || {
            error "Failed to create directory: $dir"
            return 1
        }
    fi
}

ensure_file() {
    local file="$1"
    local content="${2:-}"

    if [ ! -f "$file" ]; then
        debug "Creating file: $file"
        echo "$content" > "$file" || {
            error "Failed to create file: $file"
            return 1
        }
    fi
}

backup_file() {
    local file="$1"
    local backup_suffix="${2:-.$(date +%Y%m%d_%H%M%S)}"

    if [ -f "$file" ]; then
        local backup_file="${file}${backup_suffix}"
        debug "Backing up $file to $backup_file"
        cp "$file" "$backup_file" || {
            error "Failed to backup file: $file"
            return 1
        }
    fi
}

# =====================================================================================
# Process Management Functions
# =====================================================================================

is_process_running() {
    local process_name="$1"

    if pgrep -f "$process_name" > /dev/null; then
        return 0
    else
        return 1
    fi
}

kill_process() {
    local process_name="$1"
    local signal="${2:-TERM}"

    debug "Killing process: $process_name (signal: $signal)"

    if pkill -"$signal" -f "$process_name"; then
        debug "Process killed successfully"
        return 0
    else
        warning "Failed to kill process: $process_name"
        return 1
    fi
}

wait_for_process() {
    local process_name="$1"
    local timeout="${2:-30}"

    debug "Waiting for process: $process_name (timeout: ${timeout}s)"

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if is_process_running "$process_name"; then
            debug "Process is now running: $process_name"
            return 0
        fi

        sleep 1
        elapsed=$((elapsed + 1))
    done

    error "Timeout waiting for process: $process_name"
    return 1
}

# =====================================================================================
# String and Text Functions
# =====================================================================================

to_uppercase() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

to_lowercase() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

trim() {
    local string="$1"
    # Remove leading/trailing whitespace
    string="${string#"${string%%[![:space:]]*}"}"
    string="${string%"${string##*[![:space:]]}"}"
    echo "$string"
}

contains() {
    local string="$1"
    local substring="$2"

    if [[ "$string" == *"$substring"* ]]; then
        return 0
    else
        return 1
    fi
}

# =====================================================================================
# Progress and Status Functions
# =====================================================================================

show_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-Progress}"

    if [ "$total" -gt 0 ]; then
        local percentage=$((current * 100 / total))
        local progress_bar=""
        local filled=$((percentage / 5))
        local empty=$((20 - filled))

        for ((i = 0; i < filled; i++)); do
            progress_bar="${progress_bar}█"
        done

        for ((i = 0; i < empty; i++)); do
            progress_bar="${progress_bar}░"
        done

        printf "\r%s: [%s] %d%% (%d/%d)" "$message" "$progress_bar" "$percentage" "$current" "$total" >&2
    fi
}

show_spinner() {
    local message="$1"
    local pid="$2"
    local spinner_chars="/-\|"

    printf "%s " "$message" >&2

    while kill -0 "$pid" 2>/dev/null; do
        for ((i = 0; i < ${#spinner_chars}; i++)); do
            printf "\b%s" "${spinner_chars:i:1}" >&2
            sleep 0.1
        done
    done

    printf "\b \n" >&2
}

# =====================================================================================
# Cleanup Functions
# =====================================================================================

cleanup_temp_files() {
    local temp_dir="${1:-/tmp}"

    debug "Cleaning up temporary files in $temp_dir"

    # Remove old log files (older than 7 days)
    find "$temp_dir" -name "mycelium-matrix-*.log" -mtime +7 -delete 2>/dev/null || true

    # Remove temporary deployment files
    find "$temp_dir" -name "deploy-*.sh" -mtime +1 -delete 2>/dev/null || true
    find "$temp_dir" -name "prepare-*.sh" -mtime +1 -delete 2>/dev/null || true
}

# =====================================================================================
# Version and Compatibility Functions
# =====================================================================================

compare_versions() {
    local version1="$1"
    local version2="$2"

    # Simple version comparison (supports x.y.z format)
    if [[ "$version1" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] && [[ "$version2" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        local v1_major="${BASH_REMATCH[1]}"
        local v1_minor="${BASH_REMATCH[2]}"
        local v1_patch="${BASH_REMATCH[3]}"

        local v2_major="${BASH_REMATCH[1]}"
        local v2_minor="${BASH_REMATCH[2]}"
        local v2_patch="${BASH_REMATCH[3]}"

        if [ "$v1_major" -gt "$v2_major" ]; then
            echo "greater"
        elif [ "$v1_major" -lt "$v2_major" ]; then
            echo "less"
        elif [ "$v1_minor" -gt "$v2_minor" ]; then
            echo "greater"
        elif [ "$v1_minor" -lt "$v2_minor" ]; then
            echo "less"
        elif [ "$v1_patch" -gt "$v2_patch" ]; then
            echo "greater"
        elif [ "$v1_patch" -lt "$v2_patch" ]; then
            echo "less"
        else
            echo "equal"
        fi
    else
        error "Invalid version format. Expected: x.y.z"
        return 1
    fi
}

# =====================================================================================
# Initialization
# =====================================================================================

# Initialize logging
ensure_directory "$(dirname "$LOG_FILE")"

# Clean up old temporary files on startup
cleanup_temp_files