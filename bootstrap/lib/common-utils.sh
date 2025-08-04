#!/bin/bash
# Common utilities for PrivateBox bootstrap
# Minimal set of actually used functions

# Exit codes
EXIT_MISSING_DEPS=2

# Ensure we have logging functions available
if ! declare -f log_info >/dev/null 2>&1; then
    # Basic fallback logging if not available
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*"; }
fi

# Check if required command exists
require_command() {
    local cmd="${1}"
    local message="${2:-Command required}"
    
    if ! command -v "${cmd}" &> /dev/null; then
        log_error "${message}: ${cmd}"
        exit ${EXIT_MISSING_DEPS}
    fi
}

# Validate IP address format
validate_ip() {
    local ip="${1:-}"
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    # Check if empty
    if [[ -z "$ip" ]]; then
        log_debug "IP validation failed: empty input"
        return 1
    fi
    
    # Check format
    if [[ ! "$ip" =~ $valid_ip_regex ]]; then
        log_debug "IP validation failed: invalid format - $ip"
        return 1
    fi
    
    # Check each octet
    local IFS='.'
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        # Remove leading zeros to prevent octal interpretation
        octet=$((10#$octet))
        if [[ $octet -gt 255 ]]; then
            log_debug "IP validation failed: octet out of range - $octet"
            return 1
        fi
    done
    
    return 0
}

# Note: validate_config is provided by config_manager.sh

# Cleanup arrays
CLEANUP_FUNCTIONS=()
TEMP_FILES=()
TEMP_DIRS=()

# Register a cleanup function
register_cleanup() {
    local func="${1}"
    CLEANUP_FUNCTIONS+=("${func}")
    log_debug "Registered cleanup function: ${func}"
}

# Setup error handling
setup_error_handling() {
    set -euo pipefail
    
    # Simple error trap
    trap 'echo "[ERROR] Error occurred at line $LINENO" >&2; exit 1' ERR
    
    # Simple cleanup on exit
    trap 'for func in "${CLEANUP_FUNCTIONS[@]}"; do $func || true; done' EXIT INT TERM
    
    log_debug "Error handling configured"
}

# Export functions
export -f require_command
export -f validate_ip
export -f register_cleanup
export -f setup_error_handling