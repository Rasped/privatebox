#!/bin/bash
# SSH Manager - Consolidated SSH key management functions
# 
# This module provides functions for managing SSH keys, including
# generation, validation, and deployment.

# Source required modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/bootstrap_logger.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/constants.sh" 2>/dev/null || true

# Generate SSH key pair with specified parameters
generate_ssh_key() {
    local key_path="${1}"
    local key_type="${2:-rsa}"
    local key_bits="${3:-4096}"
    local comment="${4:-privatebox@$(hostname)}"
    local passphrase="${5:-}"
    
    log_info "Generating ${key_type} SSH key: ${key_path}"
    
    # Create directory if it doesn't exist
    local key_dir=$(dirname "${key_path}")
    if [[ ! -d "${key_dir}" ]]; then
        mkdir -p "${key_dir}"
        chmod 700 "${key_dir}"
    fi
    
    # Remove existing key if it exists
    if [[ -f "${key_path}" ]]; then
        log_warn "Removing existing key: ${key_path}"
        rm -f "${key_path}" "${key_path}.pub"
    fi
    
    # Generate the key
    local keygen_opts="-q -f ${key_path} -C ${comment}"
    
    case "${key_type}" in
        rsa)
            keygen_opts="${keygen_opts} -t rsa -b ${key_bits}"
            ;;
        ed25519)
            keygen_opts="${keygen_opts} -t ed25519"
            ;;
        ecdsa)
            keygen_opts="${keygen_opts} -t ecdsa -b ${key_bits}"
            ;;
        *)
            log_error "Unsupported key type: ${key_type}"
            return 1
            ;;
    esac
    
    # Add passphrase option
    keygen_opts="${keygen_opts} -N '${passphrase}'"
    
    # Generate the key
    if ssh-keygen ${keygen_opts} >/dev/null 2>&1; then
        # Set permissions
        chmod 600 "${key_path}"
        chmod 644 "${key_path}.pub"
        
        log_info "SSH key generated successfully"
        log_debug "Private key: ${key_path}"
        log_debug "Public key: ${key_path}.pub"
        return 0
    else
        log_error "Failed to generate SSH key"
        return 1
    fi
}

# Ensure SSH key exists, generate if not
ensure_ssh_key() {
    local key_path="${1:-${HOME}/.ssh/id_rsa}"
    local key_type="${2:-rsa}"
    local key_bits="${3:-4096}"
    local comment="${4:-privatebox@$(hostname)}"
    
    if [[ -f "${key_path}.pub" ]]; then
        log_info "SSH key already exists: ${key_path}"
        return 0
    else
        log_info "SSH key not found, generating new key..."
        generate_ssh_key "${key_path}" "${key_type}" "${key_bits}" "${comment}"
        return $?
    fi
}

# Get SSH public key content
get_ssh_public_key() {
    local key_path="${1:-${HOME}/.ssh/id_rsa}"
    
    if [[ -f "${key_path}.pub" ]]; then
        cat "${key_path}.pub"
        return 0
    else
        log_error "SSH public key not found: ${key_path}.pub"
        return 1
    fi
}

# Add SSH key to authorized_keys
add_authorized_key() {
    local public_key="${1}"
    local user="${2:-$(whoami)}"
    local user_home=$(eval echo "~${user}")
    local auth_keys="${user_home}/.ssh/authorized_keys"
    
    # Create .ssh directory if it doesn't exist
    if [[ ! -d "${user_home}/.ssh" ]]; then
        mkdir -p "${user_home}/.ssh"
        chown "${user}:${user}" "${user_home}/.ssh"
        chmod 700 "${user_home}/.ssh"
    fi
    
    # Check if key already exists
    if [[ -f "${auth_keys}" ]] && grep -qF "${public_key}" "${auth_keys}"; then
        log_info "SSH key already in authorized_keys"
        return 0
    fi
    
    # Add the key
    echo "${public_key}" >> "${auth_keys}"
    chown "${user}:${user}" "${auth_keys}"
    chmod 600 "${auth_keys}"
    
    log_info "SSH key added to authorized_keys"
    return 0
}

# Copy SSH key to remote host
copy_ssh_key() {
    local key_path="${1}"
    local remote_user="${2}"
    local remote_host="${3}"
    local remote_port="${4:-22}"
    
    if [[ ! -f "${key_path}.pub" ]]; then
        log_error "SSH public key not found: ${key_path}.pub"
        return 1
    fi
    
    log_info "Copying SSH key to ${remote_user}@${remote_host}:${remote_port}"
    
    # Use ssh-copy-id if available
    if command -v ssh-copy-id &> /dev/null; then
        ssh-copy-id -i "${key_path}" -p "${remote_port}" "${remote_user}@${remote_host}"
        return $?
    else
        # Manual copy
        local pub_key=$(cat "${key_path}.pub")
        ssh -p "${remote_port}" "${remote_user}@${remote_host}" \
            "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '${pub_key}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
        return $?
    fi
}

# Test SSH connection
test_ssh_connection() {
    local host="${1}"
    local user="${2:-$(whoami)}"
    local port="${3:-22}"
    local key_path="${4:-${HOME}/.ssh/id_rsa}"
    local timeout="${5:-${SSH_CONNECT_TIMEOUT:-10}}"
    
    log_debug "Testing SSH connection to ${user}@${host}:${port}"
    
    ssh -q -o ConnectTimeout="${timeout}" \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o PasswordAuthentication=no \
        -i "${key_path}" \
        -p "${port}" \
        "${user}@${host}" "exit 0" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_debug "SSH connection successful"
        return 0
    else
        log_debug "SSH connection failed"
        return 1
    fi
}

# Wait for SSH to become available
wait_for_ssh() {
    local host="${1}"
    local user="${2:-$(whoami)}"
    local port="${3:-22}"
    local timeout="${4:-300}"
    local key_path="${5:-${HOME}/.ssh/id_rsa}"
    
    log_info "Waiting for SSH to be available on ${host}..."
    
    local elapsed=0
    while [[ ${elapsed} -lt ${timeout} ]]; do
        if test_ssh_connection "${host}" "${user}" "${port}" "${key_path}"; then
            log_info "SSH is now available"
            return 0
        fi
        
        sleep ${SERVICE_CHECK_INTERVAL:-5}
        elapsed=$((elapsed + SERVICE_CHECK_INTERVAL))
        
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log_info "Still waiting for SSH... (${elapsed}/${timeout}s)"
        fi
    done
    
    log_error "Timeout waiting for SSH connection"
    return 1
}

# Generate host SSH keys
generate_host_keys() {
    local host_key_dir="${1:-/etc/ssh}"
    
    log_info "Generating host SSH keys..."
    
    local key_types=("rsa" "ecdsa" "ed25519")
    
    for key_type in "${key_types[@]}"; do
        local key_file="${host_key_dir}/ssh_host_${key_type}_key"
        
        if [[ -f "${key_file}" ]]; then
            log_debug "Host ${key_type} key already exists"
            continue
        fi
        
        log_info "Generating ${key_type} host key..."
        ssh-keygen -q -t "${key_type}" -f "${key_file}" -N "" < /dev/null
        
        if [[ $? -eq 0 ]]; then
            chmod 600 "${key_file}"
            chmod 644 "${key_file}.pub"
            log_debug "Generated ${key_type} host key"
        else
            log_error "Failed to generate ${key_type} host key"
            return 1
        fi
    done
    
    log_info "Host SSH keys generated successfully"
    return 0
}

# Function to check if module is loaded
ssh_manager_loaded() {
    return 0
}