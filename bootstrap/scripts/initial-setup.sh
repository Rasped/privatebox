#!/bin/bash
# VM post-installation setup script
# This script runs after cloud-init completes
#
# IMPORTANT: DO NOT USE ERR TRAPS IN THIS SCRIPT!
# Cloud-init has issues with ERR traps and 'set -e' which can cause:
# - Premature script termination
# - False failure reports even when the script succeeds
# - Difficult to debug errors
# Instead, use explicit error checking with error_exit() function
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Missing dependencies

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define cloud-init status file
export CLOUD_INIT_STATUS_FILE="/tmp/privatebox-install-status"

# Define detailed log file for debugging
SETUP_LOG="/var/log/privatebox-setup.log"
SETUP_DEBUG_LOG="/var/log/privatebox-setup-debug.log"

# Initialize log files
mkdir -p /var/log
echo "=== PrivateBox Initial Setup Log ===" > "$SETUP_LOG"
echo "Started at: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$SETUP_LOG"
echo "Script: $0" >> "$SETUP_LOG"
echo "User: $(whoami)" >> "$SETUP_LOG"
echo "PWD: $(pwd)" >> "$SETUP_LOG"
echo "=================================" >> "$SETUP_LOG"

# Enable debug logging
exec 2> >(tee -a "$SETUP_DEBUG_LOG")

# Source common library if available (fallback to basic logging)
if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
    # shellcheck source=../lib/common.sh
    source "${SCRIPT_DIR}/../lib/common.sh"
    # WARNING: Do NOT use setup_cloud_init_error_handling() here!
    # That function sets 'set -euo pipefail' and ERR traps which cause
    # cloud-init to fail even when the script succeeds.
    # Just use the simple logging functions from common.sh
    
    # Override log functions to also write to our setup logs
    original_log_info=$(declare -f log_info)
    log_info() {
        bootstrap_log INFO "$*"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" >> "$SETUP_LOG"
    }
    
    original_log_error=$(declare -f log_error)
    log_error() {
        bootstrap_log ERROR "$*"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$SETUP_LOG"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$SETUP_DEBUG_LOG"
    }
    
    log_info "Using common library functions (without error traps)"
else
    # Fallback for embedded environment
    # Define minimal error handling functions
    log() {
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] $1" | tee -a "$SETUP_LOG"
    }
    log_info() { log "INFO: $*"; }
    log_warn() { log "WARN: $*"; }
    log_error() { 
        log "ERROR: $*" >&2
        echo "[$timestamp] ERROR: $*" >> "$SETUP_DEBUG_LOG"
    }
    log_success() { log "SUCCESS: $*"; }
    log_debug() { 
        log "DEBUG: $*"
        echo "[$timestamp] DEBUG: $*" >> "$SETUP_DEBUG_LOG"
    }
    
    # Error exit with status file update
    error_exit() { 
        local error_msg="$1"
        local exit_code="${2:-1}"
        log_error "$error_msg"
        
        # Write detailed error report
        cat >> "$SETUP_LOG" <<EOF

=== ERROR Report ===
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Error: $error_msg
Exit Code: $exit_code
Script Line: ${BASH_LINENO[0]}
Function: ${FUNCNAME[1]:-main}
===================
EOF
        
        # Write error to status file for Proxmox to see
        if [[ -w /etc/privatebox-cloud-init-complete ]]; then
            echo "INITIAL_SETUP_ERROR=$error_msg" >> /etc/privatebox-cloud-init-complete
            echo "INITIAL_SETUP_EXIT_CODE=$exit_code" >> /etc/privatebox-cloud-init-complete
            echo "INITIAL_SETUP_ERROR_LINE=${BASH_LINENO[0]}" >> /etc/privatebox-cloud-init-complete
            echo "INITIAL_SETUP_ERROR_FUNC=${FUNCNAME[1]:-main}" >> /etc/privatebox-cloud-init-complete
        fi
        # Also write to cloud-init status file
        if [[ -n "${CLOUD_INIT_STATUS_FILE}" ]]; then
            cat > "${CLOUD_INIT_STATUS_FILE}" <<EOF
ERROR
$1
Exit code: ${2:-1}
Time: $(date +"%Y-%m-%d %H:%M:%S")
EOF
        fi
        exit "${2:-1}"
    }
    
    # Error handler for the script
    handle_error() {
        local exit_code=$?
        local line_number=$1
        local error_msg="Script failed at line $line_number with exit code $exit_code"
        log_error "$error_msg"
        
        # Update status files
        if [[ -w /etc/privatebox-cloud-init-complete ]]; then
            echo "INITIAL_SETUP_ERROR=$error_msg" >> /etc/privatebox-cloud-init-complete
            echo "INITIAL_SETUP_EXIT_CODE=$exit_code" >> /etc/privatebox-cloud-init-complete
        fi
        if [[ -n "${CLOUD_INIT_STATUS_FILE}" ]]; then
            cat > "${CLOUD_INIT_STATUS_FILE}" <<EOF
ERROR
$error_msg
Exit code: $exit_code
Time: $(date +"%Y-%m-%d %H:%M:%S")
EOF
        fi
        exit $exit_code
    }
    
    # Note: Not using ERR trap or set -e in cloud-init environment
    # as they can cause unexpected behavior. Using explicit error checking instead.
    
    # Define exit codes
    EXIT_SUCCESS=0
    EXIT_ERROR=1
    EXIT_MISSING_DEPS=2
