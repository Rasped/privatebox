#!/bin/bash
# PrivateBox Bootstrap Deployment Script
# Deploy bootstrap files to a remote server and optionally run tests
#
# Usage: ./deploy-to-server.sh <server> [username] [options]
# Options:
#   --test          Run integration tests after deployment
#   --cleanup       Clean up deployed files after execution
#   --no-execute    Deploy files only, don't run bootstrap
#   --verbose       Enable verbose output
#   --help          Show this help message
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Missing dependencies
#   3 - SSH connection failed
#   4 - Deployment failed
#   5 - Remote execution failed

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="deploy-to-server"
REMOTE_DEPLOY_DIR="/tmp/privatebox-bootstrap"
DEFAULT_USERNAME="root"

# Set log directory for non-root users
export LOG_DIR="/tmp/privatebox-logs"
export LOG_FILE="/tmp/privatebox-logs/${SCRIPT_NAME}.log"
mkdir -p "${LOG_DIR}" 2>/dev/null || true

# Source common library
source "${SCRIPT_DIR}/lib/common.sh" || {
    echo "[ERROR] Cannot source common library from ${SCRIPT_DIR}/lib/common.sh" >&2
    exit 1
}

# Setup standardized error handling
setup_error_handling

# Define additional exit codes
EXIT_SSH_FAILED=3
EXIT_DEPLOY_FAILED=4
EXIT_REMOTE_EXEC_FAILED=5

# Check required commands
require_command "ssh" "SSH client is required"
require_command "scp" "SCP is required for file transfer"
require_command "tar" "tar is required for archive creation"

# Default values
RUN_TESTS=false
CLEANUP_AFTER=false
EXECUTE_BOOTSTRAP=true
VERBOSE=false

# Function to display usage
show_usage() {
    cat << EOF
PrivateBox Bootstrap Deployment Script

Usage: $0 <server> [username] [options]

Arguments:
  server          Target server IP or hostname (required)
  username        SSH username (default: root)

Options:
  --test          Run integration tests after deployment
  --cleanup       Clean up deployed files after execution
  --no-execute    Deploy files only, don't run bootstrap
  --verbose       Enable verbose output
  --help          Show this help message

Examples:
  # Basic deployment
  $0 192.168.1.10

  # Deploy with specific user
  $0 192.168.1.10 admin

  # Deploy and run tests
  $0 192.168.1.10 root --test

  # Deploy only (no execution)
  $0 192.168.1.10 root --no-execute

  # Deploy, run, and cleanup
  $0 192.168.1.10 root --cleanup

EOF
}

# Parse command line arguments
parse_arguments() {
    # Check for help first
    if [[ $# -eq 0 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        show_usage
        exit 0
    fi

    # Check for minimum arguments
    if [[ $# -lt 1 ]]; then
        show_usage
        exit ${EXIT_ERROR}
    fi

    # Parse server (required)
    SERVER="$1"
    shift

    # Parse username (optional, might be an option if starts with --)
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; then
        USERNAME="$1"
        shift
    else
        USERNAME="${DEFAULT_USERNAME}"
    fi

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --test)
                RUN_TESTS=true
                shift
                ;;
            --cleanup)
                CLEANUP_AFTER=true
                shift
                ;;
            --no-execute)
                EXECUTE_BOOTSTRAP=false
                shift
                ;;
            --verbose)
                VERBOSE=true
                LOG_LEVEL="DEBUG"
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit ${EXIT_ERROR}
                ;;
        esac
    done
}

# Validate SSH connectivity
validate_ssh_connection() {
    log_info "Validating SSH connection to ${USERNAME}@${SERVER}..."
    
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "${USERNAME}@${SERVER}" "echo 'SSH connection successful'" &>/dev/null; then
        log_error "Failed to connect to ${USERNAME}@${SERVER}"
        log_error "Please ensure:"
        log_error "  1. The server is reachable"
        log_error "  2. SSH service is running"
        log_error "  3. Your SSH key is authorized or password authentication is enabled"
        return 1
    fi
    
    log_info "SSH connection validated successfully"
    return ${EXIT_SUCCESS}
}

