#!/bin/bash
# Installation Verification
# Runs on Proxmox host to verify VM setup

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Log file location
LOG_FILE="${LOG_FILE:-/tmp/privatebox-bootstrap.log}"

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
SSH_KEY_PATH="${SSH_KEY_PATH:-/root/.ssh/id_ed25519}"  # Default to root's Ed25519 key

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
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
    local vm_ip="${STATIC_IP}"  # Use hardcoded IP from config
    
    log "Waiting for VM to be accessible at $vm_ip..."
    
    while [[ $elapsed -lt $TIMEOUT ]]; do
        # Try SSH connection directly to known IP
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_PATH" "${VM_USERNAME}@${vm_ip}" "echo 'SSH connection successful'" &>/dev/null; then
            log "SSH connection established to $vm_ip"
            echo "$vm_ip"  # Return only the IP, not log messages
            return 0
        fi
        
        sleep $CHECK_INTERVAL
        elapsed=$((elapsed + CHECK_INTERVAL))
        
        # Show progress
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            echo "   Still waiting... (${elapsed}s elapsed)" >&2
        fi
    done
    
    log "Timeout waiting for VM at $vm_ip"
    return 1
}

# Check marker file
check_marker_file() {
    local vm_ip="$1"
    local elapsed=0
    local last_line_count=0

    log "Checking for installation completion..."

    # Check if Phase 4 already showed progress
    local show_progress=true
    if [[ "${PHASE4_PROGRESS_SHOWN:-false}" == "true" ]]; then
        show_progress=false
        log "Phase 4 already displayed progress, skipping duplicate display"
    else
        log "Phase 4 did not show progress, will display it now"
    fi

    # Use appropriate timeout based on whether we're showing progress
    local timeout=900  # 15 minutes if showing progress
    if [[ "$show_progress" == false ]]; then
        timeout=60  # 1 minute if just verifying
    fi

    while [[ $elapsed -lt $timeout ]]; do
        # Get the marker file content
        local file_content=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_PATH" \
                      "${VM_USERNAME}@${vm_ip}" "cat /etc/privatebox-install-complete 2>/dev/null" || echo "PENDING")

        # Get the last line for status check
        local status=$(echo "$file_content" | tail -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Show progress only if Phase 4 didn't
        if [[ "$show_progress" == true ]] && [[ -n "$file_content" ]] && [[ "$file_content" != "PENDING" ]]; then
            local current_line_count=$(echo "$file_content" | wc -l)

            # Display new progress messages since last check
            if [[ $current_line_count -gt $last_line_count ]]; then
                local new_lines=$(echo "$file_content" | tail -n $((current_line_count - last_line_count)))
                while IFS= read -r line; do
                    if [[ "$line" == PROGRESS:* ]]; then
                        local progress_msg="${line#PROGRESS:}"
                        display "   ✓ ${progress_msg}"
                        log "Progress: $progress_msg"
                    fi
                done <<< "$new_lines"
                last_line_count=$current_line_count
            fi
        fi

        case "$status" in
            SUCCESS)
                log "Installation completed successfully"
                return 0
                ;;
            ERROR)
                log "Installation failed with error"
                return 1
                ;;
            PENDING|PROGRESS:*)
                sleep 10
                elapsed=$((elapsed + 10))

                if [[ $((elapsed % 30)) -eq 0 ]] && [[ "$status" == "PENDING" ]]; then
                    if [[ "$show_progress" == true ]]; then
                        display "   Guest setup in progress... (${elapsed}s elapsed)"
                    fi
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
    if curl -sfk "https://${vm_ip}:1443/api/status" > /dev/null 2>&1; then
        display "  ✅ Portainer is accessible at https://${vm_ip}:1443"
        log "Portainer health check passed"
    else
        display "  ⚠️  Portainer is not accessible"
        log "Portainer health check failed"
        all_healthy=false
    fi
    
    # Check Semaphore
    if curl -sfk "https://${vm_ip}:2443/api/ping" > /dev/null 2>&1; then
        display "  ✅ Semaphore is accessible at https://${vm_ip}:2443"
        log "Semaphore health check passed"
    else
        display "  ⚠️  Semaphore is not accessible"
        log "Semaphore health check failed"
        all_healthy=false
    fi
    
    # Check SSH
    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY_PATH" \
           "${VM_USERNAME}@${vm_ip}" "systemctl is-active portainer semaphore" &>/dev/null; then
        display "  ✅ Services are running"
        log "Service status check passed"
    else
        display "  ⚠️  Some services are not running"
        log "Service status check failed"
        all_healthy=false
    fi
    
    # Check Semaphore API configuration
    log "Checking Semaphore API configuration..."
    
    # Try to get Semaphore project via API
    local api_check=$(curl -sk -c - -X POST -H "Content-Type: application/json" \
        -d "{\"auth\": \"admin\", \"password\": \"${SERVICES_PASSWORD}\"}" \
        "https://${vm_ip}:2443/api/auth/login" 2>/dev/null | grep 'semaphore')
    
    if [[ -n "$api_check" ]]; then
        display "  ✅ Semaphore API authentication working"
        
        # Check if PrivateBox project exists
        local cookie=$(echo "$api_check" | tail -1 | awk -F'\t' '{print $7}')
        local projects=$(curl -sk -H "Cookie: semaphore=$cookie" \
            "https://${vm_ip}:2443/api/projects" 2>/dev/null)
        
        if echo "$projects" | grep -q "PrivateBox"; then
            display "  ✅ PrivateBox project configured"
            log "Semaphore API configuration verified"
        else
            display "  ⚠️  PrivateBox project not found in Semaphore"
            log "WARNING: Semaphore API configuration may be incomplete"
            all_healthy=false
        fi
    else
        display "  ⚠️  Semaphore API authentication failed"
        log "WARNING: Could not verify Semaphore API configuration"
        all_healthy=false
    fi
    
    $all_healthy
}

# Main verification
main() {
    display "Starting installation verification..."
    log "Installation verification started"
    
    # Wait for VM to be accessible
    display "⏳ Waiting for VM to become accessible..."
    if ! VM_IP=$(wait_for_vm); then
        error_exit "VM did not become accessible within ${TIMEOUT} seconds"
    fi
    
    display "✅ VM is accessible at $VM_IP"
    
    # Verify installation completed
    if [[ "${PHASE4_PROGRESS_SHOWN:-false}" == "true" ]]; then
        display "Verifying installation status..."
    else
        display "⏳ Waiting for guest configuration to complete..."
    fi

    if ! check_marker_file "$VM_IP"; then
        error_exit "Guest configuration did not complete successfully"
    fi

    if [[ "${PHASE4_PROGRESS_SHOWN:-false}" == "true" ]]; then
        display "✅ Installation verified"
    else
        display "✅ Guest configuration completed"
    fi
    
    # Check service health
    display ""
    display "Verifying services..."
    if ! check_services "$VM_IP"; then
        display "⚠️  Some services may not be fully operational"
        log "WARNING: Some services failed health checks"
    fi

    log "Installation verification completed successfully"
}

# Run main function
main "$@"