#!/bin/bash
# PrivateBox Bootstrap Script
# This is the single entry point for complete PrivateBox installation
# It handles everything from network discovery to service verification
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Missing dependencies
#   4 - Not running as root
#   5 - Not running on Proxmox

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library which provides all functions and constants
source "${SCRIPT_DIR}/lib/common.sh"

# Setup standardized error handling
setup_error_handling

# Print banner
print_banner() {
    echo ""
    echo "==========================================="
    echo "     PrivateBox Bootstrap Installer"
    echo "==========================================="
    echo ""
}

# Use check_root from common.sh

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --help, -h  Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}


# Main installation function
main() {
    # Parse command line arguments first
    parse_args "$@"
    
    print_banner
    
    # Basic checks
    check_root
    
    # Check if we're on Proxmox
    if [[ ! -f /etc/pve/pve-root-ca.pem ]] && [[ ! -d /etc/pve ]]; then
        log_error "This script must be run on a Proxmox VE host"
        exit ${EXIT_NOT_PROXMOX}
    fi
    
    log_info "Starting PrivateBox installation..."
    
    # Set environment variable to wait for cloud-init
    export WAIT_FOR_CLOUD_INIT=true
    
    # Run the main creation script with auto-discovery
    log_info "Starting Debian VM creation with network auto-discovery..."
    
    "${SCRIPT_DIR}/scripts/create-debian-vm.sh" --auto-discover
    local exit_code=$?
    
    echo ""
    echo "==========================================="
    
    # Load the generated config to show access info
    if [[ -f "${SCRIPT_DIR}/config/privatebox.conf" ]]; then
        source "${SCRIPT_DIR}/config/privatebox.conf" || check_result $? "Failed to load configuration file"
        
        # Check for installation errors first
        if [[ -n "${INSTALLATION_ERROR_STAGE:-}" ]]; then
            echo "     Installation Failed"
            echo "==========================================="
            echo ""
            echo -e "${RED:-\033[0;31m}ERROR: Cloud-init installation failed!${NC:-\033[0m}"
            echo ""
            echo "Error Details:"
            echo "  Stage: ${INSTALLATION_ERROR_STAGE}"
            echo "  Message: ${INSTALLATION_ERROR_MESSAGE:-No error message}"
            echo "  Exit Code: ${INSTALLATION_ERROR_CODE:-1}"
            echo ""
            echo "VM Information:"
            echo "  VM IP Address: ${STATIC_IP}"
            echo "  SSH: ssh ${VM_USERNAME}@${STATIC_IP}"
            echo ""
            echo "To investigate the error:"
            echo "  1. SSH into the VM: ssh ${VM_USERNAME}@${STATIC_IP}"
            echo "  2. Check cloud-init logs: sudo cat /var/log/cloud-init-output.log"
            echo "  3. Check status file: cat /etc/privatebox-cloud-init-complete"
            echo ""
            log_error "Installation failed at stage: ${INSTALLATION_ERROR_STAGE}"
            return ${EXIT_ERROR}
        elif [[ $exit_code -eq 0 ]]; then
            echo "     Installation Complete!"
            echo "==========================================="
            echo ""
            echo "VM Access Information:"
            echo "  VM IP Address: ${STATIC_IP}"
            echo "  SSH Access: ssh ${VM_USERNAME}@${STATIC_IP}"
            echo ""
            echo "VM Login Credentials:"
            echo "  Username: ${VM_USERNAME}"
            echo "  Password: ${ADMIN_PASSWORD:-${VM_PASSWORD:-Changeme123}}"
            echo ""
            echo "Web Services (accessible after VM login):"
            echo "  Portainer: http://${STATIC_IP}:9000"
            echo "  Semaphore: http://${STATIC_IP}:3000"
            echo ""
            echo "Semaphore Credentials:"
            echo "  Semaphore Admin: admin"
            
            # Try to get Semaphore password from config
            if [[ -n "${SEMAPHORE_ADMIN_PASSWORD:-}" ]]; then
                echo "  Semaphore Password: ${SEMAPHORE_ADMIN_PASSWORD}"
            else
                echo "  Semaphore Password: (see /root/.credentials/semaphore_credentials.txt on VM)"
            fi
            echo ""
            echo "IMPORTANT: Please change the VM password after first login!"
            echo ""
            log_info "PrivateBox is ready for use!"
        else
            echo "     VM Created - Waiting for Installation"
            echo "==========================================="
            echo ""
            echo "The VM was created successfully!"
            echo "Cloud-init is still running and will complete in 5-10 minutes."
            echo ""
            echo "VM Access Information:"
            echo "  VM IP Address: ${STATIC_IP}"
            echo "  SSH Access: ssh ${VM_USERNAME}@${STATIC_IP}"
            echo ""
            echo "VM Login Credentials:"
            echo "  Username: ${VM_USERNAME}"
            echo "  Password: ${ADMIN_PASSWORD:-${VM_PASSWORD:-Changeme123}}"
            echo ""
            echo "Web Services (will be available once installation completes):"
            echo "  Portainer: http://${STATIC_IP}:9000"
            echo "  Semaphore: http://${STATIC_IP}:3000"
            echo ""
            echo "Semaphore Credentials:"
            echo "  Semaphore Admin: admin"
            
            # Try to get Semaphore password from config
            if [[ -n "${SEMAPHORE_ADMIN_PASSWORD:-}" ]]; then
                echo "  Semaphore Password: ${SEMAPHORE_ADMIN_PASSWORD}"
            else
                echo "  Semaphore Password: (will be available at /root/.credentials/semaphore_credentials.txt on VM)"
            fi
            echo ""
            echo "To check if installation is complete:"
            echo "  ssh ${VM_USERNAME}@${STATIC_IP} 'cat /etc/privatebox-cloud-init-complete'"
            echo ""
            echo "IMPORTANT: Please change the VM password after first login!"
            echo ""
            log_info "VM created successfully. Waiting for cloud-init to complete..."
        fi
    else
        echo "     Installation Failed"
        echo "==========================================="
        log_error "Installation failed. Please check the logs."
        return ${EXIT_ERROR}
    fi
    
    return ${EXIT_SUCCESS}
}

# Run main function
main "$@"
exit $?