# Deploy files to remote server
deploy_files() {
    log_info "Deploying bootstrap files to ${SERVER}:${REMOTE_DEPLOY_DIR}..."
    
    # Clean up any existing directory and create new one
    ssh "${USERNAME}@${SERVER}" "rm -rf ${REMOTE_DEPLOY_DIR} && mkdir -p ${REMOTE_DEPLOY_DIR}" || {
        log_error "Failed to create remote directory"
        return ${EXIT_SSH_FAILED}
    }
    
    # Use rsync to copy files
    log_debug "Running rsync to copy files..."
    rsync -avz --exclude='.git' --exclude='*.log' --exclude='*.swp' \
        "${SCRIPT_DIR}/" "${USERNAME}@${SERVER}:${REMOTE_DEPLOY_DIR}/" || {
        log_error "Failed to deploy files via rsync"
        return ${EXIT_DEPLOY_FAILED}
    }
    log_info "Files deployed successfully"
    
    # Make scripts executable
    log_info "Making scripts executable on remote server..."
    if ssh "${USERNAME}@${SERVER}" "find ${REMOTE_DEPLOY_DIR} -name '*.sh' -type f -exec chmod +x {} \;"; then
        log_info "Scripts are now executable"
    else
        log_warn "Failed to make some scripts executable"
    fi
    
    return ${EXIT_SUCCESS}
}

# Execute bootstrap on remote server
execute_bootstrap() {
    log_info "Executing bootstrap.sh on remote server..."
    
    # Check if bootstrap.sh exists
    if ! ssh "${USERNAME}@${SERVER}" "test -f ${REMOTE_DEPLOY_DIR}/bootstrap.sh"; then
        log_error "bootstrap.sh not found in deployed files"
        return 1
    fi
    
    # Execute bootstrap
    log_info "Starting bootstrap process (this may take 5-10 minutes)..."
    # If already root, don't use sudo
    if [[ "${USERNAME}" == "root" ]]; then
        if ssh -t "${USERNAME}@${SERVER}" "cd ${REMOTE_DEPLOY_DIR} && ./bootstrap.sh"; then
            log_info "Bootstrap completed successfully"
            return 0
        else
            log_error "Bootstrap execution failed"
            return 1
        fi
    else
        if ssh -t "${USERNAME}@${SERVER}" "cd ${REMOTE_DEPLOY_DIR} && sudo ./bootstrap.sh"; then
            log_info "Bootstrap completed successfully"
            return 0
        else
            log_error "Bootstrap execution failed"
            return 1
        fi
    fi
}

# Run integration tests
run_integration_tests() {
    log_info "Running integration tests on remote server..."
    
    # Check if VM was created successfully
    log_info "Checking if VM was created..."
    local qm_cmd="qm status 9000"
    if [[ "${USERNAME}" != "root" ]]; then
        qm_cmd="sudo ${qm_cmd}"
    fi
    
    if ssh "${USERNAME}@${SERVER}" "${qm_cmd} &>/dev/null"; then
        log_info "VM 9000 is running"
    else
        log_error "VM 9000 not found or not running"
        return 1
    fi
    
    # Get VM IP from config
    local vm_ip
    vm_ip=$(ssh "${USERNAME}@${SERVER}" "grep STATIC_IP ${REMOTE_DEPLOY_DIR}/config/privatebox.conf 2>/dev/null | cut -d'=' -f2" | tr -d '"' | tr -d ' ')
    
    if [[ -z "${vm_ip}" ]]; then
        log_error "Could not determine VM IP address"
        return 1
    fi
    
    log_info "VM IP address: ${vm_ip}"
    
    # Test SSH connectivity to VM
    log_info "Testing SSH connectivity to VM..."
    if ssh "${USERNAME}@${SERVER}" "ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no admin@${vm_ip} 'echo VM is accessible' 2>/dev/null"; then
        log_info "VM SSH access confirmed"
    else
        log_warn "VM SSH not yet available (cloud-init may still be running)"
    fi
    
    # Check for cloud-init completion
    log_info "Checking cloud-init status..."
    if ssh "${USERNAME}@${SERVER}" "ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no admin@${vm_ip} 'test -f /etc/privatebox-cloud-init-complete' 2>/dev/null"; then
        log_info "Cloud-init completed successfully"
        
        # Check services
        log_info "Checking Portainer service..."
        if ssh "${USERNAME}@${SERVER}" "curl -s -f --connect-timeout 5 http://${vm_ip}:9000 >/dev/null 2>&1"; then
            log_info "✓ Portainer is accessible at http://${vm_ip}:9000"
        else
            log_warn "✗ Portainer is not yet accessible"
        fi
        
        log_info "Checking Semaphore service..."
        if ssh "${USERNAME}@${SERVER}" "curl -s -f --connect-timeout 5 http://${vm_ip}:3000/api/ping >/dev/null 2>&1"; then
            log_info "✓ Semaphore is accessible at http://${vm_ip}:3000"
        else
            log_warn "✗ Semaphore is not yet accessible"
        fi
    else
        log_warn "Cloud-init is still running. Services will be available once it completes."
        log_info "You can check the status with:"
        log_info "  ssh ${USERNAME}@${SERVER} \"ssh admin@${vm_ip} 'sudo cloud-init status'\""
    fi
    
    return ${EXIT_SUCCESS}
}

