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

# Note: Repository fixes are now handled by proxmox-optimize.sh
# which runs early in the bootstrap process

# Check and install required dependencies
check_dependencies() {
    display "  Checking required dependencies..."
    local missing_deps=()
    local deps_to_install=()

    # Check for required commands
    local required_commands=("ethtool" "sshpass" "zstd" "curl" "wget" "openssl" "jq")
    local required_packages=("ethtool" "sshpass" "zstd" "curl" "wget" "openssl" "jq")

    for i in "${!required_commands[@]}"; do
        if ! command -v "${required_commands[$i]}" &> /dev/null; then
            missing_deps+=("${required_commands[$i]}")
            deps_to_install+=("${required_packages[$i]}")
            log "Missing dependency: ${required_commands[$i]}"
        else
            log "✓ ${required_commands[$i]} is available"
        fi
    done

    # Install missing dependencies
    if [[ ${#deps_to_install[@]} -gt 0 ]]; then
        display "  Installing missing dependencies: ${deps_to_install[*]}"
        log "Installing packages: ${deps_to_install[*]}"

        # Note: Repository fixes are handled by proxmox-optimize.sh
        # Update package list
        apt-get update >/dev/null 2>&1 || error_exit "Failed to update package list"

        # Install missing packages
        if DEBIAN_FRONTEND=noninteractive apt-get install -y "${deps_to_install[@]}" >/dev/null 2>&1; then
            display "  ✓ Dependencies installed successfully"
            log "Dependencies installed: ${deps_to_install[*]}"
        else
            error_exit "Failed to install required dependencies: ${deps_to_install[*]}"
        fi
    else
        log "✓ All required dependencies are installed"
    fi
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
    
    # Check and install dependencies
    check_dependencies
    
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

# Detect WAN bridge (for OPNsense external interface)
detect_wan_bridge() {
    display "Detecting WAN bridge..."
    
    # Find bridge with default route (typically vmbr0)
    local wan_bridge=""
    local default_route=$(ip route | grep "^default" | head -1)
    
    if [[ -n "$default_route" ]]; then
        # Extract bridge name from default route
        wan_bridge=$(echo "$default_route" | grep -o 'vmbr[0-9]*' || true)
    fi
    
    # If not found via route, look for vmbr0 as fallback
    if [[ -z "$wan_bridge" ]] && ip link show vmbr0 &>/dev/null; then
        wan_bridge="vmbr0"
        log "Using vmbr0 as WAN bridge (fallback)"
    fi
    
    if [[ -z "$wan_bridge" ]]; then
        error_exit "Could not detect WAN bridge. Ensure vmbr0 exists with internet connectivity."
    fi
    
    # Get Proxmox's IP on this bridge (for reference)
    local proxmox_ip=$(ip addr show $wan_bridge 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1)
    
    log "WAN bridge: $wan_bridge"
    log "Proxmox IP: ${proxmox_ip:-not configured}"
    
    display "  ✓ WAN bridge detected: $wan_bridge"
    
    # Set global variables
    WAN_BRIDGE="$wan_bridge"
    PROXMOX_IP="${proxmox_ip:-unknown}"
}

# Source password generator library for phonetic passwords
source "${SCRIPT_DIR}/lib/password-generator.sh"

# Generate configuration
generate_https_certificate() {
    display "Generating HTTPS certificate..."

    local cert_dir="/etc/privatebox/certs"

    # Create certificate directory
    mkdir -p "$cert_dir"

    # Generate self-signed certificate (10 year validity) - ECDSA P-256 for modern crypto
    openssl req -x509 -nodes -days 3650 -newkey ec \
      -pkeyopt ec_paramgen_curve:prime256v1 \
      -subj "/C=DK/O=PrivateBox/CN=privatebox.local" \
      -keyout "$cert_dir/privatebox.key" \
      -out "$cert_dir/privatebox.crt" \
      2>/dev/null || error_exit "Failed to generate HTTPS certificate"

    chmod 644 "$cert_dir/privatebox.key"
    chmod 644 "$cert_dir/privatebox.crt"

    display "  ✓ HTTPS certificate generated (valid 10 years)"
    log "HTTPS certificate created at $cert_dir"
}

generate_config() {
    display "Generating configuration..."

    # WAN bridge for OPNsense
    local wan_bridge="$WAN_BRIDGE"
    local proxmox_ip="$PROXMOX_IP"
    
    # Detect Proxmox node name - use hostname as it's more reliable
    local proxmox_node=$(hostname -s 2>/dev/null || echo "proxmox")
    
    # Generate passwords
    local admin_password=$(generate_password admin)
    local services_password=$(generate_password services)
    
    # Generate Proxmox API token
    display "Creating Proxmox API token for automation..."
    local proxmox_token_secret=""
    local proxmox_token_id="automation@pve!ansible"
    local proxmox_api_host="${proxmox_ip}"
    
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
    
    # Fixed IP addresses for Services VLAN (10.10.20.0/24)
    # According to network design:
    # - 10.10.20.1: OPNsense (VLAN gateway)
    # - 10.10.20.10: Management VM (Debian with all services)
    # - 10.10.20.20: Proxmox host (for management access)
    display "Configuring Services VLAN IP addresses..."
    
    local mgmt_vm_ip="10.10.20.10"
    local services_gateway="10.10.20.1"
    local services_network="10.10.20"
    local proxmox_services_ip="10.10.20.20"
    
    log "Management VM IP: $mgmt_vm_ip"
    log "Services gateway (OPNsense): $services_gateway"
    log "Proxmox Services IP: $proxmox_services_ip"
    log "Services network: ${services_network}.0/24"
    
    # Write configuration file
    cat > "$CONFIG_FILE" <<EOF
# PrivateBox Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# WAN Network (Internet access)
WAN_BRIDGE="$wan_bridge"
PROXMOX_IP="$proxmox_ip"

# Services VLAN Configuration (10.10.20.0/24)
SERVICES_NETWORK="$services_network"
SERVICES_GATEWAY="$services_gateway"
SERVICES_NETMASK="24"
MGMT_VM_IP="$mgmt_vm_ip"
PROXMOX_SERVICES_IP="$proxmox_services_ip"

# VM Configuration
VMID="$VMID"
VM_USERNAME="debian"
VM_MEMORY="2048"
VM_CORES="2"
VM_DISK_SIZE="10G"
VM_STORAGE="$STORAGE"

# Credentials
ADMIN_PASSWORD="$admin_password"
SERVICES_PASSWORD="$services_password"

# Proxmox API Token
PROXMOX_TOKEN_ID="$proxmox_token_id"
PROXMOX_TOKEN_SECRET="$proxmox_token_secret"
PROXMOX_API_HOST="$proxmox_api_host"
PROXMOX_NODE="$proxmox_node"

# Legacy compatibility (for create-vm.sh)
STATIC_IP="$mgmt_vm_ip"
GATEWAY="$services_gateway"
NETMASK="24"
CONTAINER_HOST_IP="$mgmt_vm_ip"
PROXMOX_HOST="$proxmox_services_ip"
EOF

    log "Configuration generated successfully"
    display "  ✓ Configuration file created"
    
    # Display summary
    display ""
    display "Configuration Summary:"
    display "  WAN Bridge: $wan_bridge"
    display "  Proxmox IP: $proxmox_ip"
    display ""
    display "  Services VLAN (VLAN 20):"
    display "    Network: ${services_network}.0/24"
    display "    Gateway: $services_gateway (OPNsense)"
    display "    Management VM: $mgmt_vm_ip"
    display "    Proxmox: $proxmox_services_ip"
}

# Generate SSH keys if they don't exist
generate_ssh_keys() {
    display "Checking SSH keys..."

    # Clean slate: Remove old PrivateBox-generated keys from authorized_keys
    if [[ -f /root/.ssh/authorized_keys ]]; then
        log "Removing old PrivateBox SSH keys from authorized_keys"
        sed -i '/privatebox@/d' /root/.ssh/authorized_keys 2>/dev/null || true
    fi

    if [[ ! -f /root/.ssh/id_ed25519 ]]; then
        log "SSH key not found at /root/.ssh/id_ed25519, generating new key pair"
        display "  Generating SSH key pair for VM access..."

        # Create .ssh directory if it doesn't exist
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh

        # Generate SSH key pair (no passphrase) - Ed25519 for modern crypto
        ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519 -N "" -C "privatebox@$(hostname)" >/dev/null 2>&1

        if [[ -f /root/.ssh/id_ed25519 ]]; then
            chmod 600 /root/.ssh/id_ed25519
            chmod 644 /root/.ssh/id_ed25519.pub
            display "  ✓ SSH key pair generated successfully (Ed25519)"
            log "SSH key pair generated at /root/.ssh/id_ed25519"
        else
            error_exit "Failed to generate SSH key pair"
        fi
    else
        display "  ✓ SSH key pair already exists"
        log "SSH key pair already exists at /root/.ssh/id_ed25519"
    fi

    # Add Proxmox's public key to its own authorized_keys for Semaphore access
    if [[ -f /root/.ssh/id_ed25519.pub ]]; then
        log "Adding Proxmox public key to authorized_keys for self-access"
        cat /root/.ssh/id_ed25519.pub >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        display "  ✓ Public key authorized for Semaphore → Proxmox access"
        log "Proxmox can now accept SSH connections from Semaphore using embedded private key"
    fi
}

# Setup network bridges for PrivateBox
setup_network_bridges() {
    log "Configuring network bridges for PrivateBox..."
    display "  Checking network bridge configuration..."
    
    # First check if vmbr1 already exists and is properly configured
    if ip link show vmbr1 &>/dev/null 2>&1; then
        log "vmbr1 already exists, checking configuration..."
        
        # Check configuration in both possible locations
        local bridge_ports=""
        if [[ -f /etc/network/interfaces.d/vmbr1 ]]; then
            bridge_ports=$(grep "bridge-ports" /etc/network/interfaces.d/vmbr1 2>/dev/null | awk '{print $2}')
        fi
        if [[ -z "$bridge_ports" ]]; then
            bridge_ports=$(grep -A5 "iface vmbr1" /etc/network/interfaces 2>/dev/null | grep "bridge-ports" | awk '{print $2}')
        fi
        
        # Check if it's configured with a physical NIC (not "none" or empty)
        if [[ -n "$bridge_ports" ]] && [[ "$bridge_ports" != "none" ]]; then
            # vmbr1 is properly configured, check if it's VLAN-aware
            local vlan_aware=$(grep -A10 "iface vmbr1" /etc/network/interfaces 2>/dev/null | grep "bridge-vlan-aware yes" || true)
            if [[ -n "$vlan_aware" ]]; then
                display "  ✓ vmbr1 already properly configured on $bridge_ports with VLAN support"
                log "vmbr1 is already properly configured on $bridge_ports with VLAN support"
                return 0  # All good, nothing to do
            else
                display "  ⚠ vmbr1 exists on $bridge_ports but missing VLAN support, updating..."
                # Add VLAN support to existing bridge
                sed -i '/iface vmbr1/,/^$/s/bridge-fd 0/bridge-fd 0\n\tbridge-vlan-aware yes\n\tbridge-vids 2-4094/' /etc/network/interfaces
                ifdown vmbr1 2>/dev/null || true
                ifup vmbr1 2>/dev/null || true
                display "  ✓ vmbr1 updated with VLAN support"
                return 0
            fi
        fi
        # If we get here, vmbr1 exists but has no physical port
        display "  ⚠ vmbr1 exists but has no physical port"
    fi
    
    # Need to find a NIC for vmbr1
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
    
    # If vmbr1 exists but needs fixing, fix it
    if ip link show vmbr1 &>/dev/null 2>&1; then
        fix_vmbr1_config "$second_nic"
    else
        # Create vmbr1
        create_vmbr1 "$second_nic"
    fi
}

create_vmbr1() {
    local nic="$1"
    display "  Creating vmbr1 on $nic for internal network..."
    log "Creating vmbr1 bridge on interface $nic"
    
    # Add the bridge configuration to main interfaces file (for Proxmox UI visibility)
    cat >> /etc/network/interfaces <<EOF

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
        rm /etc/network/interfaces.d/vmbr1
        log "Backed up and removed vmbr1 from interfaces.d"
    fi
    
    # Remove vmbr1 from main interfaces file if it exists
    if grep -q "^auto vmbr1" /etc/network/interfaces; then
        cp /etc/network/interfaces /etc/network/interfaces.bak
        sed -i '/^auto vmbr1/,/^$/d' /etc/network/interfaces
        log "Removed old vmbr1 config from main interfaces file"
    fi
    
    # Down the interface first
    ifdown vmbr1 2>/dev/null || true
    
    # Rewrite the config
    create_vmbr1 "$nic"
}

# Configure Services Network
configure_services_network() {
    display "Configuring Services network (VLAN 20)..."
    
    # Check if VLAN 20 interface exists and has correct IP
    if ip addr show vmbr1.20 2>/dev/null | grep -q "10.10.20.20/24"; then
        log "VLAN 20 interface already has correct IP 10.10.20.20/24"
        display "  ✓ Services network already configured on VLAN 20"
        
        # Verify it's in the config file for persistence
        if ! grep -q "^auto vmbr1.20" /etc/network/interfaces; then
            log "Adding VLAN 20 to interfaces file for persistence"
            cat >> /etc/network/interfaces <<EOF

auto vmbr1.20
iface vmbr1.20 inet static
	address 10.10.20.20/24
	# PrivateBox Services network (VLAN 20)
EOF
            display "  ✓ Added persistent configuration for VLAN 20"
        fi
        return 0
    fi
    
    # Check if VLAN 20 is configured in interfaces file but not active
    if grep -q "^auto vmbr1.20" /etc/network/interfaces; then
        log "VLAN 20 interface configured but not active, bringing it up..."
        display "  Activating VLAN 20 interface..."
        ifup vmbr1.20 2>/dev/null || true
    else
        # Add persistent VLAN 20 configuration
        log "Adding persistent VLAN 20 configuration to /etc/network/interfaces"
        cat >> /etc/network/interfaces <<EOF

auto vmbr1.20
iface vmbr1.20 inet static
	address 10.10.20.20/24
	# PrivateBox Services network (VLAN 20)
EOF
        
        display "  ✓ Added persistent VLAN 20 configuration"
        
        # Bring up the VLAN interface using ifup for immediate activation
        log "Bringing up VLAN 20 interface..."
        if ifup vmbr1.20 2>/dev/null; then
            display "  ✓ VLAN 20 interface (10.10.20.20/24) is active"
            log "VLAN 20 interface brought up successfully"
        else
            # Fallback to manual activation if ifup fails
            log "ifup failed, trying manual activation..."
            ip link add link vmbr1 name vmbr1.20 type vlan id 20 2>/dev/null || true
            ip link set vmbr1.20 up
            ip addr add 10.10.20.20/24 dev vmbr1.20 2>/dev/null || true
            display "  ✓ VLAN 20 interface (10.10.20.20/24) is active (manual)"
        fi
    fi
    
    # Ensure no conflicting IP on untagged interface
    if ip addr show vmbr1 | grep -q "10.10.20.20/24"; then
        log "WARNING: Found 10.10.20.20/24 on untagged vmbr1, removing..."
        ip addr del 10.10.20.20/24 dev vmbr1 2>/dev/null || true
        display "  ⚠ Removed conflicting untagged IP from vmbr1"
    fi
    
    # Verify VLAN 20 is active and has correct IP
    if ip addr show vmbr1.20 2>/dev/null | grep -q "10.10.20.20/24"; then
        log "Verified: VLAN 20 interface has correct IP"
    else
        log "WARNING: VLAN 20 interface missing expected IP, attempting to add..."
        ip addr add 10.10.20.20/24 dev vmbr1.20 2>/dev/null || true
    fi
    
    # Test connectivity to OPNsense (if deployed)
    if ping -I vmbr1.20 -c 1 -W 2 10.10.20.1 &>/dev/null; then
        log "OPNsense is reachable at 10.10.20.1 via VLAN 20"
        display "  ✓ OPNsense detected at 10.10.20.1 on VLAN 20"
    else
        log "OPNsense not yet deployed or VLAN 20 not configured on OPNsense"
        display "  ℹ OPNsense will be at 10.10.20.1 on VLAN 20"
    fi
}

# Main execution
main() {
    display "Starting host preparation..."
    log "Phase 1: Host preparation started"

    # Run pre-flight checks
    run_preflight_checks

    # Optimize Proxmox (repos, nag removal, HA services)
    bash "${SCRIPT_DIR}/proxmox-optimize.sh"

    # Generate SSH keys if needed
    generate_ssh_keys
    
    # Detect WAN bridge for OPNsense
    detect_wan_bridge
    
    # Setup network bridges
    setup_network_bridges
    
    # Configure Services network
    configure_services_network

    # Generate HTTPS certificate
    generate_https_certificate

    # Generate configuration
    generate_config
    
    display ""
    display "✓ Host preparation complete"
    log "Phase 1 completed successfully"
}

# Run main
main "$@"