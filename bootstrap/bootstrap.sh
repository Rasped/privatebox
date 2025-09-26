#!/bin/bash
#
# PrivateBox Bootstrap - Main Orchestrator
# Simple, robust, phased installation process
#

set -euo pipefail

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
LOG_FILE="/tmp/privatebox-bootstrap.log"
CONFIG_FILE="/tmp/privatebox-config.conf"

# Default values
DRY_RUN=false
VERBOSE=false
VMID=9000

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --setup-proxmox-api)
            # Run Proxmox API setup
            if [[ ! -f "${SCRIPT_DIR}/scripts/setup-proxmox-api-token.sh" ]]; then
                echo "ERROR: Proxmox API setup script not found"
                exit 1
            fi
            exec "${SCRIPT_DIR}/scripts/setup-proxmox-api-token.sh"
            ;;
        --help|-h)
            cat <<EOF
PrivateBox Bootstrap

Usage: $0 [OPTIONS]

Options:
    --dry-run       Run pre-flight checks and generate config only (no VM creation)
    --verbose, -v   Show detailed output
    --help, -h      Show this help message
    --setup-proxmox-api  Setup Proxmox API token (run on Proxmox host)

The bootstrap process has 4 phases:
1. Host preparation - Pre-flight checks and config generation
2. VM provisioning - Create and configure VM with cloud-init
3. Guest setup - Install services inside VM
4. Verification - Confirm successful installation

Optional: Setup Proxmox API token for automation (use --setup-proxmox-api)

Logs are written to: $LOG_FILE
Configuration saved to: $CONFIG_FILE
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Initialize logging
init_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] PrivateBox Bootstrap starting" > "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Arguments: dry-run=$DRY_RUN, verbose=$VERBOSE" >> "$LOG_FILE"
}

# Log function
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    if [[ "$VERBOSE" == true ]]; then
        echo "$message"
    fi
}

# Display important messages (always shown)
display() {
    local message="$1"
    echo "$message"
    log "$message"
}

# Error handler
error_exit() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message" >> "$LOG_FILE"
    echo "ERROR: $message" >&2
    echo "Check log file for details: $LOG_FILE"
    exit 1
}

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log "Bootstrap failed with exit code: $exit_code"
        display "❌ Bootstrap failed. Check $LOG_FILE for details"
    fi
}

trap cleanup EXIT

# Main execution
main() {
    init_log
    
    display "======================================"
    display "   PrivateBox Bootstrap"
    display "======================================"
    display ""
    
    # Phase 1: Host Preparation
    display "Phase 1: Host Preparation"
    display "-------------------------"
    log "Starting Phase 1: Host preparation"
    
    if [[ ! -f "${SCRIPT_DIR}/prepare-host.sh" ]]; then
        error_exit "prepare-host.sh not found"
    fi
    
    if ! bash "${SCRIPT_DIR}/prepare-host.sh"; then
        error_exit "Host preparation failed"
    fi
    
    # Load generated config
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file not generated: $CONFIG_FILE"
    fi
    
    source "$CONFIG_FILE"
    log "Configuration loaded successfully"
    
    display "✅ Host preparation complete"
    display ""
    
    # Check for dry-run mode
    if [[ "$DRY_RUN" == true ]]; then
        display "======================================"
        display "   Dry-run Complete"
        display "======================================"
        display ""
        display "Configuration generated at: $CONFIG_FILE"
        display "Network settings:"
        display "  Gateway: ${GATEWAY:-not set}"
        display "  Bridge: ${VM_NET_BRIDGE:-not set}"
        display "  VM IP: ${STATIC_IP:-not set}"
        display ""
        display "Credentials generated:"
        display "  Admin password: ${ADMIN_PASSWORD:-not set}"
        display "  Services password: ${SERVICES_PASSWORD:-not set}"
        display ""
        display "Run without --dry-run to create VM"
        log "Dry-run completed successfully"
        exit 0
    fi
    
    # Phase 2: OPNsense Deployment
    display "Phase 2: OPNsense Deployment"
    display "-----------------------------"
    log "Starting Phase 2: OPNsense deployment"
    
    if [[ ! -f "${SCRIPT_DIR}/deploy-opnsense.sh" ]]; then
        display "⚠️  OPNsense deployment script not found"
        display "   Skipping firewall deployment"
        display "   Note: Management VM will need a gateway configured"
        log "WARNING: deploy-opnsense.sh not found, skipping"
    else
        if ! bash "${SCRIPT_DIR}/deploy-opnsense.sh"; then
            error_exit "OPNsense deployment failed - cannot continue without firewall"
        else
            display "✅ OPNsense firewall deployed"
            log "OPNsense deployed successfully"
        fi
    fi
    display ""
    
    # Phase 3: Management VM Provisioning
    display "Phase 3: Management VM Provisioning"
    display "------------------------------------"
    log "Starting Phase 3: Management VM provisioning"
    
    if [[ ! -f "${SCRIPT_DIR}/create-vm.sh" ]]; then
        error_exit "create-vm.sh not found"
    fi
    
    if ! bash "${SCRIPT_DIR}/create-vm.sh"; then
        error_exit "VM creation failed"
    fi
    
    display "✅ VM provisioning complete"
    display ""
    
    # Note: Phase 4 runs inside the VM via cloud-init
    display "Phase 4: Service Configuration"
    display "-------------------------------"
    display "⏳ Waiting for guest setup to complete..."
    display "   This may take 5-10 minutes"
    log "Phase 4: Service configuration started via cloud-init"
    
    # Phase 5: Installation Verification
    display ""
    display "Phase 5: Installation Verification"
    display "----------------------------------"
    log "Starting Phase 5: Installation verification"
    
    if [[ ! -f "${SCRIPT_DIR}/verify-install.sh" ]]; then
        error_exit "verify-install.sh not found"
    fi
    
    if ! bash "${SCRIPT_DIR}/verify-install.sh"; then
        error_exit "Installation verification failed"
    fi
    
    display "✅ Installation verified successfully"
    display ""
    
    # Final summary
    display "======================================"
    display "   Installation Complete!"
    display "======================================"
    display ""
    display "VM Details:"
    display "  VM ID: $VMID"
    display "  IP Address: $STATIC_IP"
    display "  Username: ${VM_USERNAME:-debian}"
    display ""
    display "Access Credentials:"
    display "  SSH: ssh ${VM_USERNAME:-debian}@$STATIC_IP"
    display "  Password: $ADMIN_PASSWORD"
    display ""
    display "Service Access:"
    display "  Portainer: http://$STATIC_IP:9000"
    display "  Semaphore: http://$STATIC_IP:3000"
    display "  Admin Password: $SERVICES_PASSWORD"
    display ""
    display "Logs saved to: $LOG_FILE"
    display "Configuration saved to: $CONFIG_FILE"
    
    log "Bootstrap completed successfully"
    
    # Clean up config file (contains passwords)
    if [[ -f "$CONFIG_FILE" ]]; then
        log "Removing temporary config file"
        rm -f "$CONFIG_FILE"
    fi
}

# Run main function
main "$@"