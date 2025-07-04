#!/bin/bash
# Common library for PrivateBox bootstrap scripts
# Provides logging, error handling, and utility functions

# Global variables
SCRIPT_NAME="${SCRIPT_NAME:-$(basename "${BASH_SOURCE[1]:-$0}")}"
LOG_DIR="${LOG_DIR:-/var/log/privatebox}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/${SCRIPT_NAME}.log}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
VERBOSE="${VERBOSE:-false}"

# Color codes for output
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_NC='\033[0m' # No Color

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_MISSING_DEPS=2
readonly EXIT_INVALID_CONFIG=3
readonly EXIT_VM_OPERATION_FAILED=4
readonly EXIT_NETWORK_ERROR=5
readonly EXIT_SERVICE_ERROR=6

# Cleanup functions array
declare -a CLEANUP_FUNCTIONS=()

# Initialize logging
initialize_logging() {
    # Create log directory if it doesn't exist
    if [[ ! -d "$LOG_DIR" ]]; then
        mkdir -p "$LOG_DIR" 2>/dev/null || {
            # Fall back to /tmp if we can't create the log directory
            LOG_DIR="/tmp"
            # Must recompute LOG_FILE since LOG_DIR changed
            LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
        }
    fi
    
    # Create log file
    touch "$LOG_FILE" 2>/dev/null || {
        echo "Warning: Cannot create log file at $LOG_FILE" >&2
        LOG_FILE="/dev/null"
    }
    
    # Log initialization
    log_info "=== Starting $SCRIPT_NAME at $(date) ==="
}

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Write to console based on log level and verbosity
    case "$level" in
        ERROR)
            echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $message" >&2
            ;;
        WARN)
            echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $message" >&2
            ;;
        INFO)
            if [[ "$LOG_LEVEL" != "WARN" ]] && [[ "$LOG_LEVEL" != "ERROR" ]]; then
                echo -e "${COLOR_BLUE}[INFO]${COLOR_NC} $message"
            fi
            ;;
        SUCCESS)
            echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_NC} $message"
            ;;
        DEBUG)
            if [[ "$LOG_LEVEL" == "DEBUG" ]] || [[ "$VERBOSE" == "true" ]]; then
                echo -e "[DEBUG] $message"
            fi
            ;;
    esac
}

log_error() { log "ERROR" "$@"; }
log_warn() { log "WARN" "$@"; }
log_info() { log "INFO" "$@"; }
log_success() { log "SUCCESS" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=${1:-0}
    local bash_lineno=${BASH_LINENO[0]}
    local command="${BASH_COMMAND:-unknown}"
    
    log_error "Command failed with exit code $exit_code at line $line_number"
    log_error "Failed command: $command"
    
    # Call cleanup functions
    run_cleanup
    
    exit $exit_code
}

# Setup error handling for a script
setup_error_handling() {
    set -eEuo pipefail
    trap 'handle_error $LINENO' ERR
    
    # Also trap EXIT for cleanup
    trap 'run_cleanup' EXIT
}

# Register a cleanup function
register_cleanup() {
    local func="$1"
    CLEANUP_FUNCTIONS+=("$func")
    log_debug "Registered cleanup function: $func"
}

# Run all cleanup functions
run_cleanup() {
    local exit_code=$?
    
    if [[ ${#CLEANUP_FUNCTIONS[@]} -gt 0 ]]; then
        log_debug "Running cleanup functions..."
        for func in "${CLEANUP_FUNCTIONS[@]}"; do
            if declare -f "$func" > /dev/null; then
                log_debug "Running cleanup: $func"
                "$func" || true  # Don't fail on cleanup errors
            fi
        done
    fi
    
    return $exit_code
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit $EXIT_GENERAL_ERROR
    fi
}

# Check if running on Proxmox
is_proxmox() {
    if [[ -f /etc/pve/version ]]; then
        return 0
    else
        return 1
    fi
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Require a command to be available
require_command() {
    local cmd="$1"
    local package="${2:-$cmd}"
    
    if ! command_exists "$cmd"; then
        log_error "Required command '$cmd' not found. Please install package '$package'"
        exit $EXIT_MISSING_DEPS
    fi
}

# Validate IP address
validate_ip() {
    local ip="$1"
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ ! $ip =~ $valid_ip_regex ]]; then
        return 1
    fi
    
    # Check each octet
    IFS='.' read -ra OCTETS <<< "$ip"
    for octet in "${OCTETS[@]}"; do
        if (( octet > 255 )); then
            return 1
        fi
    done
    
    return 0
}

# Get confirmation from user
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"
    
    local yn
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -r -p "$prompt" yn
    yn=${yn:-$default}
    
    case "$yn" in
        [Yy]* ) return 0;;
        * ) return 1;;
    esac
}

# Retry a command with exponential backoff
retry_with_backoff() {
    local max_attempts="${1}"
    local initial_delay="${2:-1}"
    shift 2
    local command=("$@")
    
    local attempt=1
    local delay="$initial_delay"
    
    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: ${command[*]}"
        
        if "${command[@]}"; then
            return 0
        fi
        
        if [[ $attempt -eq $max_attempts ]]; then
            log_error "Command failed after $max_attempts attempts: ${command[*]}"
            return 1
        fi
        
        log_warn "Command failed, retrying in $delay seconds..."
        sleep "$delay"
        
        # Exponential backoff
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
}

# Create a temporary file that will be cleaned up
create_temp_file() {
    local prefix="${1:-privatebox}"
    local temp_file
    
    temp_file=$(mktemp "/tmp/${prefix}.XXXXXX")
    
    # Register cleanup
    register_cleanup "rm -f '$temp_file'"
    
    echo "$temp_file"
}

# Display a progress message
show_progress() {
    local message="$1"
    echo -en "\r${COLOR_BLUE}[*]${COLOR_NC} $message..."
}

# Clear progress message and show result
end_progress() {
    local status="${1:-success}"
    local message="${2:-Done}"
    
    echo -en "\r\033[K"  # Clear line
    
    case "$status" in
        success)
            log_success "$message"
            ;;
        error)
            log_error "$message"
            ;;
        warn)
            log_warn "$message"
            ;;
    esac
}

# Initialize logging when sourced (only once)
if [[ -z "${LOGGING_INITIALIZED:-}" ]]; then
    initialize_logging
    LOGGING_INITIALIZED=true
fi