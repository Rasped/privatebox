#!/bin/bash
# =============================================================================
# Script Name: network-discovery.sh
# Description: Discovers available IP addresses and validates network 
#              configuration for PXE server deployment
# Author: PrivateBox Team
# Date: 2024
# Version: 1.0.0
# =============================================================================
# Usage:
#   ./network-discovery.sh [options]
#
# Options:
#   -h, --help           Show this help message
#   -d, --debug          Enable debug mode
#   --interface <iface>  Specify network interface (auto-detect if not specified)
#   --network <net>      Specify network CIDR (e.g., 192.168.1.0/24)
#   --output <file>      Write configuration to file (default: stdout)
#
# Examples:
#   ./network-discovery.sh
#   ./network-discovery.sh --interface eth0 --network 192.168.1.0/24
#   ./network-discovery.sh --output /tmp/pxe-config.conf
#
# Dependencies:
#   - bash 4.0+
#   - ip command (iproute2)
#   - ping
#   - Common libraries
# =============================================================================
#
# This script:
# 1. Detects network interfaces and their configuration
# 2. Finds available IP addresses for PXE server
# 3. Checks for DHCP server conflicts
# 4. Validates network connectivity
# 5. Generates network configuration

set -euo pipefail

# Source common library for logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || {
    echo "ERROR: Cannot source common library" >&2
    exit 1
}

# Source validation library
if [[ -f "${SCRIPT_DIR}/../lib/validation.sh" ]]; then
    # shellcheck source=../lib/validation.sh
    source "${SCRIPT_DIR}/../lib/validation.sh"
else
    log_warn "Validation library not found, using basic validation"
fi

# =============================================================================
# CONFIGURATION
# =============================================================================

