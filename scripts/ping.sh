#!/bin/bash
# Test connectivity to the deployed Mycelium-Matrix Chat VM
# Similar to tfgrid-k3s ping functionality but adapted for single VM with mycelium IP

# Get script directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT="$SCRIPT_DIR/.."
INVENTORY_FILE="$PROJECT_ROOT/platform/inventory/hosts.ini"

# Check if inventory exists
if [ ! -f "$INVENTORY_FILE" ]; then
    echo "❌ Inventory file not found: $INVENTORY_FILE"
    echo "   Run 'make vm' first to deploy infrastructure."
    exit 1
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Configuration
MAX_SCRIPT_RETRIES=5
SCRIPT_RETRY_DELAY=15  # seconds between full script retries
MAX_HOST_RETRIES=3     # Retries for a single host within one script attempt
HOST_RETRY_DELAY=5     # seconds between checks for a single host
SSH_CONNECT_TIMEOUT=15 # SSH connection timeout (seconds)

# Function to test connectivity to the MMC VM
test_mmc_connectivity() {
    local user=$1
    local ip=$2
    local name=$3
    local host_retries=0

    echo -n "  Testing $name (${user}@${ip})... "

    while [ $host_retries -lt $MAX_HOST_RETRIES ]; do
        # Test SSH connectivity with mycelium IP
        if ssh -o StrictHostKeyChecking=no \
               -o ConnectTimeout=$SSH_CONNECT_TIMEOUT \
               -o UserKnownHostsFile=/dev/null \
               "${user}@${ip}" \
               "echo 'MMC VM is reachable'" &>/dev/null; then
            echo -e "${GREEN}Success!${NC}"
            return 0
        else
            host_retries=$((host_retries+1))

            if [ $host_retries -lt $MAX_HOST_RETRIES ]; then
                echo -e "${YELLOW}Failed (attempt $host_retries/$MAX_HOST_RETRIES)${NC}"
                echo -n "  Retrying in $HOST_RETRY_DELAY seconds... "
                sleep $HOST_RETRY_DELAY
                echo -n "  Testing $name (${user}@${ip})... "
            else
                echo -e "${RED}Failed after $MAX_HOST_RETRIES attempts!${NC}"
                return 1
            fi
        fi
    done
    return 1
}

# Parse inventory file to extract MMC server details
parse_inventory() {
    local mmc_servers_found=0

    echo -e "${BLUE}=== Parsing MMC Inventory ===${NC}"

    # Look for mmc_servers section
    local in_mmc_section=0
    local mmc_ip=""
    local mmc_user=""

    while IFS= read -r line; do
        # Check for mmc_servers section
        if [[ "$line" == "[mmc_servers]" ]]; then
            in_mmc_section=1
            continue
        fi

        # Stop at next section
        if [[ $in_mmc_section -eq 1 && "$line" =~ ^\s*\[ ]]; then
            break
        fi

        # Parse mmc_servers lines
        if [[ $in_mmc_section -eq 1 && "$line" =~ ansible_host ]] && [[ -n "$line" ]] && [[ ! "$line" =~ ^\s*# ]]; then
            mmc_name=$(echo "$line" | awk '{print $1}')
            mmc_ip=$(echo "$line" | grep -o "ansible_host=[^ ]*" | cut -d= -f2)
            mmc_user=$(echo "$line" | grep -o "ansible_user=[^ ]*" | cut -d= -f2)

            if [ -n "$mmc_ip" ] && [ -n "$mmc_user" ]; then
                mmc_servers_found=1
                break
            fi
        fi
    done < "$INVENTORY_FILE"

    if [ $mmc_servers_found -eq 0 ]; then
        echo -e "${RED}❌ No MMC servers found in inventory${NC}"
        echo "   Make sure 'make vm' has been run successfully."
        return 1
    fi

    echo -e "${CYAN}  Found MMC server: $mmc_name${NC}"
    echo -e "${CYAN}  Mycelium IP: $mmc_ip${NC}"
    echo -e "${CYAN}  SSH User: $mmc_user${NC}"

    # Export variables for use in main script
    MMC_NAME="$mmc_name"
    MMC_IP="$mmc_ip"
    MMC_USER="$mmc_user"
    return 0
}

# Main script logic with retries
main() {
    echo -e "${CYAN}🔗 Testing Mycelium-Matrix Chat VM Connectivity${NC}"
    echo -e "${CYAN}===========================================${NC}"

    # Parse inventory first
    if ! parse_inventory; then
        exit 1
    fi

    local script_attempt=1
    local overall_success=0

    while [ $script_attempt -le $MAX_SCRIPT_RETRIES ]; do
        echo -e "\n${CYAN}<<<<< Connectivity Test Attempt $script_attempt / $MAX_SCRIPT_RETRIES >>>>>${NC}"

        echo -e "${BLUE}=== Testing MMC VM Connectivity ===${NC}"

        if test_mmc_connectivity "$MMC_USER" "$MMC_IP" "$MMC_NAME"; then
            echo -e "\n${BLUE}----- Attempt $script_attempt Summary -----${NC}"
            echo -e "${GREEN}✓ MMC VM is reachable via Mycelium network${NC}"
            overall_success=1
            break
        else
            echo -e "\n${BLUE}----- Attempt $script_attempt Summary -----${NC}"
            echo -e "${RED}✗ MMC VM unreachable via Mycelium network${NC}"

            if [ $script_attempt -lt $MAX_SCRIPT_RETRIES ]; then
                echo -e "${YELLOW}Retrying in $SCRIPT_RETRY_DELAY seconds...${NC}"
                sleep $SCRIPT_RETRY_DELAY
            fi
        fi

        script_attempt=$((script_attempt+1))
    done

    # Final result
    echo -e "\n${BLUE}====== Final Connectivity Test Result ======${NC}"
    if [ $overall_success -eq 1 ]; then
        echo -e "${GREEN}✅ SUCCESS: MMC VM is reachable via Mycelium network!${NC}"
        echo -e "${CYAN}   🌐 Mycelium IP: $MMC_IP${NC}"
        echo -e "${CYAN}   🔗 SSH Access: ssh -o StrictHostKeyChecking=no $MMC_USER@$MMC_IP${NC}"
        exit 0
    else
        echo -e "${RED}❌ FAILED: MMC VM is not reachable after $MAX_SCRIPT_RETRIES attempts${NC}"
        echo -e "${YELLOW}   💡 Possible issues:${NC}"
        echo -e "${YELLOW}      - VM is still initializing (wait a few minutes)${NC}"
        echo -e "${YELLOW}      - Mycelium network not properly configured${NC}"
        echo -e "${YELLOW}      - Firewall blocking SSH access${NC}"
        echo -e "${YELLOW}      - VM deployment failed${NC}"
        exit 1
    fi
}

# Run main function
main "$@"