#!/bin/bash
# Common library for PrivateBox scripts
# Provides shared functions for logging, error handling, and utilities

# Enable strict error handling
set -euo pipefail

# Global variables
SCRIPT_NAME="${SCRIPT_NAME:-$(basename "${BASH_SOURCE[1]}")}"
LOG_DIR="${LOG_DIR:-/var/log/privatebox}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/${SCRIPT_NAME}.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
DRY_RUN="${DRY_RUN:-false}"

# Color codes for output
if [[ -z "${COLOR_RED:-}" ]]; then
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_YELLOW='\033[1;33m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_NC='\033[0m' # No Color
fi

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# Logging functions
log() {
    local level="${1}"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}"
    
    # Log to console with colors
    case "${level}" in
        ERROR)
            echo -e "${COLOR_RED}[${timestamp}] [${level}] ${message}${COLOR_NC}" >&2
            ;;
        WARN)
            echo -e "${COLOR_YELLOW}[${timestamp}] [${level}] ${message}${COLOR_NC}" >&2
            ;;
        INFO)
            echo -e "${COLOR_GREEN}[${timestamp}] [${level}] ${message}${COLOR_NC}"
            ;;
        DEBUG)
            if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
                echo -e "${COLOR_BLUE}[${timestamp}] [${level}] ${message}${COLOR_NC}"
            fi
            ;;
        *)
            echo "[${timestamp}] [${level}] ${message}"
            ;;
    esac
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

log_debug() {
    log "DEBUG" "$@"
}

log_success() {
    log "INFO" "$@"
}

# Error handling
error_exit() {
    local message="${1:-Unknown error}"
    local exit_code="${2:-1}"
    log_error "${message}"
    exit "${exit_code}"
}

# Trap handler for cleanup
cleanup_handler() {
    local exit_code=$?
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "Script failed with exit code: ${exit_code}"
    fi
    # Call script-specific cleanup function if defined
    if declare -f cleanup >/dev/null; then
        cleanup
    fi
    exit ${exit_code}
}

# Set trap for cleanup
trap cleanup_handler EXIT ERR INT TERM

# Utility functions
check_command() {
    local cmd="${1}"
    local package="${2:-${cmd}}"
    
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        error_exit "Required command '${cmd}' not found. Please install package '${package}'."
    fi
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
}

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

# Wait for service to be ready
wait_for_service() {
    local service="${1}"
    local port="${2}"
    local timeout="${3:-60}"
    local host="${4:-localhost}"
    
    log_info "Waiting for ${service} to be ready on ${host}:${port}..."
    
    local elapsed=0
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if nc -z "${host}" "${port}" 2>/dev/null; then
            log_info "${service} is ready"
            return 0
        fi
        
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    log_error "${service} failed to become ready within ${timeout} seconds"
    return 1
}

# Generate secure password
generate_password() {
    local length="${1:-20}"
    local password=""
    
    # Ensure we have required character types
    local upper=$(tr -dc 'A-Z' < /dev/urandom | head -c 1)
    local lower=$(tr -dc 'a-z' < /dev/urandom | head -c 1)
    local digit=$(tr -dc '0-9' < /dev/urandom | head -c 1)
    local special=$(tr -dc '!@#$%^&*()_+=<>?-' < /dev/urandom | head -c 1)
    
    # Generate remaining characters
    local remaining=$((length - 4))
    local rest=$(tr -dc 'A-Za-z0-9!@#$%^&*()_+=<>?-' < /dev/urandom | head -c "${remaining}")
    
    # Combine and shuffle
    password="${upper}${lower}${digit}${special}${rest}"
    echo "${password}" | fold -w1 | shuf | tr -d '\n'
}

# Validate IP address
validate_ip() {
    local ip="${1}"
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ ! ${ip} =~ ${valid_ip_regex} ]]; then
        return 1
    fi
    
    # Check each octet
    local IFS='.'
    read -ra octets <<< "${ip}"
    for octet in "${octets[@]}"; do
        if [[ ${octet} -gt 255 ]]; then
            return 1
        fi
    done
    
    return 0
}

