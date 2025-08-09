#!/bin/bash
#
# PrivateBox Bootstrap v2 - Phase 1: Host Preparation
# Pre-flight checks and configuration generation
#

set -euo pipefail

# Get script directory for sourcing libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
LOG_FILE="/tmp/privatebox-bootstrap.log"
CONFIG_FILE="/tmp/privatebox-config.conf"
VMID=9000
STORAGE="local-lvm"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

display() {
    echo "$1"
    log "$1"
}

error_exit() {
    echo "ERROR: $1" >&2
    log "ERROR: $1"
    exit 1
}

# Pre-flight checks
run_preflight_checks() {
    display "Running pre-flight checks..."
    
    # Check root user
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
    log "✓ Running as root"
    
    # Check Proxmox environment
    if [[ ! -d /etc/pve ]]; then
        error_exit "Proxmox VE not detected (/etc/pve not found)"
    fi
    log "✓ Proxmox VE environment detected"
    
    # Check qm command
    if ! command -v qm &> /dev/null; then
        error_exit "qm command not found"
    fi
    log "✓ qm command available"
    
    # Check existing VM
    if qm status $VMID &>/dev/null; then
        display "  ⚠️  VM $VMID exists - will be destroyed"
        log "VM $VMID exists and will be destroyed"
        
        # Stop VM if running
        if qm status $VMID 2>/dev/null | grep -q "running"; then
            log "Stopping VM $VMID"
            qm stop $VMID --timeout 30 || true
            sleep 2
        fi
        
        # Destroy VM
        log "Destroying VM $VMID"
        qm destroy $VMID --purge || error_exit "Failed to destroy existing VM $VMID"
        display "  ✓ Removed existing VM $VMID"
    else
        log "✓ VM $VMID does not exist"
    fi
    
    # Check disk space (40GB required)
    local available_space=$(pvesm status -storage $STORAGE 2>/dev/null | grep "^$STORAGE" | awk '{print $4}')
    if [[ -z "$available_space" ]]; then
        error_exit "Could not determine available space on storage $STORAGE"
    fi
    
    # Convert to GB (pvesm shows in KB)
    local available_gb=$((available_space / 1024 / 1024))
    if [[ $available_gb -lt 40 ]]; then
        error_exit "Insufficient disk space. Need 40GB, have ${available_gb}GB"
    fi
    log "✓ Sufficient disk space: ${available_gb}GB available"
    
    display "  ✓ All pre-flight checks passed"
}

# Network detection
detect_network() {
    display "Detecting network configuration..."
    
    local gateway=""
    local bridge=""
    local base_network=""
    local host_ip=""
    
    # Find all vmbr interfaces
    local bridges=$(ip link show | grep -o 'vmbr[0-9]*' | sort -u)
    if [[ -z "$bridges" ]]; then
        error_exit "No Proxmox bridge interfaces found"
    fi
    
    log "Found bridges: $(echo $bridges | tr '\n' ' ')"
    
    # Check each bridge for connectivity
    for br in $bridges; do
        # Get IP address of bridge
        local br_ip=$(ip addr show $br 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1)
        if [[ -n "$br_ip" ]]; then
            # Get gateway for this bridge
            local br_gw=$(ip route | grep "default.*$br" | awk '{print $3}' | head -1)
            if [[ -n "$br_gw" ]]; then
                # Test gateway connectivity
                if ping -c 1 -W 2 "$br_gw" &>/dev/null; then
                    bridge="$br"
                    host_ip="$br_ip"
                    gateway="$br_gw"
                    base_network=$(echo "$br_ip" | cut -d. -f1-3)
                    log "Selected bridge $br with IP $br_ip, gateway $br_gw"
                    break
                fi
            fi
        fi
    done
    
    # Validate network detection
    if [[ -z "$gateway" ]] || [[ -z "$bridge" ]]; then
        error_exit "Could not detect network configuration"
    fi
    
    # Test gateway connectivity
    display "  Testing gateway connectivity..."
    if ! ping -c 2 -W 2 "$gateway" &>/dev/null; then
        error_exit "Cannot reach gateway $gateway"
    fi
    log "✓ Gateway $gateway is reachable"
    
    display "  ✓ Network detected: $bridge ($base_network.0/24)"
    
    # Return values via global variables
    GATEWAY="$gateway"
    VM_NET_BRIDGE="$bridge"
    BASE_NETWORK="$base_network"
    PROXMOX_HOST="$host_ip"
}

# Source password generator library for phonetic passwords
source "${SCRIPT_DIR}/lib/password-generator.sh"