fi

# Source setup scripts
if [[ -f /usr/local/bin/portainer-setup.sh ]]; then
    source /usr/local/bin/portainer-setup.sh
else
    error_exit "portainer-setup.sh not found" ${EXIT_MISSING_DEPS}
fi

if [[ -f /usr/local/bin/semaphore-setup-boltdb.sh ]]; then
    source /usr/local/bin/semaphore-setup-boltdb.sh
else
    error_exit "semaphore-setup-boltdb.sh not found" ${EXIT_MISSING_DEPS}
fi

log_info "Starting VM post-installation setup..."

# Configure system settings
log_info "Configuring system settings..."
# Add your system configurations here

# Install additional packages if needed
if ! command -v curl &>/dev/null || ! command -v jq &>/dev/null; then
    log_info "Installing required packages..."
    apt-get update
    apt-get install -y curl jq
else
    log_info "Required packages already installed"
fi

# Proxmox host IP is now provided via cloud-init at /etc/privatebox-proxmox-host
# No need to discover it anymore
if [[ -f /etc/privatebox-proxmox-host ]]; then
    PROXMOX_IP=$(cat /etc/privatebox-proxmox-host | tr -d '[:space:]')
    log_info "Proxmox host IP from cloud-init: $PROXMOX_IP"
else
    log_info "No Proxmox host IP provided via cloud-init"
fi

# Enable Podman socket for Docker API compatibility
# Podman is always installed by cloud-init, so we just need to enable the socket
log_info "Enabling Podman socket..."
systemctl enable --now podman.socket || {
    log_error "Failed to enable Podman socket"
    error_exit "Podman socket setup failed"
}
log_info "Podman socket enabled successfully"

# Create directory for systemd service files (ensure it exists before any setup function that might use it)
mkdir -p /etc/systemd/system

# Set up Portainer
setup_portainer

# Set up Semaphore
setup_semaphore

# Services are started by their respective setup scripts
# No need for additional systemd operations here

log_info "VM setup completed successfully!"

# Collect final status information
FINAL_STATUS="SUCCESS"
PORTAINER_STATUS=$(systemctl is-active portainer.service 2>/dev/null || echo "failed")
SEMAPHORE_STATUS=$(systemctl is-active semaphore.service 2>/dev/null || echo "failed")

# Write detailed status report
cat >> "$SETUP_LOG" <<EOF

=== Final Status Report ===
Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
Overall Status: $FINAL_STATUS
Services:
  - Portainer: $PORTAINER_STATUS
  - Semaphore: $SEMAPHORE_STATUS

Exit Code: 0
Log Files:
  - Main Log: $SETUP_LOG
  - Debug Log: $SETUP_DEBUG_LOG
===========================
EOF

# Write success status with detailed info
if [[ -w /etc/privatebox-cloud-init-complete ]]; then
    echo "POST_INSTALL_SUCCESS=true" >> /etc/privatebox-cloud-init-complete
    echo "POST_INSTALL_EXIT_CODE=0" >> /etc/privatebox-cloud-init-complete
    echo "POST_INSTALL_LOG=$SETUP_LOG" >> /etc/privatebox-cloud-init-complete
    echo "POST_INSTALL_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /etc/privatebox-cloud-init-complete
    echo "POST_INSTALL_SERVICES=portainer:$PORTAINER_STATUS,semaphore:$SEMAPHORE_STATUS" >> /etc/privatebox-cloud-init-complete
fi

# Copy logs to a persistent location
cp "$SETUP_LOG" /var/log/privatebox-setup-final.log 2>/dev/null || true
cp "$SETUP_DEBUG_LOG" /var/log/privatebox-setup-debug-final.log 2>/dev/null || true

log_info "Setup logs written to: $SETUP_LOG and $SETUP_DEBUG_LOG"

exit ${EXIT_SUCCESS}