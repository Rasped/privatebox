#!/bin/bash
# Config Manager for PrivateBox
# Checks configuration, generates missing fields, manages passwords

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
CONFIG_FILE="${CONFIG_DIR}/privatebox.conf"

# Source password generator only - avoid common.sh log directory creation
source "${SCRIPT_DIR}/password-generator.sh"

# Simple logging functions that don't create directories
log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[SUCCESS] $*"
}

# Configuration defaults
declare -A REQUIRED_FIELDS=(
    ["CONTAINER_HOST_IP"]=""
    ["CADDY_HOST_IP"]=""
    ["OPNSENSE_IP"]=""
    ["GATEWAY"]=""
    ["ADMIN_PASSWORD"]=""
    ["SERVICES_PASSWORD"]=""
)

declare -A OPTIONAL_FIELDS=(
    ["VM_MEMORY"]="4096"
    ["VM_CORES"]="2"
    ["VM_DISK_SIZE"]="40G"
    ["VM_USERNAME"]="ubuntuadmin"
    ["VM_STORAGE"]="local-lvm"
    ["VM_NET_BRIDGE"]="vmbr0"
)

# Detect network configuration
detect_network() {
    local gateway=""
    local base_network=""
    
    # Try to detect gateway
    if command -v ip >/dev/null 2>&1; then
        gateway=$(ip route | grep default | head -1 | awk '{print $3}' || true)
    fi
    
    # Fallback to default if detection fails
    if [[ -z "$gateway" ]]; then
        gateway="192.168.1.3"
        log_warn "Could not detect gateway, using default: $gateway"
    fi
    
    # Extract base network (e.g., 192.168.1.3 -> 192.168.1)
    base_network=$(echo "$gateway" | cut -d. -f1-3)
    
    echo "$gateway|$base_network"
}

# Load existing configuration
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Source the config file to get existing values
        source "$CONFIG_FILE"
        return 0
    fi
    return 1
}

# Check if a field exists and has a value
field_exists() {
    local field_name="$1"
    local field_value="${!field_name:-}"
    
    [[ -n "$field_value" ]]
}

# Generate missing configuration
generate_missing_config() {
    local network_info=$(detect_network)
    local gateway="${network_info%|*}"
    local base_network="${network_info#*|}"
    local generated_fields=()
    
    # Set gateway if not already set
    if ! field_exists "GATEWAY"; then
        GATEWAY="$gateway"
        generated_fields+=("GATEWAY=$GATEWAY")
    fi
    
    # Generate IPs based on detected network
    if ! field_exists "CONTAINER_HOST_IP"; then
        CONTAINER_HOST_IP="${base_network}.20"
        generated_fields+=("CONTAINER_HOST_IP=$CONTAINER_HOST_IP")
    fi
    
    if ! field_exists "CADDY_HOST_IP"; then
        CADDY_HOST_IP="${base_network}.21"
        generated_fields+=("CADDY_HOST_IP=$CADDY_HOST_IP")
    fi
    
    if ! field_exists "OPNSENSE_IP"; then
        OPNSENSE_IP="${base_network}.47"
        generated_fields+=("OPNSENSE_IP=$OPNSENSE_IP")
    fi
    
    # Generate passwords if missing
    if ! field_exists "ADMIN_PASSWORD"; then
        ADMIN_PASSWORD=$(generate_password admin)
        generated_fields+=("ADMIN_PASSWORD=$ADMIN_PASSWORD")
    fi
    
    if ! field_exists "SERVICES_PASSWORD"; then
        SERVICES_PASSWORD=$(generate_password services)
        generated_fields+=("SERVICES_PASSWORD=$SERVICES_PASSWORD")
    fi
    
    # Set optional fields to defaults if not set
    for field in "${!OPTIONAL_FIELDS[@]}"; do
        if ! field_exists "$field"; then
            eval "$field=\"${OPTIONAL_FIELDS[$field]}\""
        fi
    done
    
    # Return list of generated fields
    printf '%s\n' "${generated_fields[@]}"
}

# Write configuration to file
write_config() {
    local update_only="${1:-false}"
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Full write mode - always rewrite the entire file
    cat > "$CONFIG_FILE" << EOF
# PrivateBox Configuration File
# Generated on $(date)
# This file contains configuration for PrivateBox installation

# Network Configuration
GATEWAY="${GATEWAY:-}"
CONTAINER_HOST_IP="${CONTAINER_HOST_IP:-}"
CADDY_HOST_IP="${CADDY_HOST_IP:-}"
OPNSENSE_IP="${OPNSENSE_IP:-}"

# Security Configuration
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
SERVICES_PASSWORD="${SERVICES_PASSWORD:-}"

# VM Configuration
VM_USERNAME="${VM_USERNAME:-ubuntuadmin}"
VM_MEMORY="${VM_MEMORY:-4096}"
VM_CORES="${VM_CORES:-2}"
VM_DISK_SIZE="${VM_DISK_SIZE:-40G}"
VM_STORAGE="${VM_STORAGE:-local-lvm}"
VM_NET_BRIDGE="${VM_NET_BRIDGE:-vmbr0}"
EOF
    
    # Set secure permissions
    chmod 600 "$CONFIG_FILE"
}

