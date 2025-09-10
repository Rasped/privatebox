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
    
    # Check disk space (15GB required)
    local available_space=$(pvesm status -storage $STORAGE 2>/dev/null | grep "^$STORAGE" | awk '{print $4}')
    if [[ -z "$available_space" ]]; then
        error_exit "Could not determine available space on storage $STORAGE"
    fi
    
    # Convert to GB (pvesm shows in KB)
    local available_gb=$((available_space / 1024 / 1024))
    if [[ $available_gb -lt 15 ]]; then
        error_exit "Insufficient disk space. Need 15GB, have ${available_gb}GB"
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
    
    # Detect Proxmox node name - use hostname as it's more reliable
    local proxmox_node=$(hostname -s 2>/dev/null || echo "proxmox")
    
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
    
    # Find available IP addresses using probe-before-allocate
    display "Finding available IP addresses..."
    local container_host_ip=""
    local start_ip=100  # Start at .100 (common DHCP range start)
    
    # Probe for available container host IP
    for i in $(seq $start_ip 250); do
        local test_ip="${base_network}.${i}"
        if ! ping -c 1 -W 1 "$test_ip" >/dev/null 2>&1; then
            container_host_ip="$test_ip"
            log "Found available IP for container host: $container_host_ip"
            break
        fi
    done
    
    if [[ -z "$container_host_ip" ]]; then
        error_exit "Could not find available IP address in range ${base_network}.${start_ip}-250"
    fi
    
    # Find next available IP for Caddy (skip the one we just allocated)
    local caddy_host_ip=""
    for i in $(seq $((start_ip + 1)) 250); do
        local test_ip="${base_network}.${i}"
        if [[ "$test_ip" != "$container_host_ip" ]] && ! ping -c 1 -W 1 "$test_ip" >/dev/null 2>&1; then
            caddy_host_ip="$test_ip"
            log "Found available IP for Caddy host: $caddy_host_ip"
            break
        fi
    done
    
    if [[ -z "$caddy_host_ip" ]]; then
        # Fallback: use container_host_ip + 1 if we can't find another
        local last_octet="${container_host_ip##*.}"
        caddy_host_ip="${base_network}.$((last_octet + 1))"
        log "Using fallback IP for Caddy host: $caddy_host_ip"
    fi
    
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

# VM Configuration
VMID="$VMID"
VM_USERNAME="debian"
VM_MEMORY="4096"
VM_CORES="2"
VM_DISK_SIZE="15G"
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
    display "  Management VM IP: $container_host_ip (probed as available)"
    display "  Caddy VM IP: $caddy_host_ip (reserved for future use)"
}

# Generate SSH keys if they don't exist
generate_ssh_keys() {
    display "Checking SSH keys..."
    
    if [[ ! -f /root/.ssh/id_rsa ]]; then
        log "SSH key not found at /root/.ssh/id_rsa, generating new key pair"
        display "  Generating SSH key pair for VM access..."
        
        # Create .ssh directory if it doesn't exist
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        
        # Generate SSH key pair (no passphrase)
        ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -C "privatebox@$(hostname)" >/dev/null 2>&1
        
        if [[ -f /root/.ssh/id_rsa ]]; then
            chmod 600 /root/.ssh/id_rsa
            chmod 644 /root/.ssh/id_rsa.pub
            display "  ✓ SSH key pair generated successfully"
            log "SSH key pair generated at /root/.ssh/id_rsa"
        else
            error_exit "Failed to generate SSH key pair"
        fi
    else
        display "  ✓ SSH key pair already exists"
        log "SSH key pair already exists at /root/.ssh/id_rsa"
    fi
}

