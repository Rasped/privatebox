#!/bin/bash
# PrivateBox Bootstrap Script
# This is the single entry point for complete PrivateBox installation
# It handles everything from network discovery to service verification

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m' # No Color

# Simple logging functions (before sourcing common.sh)
log_msg() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "${level}" in
        ERROR)
            echo -e "${COLOR_RED}[${timestamp}] [${level}] ${message}${COLOR_NC}" >&2
            ;;
        WARN)
            echo -e "${COLOR_YELLOW}[${timestamp}] [${level}] ${message}${COLOR_NC}" >&2
            ;;
        INFO)
            echo -e "${COLOR_GREEN}[${timestamp}] [${level}] ${message}${COLOR_NC}"
            ;;
        *)
            echo "[${timestamp}] [${level}] ${message}"
            ;;
    esac
}

# Print banner
print_banner() {
    echo ""
    echo "==========================================="
    echo "     PrivateBox Bootstrap Installer"
    echo "==========================================="
    echo ""
}

# Check if running as root
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_msg ERROR "This script must be run as root"
        exit 1
    fi
}

# Make all scripts executable
make_scripts_executable() {
    log_msg INFO "Making scripts executable..."
    chmod +x "${SCRIPT_DIR}/scripts"/*.sh
    log_msg INFO "Scripts are now executable"
}

# Main installation function
main() {
    print_banner
    
    # Basic checks
    check_root
    
    # Make scripts executable
    make_scripts_executable
    
    # Check if we're on Proxmox
    if [[ ! -f /etc/pve/pve-root-ca.pem ]] && [[ ! -d /etc/pve ]]; then
        log_msg ERROR "This script must be run on a Proxmox VE host"
        exit 1
    fi
    
    log_msg INFO "Starting PrivateBox installation..."
    log_msg INFO "This process will:"
    log_msg INFO "  1. Detect network configuration"
    log_msg INFO "  2. Create Ubuntu VM"
    log_msg INFO "  3. Install and configure services"
    log_msg INFO "  4. Wait for complete installation (5-10 minutes)"
    echo ""
    
    # Set environment variable to wait for cloud-init
    export WAIT_FOR_CLOUD_INIT=true
    
    # Run the main creation script with auto-discovery
    log_msg INFO "Starting VM creation with network auto-discovery..."
    
    # Run create-ubuntu-vm.sh and capture the exit code
    "${SCRIPT_DIR}/scripts/create-ubuntu-vm.sh" --auto-discover
    local exit_code=$?
    
    echo ""
    echo "==========================================="
    
    # Load the generated config to show access info
    if [[ -f "${SCRIPT_DIR}/config/privatebox.conf" ]]; then
        source "${SCRIPT_DIR}/config/privatebox.conf"
        
        if [[ $exit_code -eq 0 ]]; then
            echo "     Installation Complete!"
            echo "==========================================="
            echo ""
            echo "VM Access Information:"
            echo "  VM IP Address: ${STATIC_IP}"
            echo "  SSH Access: ssh ${VM_USERNAME}@${STATIC_IP}"
            echo ""
            echo "VM Login Credentials:"
            echo "  Username: ${VM_USERNAME}"
            echo "  Password: ${VM_PASSWORD}"
            echo ""
            echo "Web Services (accessible after VM login):"
            echo "  Portainer: http://${STATIC_IP}:9000"
            echo "  Semaphore: http://${STATIC_IP}:3000"
            echo ""
            echo "Service Credentials:"
            echo "  Semaphore Admin: admin"
            echo "  Semaphore Password: (see /root/.credentials/semaphore_credentials.txt on VM)"
            echo ""
            echo "IMPORTANT: Please change the VM password after first login!"
            echo ""
            log_msg INFO "PrivateBox is ready for use!"
        else
            echo "     VM Created - Manual Verification Required"
            echo "==========================================="
            echo ""
            echo "The VM was created successfully but cloud-init is still running."
            echo "This is normal and may take 5-10 more minutes to complete."
            echo ""
            echo "VM Information:"
            echo "  VM IP Address: ${STATIC_IP}"
            echo "  SSH: ssh ${VM_USERNAME}@${STATIC_IP}"
            echo ""
            echo "To check if installation is complete:"
            echo "  ssh ${VM_USERNAME}@${STATIC_IP} 'cat /etc/privatebox-cloud-init-complete'"
            echo ""
            echo "Once complete, services will be available at:"
            echo "  Portainer: http://${STATIC_IP}:9000"
            echo "  Semaphore: http://${STATIC_IP}:3000"
            echo ""
            log_msg WARN "Please wait for cloud-init to complete before accessing services."
        fi
    else
        echo "     Installation Failed"
        echo "==========================================="
        log_msg ERROR "Installation failed. Please check the logs."
        return 1
    fi
    
    return 0
}

# Run main function
main "$@"