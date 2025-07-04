#!/bin/bash
# Network discovery and validation utilities for PrivateBox

# Source common library if not already sourced
if [[ -z "${COMMON_LIB_SOURCED:-}" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
    COMMON_LIB_SOURCED=true
fi

# Global variables for network configuration
DISCOVERED_GATEWAY=""
DISCOVERED_INTERFACE=""
DISCOVERED_BRIDGE=""
DISCOVERED_NETWORK=""
DISCOVERED_NETMASK=""
DISCOVERED_IP=""

# Get default gateway and interface
discover_default_gateway() {
    log_info "Discovering default gateway..."
    
    # Get default route
    local route_info=$(ip route show default 2>/dev/null | head -n1)
    
    if [[ -z "$route_info" ]]; then
        log_error "No default route found"
        return 1
    fi
    
    # Extract gateway and interface
    DISCOVERED_GATEWAY=$(echo "$route_info" | awk '{print $3}')
    DISCOVERED_INTERFACE=$(echo "$route_info" | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
    
    if [[ -z "$DISCOVERED_GATEWAY" ]] || [[ -z "$DISCOVERED_INTERFACE" ]]; then
        log_error "Failed to parse gateway information"
        return 1
    fi
    
    log_success "Found gateway: $DISCOVERED_GATEWAY on interface: $DISCOVERED_INTERFACE"
    return 0
}

# Discover Proxmox bridges
discover_proxmox_bridge() {
    log_info "Discovering Proxmox bridges..."
    
    # List all bridges
    local bridges=$(ip link show type bridge 2>/dev/null | grep -E '^[0-9]+:' | cut -d: -f2 | tr -d ' ')
    
    if [[ -z "$bridges" ]]; then
        log_warn "No bridges found, using default vmbr0"
        DISCOVERED_BRIDGE="vmbr0"
        return 0
    fi
    
    # Look for vmbr0 first (most common)
    if echo "$bridges" | grep -q "vmbr0"; then
        DISCOVERED_BRIDGE="vmbr0"
    else
        # Use the first available bridge
        DISCOVERED_BRIDGE=$(echo "$bridges" | head -n1)
    fi
    
    log_success "Found bridge: $DISCOVERED_BRIDGE"
    return 0
}

# Get network information from interface
discover_network_info() {
    local interface="${1:-$DISCOVERED_INTERFACE}"
    
    if [[ -z "$interface" ]]; then
        log_error "No interface specified"
        return 1
    fi
    
    log_info "Getting network information from interface: $interface"
    
    # Get IP address and netmask
    local ip_info=$(ip addr show "$interface" 2>/dev/null | grep -E "inet\s" | head -n1)
    
    if [[ -z "$ip_info" ]]; then
        log_error "No IP information found for interface $interface"
        return 1
    fi
    
    # Extract IP and CIDR
    local ip_cidr=$(echo "$ip_info" | awk '{print $2}')
    local host_ip=$(echo "$ip_cidr" | cut -d/ -f1)
    local cidr=$(echo "$ip_cidr" | cut -d/ -f2)
    
    # Calculate network address
    DISCOVERED_NETWORK=$(calculate_network "$host_ip" "$cidr")
    DISCOVERED_NETMASK=$(cidr_to_netmask "$cidr")
    
    log_success "Network: $DISCOVERED_NETWORK/$cidr (Netmask: $DISCOVERED_NETMASK)"
    return 0
}

# Calculate network address from IP and CIDR
calculate_network() {
    local ip="$1"
    local cidr="$2"
    
    # Convert IP to binary
    local ip_binary=""
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        # Convert to binary without bc
        local binary=""
        local n=$octet
        for ((j=7; j>=0; j--)); do
            if ((n >= (1<<j))); then
                binary+="1"
                n=$((n - (1<<j)))
            else
                binary+="0"
            fi
        done
        ip_binary+="$binary"
    done
    
    # Apply netmask
    local network_binary="${ip_binary:0:$cidr}"
    local padding=$((32 - cidr))
    for ((i=0; i<padding; i++)); do
        network_binary+="0"
    done
    
    # Convert back to decimal
    local network=""
    for ((i=0; i<4; i++)); do
        local octet_binary="${network_binary:$((i*8)):8}"
        local octet_decimal=$((2#$octet_binary))
        network+="$octet_decimal"
        [[ $i -lt 3 ]] && network+="."
    done
    
    echo "$network"
}

# Convert CIDR to netmask
cidr_to_netmask() {
    local cidr="$1"
    local mask=""
    local full_octets=$((cidr / 8))
    local remaining_bits=$((cidr % 8))
    
    # Full octets
    for ((i=0; i<full_octets; i++)); do
        mask+="255"
        [[ $i -lt 3 ]] && mask+="."
    done
    
    # Partial octet
    if [[ $remaining_bits -gt 0 ]] && [[ $full_octets -lt 4 ]]; then
        [[ -n "$mask" ]] && mask+="."
        local value=0
        for ((i=0; i<remaining_bits; i++)); do
            value=$((value + (1 << (7 - i))))
        done
        mask+="$value"
        full_octets=$((full_octets + 1))
    fi
    
    # Zero octets
    for ((i=full_octets; i<4; i++)); do
        [[ $i -gt 0 ]] && mask+="."
        mask+="0"
    done
    
    echo "$mask"
}

# Find an available IP in the network
find_available_ip() {
    local network="${1:-$DISCOVERED_NETWORK}"
    local start_offset="${2:-50}"  # Start checking from .50
    local max_attempts="${3:-200}"
    
    if [[ -z "$network" ]]; then
        log_error "No network specified"
        return 1
    fi
    
    log_info "Searching for available IP in network $network..."
    
    local base_ip="${network%.*}"
    local found=false
    
    for ((i=start_offset; i<start_offset+max_attempts; i++)); do
        local test_ip="${base_ip}.${i}"
        
        # Skip special addresses
        [[ $i -eq 0 ]] || [[ $i -eq 255 ]] && continue
        
        # Check if IP is in use (ping with short timeout)
        if ! ping -c 1 -W 1 "$test_ip" >/dev/null 2>&1; then
            # Double check with arping if available
            if command_exists arping; then
                if ! arping -c 1 -w 1 "$test_ip" >/dev/null 2>&1; then
                    DISCOVERED_IP="$test_ip"
                    found=true
                    break
                fi
            else
                DISCOVERED_IP="$test_ip"
                found=true
                break
            fi
        fi
    done
    
    if [[ "$found" == "true" ]]; then
        log_success "Found available IP: $DISCOVERED_IP"
        return 0
    else
        log_error "No available IP found in range"
        return 1
    fi
}

# Validate network connectivity
validate_network_connectivity() {
    local gateway="${1:-$DISCOVERED_GATEWAY}"
    
    log_info "Validating network connectivity..."
    
    # Check gateway connectivity
    if ping -c 2 -W 2 "$gateway" >/dev/null 2>&1; then
        log_success "Gateway $gateway is reachable"
    else
        log_error "Cannot reach gateway $gateway"
        return 1
    fi
    
    # Check internet connectivity
    if ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1; then
        log_success "Internet connectivity confirmed"
    else
        log_warn "No internet connectivity detected"
    fi
    
    return 0
}

# Main network discovery function
discover_network() {
    log_info "Starting network discovery..."
    
    # Discover default gateway
    if ! discover_default_gateway; then
        return 1
    fi
    
    # Discover Proxmox bridge
    if ! discover_proxmox_bridge; then
        return 1
    fi
    
    # Get network information
    if ! discover_network_info; then
        return 1
    fi
    
    # Find available IP
    if ! find_available_ip; then
        return 1
    fi
    
    # Validate connectivity
    if ! validate_network_connectivity; then
        log_warn "Network validation failed, but continuing..."
    fi
    
    # Export discovered values
    export DISCOVERED_GATEWAY
    export DISCOVERED_INTERFACE
    export DISCOVERED_BRIDGE
    export DISCOVERED_NETWORK
    export DISCOVERED_NETMASK
    export DISCOVERED_IP
    
    log_success "Network discovery completed successfully"
    return 0
}

# Display discovered network configuration
display_network_config() {
    echo ""
    echo "Discovered Network Configuration:"
    echo "================================="
    echo "Gateway:    ${DISCOVERED_GATEWAY:-Not found}"
    echo "Interface:  ${DISCOVERED_INTERFACE:-Not found}"
    echo "Bridge:     ${DISCOVERED_BRIDGE:-Not found}"
    echo "Network:    ${DISCOVERED_NETWORK:-Not found}"
    echo "Netmask:    ${DISCOVERED_NETMASK:-Not found}"
    echo "Available IP: ${DISCOVERED_IP:-Not found}"
    echo "================================="
    echo ""
}

# Save network configuration to file
save_network_config() {
    local config_file="${1:-/root/.privatebox/network.conf}"
    local config_dir=$(dirname "$config_file")
    
    # Create directory if it doesn't exist
    [[ ! -d "$config_dir" ]] && mkdir -p "$config_dir"
    
    cat > "$config_file" <<EOF
# PrivateBox Network Configuration
# Generated: $(date)

GATEWAY="$DISCOVERED_GATEWAY"
INTERFACE="$DISCOVERED_INTERFACE"
BRIDGE="$DISCOVERED_BRIDGE"
NETWORK="$DISCOVERED_NETWORK"
NETMASK="$DISCOVERED_NETMASK"
STATIC_IP="$DISCOVERED_IP"
EOF
    
    chmod 600 "$config_file"
    log_success "Network configuration saved to $config_file"
}