# Setup network bridges for PrivateBox
setup_network_bridges() {
    log "Configuring network bridges for PrivateBox..."
    display "  Checking network bridge configuration..."
    
    # Check for dual NIC requirement
    local nic_count=$(ip link show | grep -E "^[0-9]+: (enp|eno|eth)" | grep -v "lo:" | wc -l)
    local second_nic=""
    
    # Find a NIC that's not assigned to any bridge
    for nic in $(ip link show | grep -E "^[0-9]+: (enp|eno|eth)" | cut -d: -f2 | tr -d ' '); do
        # Check if this NIC is assigned to any bridge via bridge-ports
        if ! grep -E "bridge-ports.*$nic" /etc/network/interfaces 2>/dev/null | grep -q "$nic"; then
            # Also check it's not in any interfaces.d file
            if ! grep -E "bridge-ports.*$nic" /etc/network/interfaces.d/* 2>/dev/null | grep -q "$nic"; then
                second_nic="$nic"
                log "Found unassigned NIC: $nic"
                # Verify the NIC has link (cable connected)
                ip link set "$nic" up 2>/dev/null
                sleep 2
                if ethtool "$nic" 2>/dev/null | grep -q "Link detected: yes"; then
                    log "NIC $nic has link detected"
                else
                    log "Warning: NIC $nic has no link detected, but will use it anyway"
                fi
                break
            fi
        fi
    done
    
    if [[ -z "$second_nic" ]]; then
        local used_nics=$(grep -h bridge-ports /etc/network/interfaces /etc/network/interfaces.d/* 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
        local found_nics=$(ip link show | grep -E '^[0-9]+: (enp|eno|eth)' | cut -d: -f2 | tr -d ' ' | tr '\n' ' ')
        error_exit "PrivateBox requires dual NICs for proper network isolation.
        
        Current configuration:
        - Found NICs: $found_nics
        - NICs assigned to bridges: $used_nics
        - No unassigned NIC available for vmbr1 (internal network)
        
        Please ensure your system has two network interfaces and one is not assigned to any bridge."
    fi
    
    # Check if vmbr1 already exists
    if ip link show vmbr1 &>/dev/null 2>&1; then
        log "vmbr1 already exists, checking configuration..."
        
        # Check if it's properly configured
        if [[ -f /etc/network/interfaces.d/vmbr1 ]]; then
            if grep -q "bridge-ports none" /etc/network/interfaces.d/vmbr1; then
                display "  ⚠ vmbr1 exists but has no physical port, fixing..."
                fix_vmbr1_config "$second_nic"
            else
                local current_nic=$(grep "bridge-ports" /etc/network/interfaces.d/vmbr1 | awk '{print $2}')
                display "  ✓ vmbr1 already configured on $current_nic"
                log "vmbr1 is already properly configured on $current_nic"
            fi
        else
            # vmbr1 exists but not in interfaces.d, might be in main interfaces file
            if grep -A5 "iface vmbr1" /etc/network/interfaces | grep -q "bridge-ports none"; then
                display "  ⚠ vmbr1 exists but has no physical port, fixing..."
                fix_vmbr1_config "$second_nic"
            else
                display "  ✓ vmbr1 already configured"
                log "vmbr1 is already configured"
            fi
        fi
    else
        # Create vmbr1
        create_vmbr1 "$second_nic"
    fi
}

create_vmbr1() {
    local nic="$1"
    display "  Creating vmbr1 on $nic for internal network..."
    log "Creating vmbr1 bridge on interface $nic"
    
    # Create the bridge configuration
    cat > /etc/network/interfaces.d/vmbr1 <<EOF
auto vmbr1
iface vmbr1 inet manual
	bridge-ports $nic
	bridge-stp off
	bridge-fd 0
	bridge-vlan-aware yes
	bridge-vids 2-4094
	# PrivateBox internal network (LAN + VLANs)
EOF
    
    # Bring up the bridge
    if ifup vmbr1 2>/dev/null; then
        display "  ✓ vmbr1 created successfully on $nic"
        log "vmbr1 bridge created and brought up successfully"
    else
        error_exit "Failed to bring up vmbr1 bridge. Check network configuration."
    fi
}

fix_vmbr1_config() {
    local nic="$1"
    display "  Updating vmbr1 to use $nic..."
    log "Fixing vmbr1 configuration to use $nic"
    
    # Backup current config
    if [[ -f /etc/network/interfaces.d/vmbr1 ]]; then
        cp /etc/network/interfaces.d/vmbr1 /etc/network/interfaces.d/vmbr1.bak
        log "Backed up existing vmbr1 config"
    fi
    
    # Down the interface first
    ifdown vmbr1 2>/dev/null || true
    
    # Rewrite the config
    create_vmbr1 "$nic"
}

# Main execution
main() {
    display "Starting host preparation..."
    log "Phase 1: Host preparation started"
    
    # Run pre-flight checks
    run_preflight_checks
    
    # Generate SSH keys if needed
    generate_ssh_keys
    
    # Detect network
    detect_network
    
    # Setup network bridges
    setup_network_bridges
    
    # Generate configuration
    generate_config
    
    display ""
    display "✓ Host preparation complete"
    log "Phase 1 completed successfully"
}

# Run main
main "$@"