# Generate configuration
generate_config() {
    display "Generating configuration..."
    
    # Network settings (from detection)
    local gateway="$GATEWAY"
    local bridge="$VM_NET_BRIDGE"
    local base_network="$BASE_NETWORK"
    local proxmox_host="$PROXMOX_HOST"
    
    # Detect Proxmox node name
    local proxmox_node=$(pvesh get /nodes --output-format json | jq -r '.[0].node' 2>/dev/null || echo "pve")
    
    # Generate passwords
    local admin_password=$(generate_password admin)
    local services_password=$(generate_password services)
    
    # Generate Proxmox API token
    display "Creating Proxmox API token for automation..."
    local proxmox_token_secret=""
    local proxmox_token_id="automation@pve!ansible"
    local proxmox_host_ip="$proxmox_host"
    
    # Clean up any old token files
    rm -f /root/.proxmox-api-token 2>/dev/null || true
    
    # Check if user exists
    if ! pveum user list | grep -q "^automation@pve"; then
        pveum user add automation@pve --comment "Automation user for Ansible" >/dev/null 2>&1 || true
    fi
    
    # Check if token already exists and remove it
    if pveum user token list automation@pve 2>/dev/null | grep -q "│ ansible "; then
        log "Removing existing token..."
        pveum user token remove automation@pve ansible >/dev/null 2>&1 || true
        sleep 1  # Brief pause to ensure removal completes
    fi
    
    # Create new token without privilege separation (for Proxmox 8.4+ compatibility)
    # Note: privsep=0 allows token to inherit user permissions
    local token_output=$(pveum user token add automation@pve ansible --privsep 0 --output-format json 2>&1)
    if [[ "$token_output" == *"value"* ]]; then
        proxmox_token_secret=$(echo "$token_output" | grep -oP '"value"\s*:\s*"\K[^"]+' || true)
        
        # Set permissions on the user (Proxmox 8.4+ doesn't support -token parameter)
        # Token with privsep=0 will inherit these permissions
        pveum acl modify /vms --users "automation@pve" --roles PVEVMAdmin >/dev/null 2>&1
        pveum acl modify /storage --users "automation@pve" --roles PVEDatastoreUser >/dev/null 2>&1
        pveum acl modify /nodes --users "automation@pve" --roles PVEAuditor >/dev/null 2>&1
        
        log "✓ API token created: $proxmox_token_id"
    else
        log "WARNING: Failed to create API token - automation features will be limited"
        log "Token creation output: $token_output"
        proxmox_token_secret=""  # Ensure it's empty on failure
    fi
    
    # VM network settings (using hardcoded design)
    local container_host_ip="${base_network}.20"
    local caddy_host_ip="${base_network}.21"
    local opnsense_ip="${base_network}.47"
    
    # Write configuration file
    cat > "$CONFIG_FILE" <<EOF
# PrivateBox Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# Network Configuration
GATEWAY="$gateway"
VM_NET_BRIDGE="$bridge"
BASE_NETWORK="$base_network"
PROXMOX_HOST="$proxmox_host"
NETMASK="24"

# VM Network IPs (by design)
STATIC_IP="$container_host_ip"
CONTAINER_HOST_IP="$container_host_ip"
CADDY_HOST_IP="$caddy_host_ip"
OPNSENSE_IP="$opnsense_ip"

# VM Configuration
VMID="$VMID"
VM_USERNAME="debian"
VM_MEMORY="4096"
VM_CORES="2"
VM_DISK_SIZE="40G"
VM_STORAGE="$STORAGE"

# Credentials
ADMIN_PASSWORD="$admin_password"
SERVICES_PASSWORD="$services_password"

# Proxmox API Token
PROXMOX_TOKEN_ID="$proxmox_token_id"
PROXMOX_TOKEN_SECRET="$proxmox_token_secret"
PROXMOX_API_HOST="$proxmox_host_ip"
PROXMOX_NODE="$proxmox_node"

# Legacy compatibility
STORAGE="$STORAGE"
EOF

    log "Configuration generated successfully"
    display "  ✓ Configuration file created"
    
    # Display summary
    display ""
    display "Configuration Summary:"
    display "  Network: ${base_network}.0/24"
    display "  Gateway: $gateway"
    display "  Bridge: $bridge"
    display "  VM IP: $container_host_ip"
}

# Main execution
main() {
    display "Starting host preparation..."
    log "Phase 1: Host preparation started"
    
    # Run pre-flight checks
    run_preflight_checks
    
    # Detect network
    detect_network
    
    # Generate configuration
    generate_config
    
    display ""
    display "✓ Host preparation complete"
    log "Phase 1 completed successfully"
}

# Run main
main "$@"