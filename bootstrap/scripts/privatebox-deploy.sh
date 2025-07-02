#!/bin/bash
# PrivateBox Streamlined Deployment Script
# Single-command solution for complete VM creation and service deployment

# Source common library
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh" || {
    echo "ERROR: Cannot source common library" >&2
    exit 1
}

# Script configuration
SCRIPT_NAME="privatebox-deploy"
DEFAULT_TIMEOUT=1800  # 30 minutes
MONITOR_INTERVAL=10   # Check every 10 seconds
SSH_RETRY_DELAY=5     # Wait 5 seconds between SSH attempts
MAX_SSH_RETRIES=60    # Max SSH connection attempts (5 minutes)

# Parse command line arguments
VERBOSE=false
TIMEOUT=$DEFAULT_TIMEOUT
SKIP_HEALTH_CHECK=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose|-v)
            VERBOSE=true
            LOG_LEVEL="DEBUG"
            shift
            ;;
        --timeout|-t)
            TIMEOUT="$2"
            shift 2
            ;;
        --skip-health-check)
            SKIP_HEALTH_CHECK=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --verbose, -v        Enable verbose output"
            echo "  --timeout, -t SEC    Set timeout in seconds (default: $DEFAULT_TIMEOUT)"
            echo "  --skip-health-check  Skip final health check"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "This script performs a complete PrivateBox deployment:"
            echo "  1. Creates Ubuntu VM on Proxmox"
            echo "  2. Monitors cloud-init completion"
            echo "  3. Verifies all services are running"
            echo "  4. Displays access information"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Load configuration
CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/../config/privatebox.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    log_info "Loading configuration from: $CONFIG_FILE"
    # shellcheck source=../config/privatebox.conf
    source "$CONFIG_FILE"
else
    log_error "Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Set variables from config with defaults
VMID="${VMID:-9000}"
STATIC_IP="${STATIC_IP:-192.168.1.22}"
VM_USERNAME="${VM_USERNAME:-ubuntuadmin}"
VM_PASSWORD="${VM_PASSWORD:-Changeme123}"

# Function to fix cloud-init configuration
fix_cloud_init_config() {
    log_info "Fixing cloud-init configuration to enable post-install setup..."
    
    local user_data_file="/var/lib/vz/snippets/user-data-${VMID}.yaml"
    
    if [[ ! -f "$user_data_file" ]]; then
        log_error "Cloud-init user-data file not found: $user_data_file"
        return 1
    fi
    
    # Uncomment the post-install setup execution
    if sed -i 's|# - /usr/local/bin/post-install-setup.sh|- /usr/local/bin/post-install-setup.sh|' "$user_data_file"; then
        log_info "Cloud-init configuration fixed successfully"
        return 0
    else
        log_error "Failed to fix cloud-init configuration"
        return 1
    fi
}

# Function to run VM creation
create_vm() {
    log_info "Starting VM creation process..."
    
    local create_script="$(dirname "${BASH_SOURCE[0]}")/create-ubuntu-vm.sh"
    
    if [[ ! -x "$create_script" ]]; then
        log_error "VM creation script not found or not executable: $create_script"
        return 1
    fi
    
    # Run the creation script
    if "$create_script"; then
        log_info "VM creation completed successfully"
        return 0
    else
        log_error "VM creation failed"
        return 1
    fi
}

# Function to wait for VM to be accessible via SSH
wait_for_ssh() {
    log_info "Waiting for VM to be accessible via SSH..."
    
    local retries=0
    while [ $retries -lt $MAX_SSH_RETRIES ]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           "${VM_USERNAME}@${STATIC_IP}" "echo 'SSH connection successful'" &>/dev/null; then
            log_info "SSH connection established"
            return 0
        fi
        
        ((retries++))
        if [[ $((retries % 6)) -eq 0 ]]; then
            log_info "Still waiting for SSH... (attempt $retries/$MAX_SSH_RETRIES)"
        fi
        sleep $SSH_RETRY_DELAY
    done
    
    log_error "Failed to establish SSH connection after $MAX_SSH_RETRIES attempts"
    return 1
}

# Function to check cloud-init status
check_cloud_init_status() {
    local status
    status=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "${VM_USERNAME}@${STATIC_IP}" "sudo cloud-init status 2>/dev/null" 2>/dev/null || echo "error")
    
    echo "$status"
}

# Function to monitor cloud-init progress
monitor_cloud_init() {
    log_info "Monitoring cloud-init progress..."
    
    local start_time=$(date +%s)
    local timeout_time=$((start_time + TIMEOUT))
    local last_status=""
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        # Check timeout
        if [ $current_time -gt $timeout_time ]; then
            log_error "Cloud-init monitoring timed out after $TIMEOUT seconds"
            return 1
        fi
        
        # Get cloud-init status
        local status=$(check_cloud_init_status)
        
        # Log status changes
        if [[ "$status" != "$last_status" ]]; then
            log_info "Cloud-init status: $status (elapsed: ${elapsed}s)"
            last_status="$status"
        fi
        
        # Check if cloud-init is done
        if [[ "$status" == *"done"* ]]; then
            log_info "Cloud-init completed successfully"
            return 0
        elif [[ "$status" == *"error"* ]] && [[ "$status" != "error" ]]; then
            log_error "Cloud-init reported an error: $status"
            return 1
        fi
        
        # Check if boot-finished flag exists (alternative method)
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           "${VM_USERNAME}@${STATIC_IP}" "sudo test -f /var/lib/cloud/instance/boot-finished" &>/dev/null; then
            log_info "Cloud-init boot-finished flag detected"
            
            # Give it a few more seconds for services to stabilize
            log_info "Waiting for services to stabilize..."
            sleep 10
            return 0
        fi
        
        # Verbose logging of cloud-init logs
        if [[ "$VERBOSE" == "true" ]] && [[ $((elapsed % 30)) -eq 0 ]]; then
            log_debug "Checking cloud-init logs..."
            ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                "${VM_USERNAME}@${STATIC_IP}" "sudo tail -n 5 /var/log/cloud-init-output.log" 2>/dev/null || true
        fi
        
        sleep $MONITOR_INTERVAL
    done
}

