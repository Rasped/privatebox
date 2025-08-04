#!/bin/bash
# Minimal error handler - All functions preserved for cloud-init embedding

# Minimal logging for standalone use
if ! type -t log_error &> /dev/null; then
    log_error() { echo "[ERROR] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_info() { echo "[INFO] $*"; }
    log_debug() { [[ "${DEBUG:-0}" -eq 1 ]] && echo "[DEBUG] $*"; }
fi

# Exit codes
: ${EXIT_SUCCESS:=0}
: ${EXIT_ERROR:=1}
: ${EXIT_MISSING_DEPS:=2}

CLOUD_INIT_STATUS_FILE="/tmp/privatebox-install-status"

# Cleanup tracking arrays
declare -a CLEANUP_FUNCTIONS=()
declare -a TEMP_FILES=()
declare -a TEMP_DIRS=()
declare -a CLEANUP_PIDS=()

register_cleanup() {
    CLEANUP_FUNCTIONS+=("${1}")
    log_debug "Registered cleanup function: ${1}"
}

register_temp_file() {
    TEMP_FILES+=("${1}")
    log_debug "Registered temporary file: ${1}"
}

register_temp_dir() {
    TEMP_DIRS+=("${1}")
    log_debug "Registered temporary directory: ${1}"
}

register_cleanup_pid() {
    CLEANUP_PIDS+=("${1}")
    log_debug "Registered PID for cleanup: ${1}"
}

cleanup_handler() {
    local exit_code=$?
    
    if [[ "${CLEANING_UP:-0}" -eq 1 ]]; then
        return
    fi
    CLEANING_UP=1
    
    log_info "Performing cleanup..."
    
    for pid in "${CLEANUP_PIDS[@]}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            log_debug "Killing process: ${pid}"
            kill -TERM "${pid}" 2>/dev/null || true
        fi
    done
    
    for file in "${TEMP_FILES[@]}"; do
        if [[ -f "${file}" ]]; then
            log_debug "Removing temporary file: ${file}"
            rm -f "${file}" || true
        fi
    done
    
    for dir in "${TEMP_DIRS[@]}"; do
        if [[ -d "${dir}" ]]; then
            log_debug "Removing temporary directory: ${dir}"
            rm -rf "${dir}" || true
        fi
    done
    
    for func in "${CLEANUP_FUNCTIONS[@]}"; do
        log_debug "Calling cleanup function: ${func}"
        "${func}" || true
    done
    
    if [[ ${exit_code} -eq 0 ]]; then
        log_info "Cleanup completed successfully"
    else
        log_warn "Cleanup completed with exit code: ${exit_code}"
    fi
    
    return ${exit_code}
}

error_handler() {
    local exit_code=$?
    local line_no="${1:-}"
    local bash_lineno="${2:-}"
    local last_command="${3:-}"
    local func_stack=("${@:4}")
    
    if [[ "${CLEANING_UP:-0}" -eq 1 ]]; then
        return
    fi
    
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
    
    write_error_status "${error_msg}" ${exit_code}
    cleanup_handler
    exit ${exit_code}
}

setup_error_handling() {
    set -euo pipefail
    trap 'error_handler ${LINENO} ${BASH_LINENO} "$BASH_COMMAND" "${FUNCNAME[@]}"' ERR
    trap cleanup_handler EXIT INT TERM
    log_debug "Error handling configured"
}

disable_error_handling() {
    set +euo pipefail
    trap - ERR EXIT INT TERM
}

enable_error_handling() {
    setup_error_handling
}

run_safe() {
    local cmd=("$@")
    local result
    
    disable_error_handling
    "${cmd[@]}"
    result=$?
    enable_error_handling
    
    return ${result}
}

check_result() {
    local result="${1}"
    local message="${2}"
    local exit_code="${3:-${EXIT_ERROR}}"
    
    if [[ ${result} -ne 0 ]]; then
        log_error "${message}"
        exit ${exit_code}
    fi
}

assert() {
    local condition="${1}"
    local message="${2:-Assertion failed}"
    
    if ! eval "${condition}"; then
        log_error "${message}: ${condition}"
        exit ${EXIT_ERROR}
    fi
}

require_command() {
    local cmd="${1}"
    local message="${2:-Command required}"
    
    if ! command -v "${cmd}" &> /dev/null; then
        log_error "${message}: ${cmd}"
        exit ${EXIT_MISSING_DEPS}
    fi
}

require_file() {
    local file="${1}"
    local message="${2:-File required}"
    
    if [[ ! -f "${file}" ]]; then
        log_error "${message}: ${file}"
        exit ${EXIT_ERROR}
    fi
}

require_dir() {
    local dir="${1}"
    local message="${2:-Directory required}"
    
    if [[ ! -d "${dir}" ]]; then
        log_error "${message}: ${dir}"
        exit ${EXIT_ERROR}
    fi
}

create_checkpoint() {
    local name="${1}"
    local data="${2}"
    
    local checkpoint_file="/tmp/.privatebox-checkpoint-${name}"
    echo "${data}" > "${checkpoint_file}"
    register_temp_file "${checkpoint_file}"
    
    log_debug "Created checkpoint: ${name}"
}

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

error_handler_loaded() {
    return 0
}