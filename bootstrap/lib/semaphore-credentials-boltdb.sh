#!/bin/bash
# Semaphore credentials management library

# Function to generate SSH key pair for VM self-management
generate_vm_ssh_key_pair() {
    log_info "Generating SSH key pair for VM self-management..."
    
    local vm_key_path="/root/.credentials/semaphore_vm_key"
    local vm_key_comment="semaphore-vm-self-management@$(hostname)"
    
    # Ensure credentials directory exists
    mkdir -p /root/.credentials
    chmod 700 /root/.credentials
    
    # Remove existing keys if they exist
    rm -f "${vm_key_path}" "${vm_key_path}.pub"
    
    # Generate new SSH key pair
    ssh-keygen -t ed25519 -f "${vm_key_path}" -C "${vm_key_comment}" -N "" -q
    
    if [ $? -ne 0 ]; then
        log_info "ERROR: Failed to generate VM SSH key pair"
        return 1
    fi
    
    # Set secure permissions
    chmod 600 "${vm_key_path}"
    chmod 644 "${vm_key_path}.pub"
    
    # Add public key to debian's authorized_keys (for Ansible SSH access)
    local admin_home="/home/debian"
    if [ -d "$admin_home" ]; then
        mkdir -p "${admin_home}/.ssh"
        chmod 700 "${admin_home}/.ssh"
        cat "${vm_key_path}.pub" >> "${admin_home}/.ssh/authorized_keys"
        chmod 600 "${admin_home}/.ssh/authorized_keys"
        chown -R debian:debian "${admin_home}/.ssh"
        log_info "Added VM SSH public key to debian's authorized_keys"
    else
        log_info "WARNING: debian home directory not found, skipping authorized_keys update"
    fi
    
    log_info "VM SSH key pair generated and added to authorized_keys"
    return 0
}

# Generate secure credentials and save them to a protected file
generate_and_save_credentials() {
    log_info "Generating secure credentials..."

    # No MySQL passwords needed for BoltDB version
    
    # Use SERVICES_PASSWORD for Semaphore admin if provided via environment
    if [[ -n "${SERVICES_PASSWORD:-}" ]]; then
        SEMAPHORE_ADMIN_PASSWORD="${SERVICES_PASSWORD}"
        log_info "Using SERVICES_PASSWORD for Semaphore admin"
    elif [[ -z "${SEMAPHORE_ADMIN_PASSWORD:-}" ]]; then
        # Generate password if not provided
        # Source password generator if available
        if [[ -f "/usr/local/lib/password-generator.sh" ]]; then
            source /usr/local/lib/password-generator.sh
            SEMAPHORE_ADMIN_PASSWORD=$(generate_password semaphore-admin)
        else
            # Fallback to simple generation if password generator not available
            SEMAPHORE_ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9@*()_+=-' < /dev/urandom | head -c 32)
        fi
        log_info "Generated new Semaphore admin password"
    fi
    
    # Generate strong encryption key as per Semaphore documentation
    SEMAPHORE_ACCESS_KEY_ENCRYPTION_KEY=$(head -c32 /dev/urandom | base64)

    # Generate SSH key pair for VM self-management
    generate_vm_ssh_key_pair

    # Save passwords to a secure file with extra safeguards
    mkdir -p /root/.credentials
    chmod 700 /root/.credentials  # Secure the directory itself
    
    # Create credentials file with clear sections and security notes
    cat > /root/.credentials/semaphore_credentials.txt << EOF
# Semaphore Credentials - CONFIDENTIAL
# Generated on: $(date '+%Y-%m-%d %H:%M:%S')
# Keep this file secure and do not share these credentials

## Database
Type: BoltDB (embedded)
Location: /opt/semaphore/data/database.boltdb

## User Credentials
Admin Password: $SEMAPHORE_ADMIN_PASSWORD

## System Credentials
Semaphore Access Key Encryption: $SEMAPHORE_ACCESS_KEY_ENCRYPTION_KEY

## SSH Keys

## VM Self-Management SSH Keys
VM SSH Private Key Path: /root/.credentials/semaphore_vm_key
VM SSH Public Key Path: /root/.credentials/semaphore_vm_key.pub

## Proxmox SSH Key
Note: The Proxmox SSH private key has been securely uploaded to Semaphore
      and removed from the VM filesystem for security reasons.

## Security Note
# These passwords were automatically generated with strong security requirements.
# It is recommended to change these passwords periodically for optimal security.
EOF

    # Set very restrictive permissions
    chmod 600 /root/.credentials/semaphore_credentials.txt
    log_info "Secure credentials saved to /root/.credentials/semaphore_credentials.txt"
    log_info "Directory and file permissions set to restrict access to root only"
}

