#!/bin/bash
# PrivateBox Bootstrap Script
# This is the single entry point for complete PrivateBox installation
# It handles everything from network discovery to service verification

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the bootstrap logger for early logging
source "${SCRIPT_DIR}/lib/bootstrap_logger.sh" 2>/dev/null || {
    # Fallback if bootstrap_logger.sh is not available
    log_msg() {
        local level="$1"
        shift
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    }
    log_info() { log_msg "INFO" "$@"; }
    log_error() { log_msg "ERROR" "$@" >&2; }
    log_warn() { log_msg "WARN" "$@" >&2; }
}

# Source constants for shared values
source "${SCRIPT_DIR}/lib/constants.sh" 2>/dev/null || true

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
        log_error "This script must be run as root"
        exit ${EXIT_NOT_ROOT:-4}
    fi
}

# Make all scripts executable
make_scripts_executable() {
    log_info "Making scripts executable..."
    chmod +x "${SCRIPT_DIR}/scripts"/*.sh
    log_info "Scripts are now executable"
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
        log_error "This script must be run on a Proxmox VE host"
        exit ${EXIT_NOT_PROXMOX:-5}
    fi
    
    log_info "Starting PrivateBox installation..."
    log_info "This process will:"
    log_info "  1. Detect network configuration"
    log_info "  2. Create Ubuntu VM"
    log_info "  3. Install and configure services"
    log_info "  4. Wait for complete installation (5-10 minutes)"
    echo ""
    
    # Set environment variable to wait for cloud-init
    export WAIT_FOR_CLOUD_INIT=true
    
    # Run the main creation script with auto-discovery
    log_info "Starting VM creation with network auto-discovery..."
    
    # Run create-ubuntu-vm.sh and capture the exit code
    "${SCRIPT_DIR}/scripts/create-ubuntu-vm.sh" --auto-discover
    local exit_code=$?
    
    echo ""
    echo "==========================================="
    
    # Load the generated config to show access info
    if [[ -f "${SCRIPT_DIR}/config/privatebox.conf" ]]; then
        source "${SCRIPT_DIR}/config/privatebox.conf"
        
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
            return 1
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
            echo "  Password: ${VM_PASSWORD}"
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
            log_warn "Please wait for cloud-init to complete before accessing services."
        fi
    else
        echo "     Installation Failed"
        echo "==========================================="
        log_error "Installation failed. Please check the logs."
        return 1
    fi
    
    return 0
}

# Run main function
main "$@"