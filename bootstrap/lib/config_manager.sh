#!/bin/bash
# Config Manager - Consolidated configuration management functions
# 
# This module provides functions for loading, validating, and managing
# configuration files across the PrivateBox bootstrap system.

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/bootstrap_logger.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/constants.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/validation.sh" 2>/dev/null || true

# Default configuration paths
CONFIG_SEARCH_PATHS=(
    "${PRIVATEBOX_CONFIG_DIR:-/etc/privatebox}"
    "${HOME}/.privatebox"
    "/opt/privatebox/config"
    "./config"
    "../config"
)

# Load configuration file with validation
load_config() {
    local config_file="${1}"
    local required_vars=("${@:2}")
    
    if [[ ! -f "${config_file}" ]]; then
        log_error "Configuration file not found: ${config_file}"
        return 1
    fi
    
    log_info "Loading configuration from: ${config_file}"
    
    # Check file permissions
    local file_perms=$(stat -c %a "${config_file}" 2>/dev/null || stat -f %p "${config_file}" 2>/dev/null | cut -c 4-6)
    if [[ "${file_perms}" != "600" ]] && [[ "${file_perms}" != "400" ]]; then
        log_warn "Configuration file has insecure permissions: ${file_perms}"
        log_warn "Recommended permissions: 600 or 400"
    fi
    
    # Source the configuration file
    # shellcheck source=/dev/null
    if ! source "${config_file}"; then
        log_error "Failed to source configuration file"
        return 1
    fi
    
    # Validate required variables if specified
    if [[ ${#required_vars[@]} -gt 0 ]]; then
        local missing_vars=()
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                missing_vars+=("${var}")
            fi
        done
        
        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            log_error "Missing required configuration variables: ${missing_vars[*]}"
            return 1
        fi
    fi
    
    log_info "Configuration loaded successfully"
    return 0
}

# Find configuration file in standard locations
find_config() {
    local config_name="${1:-privatebox.conf}"
    
    # Check explicit path first
    if [[ -f "${config_name}" ]]; then
        echo "${config_name}"
        return 0
    fi
    
    # Search in standard paths
    for path in "${CONFIG_SEARCH_PATHS[@]}"; do
        local config_path="${path}/${config_name}"
        if [[ -f "${config_path}" ]]; then
            log_debug "Found configuration at: ${config_path}"
            echo "${config_path}"
            return 0
        fi
    done
    
    log_debug "Configuration file not found: ${config_name}"
    return 1
}

# Create default configuration
create_default_config() {
    local config_file="${1}"
    local template_file="${2:-}"
    
    log_info "Creating default configuration: ${config_file}"
    
    # Create directory if needed
    local config_dir=$(dirname "${config_file}")
    if [[ ! -d "${config_dir}" ]]; then
        mkdir -p "${config_dir}"
        chmod 755 "${config_dir}"
    fi
    
    # Use template if provided
    if [[ -n "${template_file}" ]] && [[ -f "${template_file}" ]]; then
        cp "${template_file}" "${config_file}"
    else
        # Create basic configuration
        cat > "${config_file}" <<EOF
# PrivateBox Configuration
# Generated on $(date)

# VM Configuration
VM_ID="${DEFAULT_VM_ID}"
VM_NAME="${DEFAULT_VM_NAME}"
VM_CORES="${DEFAULT_VM_CORES}"
VM_MEMORY="${DEFAULT_VM_MEMORY}"
VM_DISK_SIZE="${DEFAULT_VM_DISK_SIZE}"

# Network Configuration
VM_BRIDGE="${DEFAULT_VM_BRIDGE}"
# VM_IP=""  # Leave empty for DHCP
# VM_GATEWAY=""
# VM_NETMASK="${DEFAULT_NETMASK}"

# User Configuration
VM_USERNAME="${DEFAULT_USERNAME}"
VM_PASSWORD=""  # Will be generated if not set

# Storage Configuration
STORAGE="${DEFAULT_STORAGE}"

# Service Ports
PORTAINER_PORT="${PORTAINER_PORT}"
SEMAPHORE_PORT="${SEMAPHORE_PORT}"
EOF
    fi
    
    # Set secure permissions
    chmod "${CONFIG_FILE_MODE:-600}" "${config_file}"
    
    log_info "Default configuration created"
    return 0
}

# Merge configuration with defaults
merge_config_with_defaults() {
    # VM Configuration
    VM_ID="${VM_ID:-${DEFAULT_VM_ID}}"
    VM_NAME="${VM_NAME:-${DEFAULT_VM_NAME}}"
    VM_CORES="${VM_CORES:-${DEFAULT_VM_CORES}}"
    VM_MEMORY="${VM_MEMORY:-${DEFAULT_VM_MEMORY}}"
    VM_DISK_SIZE="${VM_DISK_SIZE:-${DEFAULT_VM_DISK_SIZE}}"
    
    # Network Configuration
    VM_BRIDGE="${VM_BRIDGE:-${DEFAULT_VM_BRIDGE}}"
    VM_NETMASK="${VM_NETMASK:-${DEFAULT_NETMASK}}"
    VM_DNS1="${VM_DNS1:-${DEFAULT_DNS1}}"
    VM_DNS2="${VM_DNS2:-${DEFAULT_DNS2}}"
    
    # User Configuration
    VM_USERNAME="${VM_USERNAME:-${DEFAULT_USERNAME}}"
    
    # Storage Configuration
    STORAGE="${STORAGE:-${DEFAULT_STORAGE}}"
    
    # Service Ports
    PORTAINER_PORT="${PORTAINER_PORT:-${DEFAULT_PORTAINER_PORT}}"
    SEMAPHORE_PORT="${SEMAPHORE_PORT:-${DEFAULT_SEMAPHORE_PORT}}"
    
    log_debug "Configuration merged with defaults"
}

# Validate configuration
validate_config() {
    local errors=0
    
    log_info "Validating configuration..."
    
    # Validate VM ID
    if ! validate_input "number" "${VM_ID}" 1 999999; then
        log_error "Invalid VM ID: ${VM_ID}"
        ((errors++))
    fi
    
    # Validate VM resources
    if ! validate_input "number" "${VM_CORES}" 1 128; then
        log_error "Invalid VM cores: ${VM_CORES}"
        ((errors++))
    fi
    
    if ! validate_input "number" "${VM_MEMORY}" 512 999999; then
        log_error "Invalid VM memory: ${VM_MEMORY}"
        ((errors++))
    fi
    
    # Validate network settings if provided
    if [[ -n "${VM_IP:-}" ]]; then
        if ! validate_input "ip" "${VM_IP}"; then
            log_error "Invalid VM IP address: ${VM_IP}"
            ((errors++))
        fi
    fi
    
    if [[ -n "${VM_GATEWAY:-}" ]]; then
        if ! validate_input "ip" "${VM_GATEWAY}"; then
            log_error "Invalid gateway IP: ${VM_GATEWAY}"
            ((errors++))
        fi
    fi
    
    # Validate ports
    if ! validate_input "port" "${PORTAINER_PORT}"; then
        log_error "Invalid Portainer port: ${PORTAINER_PORT}"
        ((errors++))
    fi
    
    if ! validate_input "port" "${SEMAPHORE_PORT}"; then
        log_error "Invalid Semaphore port: ${SEMAPHORE_PORT}"
        ((errors++))
    fi
    
    if [[ ${errors} -gt 0 ]]; then
        log_error "Configuration validation failed with ${errors} error(s)"
        return 1
    fi
    
    log_info "Configuration validation passed"
    return 0
}

# Export configuration as environment variables
export_config() {
    # Export all VM_ prefixed variables
    local var
    for var in $(compgen -v VM_); do
        export "${var}"
    done
    
    # Export service variables
    export PORTAINER_PORT SEMAPHORE_PORT
    export STORAGE
    
    log_debug "Configuration exported to environment"
}

# Save configuration to file
save_config() {
    local config_file="${1}"
    local vars_to_save=("${@:2}")
    
    log_info "Saving configuration to: ${config_file}"
    
    # Create directory if needed
    local config_dir=$(dirname "${config_file}")
    if [[ ! -d "${config_dir}" ]]; then
        mkdir -p "${config_dir}"
        chmod 755 "${config_dir}"
    fi
    
    # Start with header
    {
        echo "# PrivateBox Configuration"
        echo "# Saved on $(date)"
        echo ""
    } > "${config_file}"
    
    # Save specified variables or all if none specified
    if [[ ${#vars_to_save[@]} -eq 0 ]]; then
        # Save all relevant variables
        vars_to_save=(
            VM_ID VM_NAME VM_CORES VM_MEMORY VM_DISK_SIZE
            VM_BRIDGE VM_IP VM_GATEWAY VM_NETMASK VM_DNS1 VM_DNS2
            VM_USERNAME VM_PASSWORD
            STORAGE
            PORTAINER_PORT SEMAPHORE_PORT
        )
    fi
    
    # Write variables
    for var in "${vars_to_save[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            echo "${var}=\"${!var}\"" >> "${config_file}"
        fi
    done
    
    # Set secure permissions
    chmod "${CONFIG_FILE_MODE:-600}" "${config_file}"
    
    log_info "Configuration saved"
    return 0
}

# Function to check if module is loaded
config_manager_loaded() {
    return 0
}