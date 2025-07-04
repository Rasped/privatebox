#!/bin/bash
# Fix Proxmox repository configuration
# This script comments out enterprise repos and enables no-subscription repo

# Enable automatic error handling
export PRIVATEBOX_AUTO_ERROR_HANDLING=true

# Source common library
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh" || {
    echo "ERROR: Cannot source common library" >&2
    exit 1
}

log_info "Fixing Proxmox repository configuration..."

# Comment out all lines in /etc/apt/sources.list.d/ceph.list
if [[ -f /etc/apt/sources.list.d/ceph.list ]]; then
    log_info "Disabling Ceph repository..."
    sed -i 's/^/#/' /etc/apt/sources.list.d/ceph.list || check_result $? "Failed to comment out Ceph repository"
fi

# Comment out all lines in /etc/apt/sources.list.d/pve-enterprise.list
if [[ -f /etc/apt/sources.list.d/pve-enterprise.list ]]; then
    log_info "Disabling Proxmox enterprise repository..."
    sed -i 's/^/#/' /etc/apt/sources.list.d/pve-enterprise.list || check_result $? "Failed to comment out enterprise repository"
fi

# Create pve-no-subscription.list with new content
log_info "Enabling Proxmox no-subscription repository..."
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list || check_result $? "Failed to create no-subscription repository"

log_success "Proxmox repositories fixed successfully"