# Validate hostname or IP address
validate_host() {
    local host="${1}"
    
    # Empty host is invalid
    if [[ -z "${host}" ]]; then
        return 1
    fi
    
    # Try IP validation first
    if validate_ip "${host}"; then
        return 0
    fi
    
    # Validate hostname format
    local hostname_regex='^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$'
    if [[ ${host} =~ ${hostname_regex} ]]; then
        return 0
    fi
    
    return 1
}

# Validate port number
validate_port() {
    local port="${1}"
    
    # Check if it's a number
    if [[ ! ${port} =~ ^[0-9]+$ ]]; then
        return 1
    fi
    
    # Check range (1-65535)
    if [[ ${port} -lt 1 || ${port} -gt 65535 ]]; then
        return 1
    fi
    
    return 0
}

# Validate configuration values
validate_config() {
    local errors=0
    
    log_info "Validating configuration..."
    
    # Validate VMID
    if [[ -n "${VMID}" ]]; then
        if [[ ! ${VMID} =~ ^[0-9]+$ ]]; then
            log_error "Invalid VMID: ${VMID} (must be a number)"
            errors=$((errors + 1))
        fi
    fi
    
    # Validate static IP
    if [[ -n "${STATIC_IP}" ]]; then
        if ! validate_ip "${STATIC_IP}"; then
            log_error "Invalid STATIC_IP: ${STATIC_IP}"
            errors=$((errors + 1))
        fi
    fi
    
    # Validate gateway
    if [[ -n "${GATEWAY}" ]]; then
        if ! validate_ip "${GATEWAY}"; then
            log_error "Invalid GATEWAY: ${GATEWAY}"
            errors=$((errors + 1))
        fi
    fi
    
    # Validate Proxmox host if configured
    if [[ -n "${PROXMOX_HOST}" ]]; then
        if ! validate_host "${PROXMOX_HOST}"; then
            log_error "Invalid PROXMOX_HOST: ${PROXMOX_HOST}"
            errors=$((errors + 1))
        fi
    fi
    
    # Validate SSH port
    if [[ -n "${PROXMOX_SSH_PORT}" ]]; then
        if ! validate_port "${PROXMOX_SSH_PORT}"; then
            log_error "Invalid PROXMOX_SSH_PORT: ${PROXMOX_SSH_PORT}"
            errors=$((errors + 1))
        fi
    fi
    
    # Validate service ports
    for port_var in PORTAINER_PORT SEMAPHORE_PORT SEMAPHORE_DB_PORT; do
        local port_value="${!port_var}"
        if [[ -n "${port_value}" ]]; then
            if ! validate_port "${port_value}"; then
                log_error "Invalid ${port_var}: ${port_value}"
                errors=$((errors + 1))
            fi
        fi
    done
    
    # Validate VM resources
    if [[ -n "${VM_MEMORY}" ]]; then
        if [[ ! ${VM_MEMORY} =~ ^[0-9]+$ ]] || [[ ${VM_MEMORY} -lt 512 ]]; then
            log_error "Invalid VM_MEMORY: ${VM_MEMORY} (must be >= 512 MB)"
            errors=$((errors + 1))
        fi
    fi
    
    if [[ -n "${VM_CORES}" ]]; then
        if [[ ! ${VM_CORES} =~ ^[0-9]+$ ]] || [[ ${VM_CORES} -lt 1 ]]; then
            log_error "Invalid VM_CORES: ${VM_CORES} (must be >= 1)"
            errors=$((errors + 1))
        fi
    fi
    
    if [[ ${errors} -eq 0 ]]; then
        log_info "Configuration validation passed"
        return 0
    else
        log_error "Configuration validation failed with ${errors} error(s)"
        return 1
    fi
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

# Load configuration file
load_config() {
    local config_file="${1}"
    
    if [[ ! -f "${config_file}" ]]; then
        log_warn "Configuration file not found: ${config_file}"
        return 1
    fi
    
    log_info "Loading configuration from: ${config_file}"
    # shellcheck source=/dev/null
    source "${config_file}"
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

# Export functions for use in other scripts
export -f log log_info log_warn log_error log_debug
export -f error_exit cleanup_handler
export -f check_command check_root backup_file
export -f retry_with_backoff is_dry_run execute
export -f wait_for_service generate_password validate_ip validate_host validate_port validate_config
export -f get_distro_info get_distro_version is_proxmox
export -f load_config save_credentials