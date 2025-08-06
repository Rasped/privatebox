#!/bin/bash
# Phase 4: Installation Verification
# Runs on Proxmox host to verify VM setup

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions and config
source "${SCRIPT_DIR}/../bootstrap/lib/common.sh"

# Load configuration
CONFIG_FILE="/tmp/privatebox-config.conf"
if [[ ! -f "$CONFIG_FILE" ]]; then
    error_exit "Configuration file not found at $CONFIG_FILE"
fi
source "$CONFIG_FILE"

# Set defaults
VMID="${VMID:-9000}"
TIMEOUT="${VERIFY_TIMEOUT:-900}"  # 15 minutes default
CHECK_INTERVAL=10

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

display() {
    echo "$1"
}

error_exit() {
    display "❌ ERROR: $1"
    log "ERROR: $1"
    exit 1
}

# Wait for VM to be accessible
wait_for_vm() {
    local elapsed=0
    local vm_ip=""
    
    log "Waiting for VM to be accessible..."
    
    while [[ $elapsed -lt $TIMEOUT ]]; do
        # Get VM IP
        vm_ip=$(qm guest cmd $VMID network-get-interfaces 2>/dev/null | \
                jq -r '.[] | select(.name=="enp0s18" or .name=="eth0") | .["ip-addresses"][] | select(.["ip-address-type"]=="ipv4") | .["ip-address"]' 2>/dev/null || true)
        
        if [[ -n "$vm_ip" ]]; then
            log "VM IP detected: $vm_ip"
            
            # Try SSH connection
            if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" "${VM_USERNAME}@${vm_ip}" "echo 'SSH connection successful'" &>/dev/null; then
                log "SSH connection established"
                echo "$vm_ip"
                return 0
            fi
        fi
        
        sleep $CHECK_INTERVAL
        elapsed=$((elapsed + CHECK_INTERVAL))
        
        # Show progress
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            display "   Still waiting... (${elapsed}s elapsed)"
        fi
    done
    
    return 1
}

# Check marker file
check_marker_file() {
    local vm_ip="$1"
    local elapsed=0
    
    log "Checking for installation marker file..."
    
    while [[ $elapsed -lt $TIMEOUT ]]; do
        local status=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" \
                      "${VM_USERNAME}@${vm_ip}" "cat /etc/privatebox-install-complete 2>/dev/null" || echo "PENDING")
        
        case "$status" in
            SUCCESS)
                log "Installation completed successfully"
                return 0
                ;;
            ERROR)
                log "Installation failed with error"
                return 1
                ;;
            PENDING|*)
                sleep $CHECK_INTERVAL
                elapsed=$((elapsed + CHECK_INTERVAL))
                
                if [[ $((elapsed % 30)) -eq 0 ]]; then
                    display "   Guest setup in progress... (${elapsed}s elapsed)"
                fi
                ;;
        esac
    done
    
    log "Timeout waiting for installation marker"
    return 1
}

# Check service health
check_services() {
    local vm_ip="$1"
    local all_healthy=true
    
    log "Checking service health..."
    
    # Check Portainer
    if curl -sf "http://${vm_ip}:9000" > /dev/null 2>&1; then
        display "  ✅ Portainer is accessible at http://${vm_ip}:9000"
        log "Portainer health check passed"
    else
        display "  ⚠️  Portainer is not accessible"
        log "Portainer health check failed"
        all_healthy=false
    fi
    
    # Check Semaphore
    if curl -sf "http://${vm_ip}:3000/api/ping" > /dev/null 2>&1; then
        display "  ✅ Semaphore is accessible at http://${vm_ip}:3000"
        log "Semaphore health check passed"
    else
        display "  ⚠️  Semaphore is not accessible"
        log "Semaphore health check failed"
        all_healthy=false
    fi
    
    # Check SSH
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" \
           "${VM_USERNAME}@${vm_ip}" "systemctl is-active portainer semaphore" &>/dev/null; then
        display "  ✅ Services are running"
        log "Service status check passed"
    else
        display "  ⚠️  Some services are not running"
        log "Service status check failed"
        all_healthy=false
    fi
    
    $all_healthy
}

# Main verification
main() {
    display "Starting installation verification..."
    log "Phase 4: Installation verification started"
    
    # Wait for VM to be accessible
    display "⏳ Waiting for VM to become accessible..."
    if ! VM_IP=$(wait_for_vm); then
        error_exit "VM did not become accessible within ${TIMEOUT} seconds"
    fi
    
    display "✅ VM is accessible at $VM_IP"
    
    # Check installation marker
    display "⏳ Waiting for guest configuration to complete..."
    if ! check_marker_file "$VM_IP"; then
        error_exit "Guest configuration did not complete successfully"
    fi
    
    display "✅ Guest configuration completed"
    
    # Check service health
    display ""
    display "Verifying services..."
    if ! check_services "$VM_IP"; then
        display "⚠️  Some services may not be fully operational"
        log "WARNING: Some services failed health checks"
    fi
    
    # Display summary
    display ""
    display "======================================"
    display "🎉 PrivateBox Installation Complete!"
    display "======================================"
    display ""
    display "Management VM Details:"
    display "  IP Address: $VM_IP"
    display "  Username: $VM_USERNAME"
    display "  SSH: ssh -i $SSH_KEY_PATH ${VM_USERNAME}@${VM_IP}"
    display ""
    display "Services:"
    display "  Portainer: http://${VM_IP}:9000"
    display "    Username: admin"
    display "    Password: ${SERVICES_PASSWORD}"
    display ""
    display "  Semaphore: http://${VM_IP}:3000"
    display "    Username: admin"
    display "    Password: ${SERVICES_PASSWORD}"
    display ""
    display "Configuration saved to: $CONFIG_FILE"
    display "======================================"
    
    log "Installation verification completed successfully"
}

# Run main function
main "$@"