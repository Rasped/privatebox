#!/bin/bash
# Service Manager - Consolidated service management functions
# 
# This module provides functions for managing services, including
# waiting for services to start, checking health, and monitoring.

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/bootstrap_logger.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/constants.sh" 2>/dev/null || true

# Wait for a service to be ready on a specific port
wait_for_service() {
    local service="${1}"
    local port="${2}"
    local timeout="${3:-${SERVICE_START_TIMEOUT:-60}}"
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
        
        # Show progress every 10 seconds
        if [[ $((elapsed % 10)) -eq 0 ]]; then
            log_info "Still waiting for ${service}... (${elapsed}/${timeout}s)"
        fi
    done
    
    log_error "${service} failed to become ready within ${timeout} seconds"
    return 1
}

# Wait for multiple services to be ready
wait_for_services() {
    local timeout="${1:-${SERVICE_START_TIMEOUT:-300}}"
    shift
    local services=("$@")
    
    log_info "Waiting for services to be ready..."
    
    for service_spec in "${services[@]}"; do
        local service_name="${service_spec%%:*}"
        local service_port="${service_spec#*:}"
        
        if ! wait_for_service "${service_name}" "${service_port}" "${timeout}"; then
            log_error "Service ${service_name} failed to start"
            return 1
        fi
    done
    
    log_info "All services are ready"
    return 0
}

# Check if a systemd service is running
check_systemd_service() {
    local service="${1}"
    
    if systemctl is-active --quiet "${service}"; then
        log_debug "${service} is active"
        return 0
    else
        log_debug "${service} is not active"
        return 1
    fi
}

# Check if a Docker container is running
check_docker_container() {
    local container="${1}"
    
    if docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
        log_debug "Container ${container} is running"
        return 0
    else
        log_debug "Container ${container} is not running"
        return 1
    fi
}

# Wait for cloud-init to complete
wait_for_cloud_init() {
    local vm_ip="${1}"
    local timeout="${2:-${CLOUD_INIT_TIMEOUT:-600}}"
    local ssh_user="${3:-${DEFAULT_USERNAME:-privatebox}}"
    local ssh_key="${4:-${HOME}/.ssh/id_rsa}"
    
    log_info "Waiting for cloud-init to complete on ${vm_ip}..."
    
    local start_time=$(date +%s)
    local elapsed=0
    
    # First wait for SSH to be available
    log_info "Waiting for SSH to be available..."
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if ssh -q -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10} \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -o PasswordAuthentication=no \
               -i "${ssh_key}" \
               "${ssh_user}@${vm_ip}" "exit 0" 2>/dev/null; then
            log_info "SSH connection established"
            break
        fi
        
        sleep ${SERVICE_CHECK_INTERVAL:-5}
        elapsed=$(($(date +%s) - start_time))
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log_info "Still waiting for SSH... (${elapsed}/${timeout}s)"
        fi
    done
    
    if [[ ${elapsed} -ge ${timeout} ]]; then
        log_error "Timeout waiting for SSH connection"
        return 1
    fi
    
    # Now wait for cloud-init to complete
    log_info "SSH available, waiting for cloud-init to finish..."
    while [[ ${elapsed} -lt ${timeout} ]]; do
        local status=$(ssh -q -o ConnectTimeout=${SSH_CONNECT_TIMEOUT:-10} \
                          -o StrictHostKeyChecking=no \
                          -o UserKnownHostsFile=/dev/null \
                          -o PasswordAuthentication=no \
                          -i "${ssh_key}" \
                          "${ssh_user}@${vm_ip}" \
                          "sudo cloud-init status --format=json 2>/dev/null" 2>/dev/null || echo '{}')
        
        if [[ -n "${status}" ]] && echo "${status}" | jq -e '.status == "done"' >/dev/null 2>&1; then
            log_info "Cloud-init completed successfully"
            
            # Check for errors
            local errors=$(echo "${status}" | jq -r '.errors[]' 2>/dev/null || true)
            if [[ -n "${errors}" ]]; then
                log_warn "Cloud-init reported errors:"
                echo "${errors}" | while read -r error; do
                    log_warn "  - ${error}"
                done
            fi
            
            return 0
        elif echo "${status}" | jq -e '.status == "error"' >/dev/null 2>&1; then
            log_error "Cloud-init failed with errors"
            local errors=$(echo "${status}" | jq -r '.errors[]' 2>/dev/null || true)
            if [[ -n "${errors}" ]]; then
                echo "${errors}" | while read -r error; do
                    log_error "  - ${error}"
                done
            fi
            return 1
        fi
        
        sleep ${SERVICE_CHECK_INTERVAL:-5}
        elapsed=$(($(date +%s) - start_time))
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            local current_status=$(echo "${status}" | jq -r '.status' 2>/dev/null || echo "unknown")
            log_info "Cloud-init status: ${current_status} (${elapsed}/${timeout}s)"
        fi
    done
    
    log_error "Timeout waiting for cloud-init to complete"
    return 1
}

# Get service health status
get_service_health() {
    local service_type="${1}"
    local service_name="${2}"
    
    case "${service_type}" in
        systemd)
            if check_systemd_service "${service_name}"; then
                echo "healthy"
            else
                echo "unhealthy"
            fi
            ;;
        docker)
            if check_docker_container "${service_name}"; then
                local health=$(docker inspect --format='{{.State.Health.Status}}' "${service_name}" 2>/dev/null || echo "none")
                case "${health}" in
                    healthy|none)
                        echo "healthy"
                        ;;
                    starting)
                        echo "starting"
                        ;;
                    *)
                        echo "unhealthy"
                        ;;
                esac
            else
                echo "stopped"
            fi
            ;;
        port)
            local port="${service_name#*:}"
            local host="${service_name%%:*}"
            if nc -z "${host}" "${port}" 2>/dev/null; then
                echo "healthy"
            else
                echo "unhealthy"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Restart a service with proper error handling
restart_service() {
    local service_type="${1}"
    local service_name="${2}"
    local wait_after="${3:-10}"
    
    log_info "Restarting ${service_type} service: ${service_name}"
    
    case "${service_type}" in
        systemd)
            if ! systemctl restart "${service_name}"; then
                log_error "Failed to restart ${service_name}"
                return 1
            fi
            ;;
        docker)
            if ! docker restart "${service_name}"; then
                log_error "Failed to restart container ${service_name}"
                return 1
            fi
            ;;
        *)
            log_error "Unknown service type: ${service_type}"
            return 1
            ;;
    esac
    
    # Wait a bit for service to stabilize
    sleep "${wait_after}"
    
    # Check if service is running
    local health=$(get_service_health "${service_type}" "${service_name}")
    if [[ "${health}" == "healthy" ]]; then
        log_info "${service_name} restarted successfully"
        return 0
    else
        log_error "${service_name} failed to start properly after restart"
        return 1
    fi
}

# Function to check if module is loaded
service_manager_loaded() {
    return 0
}