# Cleanup deployed files
cleanup_remote() {
    log_info "Cleaning up deployed files on remote server..."
    
    if ssh "${USERNAME}@${SERVER}" "rm -rf ${REMOTE_DEPLOY_DIR}"; then
        log_info "Remote files cleaned up successfully"
    else
        log_warn "Failed to clean up some remote files"
    fi
}

# Main execution
main() {
    log_info "PrivateBox Bootstrap Deployment Script"
    log_info "======================================"
    
    # Validate SSH connection
    validate_ssh_connection || check_result $? "SSH connection validation failed"
    
    # Deploy files
    deploy_files || check_result $? "File deployment failed"
    
    log_info "Files deployed to: ${REMOTE_DEPLOY_DIR}"
    
    # Execute bootstrap if requested
    if [[ "${EXECUTE_BOOTSTRAP}" == "true" ]]; then
        if ! execute_bootstrap; then
            # Don't exit immediately on bootstrap failure
            log_warn "Bootstrap execution encountered issues"
        fi
    else
        log_info "Skipping bootstrap execution (--no-execute specified)"
        log_info "To run bootstrap manually:"
        log_info "  ssh ${USERNAME}@${SERVER} 'cd ${REMOTE_DEPLOY_DIR} && sudo ./bootstrap.sh'"
    fi
    
    # Run tests if requested
    if [[ "${RUN_TESTS}" == "true" ]]; then
        log_info ""
        log_info "Running integration tests..."
        run_integration_tests
    fi
    
    # Cleanup if requested
    if [[ "${CLEANUP_AFTER}" == "true" ]]; then
        log_info ""
        cleanup_remote
    else
        log_info ""
        log_info "Deployed files remain at: ${REMOTE_DEPLOY_DIR}"
        log_info "To clean up manually:"
        log_info "  ssh ${USERNAME}@${SERVER} 'rm -rf ${REMOTE_DEPLOY_DIR}'"
    fi
    
    log_info ""
    log_info "Deployment completed!"
    
    # Show summary if bootstrap was executed
    if [[ "${EXECUTE_BOOTSTRAP}" == "true" ]]; then
        log_info ""
        log_info "Next steps:"
        log_info "1. Wait for cloud-init to complete (if still running)"
        log_info "2. Access services once ready:"
        log_info "   - Check VM status: ssh ${USERNAME}@${SERVER} 'sudo qm status 9000'"
        log_info "   - View config: ssh ${USERNAME}@${SERVER} 'cat ${REMOTE_DEPLOY_DIR}/config/privatebox.conf'"
    fi
}

# Parse arguments
parse_arguments "$@"

# Run main function
main
exit $?