# Show current configuration
show_config() {
    echo "=== Current Configuration ==="
    echo ""
    
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Config file: $CONFIG_FILE"
        echo ""
        
        # Load the config
        load_config
        
        echo "Network Configuration:"
        echo "  Gateway: ${GATEWAY:-<not set>}"
        echo "  Container Host IP: ${CONTAINER_HOST_IP:-<not set>}"
        echo "  Caddy Host IP: ${CADDY_HOST_IP:-<not set>}"
        echo "  OPNsense IP: ${OPNSENSE_IP:-<not set>}"
        echo ""
        
        echo "Security Configuration:"
        if field_exists "ADMIN_PASSWORD"; then
            echo "  Admin Password: <set>"
        else
            echo "  Admin Password: <not set>"
        fi
        if field_exists "SERVICES_PASSWORD"; then
            echo "  Services Password: <set>"
        else
            echo "  Services Password: <not set>"
        fi
        echo ""
        
        echo "VM Configuration:"
        echo "  Username: ${VM_USERNAME:-<not set>}"
        echo "  Memory: ${VM_MEMORY:-<not set>}"
        echo "  Cores: ${VM_CORES:-<not set>}"
        echo "  Disk Size: ${VM_DISK_SIZE:-<not set>}"
    else
        echo "No configuration file found at: $CONFIG_FILE"
    fi
}

# Regenerate passwords
regenerate_passwords() {
    log_info "Regenerating passwords..."
    
    ADMIN_PASSWORD=$(generate_password admin)
    SERVICES_PASSWORD=$(generate_password services)
    
    echo "New passwords generated:"
    echo "  Admin Password: $ADMIN_PASSWORD"
    echo "  Services Password: $SERVICES_PASSWORD"
    echo ""
    echo "WARNING: This will overwrite existing passwords!"
    read -p "Continue? (y/N) " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Main function
main() {
    local action="${1:-check}"
    
    case "$action" in
        check|--check)
            log_info "Checking configuration..."
            
            # Load existing config if available
            if load_config; then
                log_info "Found existing configuration"
            else
                log_info "No configuration found, will generate defaults"
            fi
            
            # Generate missing fields
            # Note: We need to capture the output AND ensure variables are set
            local generated_output=$(generate_missing_config)
            local generated=()
            if [[ -n "$generated_output" ]]; then
                mapfile -t generated <<< "$generated_output"
            fi
            
            # Re-run generation to set variables in current shell
            generate_missing_config >/dev/null
            
            if [[ ${#generated[@]} -gt 0 ]]; then
                echo ""
                echo "Generated missing fields:"
                local show_admin_pass=""
                local show_services_pass=""
                for field in "${generated[@]}"; do
                    echo "  $field"
                    # Extract passwords for display
                    if [[ "$field" =~ ^ADMIN_PASSWORD=(.*)$ ]]; then
                        show_admin_pass="${BASH_REMATCH[1]}"
                    elif [[ "$field" =~ ^SERVICES_PASSWORD=(.*)$ ]]; then
                        show_services_pass="${BASH_REMATCH[1]}"
                    fi
                done
                echo ""
                
                # Write configuration
                write_config
                log_success "Configuration updated: $CONFIG_FILE"
                
                if [[ -n "$show_admin_pass" ]] || [[ -n "$show_services_pass" ]]; then
                    echo ""
                    echo "IMPORTANT: Please save these passwords securely!"
                    [[ -n "$show_admin_pass" ]] && echo "  Admin Password: $show_admin_pass"
                    [[ -n "$show_services_pass" ]] && echo "  Services Password: $show_services_pass"
                fi
            else
                log_success "All required fields are present"
            fi
            ;;
            
        show|--show)
            show_config
            ;;
            
        regenerate-passwords|--regenerate-passwords)
            # Load existing config
            load_config
            
            if regenerate_passwords; then
                write_config
                log_success "Passwords regenerated and saved"
            else
                log_info "Password regeneration cancelled"
            fi
            ;;
            
        help|--help)
            cat << EOF
Usage: $0 [COMMAND]

Commands:
  check, --check                  Check configuration and generate missing fields (default)
  show, --show                    Display current configuration
  regenerate-passwords            Generate new passwords (will prompt for confirmation)
  help, --help                    Show this help message

This script manages the PrivateBox configuration file, ensuring all required
fields are present and generating secure defaults for missing values.

Configuration file location: $CONFIG_FILE
EOF
            ;;
            
        *)
            log_error "Unknown command: $action"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"