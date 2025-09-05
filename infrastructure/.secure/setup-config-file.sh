#!/bin/bash

# Secure ThreeFold Mnemonic Setup Script
# This script helps you set up secure credential storage following industry standards

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check if mnemonic is already configured
check_existing_config() {
    if [ -n "$TF_VAR_mnemonic" ]; then
        warning "TF_VAR_mnemonic environment variable is already set"
        echo "This will override any config file settings."
        return 0
    fi

    local config_files=(
        "$HOME/.config/threefold/mnemonic"
        "$HOME/.threefold/mnemonic"
    )

    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            warning "Config file already exists: $config_file"
            echo "This will overwrite the existing file."
            return 0
        fi
    done
}

# Setup config directory
setup_config_directory() {
    local config_dir="$HOME/.config/threefold"

    log "Creating secure config directory: $config_dir"
    mkdir -p "$config_dir"

    # Set restrictive permissions
    chmod 700 "$HOME/.config"
    chmod 700 "$config_dir"

    success "Config directory created securely"
}

# Prompt for mnemonic securely
get_mnemonic() {
    local mnemonic=""

    echo ""
    echo "🔐 ThreeFold Mnemonic Setup"
    echo "=========================="
    echo ""
    warning "Your mnemonic phrase will be stored securely on your local machine."
    echo "Make sure you're on a trusted, private system."
    echo ""

    # Disable history recording for this session
    if [ -n "$BASH_VERSION" ]; then
        set +o history
    fi

    # Prompt for mnemonic
    read -s -p "Enter your ThreeFold mnemonic phrase: " mnemonic
    echo ""

    # Verify mnemonic (basic check)
    if [ -z "$mnemonic" ]; then
        error "Mnemonic cannot be empty"
        exit 1
    fi

    if [ ${#mnemonic} -lt 50 ]; then
        warning "Mnemonic seems short. Please verify it's complete."
        read -p "Continue anyway? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Re-enable history
    if [ -n "$BASH_VERSION" ]; then
        set -o history
    fi

    echo "$mnemonic"
}

# Save mnemonic to file securely
save_mnemonic() {
    local mnemonic="$1"
    local config_file="$HOME/.config/threefold/mnemonic"

    log "Saving mnemonic to: $config_file"

    # Write to file
    echo "$mnemonic" > "$config_file"

    # Set restrictive permissions
    chmod 600 "$config_file"

    success "Mnemonic saved securely"
    echo "File: $config_file"
    echo "Permissions: $(ls -la "$config_file" | awk '{print $1}')"
}

# Verify setup
verify_setup() {
    local config_file="$HOME/.config/threefold/mnemonic"

    log "Verifying setup..."

    # Check file exists
    if [ ! -f "$config_file" ]; then
        error "Config file not found: $config_file"
        return 1
    fi

    # Check permissions
    local perms
    perms=$(ls -la "$config_file" | awk '{print $1}')
    if [[ "$perms" != "-rw-------" ]]; then
        warning "File permissions are not restrictive: $perms"
        echo "Run: chmod 600 $config_file"
    fi

    # Test reading the mnemonic
    local test_mnemonic
    test_mnemonic=$(cat "$config_file" 2>/dev/null)
    if [ -z "$test_mnemonic" ]; then
        error "Could not read mnemonic from file"
        return 1
    fi

    success "Setup verification passed"
}

# Main execution
main() {
    echo "🔐 Secure ThreeFold Mnemonic Configuration"
    echo "=========================================="
    echo ""

    check_existing_config

    setup_config_directory

    local mnemonic
    mnemonic=$(get_mnemonic)

    save_mnemonic "$mnemonic"

    verify_setup

    echo ""
    echo "🎉 Setup Complete!"
    echo ""
    echo "Your ThreeFold mnemonic is now stored securely at:"
    echo "  $HOME/.config/threefold/mnemonic"
    echo ""
    echo "You can now run MMC deployments without manually setting environment variables:"
    echo "  make vm-tofu"
    echo ""
    echo "To view current configuration:"
    echo "  cat $HOME/.config/threefold/mnemonic"
    echo ""
    echo "To remove stored mnemonic:"
    echo "  rm $HOME/.config/threefold/mnemonic"
}

# Run main function
main "$@"