# Function to verify services are running
verify_services() {
    log_info "Verifying services are running..."
    
    # Use SSH to run health check on the VM
    if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
       "${VM_USERNAME}@${STATIC_IP}" "sudo /usr/local/bin/health-check.sh quick" &>/dev/null; then
        log_info "Services verification passed"
        return 0
    else
        # If health-check.sh doesn't exist, do manual checks
        log_info "Running manual service verification..."
        
        local all_good=true
        
        # Check Portainer
        if curl -s -f --connect-timeout 5 "http://${STATIC_IP}:9000" &>/dev/null; then
            log_info "✓ Portainer is accessible"
        else
            log_error "✗ Portainer is not accessible"
            all_good=false
        fi
        
        # Check Semaphore API
        if curl -s -f --connect-timeout 5 "http://${STATIC_IP}:3000/api/ping" &>/dev/null; then
            log_info "✓ Semaphore API is responding"
        else
            log_error "✗ Semaphore API is not responding"
            all_good=false
        fi
        
        if [[ "$all_good" == "true" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

# Function to display deployment summary
display_summary() {
    log_info "================================================================"
    log_info "🚀 PrivateBox Deployment Completed Successfully!"
    log_info "================================================================"
    log_info "VM Information:"
    log_info "  VM ID: ${VMID}"
    log_info "  IP Address: ${STATIC_IP}"
    log_info "  Username: ${VM_USERNAME}"
    log_info "  Password: ${VM_PASSWORD}"
    log_info ""
    log_info "Service URLs:"
    log_info "  Portainer: http://${STATIC_IP}:9000"
    log_info "  Semaphore: http://${STATIC_IP}:3000"
    log_info ""
    log_info "SSH Access:"
    log_info "  ssh ${VM_USERNAME}@${STATIC_IP}"
    log_info ""
    log_info "Credentials Location (on VM):"
    log_info "  /root/.credentials/semaphore_credentials.txt"
    log_info ""
    log_info "Next Steps:"
    log_info "  1. Access Portainer to manage containers"
    log_info "  2. Access Semaphore to set up Ansible automation"
    log_info "  3. Change default passwords for security"
    log_info "================================================================"
}

# Function to handle deployment failure
handle_failure() {
    log_error "================================================================"
    log_error "❌ PrivateBox Deployment Failed!"
    log_error "================================================================"
    log_error "Troubleshooting Steps:"
    log_error "  1. Check VM console: qm terminal ${VMID}"
    log_error "  2. Check cloud-init logs on VM:"
    log_error "     ssh ${VM_USERNAME}@${STATIC_IP} 'sudo cat /var/log/cloud-init-output.log'"
    log_error "  3. Check service logs on VM:"
    log_error "     ssh ${VM_USERNAME}@${STATIC_IP} 'sudo journalctl -u portainer.service'"
    log_error "     ssh ${VM_USERNAME}@${STATIC_IP} 'sudo journalctl -u semaphore.service'"
    log_error "  4. Run health check manually:"
    log_error "     ssh ${VM_USERNAME}@${STATIC_IP} 'sudo /usr/local/bin/health-check.sh'"
    log_error "================================================================"
}

# Main deployment function
main() {
    local start_time=$(date +%s)
    
    log_info "========================================="
    log_info "Starting PrivateBox Streamlined Deployment"
    log_info "========================================="
    log_info "Configuration:"
    log_info "  VM ID: ${VMID}"
    log_info "  IP Address: ${STATIC_IP}"
    log_info "  Timeout: ${TIMEOUT}s"
    log_info "  Verbose: ${VERBOSE}"
    log_info "-----------------------------------------"
    
    # Step 1: Create VM
    if ! create_vm; then
        handle_failure
        return 1
    fi
    
    # Step 2: Fix cloud-init configuration
    if ! fix_cloud_init_config; then
        handle_failure
        return 1
    fi
    
    # Step 3: Wait for SSH access
    if ! wait_for_ssh; then
        handle_failure
        return 1
    fi
    
    # Step 4: Monitor cloud-init completion
    if ! monitor_cloud_init; then
        handle_failure
        return 1
    fi
    
    # Step 5: Verify services (unless skipped)
    if [[ "$SKIP_HEALTH_CHECK" != "true" ]]; then
        log_info "Waiting for services to fully initialize..."
        sleep 20  # Give services time to start
        
        if ! verify_services; then
            log_warn "Initial service verification failed, retrying in 30 seconds..."
            sleep 30
            if ! verify_services; then
                handle_failure
                return 1
            fi
        fi
    fi
    
    # Calculate total time
    local end_time=$(date +%s)
    local total_time=$((end_time - start_time))
    local minutes=$((total_time / 60))
    local seconds=$((total_time % 60))
    
    # Display success summary
    display_summary
    log_info ""
    log_info "Total deployment time: ${minutes}m ${seconds}s"
    
    return 0
}

# Check root permissions
check_root

# Run main deployment
if main; then
    exit 0
else
    exit 1
fi