#!/bin/bash

# VM post-installation setup script
# This script runs after cloud-init completes

# Source common library if available (fallback to basic logging)
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh" ]]; then
    # shellcheck source=../lib/common.sh
    source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
else
    # Fallback logging function for embedded environment
    log() {
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$timestamp] $1"
    }
    log_info() { log "INFO: $*"; }
    log_warn() { log "WARN: $*"; }
    log_error() { log "ERROR: $*"; }
    error_exit() { 
        log_error "$1"
        # Write error to status file for Proxmox to see
        if [[ -w /etc/privatebox-cloud-init-complete ]]; then
            echo "POST_INSTALL_ERROR=$1" >> /etc/privatebox-cloud-init-complete
            echo "POST_INSTALL_EXIT_CODE=${2:-1}" >> /etc/privatebox-cloud-init-complete
        fi
        exit "${2:-1}"
    }
fi

# Error handler for the script
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "Script failed at line $line_number with exit code $exit_code"
    if [[ -w /etc/privatebox-cloud-init-complete ]]; then
        echo "POST_INSTALL_ERROR=Script failed at line $line_number" >> /etc/privatebox-cloud-init-complete
        echo "POST_INSTALL_EXIT_CODE=$exit_code" >> /etc/privatebox-cloud-init-complete
    fi
    exit $exit_code
}

# Set error trap
trap 'handle_error ${LINENO}' ERR

# Source setup scripts
source /usr/local/bin/portainer-setup.sh
source /usr/local/bin/semaphore-setup.sh

log_info "Starting VM post-installation setup..."

# Configure system settings
log_info "Configuring system settings..."
# Add your system configurations here

# Install additional packages
log_info "Installing additional packages..."
apt-get update
apt-get install -y curl git jq htop

# Check if Podman is already installed
if command -v podman &> /dev/null; then
    log_info "Podman is already installed: $(podman --version)"
else
    # Install Podman
    log_info "Installing Podman..."
    apt-get install -y podman

    # Verify Podman installation
    if ! command -v podman &> /dev/null; then
        error_exit "Podman installation failed!"
    fi
    log_info "Podman installed successfully: $(podman --version)"
fi

# Create directory for systemd service files (ensure it exists before any setup function that might use it)
mkdir -p /etc/systemd/system

# Set up Portainer
setup_portainer

# Set up Semaphore
setup_semaphore

# Reload systemd to pick up new Quadlet files and enable the services
log_info "Reloading systemd and enabling Quadlet services..."
if ! systemctl daemon-reload; then
    log_error "Failed to reload systemd daemon"
fi

# Small delay to ensure systemd has processed the new Quadlet files
sleep 2

# Start Portainer (Quadlet services are auto-enabled via [Install] section)
log_info "Starting Portainer service..."
if ! systemctl start portainer.service; then
    log_error "Failed to start Portainer service"
    # Try again after a short delay
    sleep 3
    if ! systemctl start portainer.service; then
        log_error "Failed to start Portainer service on retry"
    fi
fi

# Verify Semaphore services are running (they should be started by semaphore-setup.sh)
log_info "Verifying Semaphore services..."
if ! systemctl is-active --quiet semaphore-ui.service; then
    log_warn "Semaphore UI service is not active - it should have been started by semaphore-setup.sh"
fi
if ! systemctl is-active --quiet semaphore-db.service; then
    log_warn "Semaphore DB service is not active - it should have been started by semaphore-setup.sh"
fi

log_info "Systemd services created and enabled"

# Clean up old service files
if [ -f /etc/systemd/system/podman-auto-restart.service ]; then
    log_info "Removing old systemd service files..."
    systemctl disable podman-auto-restart.service 2>/dev/null || true
    rm -f /etc/systemd/system/podman-auto-restart.service
fi

if [ -f /etc/systemd/system/podman-volumes.service ]; then
    systemctl disable podman-volumes.service 2>/dev/null || true
    rm -f /etc/systemd/system/podman-volumes.service
fi

log_info "VM setup completed successfully!"
exit 0