# Load PXE configuration if available
if [[ -n "${PXE_CONFIG_FILE:-}" ]] && [[ -f "${PXE_CONFIG_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${PXE_CONFIG_FILE}"
fi

# Default settings
readonly DEFAULT_IP_START=20
readonly DEFAULT_IP_END=30
readonly DHCP_CHECK_TIMEOUT=5
readonly PING_TIMEOUT=2

# Script behavior
readonly DEBUG="${PXE_DEBUG:-false}"
readonly DRY_RUN="${DRY_RUN:-false}"
AUTO_MODE="false"
VALIDATE_MODE="false"

# Network configuration
SERVER_IP=""
NETWORK_INTERFACE=""
NETWORK_BASE=""
NETMASK=""
GATEWAY=""

# Working directory
readonly WORK_DIR="${WORK_DIR:-/tmp/privatebox-setup}"
readonly CONFIG_FILE="${CONFIG_FILE:-${SCRIPT_DIR}/../config/privatebox.conf}"

# =============================================================================
# LOGGING
# =============================================================================

# Alias for consistency with existing code
log_warning() {
    log_warn "$@"
}

# =============================================================================
# NETWORK DETECTION
# =============================================================================

# Detect available network interfaces
detect_interfaces() {
    log_info "Detecting network interfaces..." >&2
    
    local -a interfaces=()
    
    # Get all active interfaces with IP addresses
    while IFS= read -r line; do
        local iface
        iface="$(echo "${line}" | awk '{print $NF}')"  # Last field is interface name
        local ip
        ip="$(echo "${line}" | awk '{print $2}' | cut -d'/' -f1)"  # Second field is IP/CIDR
        
        # Prioritize Proxmox bridges (vmbr*) for VM networking
        if [[ "$iface" == vmbr* ]]; then
            if [[ -n "$ip" ]] && [[ "$ip" != "127.0.0.1" ]]; then
                interfaces+=("$iface:$ip")
                log_debug "Found interface: $iface with IP: $ip" >&2
            fi
        elif [[ "$iface" != "lo" ]] && [[ "$iface" != docker* ]] && [[ "$iface" != br-* ]] && [[ "$iface" != veth* ]]; then
            if [[ -n "$ip" ]] && [[ "$ip" != "127.0.0.1" ]]; then
                interfaces+=("$iface:$ip")
                log_debug "Found interface: $iface with IP: $ip" >&2
            fi
        fi
    done < <(ip addr show | grep 'inet ' | grep -v '127.0.0.1')
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        log_error "No suitable network interfaces found" >&2
        return 1
    fi
    
    # Return best interface (first non-virtual with IP)
    for interface_info in "${interfaces[@]}"; do
        local iface=$(echo "$interface_info" | cut -d':' -f1)
        local ip=$(echo "$interface_info" | cut -d':' -f2)
        
        log_info "Selected interface: $iface ($ip)" >&2
        echo "$iface:$ip"
        return 0
    done
    
    return 1
}

# Get network information for interface
get_network_info() {
    local interface="$1"
    local current_ip="$2"
    
    log_debug "Getting network information for $interface"
    
    # Get network base (first 3 octets)
    NETWORK_BASE=$(echo "$current_ip" | cut -d'.' -f1-3)
    
    # Get netmask from route table
    NETMASK=$(ip route | grep "$interface" | grep "${NETWORK_BASE}\.0/" | head -1 | awk '{print $1}' | cut -d'/' -f2)
    
    # Get gateway
    GATEWAY=$(ip route | grep default | grep "$interface" | awk '{print $3}' | head -1)
    
    log_debug "Network base: $NETWORK_BASE"
    log_debug "Netmask: /$NETMASK"
    log_debug "Gateway: $GATEWAY"
    
    if [[ -z "$NETWORK_BASE" ]]; then
        log_error "Could not determine network base for $interface"
        return 1
    fi
}

# =============================================================================
# IP AVAILABILITY CHECKING
# =============================================================================

# Check if IP address is available
check_ip_available() {
    local ip="$1"
    
    log_debug "Checking availability of IP: $ip"
    
    # In dry run mode, just check ping (faster and more accurate)
    if [[ "$DRY_RUN" == "true" ]]; then
        if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
            log_debug "IP $ip is in use (ping response)"
            return 1
        fi
        log_debug "IP $ip appears to be available"
        return 0
    fi
    
    # Ping test
    if ping -c 1 -W "$PING_TIMEOUT" "$ip" >/dev/null 2>&1; then
        log_debug "IP $ip is in use (ping response)"
        return 1
    fi
    
    # ARP table check (only in non-dry-run mode and only if entry shows complete)
    if arp -n "$ip" 2>/dev/null | grep -q "ether.*C"; then
        log_debug "IP $ip found in ARP table (complete entry)"
        return 1
    fi
    
    log_debug "IP $ip appears to be available"
    return 0
}

# Find available IP address
find_available_ip() {
    local network_base="$1"
    local start_ip="${2:-$DEFAULT_IP_START}"
    local end_ip="${3:-$DEFAULT_IP_END}"
    
    log_info "Searching for available IP in range ${network_base}.${start_ip}-${end_ip}" >&2
    
    for ((i=start_ip; i<=end_ip; i++)); do
        local test_ip="${network_base}.${i}"
        
        if check_ip_available "$test_ip"; then
            log_success "Found available IP: $test_ip" >&2
            echo "$test_ip"
            return 0
        fi
    done
    
    log_error "No available IP addresses found in range ${network_base}.${start_ip}-${end_ip}" >&2
    return 1
}

# =============================================================================
# NETWORK INTERFACE DETECTION  
# =============================================================================

# Check for existing DHCP servers (kept for compatibility, but simplified)
check_dhcp_conflicts() {
    local interface="$1"
    
    log_info "Checking for DHCP server conflicts on $interface"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would check for DHCP conflicts"
        return 0
    fi
    
    # Check if dnsmasq is already running
    if systemctl is-active --quiet dnsmasq 2>/dev/null; then
        log_warning "dnsmasq service is already running"
        
        # Check if it's configured for DHCP
        if grep -q "dhcp-range" /etc/dnsmasq.conf /etc/dnsmasq.d/* 2>/dev/null; then
            log_error "Existing DHCP configuration found in dnsmasq"
            return 1
        fi
    fi
    
    # Check for other DHCP services
    local dhcp_services=("isc-dhcp-server" "dhcpd" "kea-dhcp4-server")
    
    for service in "${dhcp_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log_error "Conflicting DHCP service is running: $service"
            return 1
        fi
    done
    
    # Try to detect DHCP responses on the network
    log_debug "Testing for active DHCP servers..."
    
    # Use dhcping if available, otherwise skip this test
    if command -v dhcping >/dev/null 2>&1; then
        if timeout "$DHCP_CHECK_TIMEOUT" dhcping -c 1 -i "$interface" 2>/dev/null; then
            log_warning "Active DHCP server detected on network"
            log_warning "This may cause conflicts - proceed with caution"
        else
            log_success "No active DHCP servers detected"
        fi
    else
        log_debug "dhcping not available, skipping DHCP detection"
    fi
    
    return 0
}

# =============================================================================
# NETWORK VALIDATION
# =============================================================================

# Validate network configuration
validate_network_config() {
    local server_ip="$1"
    local interface="$2"
    
    log_info "Validating network configuration"
    log_info "Server IP: $server_ip"
    log_info "Interface: $interface"
    
    # Check if interface exists
    if ! ip link show "$interface" >/dev/null 2>&1; then
        log_error "Network interface does not exist: $interface"
        return 1
    fi
    
    # Check if interface is up
    if ! ip link show "$interface" | grep -q "state UP"; then
        log_error "Network interface is not up: $interface"
        return 1
    fi
    
    # Validate IP format
    if ! [[ "$server_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_error "Invalid IP address format: $server_ip"
        return 1
    fi
    
    # Check if IP is in same network as interface
    local current_ip=$(ip addr show "$interface" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1)
    local current_network=$(echo "$current_ip" | cut -d'.' -f1-3)
    local target_network=$(echo "$server_ip" | cut -d'.' -f1-3)
    
    if [[ "$current_network" != "$target_network" ]]; then
        log_error "Server IP $server_ip is not in same network as interface $interface ($current_network.x)"
        return 1
    fi
    
    # Check if IP is available
    if ! check_ip_available "$server_ip"; then
        log_error "IP address is not available: $server_ip"
        return 1
    fi
    
    log_success "Network configuration validation passed"
    return 0
}

# =============================================================================
# CONFIGURATION OUTPUT
# =============================================================================

# Save network configuration
save_network_config() {
    log_info "Saving network configuration to $CONFIG_FILE"
    
    mkdir -p "$(dirname "$CONFIG_FILE")"
    
    # Get current host IP
    local current_ip=$(ip addr show "$NETWORK_INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1)
    
    # Create or update configuration file with PrivateBox format
    cat > "$CONFIG_FILE" << EOF
# PrivateBox Configuration File
# This file contains default configuration values for PrivateBox scripts
# Generated by network discovery at: $(date)

# VM Configuration
VMID=9000
UBUNTU_VERSION="24.04"
VM_USERNAME="ubuntuadmin"
VM_PASSWORD="Changeme123"
SEMAPHORE_ADMIN_PASSWORD=""
VM_MEMORY=4096
VM_CORES=2

# Network Configuration (Auto-discovered)
STATIC_IP="$SERVER_IP"
GATEWAY="$GATEWAY"
NET_BRIDGE="$NETWORK_INTERFACE"
NETMASK="$NETMASK"

# Storage Configuration
STORAGE="local-lvm"
VM_DISK_SIZE="40G"

# Service Configuration
PORTAINER_PORT=9000
SEMAPHORE_PORT=3000
SEMAPHORE_DB_PORT=3306

# Paths and Directories
SNIPPETS_DIR="/var/lib/vz/snippets"
LOG_DIR="/var/log/privatebox"
CREDENTIALS_DIR="/root/.credentials"

# Download Configuration
CLOUD_IMG_BASE_URL="https://cloud-images.ubuntu.com/releases"
DOWNLOAD_RETRIES=3
DOWNLOAD_TIMEOUT=300

# SSH Configuration
SSH_KEY_PATH=""  # Set to your SSH public key path
ENABLE_SSH_PASSWORD_AUTH=true

# Proxmox Host Configuration (for Ansible automation)
PROXMOX_HOST="$current_ip"  # Auto-detected current host
PROXMOX_USER="root"  # User for SSH/API access to Proxmox
PROXMOX_SSH_PORT=22  # SSH port for Proxmox host

# Security Configuration
ENABLE_UFW=true
FAIL2BAN_ENABLED=false

# Development/Debug Configuration
DRY_RUN=false
LOG_LEVEL="INFO"
DEBUG_MODE=false
EOF
    
    log_success "Network configuration saved"
}

# =============================================================================
# AUTO DISCOVERY
# =============================================================================

# Auto-discover network configuration
auto_discover() {
    log_info "Starting automatic network discovery"
    
    # Detect network interface
    local interface_info
    interface_info=$(detect_interfaces) || return 1
    
    NETWORK_INTERFACE=$(echo "$interface_info" | cut -d':' -f1)
    local current_ip=$(echo "$interface_info" | cut -d':' -f2)
    
    # Get network information
    get_network_info "$NETWORK_INTERFACE" "$current_ip" || return 1
    
    # Check for DHCP conflicts
    check_dhcp_conflicts "$NETWORK_INTERFACE" || return 1
    
    # Find available IP
    SERVER_IP=$(find_available_ip "$NETWORK_BASE") || return 1
    
    # Save configuration
    save_network_config
    
    log_success "Auto-discovery completed successfully"
    log_info "Selected configuration:"
    log_info "  Interface: $NETWORK_INTERFACE"
    log_info "  Server IP: $SERVER_IP"
    log_info "  Network: ${NETWORK_BASE}.0/$NETMASK"
    log_info "  Gateway: $GATEWAY"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --dry-run)
                DRY_RUN="true"
                shift
                ;;
            --debug)
                DEBUG="true"
                shift
                ;;
            --auto)
                AUTO_MODE="true"
                shift
                ;;
            --validate)
                VALIDATE_MODE="true"
                shift
                ;;
            --server-ip)
                if command -v validate_input >/dev/null 2>&1; then
                    if ! validate_input "$2" "ip"; then
                        echo "Error: Invalid IP address: $2" >&2
                        exit 1
                    fi
                fi
                SERVER_IP="$2"
                shift 2
                ;;
            --interface)
                NETWORK_INTERFACE="$2"
                shift 2
                ;;
            --network-base)
                # Validate network base format (e.g., 192.168.1)
                if [[ ! "$2" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                    echo "Error: Invalid network base format: $2" >&2
                    echo "Expected format: xxx.xxx.xxx (e.g., 192.168.1)" >&2
                    exit 1
                fi
                NETWORK_BASE="$2"
                shift 2
                ;;
            *)
                echo "Unknown argument: $1" >&2
                echo "Use --help for usage information" >&2
                exit 1
                ;;
        esac
    done
}

# Show help information
show_help() {
    cat << 'EOF'
Usage: network-discovery.sh [OPTIONS]

Discover and validate network configuration for PXE server setup.

OPTIONS:
    --auto                  Auto-discover network configuration
    --validate              Validate provided configuration
    --server-ip IP          Server IP address to validate
    --interface IFACE       Network interface to use
    --network-base BASE     Network base (e.g., 192.168.1)
    --dry-run               Run in dry-run mode
    --debug                 Enable debug logging
    --help                  Show this help message

EXAMPLES:
    # Auto-discover configuration
    network-discovery.sh --auto
    
    # Validate specific configuration
    network-discovery.sh --validate --server-ip 192.168.1.11 --interface eth0
    
    # Debug mode
    network-discovery.sh --auto --debug

The script will detect network interfaces, find available IP addresses,
check for DHCP conflicts, and generate configuration for the PXE server.
EOF
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

# Main function
main() {
    parse_arguments "$@"
    
    mkdir -p "$WORK_DIR"
    
    log_info "Starting network discovery"
    log_debug "Auto mode: $AUTO_MODE"
    log_debug "Validate mode: $VALIDATE_MODE"
    log_debug "Dry run: $DRY_RUN"
    
    if [[ "$AUTO_MODE" == "true" ]]; then
        auto_discover || exit 1
    elif [[ "$VALIDATE_MODE" == "true" ]]; then
        if [[ -z "$SERVER_IP" ]] || [[ -z "$NETWORK_INTERFACE" ]]; then
            log_error "Validation mode requires --server-ip and --interface"
            exit 1
        fi
        
        validate_network_config "$SERVER_IP" "$NETWORK_INTERFACE" || exit 1
        
        # Get network info and save config
        local current_ip=$(ip addr show "$NETWORK_INTERFACE" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1 | head -1)
        get_network_info "$NETWORK_INTERFACE" "$current_ip" || exit 1
        save_network_config
    else
        log_error "Must specify either --auto or --validate mode"
        exit 1
    fi
    
    log_success "Network discovery completed successfully"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi