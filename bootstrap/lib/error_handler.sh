#!/bin/bash
# Error Handler - Standardized error handling and cleanup functions
# 
# This module provides consistent error handling, trap management,
# and cleanup functions across all bootstrap scripts.

# Note: This file expects constants.sh and bootstrap_logger.sh to be sourced before it
# All dependencies should come from common.sh

# Check if we're running in a minimal environment (e.g., cloud-init)
# This allows error_handler.sh to work even without full common.sh
if ! type -t log_error &> /dev/null; then
    # Minimal logging functions for standalone use
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "[INFO] $*"; }
    log_debug() { [[ "${DEBUG:-0}" -eq 1 ]] && echo "[DEBUG] $*"; }
fi

# Define default exit codes if not already defined
: ${EXIT_SUCCESS:=0}
: ${EXIT_ERROR:=1}
: ${EXIT_MISSING_DEPS:=2}

# Cloud-init status file for error reporting
CLOUD_INIT_STATUS_FILE="/tmp/privatebox-install-status"

# Global variables for cleanup tracking
declare -a CLEANUP_FUNCTIONS=()
declare -a TEMP_FILES=()
declare -a TEMP_DIRS=()
declare -a CLEANUP_PIDS=()

# Register a cleanup function to be called on exit
register_cleanup() {
    local func="${1}"
    CLEANUP_FUNCTIONS+=("${func}")
    log_debug "Registered cleanup function: ${func}"
}

# Register a temporary file for cleanup
register_temp_file() {
    local file="${1}"
    TEMP_FILES+=("${file}")
    log_debug "Registered temporary file: ${file}"
}

# Register a temporary directory for cleanup
register_temp_dir() {
    local dir="${1}"
    TEMP_DIRS+=("${dir}")
    log_debug "Registered temporary directory: ${dir}"
}

# Register a PID for cleanup
register_cleanup_pid() {
    local pid="${1}"
    CLEANUP_PIDS+=("${pid}")
    log_debug "Registered PID for cleanup: ${pid}"
}

# Main cleanup handler
cleanup_handler() {
    local exit_code=$?
    
    # Prevent recursive cleanup
    if [[ "${CLEANING_UP:-0}" -eq 1 ]]; then
        return
    fi
    CLEANING_UP=1
    
    log_info "Performing cleanup..."
    
    # Kill registered PIDs
    for pid in "${CLEANUP_PIDS[@]}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            log_debug "Killing process: ${pid}"
            kill -TERM "${pid}" 2>/dev/null || true
        fi
    done
    
    # Remove temporary files
    for file in "${TEMP_FILES[@]}"; do
        if [[ -f "${file}" ]]; then
            log_debug "Removing temporary file: ${file}"
            rm -f "${file}" || true
        fi
    done
    
    # Remove temporary directories
    for dir in "${TEMP_DIRS[@]}"; do
        if [[ -d "${dir}" ]]; then
            log_debug "Removing temporary directory: ${dir}"
            rm -rf "${dir}" || true
        fi
    done
    
    # Call registered cleanup functions
    for func in "${CLEANUP_FUNCTIONS[@]}"; do
        log_debug "Calling cleanup function: ${func}"
        "${func}" || true
    done
    
    # Log final status
    if [[ ${exit_code} -eq 0 ]]; then
        log_info "Cleanup completed successfully"
    else
        log_warn "Cleanup completed with exit code: ${exit_code}"
    fi
    
    return ${exit_code}
}

# Error handler with context
error_handler() {
    local exit_code=$?
    local line_no="${1:-}"
    local bash_lineno="${2:-}"
    local last_command="${3:-}"
    local func_stack=("${@:4}")
    
    # Don't report on cleanup exit
    if [[ "${CLEANING_UP:-0}" -eq 1 ]]; then
        return
    fi
    
    # Build error message
    local error_msg="Error occurred in script"
    
    log_error "${error_msg}"
    log_error "Exit code: ${exit_code}"
    
    if [[ -n "${line_no}" ]]; then
        log_error "Line number: ${line_no}"
        error_msg="${error_msg} at line ${line_no}"
    fi
    
    if [[ -n "${last_command}" ]]; then
        log_error "Last command: ${last_command}"
        error_msg="${error_msg}: ${last_command}"
    fi
    
    if [[ ${#func_stack[@]} -gt 0 ]]; then
        log_error "Function stack:"
        for func in "${func_stack[@]}"; do
            log_error "  - ${func}"
        done
    fi
    
    # Write to cloud-init status file if applicable
    write_error_status "${error_msg}" ${exit_code}
    
    # Trigger cleanup
    cleanup_handler
    
    exit ${exit_code}
}

# Setup error handling for a script
setup_error_handling() {
    set -euo pipefail
    
    # Set up error trap with context
    trap 'error_handler ${LINENO} ${BASH_LINENO} "$BASH_COMMAND" "${FUNCNAME[@]}"' ERR
    
    # Set up exit trap for cleanup
    trap cleanup_handler EXIT INT TERM
    
    log_debug "Error handling configured"
}

# Temporarily disable error handling
disable_error_handling() {
    set +euo pipefail
    trap - ERR EXIT INT TERM
}

# Re-enable error handling
enable_error_handling() {
    setup_error_handling
}

# Execute command with error handling disabled
run_safe() {
    local cmd=("$@")
    local result
    
    disable_error_handling
    "${cmd[@]}"
    result=$?
    enable_error_handling
    
    return ${result}
}

# Check command result and exit on error
check_result() {
    local result="${1}"
    local message="${2}"
    local exit_code="${3:-${EXIT_ERROR}}"
    
    if [[ ${result} -ne 0 ]]; then
        log_error "${message}"
        exit ${exit_code}
    fi
}

# Assert condition is true
assert() {
    local condition="${1}"
    local message="${2:-Assertion failed}"
    
    if ! eval "${condition}"; then
        log_error "${message}: ${condition}"
        exit ${EXIT_ERROR}
    fi
}

# Require command exists
require_command() {
    local cmd="${1}"
    local message="${2:-Command required}"
    
    if ! command -v "${cmd}" &> /dev/null; then
        log_error "${message}: ${cmd}"
        exit ${EXIT_MISSING_DEPS}
    fi
}

# Require file exists
require_file() {
    local file="${1}"
    local message="${2:-File required}"
    
    if [[ ! -f "${file}" ]]; then
        log_error "${message}: ${file}"
        exit ${EXIT_ERROR}
    fi
}

# Require directory exists
require_dir() {
    local dir="${1}"
    local message="${2:-Directory required}"
    
    if [[ ! -d "${dir}" ]]; then
        log_error "${message}: ${dir}"
        exit ${EXIT_ERROR}
    fi
}

# Create a checkpoint for rollback
create_checkpoint() {
    local name="${1}"
    local data="${2}"
    
    local checkpoint_file="/tmp/.privatebox-checkpoint-${name}"
    echo "${data}" > "${checkpoint_file}"
    register_temp_file "${checkpoint_file}"
    
    log_debug "Created checkpoint: ${name}"
}

# Rollback to checkpoint
rollback_checkpoint() {
    local name="${1}"
    local checkpoint_file="/tmp/.privatebox-checkpoint-${name}"
    
    if [[ -f "${checkpoint_file}" ]]; then
        local data=$(cat "${checkpoint_file}")
        log_info "Rolling back to checkpoint: ${name}"
        echo "${data}"
        return 0
    else
        log_error "Checkpoint not found: ${name}"
        return 1
    fi
}

# Write error status for cloud-init
write_error_status() {
    local error_msg="${1:-Unknown error}"
    local exit_code="${2:-1}"
    
    if [[ -n "${CLOUD_INIT_STATUS_FILE}" ]]; then
        cat > "${CLOUD_INIT_STATUS_FILE}" <<EOF
ERROR
${error_msg}
Exit code: ${exit_code}
Time: $(date +"%Y-%m-%d %H:%M:%S")
EOF
        log_debug "Wrote error status to ${CLOUD_INIT_STATUS_FILE}"
    fi
}

# Setup error handling for cloud-init scripts
setup_cloud_init_error_handling() {
    # Use basic error handling suitable for cloud-init
    set -euo pipefail
    
    # Simple error trap that writes to status file
    trap 'write_error_status "Script failed at line $LINENO" $?; exit 1' ERR
    
    # Cleanup trap
    trap 'cleanup_handler' EXIT INT TERM
    
    log_debug "Cloud-init error handling configured"
}

# Safe command execution with fallback error handling
safe_execute() {
    local cmd=("$@")
    local result
    
    if "${cmd[@]}"; then
        return 0
    else
        result=$?
        log_error "Command failed: ${cmd[*]}"
        write_error_status "Command failed: ${cmd[*]}" ${result}
        return ${result}
    fi
}

# Function to check if module is loaded
error_handler_loaded() {
    return 0
}