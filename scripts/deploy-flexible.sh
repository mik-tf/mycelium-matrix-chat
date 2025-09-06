#!/bin/bash

# Mycelium-Matrix Chat Flexible Deployment Script
# This script helps operators choose between IPv4+Domain or Mycelium-Only deployment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if required tools are installed
check_dependencies() {
    print_info "Checking dependencies..."

    if ! command -v terraform &> /dev/null && ! command -v tofu &> /dev/null; then
        print_error "Terraform or OpenTofu is required but not installed."
        exit 1
    fi

    if ! command -v ansible &> /dev/null; then
        print_error "Ansible is required but not installed."
        exit 1
    fi

    print_success "Dependencies check passed"
}

# Function to get user choice
get_deployment_choice() {
    echo ""
    echo "Choose your deployment type:"
    echo ""
    echo "1) IPv4 + Domain (~1.0 TFT/month)"
    echo "   - Access via: https://yourdomain.com"
    echo "   - Best for: Public production services"
    echo "   - Requires: Domain name and DNS configuration"
    echo ""
    echo "2) Mycelium-Only (~0.5 TFT/month)"
    echo "   - Access via: https://[mycelium-ip]:443"
    echo "   - Best for: Private groups, testing, P2P focus"
    echo "   - Requires: Nothing (automatic mycelium IP)"
    echo ""
    read -p "Enter your choice (1 or 2): " choice

    case $choice in
        1)
            DEPLOYMENT_TYPE="ipv4"
            TF_VAR_enable_public_ipv4=true
            COST="~1.0 TFT/month"
            ;;
        2)
            DEPLOYMENT_TYPE="mycelium"
            TF_VAR_enable_public_ipv4=false
            COST="~0.5 TFT/month"
            ;;
        *)
            print_error "Invalid choice. Please enter 1 or 2."
            exit 1
            ;;
    esac
}

# Function to get domain name for IPv4 deployments
get_domain_info() {
    if [ "$DEPLOYMENT_TYPE" = "ipv4" ]; then
        echo ""
        read -p "Enter your domain name (e.g., chat.example.com): " DOMAIN_NAME
        if [ -z "$DOMAIN_NAME" ]; then
            print_error "Domain name is required for IPv4 deployment"
            exit 1
        fi
        print_info "Domain: $DOMAIN_NAME"
        print_warning "Remember to configure DNS: $DOMAIN_NAME → [Public IP from deployment]"
    fi
}

# Function to set credentials
set_credentials() {
    echo ""
    print_info "Setting up ThreeFold credentials..."

    # Check for existing mnemonic
    if [ -n "$TF_VAR_mnemonic" ]; then
        print_success "Using TF_VAR_mnemonic from environment"
    elif [ -f "$HOME/.config/threefold/mnemonic" ]; then
        print_success "Using mnemonic from $HOME/.config/threefold/mnemonic"
    else
        print_warning "No mnemonic found. Please set it using one of these methods:"
        echo ""
        echo "Method 1 - Environment variable:"
        echo "  export TF_VAR_mnemonic='your_mnemonic_here'"
        echo ""
        echo "Method 2 - Config file:"
        echo "  mkdir -p ~/.config/threefold"
        echo "  echo 'your_mnemonic_here' > ~/.config/threefold/mnemonic"
        echo "  chmod 600 ~/.config/threefold/mnemonic"
        echo ""
        read -p "Do you want to set the mnemonic now? (y/N): " set_mnemonic

        if [[ $set_mnemonic =~ ^[Yy]$ ]]; then
            read -p "Enter your ThreeFold mnemonic: " mnemonic
            export TF_VAR_mnemonic="$mnemonic"
            print_success "Mnemonic set for this session"
        else
            print_error "Mnemonic is required for deployment"
            exit 1
        fi
    fi
}

# Function to run deployment
run_deployment() {
    echo ""
    print_info "Starting deployment..."
    print_info "Type: $DEPLOYMENT_TYPE deployment"
    print_info "Cost: $COST"

    # Export the variable for make
    export TF_VAR_enable_public_ipv4

    # Run the deployment
    if make deploy; then
        print_success "Deployment completed successfully!"
        echo ""
        print_info "Deployment Summary:"
        echo "  Type: $([ "$DEPLOYMENT_TYPE" = "ipv4" ] && echo "IPv4 + Domain" || echo "Mycelium-Only")"
        echo "  Cost: $COST"
        echo ""

        # Get deployment outputs
        cd infrastructure
        echo "🔗 Access Information:"
        if [ "$DEPLOYMENT_TYPE" = "ipv4" ]; then
            PUBLIC_IP=$(terraform output -raw vm_public_ip 2>/dev/null || echo "Check terraform output")
            MYCELIUM_IP=$(terraform output -raw vm_mycelium_ip 2>/dev/null || echo "Check terraform output")
            echo "  Public IP: $PUBLIC_IP"
            echo "  Domain: Configure DNS $DOMAIN_NAME → $PUBLIC_IP"
            echo "  Mycelium: https://$MYCELIUM_IP:443"
        else
            MYCELIUM_IP=$(terraform output -raw vm_mycelium_ip 2>/dev/null || echo "Check terraform output")
            echo "  Mycelium: https://$MYCELIUM_IP:443"
        fi
        cd ..

        echo ""
        print_success "Next steps:"
        echo "1. Run 'make status' to check service status"
        echo "2. Run 'make test-phase2-quick' to verify functionality"
        if [ "$DEPLOYMENT_TYPE" = "ipv4" ]; then
            echo "3. Configure DNS: $DOMAIN_NAME → Public IP"
            echo "4. Access at: https://$DOMAIN_NAME"
        fi
        echo "5. Share mycelium URL: https://$MYCELIUM_IP:443"

    else
        print_error "Deployment failed. Check the logs above for details."
        exit 1
    fi
}

# Main execution
main() {
    echo "🚀 Mycelium-Matrix Chat Flexible Deployment"
    echo "=========================================="
    echo ""

    check_dependencies
    get_deployment_choice
    get_domain_info
    set_credentials
    run_deployment
}

# Run main function
main "$@"