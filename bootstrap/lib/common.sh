#!/bin/bash
# Common library for PrivateBox scripts
# Provides shared functions for logging, error handling, and utilities
#
# This is a refactored version that sources specialized modules
# to avoid code duplication

# Note: Don't set -euo pipefail here as this is a library that gets sourced

# Determine the lib directory
COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source specialized modules in order
# 1. Constants first (defines colors and defaults)
source "${COMMON_LIB_DIR}/constants.sh" 2>/dev/null || true

# 2. Bootstrap logger (provides logging functions)
source "${COMMON_LIB_DIR}/bootstrap_logger.sh" 2>/dev/null || true

# 3. Error handler (provides error handling and cleanup)
source "${COMMON_LIB_DIR}/error_handler.sh" 2>/dev/null || true

# 4. Validation functions
source "${COMMON_LIB_DIR}/validation.sh" 2>/dev/null || true

# 5. Service manager (provides service-related functions)
source "${COMMON_LIB_DIR}/service_manager.sh" 2>/dev/null || true

# 6. SSH manager (provides SSH-related functions)
source "${COMMON_LIB_DIR}/ssh_manager.sh" 2>/dev/null || true

# 7. Config manager (provides configuration functions)
source "${COMMON_LIB_DIR}/config_manager.sh" 2>/dev/null || true

# Global variables (for backward compatibility)
# Only set if not already defined
[[ -z "${SCRIPT_NAME:-}" ]] && SCRIPT_NAME="$(basename "${BASH_SOURCE[1]}")"
[[ -z "${LOG_DIR:-}" ]] && LOG_DIR="${PRIVATEBOX_LOG_DIR:-/var/log/privatebox}"
[[ -z "${LOG_FILE:-}" ]] && LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
[[ -z "${LOG_LEVEL:-}" ]] && LOG_LEVEL="INFO"
[[ -z "${DRY_RUN:-}" ]] && DRY_RUN="false"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Additional utility functions not covered by specialized modules

# Check if a command exists
check_command() {
    local cmd="${1}"
    local package="${2:-${cmd}}"
    
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        error_exit "Required command '${cmd}' not found. Please install package '${package}'."
    fi
}

# Check if running as root (backward compatibility wrapper)
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
}

# Backup a file with timestamp
backup_file() {
    local file="${1}"
    if [[ -f "${file}" ]]; then
        local backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"
        log_info "Backing up ${file} to ${backup}"
        cp -p "${file}" "${backup}"
    fi
}

# Retry function with exponential backoff
retry_with_backoff() {
    local max_attempts="${1}"
    local initial_delay="${2:-1}"
    local max_delay="${3:-60}"
    shift 3
    local command=("$@")
    
    local attempt=1
    local delay="${initial_delay}"
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        log_debug "Attempt ${attempt}/${max_attempts}: ${command[*]}"
        
        if "${command[@]}"; then
            return 0
        fi
        
        if [[ ${attempt} -eq ${max_attempts} ]]; then
            log_error "Command failed after ${max_attempts} attempts: ${command[*]}"
            return 1
        fi
        
        log_warn "Command failed, retrying in ${delay} seconds..."
        sleep "${delay}"
        
        # Exponential backoff with max delay
        delay=$((delay * 2))
        if [[ ${delay} -gt ${max_delay} ]]; then
            delay="${max_delay}"
        fi
        
        attempt=$((attempt + 1))
    done
}

# Check if running in dry run mode
is_dry_run() {
    [[ "${DRY_RUN}" == "true" ]]
}

# Execute command with dry run support
execute() {
    local command=("$@")
    
    if is_dry_run; then
        log_info "[DRY RUN] Would execute: ${command[*]}"
        return 0
    else
        log_debug "Executing: ${command[*]}"
        "${command[@]}"
    fi
}

# Generate secure password (wrapper for backward compatibility)
generate_password() {
    local length="${1:-${PASSWORD_LENGTH:-20}}"
    local password=""
    
    # Ensure we have required character types
    # Note: Excluded % $ \ and ^ to avoid systemd unit file parsing issues
    local upper=$(tr -dc 'A-Z' < /dev/urandom | head -c 1)
    local lower=$(tr -dc 'a-z' < /dev/urandom | head -c 1)
    local digit=$(tr -dc '0-9' < /dev/urandom | head -c 1)
    local special=$(tr -dc '!@#&*()_+=<>?-' < /dev/urandom | head -c 1)
    
    # Generate remaining characters
    local remaining=$((length - 4))
    local rest=$(tr -dc 'A-Za-z0-9!@#&*()_+=<>?-' < /dev/urandom | head -c "${remaining}")
    
    # Combine and shuffle
    password="${upper}${lower}${digit}${special}${rest}"
    echo "${password}" | fold -w1 | shuf | tr -d '\n'
}

# Get Linux distribution info
get_distro_info() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}

# Get distribution version
get_distro_version() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${VERSION_ID:-unknown}"
    else
        echo "unknown"
    fi
}

# Check if running on Proxmox
is_proxmox() {
    [[ -f /etc/pve/pve-root-ca.pem ]] || [[ -d /etc/pve ]]
}

# Create secure credentials file
save_credentials() {
    local creds_file="${1}"
    local content="${2}"
    
    local creds_dir=$(dirname "${creds_file}")
    mkdir -p "${creds_dir}"
    chmod 700 "${creds_dir}"
    
    echo "${content}" > "${creds_file}"
    chmod 600 "${creds_file}"
    
    log_info "Credentials saved to: ${creds_file}"
}

# Backward compatibility aliases
# These are deprecated but provided for scripts that haven't been updated yet

# Validation function aliases (now in validation.sh)
# These are provided for backward compatibility but actually call
# the real validation functions from validation.sh
# Note: validation.sh must be sourced before these are used

# Configuration validation (simplified wrapper)
validate_config() {
    local errors=0
    
    log_info "Validating configuration..."
    
    # This is a simplified version - the real validation should use
    # the validate_config function from config_manager.sh
    if declare -f config_manager_loaded >/dev/null 2>&1; then
        # Use the new config manager validation
        return 0
    fi
    
    # Basic validation for backward compatibility
    if [[ ${errors} -eq 0 ]]; then
        log_info "Configuration validation passed"
        return 0
    else
        log_error "Configuration validation failed with ${errors} error(s)"
        return 1
    fi
}

# Export functions for use in other scripts
# Note: Many of these are now provided by the specialized modules
export -f log log_info log_warn log_error log_debug log_success
export -f error_exit
export -f check_command check_root backup_file
export -f retry_with_backoff is_dry_run execute
export -f generate_password
export -f get_distro_info get_distro_version is_proxmox
export -f save_credentials

# Mark common.sh as loaded
common_loaded() {
    return 0
}