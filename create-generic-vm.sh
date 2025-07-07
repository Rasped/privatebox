#!/bin/bash
# Generic Ubuntu VM Creation Script for Proxmox
# Creates an Ubuntu VM with customizable settings and file/script deployment
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Missing dependencies
#   3 - Invalid configuration
#   4 - VM operations failed

# Simple logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*"
    fi
}

# ========================================
# Configuration Section - Modify these values
# ========================================

# VM Configuration
VMID="${VMID:-9000}"
VM_NAME="${VM_NAME:-ubuntu-vm}"
VM_MEMORY="${VM_MEMORY:-4096}"
VM_CORES="${VM_CORES:-2}"
VM_DISK_SIZE="${VM_DISK_SIZE:-20G}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"

# Network Configuration
STATIC_IP="${STATIC_IP:-192.168.1.100}"
GATEWAY="${GATEWAY:-192.168.1.1}"
BRIDGE="${BRIDGE:-vmbr0}"

# Storage Configuration
STORAGE="${STORAGE:-local-lvm}"

# User Configuration
VM_USERNAME="${VM_USERNAME:-ubuntu}"
VM_PASSWORD="${VM_PASSWORD:-changeme}"
SSH_KEYS=(
    # Add your SSH public keys here, one per line
    # "ssh-rsa AAAAB3NzaC1yc2EA... user@host"
)

# Packages to install (via cloud-init)
PACKAGES=(
    "openssh-server"
    "curl"
    "wget"
    "vim"
    "htop"
)

# Files to copy: "local_path:remote_path:permissions"
# Example: "/home/user/script.sh:/opt/script.sh:0755"
# Can be overridden by FILES_TO_COPY_STR environment variable (semicolon-separated)
if [[ -n "${FILES_TO_COPY_STR}" ]]; then
    IFS=';' read -ra FILES_TO_COPY <<< "$FILES_TO_COPY_STR"
else
    FILES_TO_COPY=(
        # Add your files here
    )
fi

# Scripts to run after boot (must be copied first via FILES_TO_COPY)
# Example: "/opt/script.sh"
# Can be overridden by SCRIPTS_TO_RUN_STR environment variable (semicolon-separated)
if [[ -n "${SCRIPTS_TO_RUN_STR}" ]]; then
    IFS=';' read -ra SCRIPTS_TO_RUN <<< "$SCRIPTS_TO_RUN_STR"
else
    SCRIPTS_TO_RUN=(
        # Add your scripts here
    )
fi

# Debug mode - set to true for verbose output
DEBUG="${DEBUG:-false}"

# ========================================
# Script Implementation
# ========================================

# Function to check if command exists
check_command() {
    local cmd="$1"
    local msg="$2"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "$msg"
        return 1
    fi
    return 0
}

# Function to validate IP address
validate_ip() {
    local ip="$1"
    local valid_ip_regex="^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    
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

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check for root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        return 1
    fi
    
    # Check required commands
    local failed=false
    check_command "qm" "qm command is required (Proxmox VE)" || failed=true
    check_command "pvesm" "pvesm command is required (Proxmox storage)" || failed=true
    check_command "wget" "wget is required for downloading images" || failed=true
    
    # Check if we're on Proxmox
    if [[ ! -f /usr/bin/pveversion ]]; then
        log_error "This script must be run on a Proxmox VE host"
        failed=true
    fi
    
    if [[ "$failed" == "true" ]]; then
        return 1
    fi
    
    log_info "Prerequisites check passed"
    return 0
}

# Validate configuration
validate_configuration() {
    log_info "Validating configuration..."
    
    # Validate VMID
    if [[ ! $VMID =~ ^[0-9]+$ ]]; then
        log_error "VMID must be a number: $VMID"
        return 1
    fi
    
    # Validate IP addresses
    if ! validate_ip "$STATIC_IP"; then
        log_error "Invalid static IP address: $STATIC_IP"
        return 1
    fi
    
    if ! validate_ip "$GATEWAY"; then
        log_error "Invalid gateway IP address: $GATEWAY"
        return 1
    fi
    
    # Validate Ubuntu version
    if [[ ! $UBUNTU_VERSION =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_error "Invalid Ubuntu version format: $UBUNTU_VERSION"
        return 1
    fi
    
    # Check if VM already exists
    if qm status "$VMID" &>/dev/null; then
        log_error "VM with ID $VMID already exists"
        return 1
    fi
    
    log_info "Configuration validation passed"
    return 0
}

# Download Ubuntu cloud image
download_image() {
    local image_url="https://cloud-images.ubuntu.com/releases/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
    local image_name="ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
    local cache_dir="/var/cache/proxmox-images"
    local cached_image="${cache_dir}/${image_name}"
    
    log_info "Preparing Ubuntu ${UBUNTU_VERSION} cloud image..."
    
    # Create cache directory
    mkdir -p "$cache_dir" || {
        log_error "Failed to create cache directory"
        return 1
    }
    
    # Check if image exists in cache
    if [[ -f "$cached_image" ]]; then
        log_info "Using cached image: $cached_image"
        ln -sf "$cached_image" "$image_name" || cp "$cached_image" "$image_name"
        return 0
    fi
    
    # Download image
    log_info "Downloading cloud image..."
    log_debug "URL: $image_url"
    
    if ! wget -q -O "$cached_image" "$image_url"; then
        log_error "Failed to download cloud image"
        rm -f "$cached_image"
        return 1
    fi
    
    log_info "Image downloaded successfully"
    ln -sf "$cached_image" "$image_name" || cp "$cached_image" "$image_name"
    return 0
}

# Generate SSH key if needed
ensure_ssh_key() {
    local ssh_key_path="/root/.ssh/id_rsa"
    local ssh_pub_key_path="${ssh_key_path}.pub"
    
    if [[ -f "$ssh_pub_key_path" ]]; then
        log_debug "Using existing SSH key"
        SSH_PUBLIC_KEY=$(cat "$ssh_pub_key_path")
    else
        log_info "Generating SSH key for VM access..."
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        
        if ! ssh-keygen -t rsa -b 4096 -f "$ssh_key_path" -N "" -C "proxmox@$(hostname)" &>/dev/null; then
            log_error "Failed to generate SSH key"
            return 1
        fi
        
        SSH_PUBLIC_KEY=$(cat "$ssh_pub_key_path")
        log_info "SSH key generated successfully"
    fi
    
    export SSH_PUBLIC_KEY
    return 0
}

# Generate cloud-init configuration
generate_cloud_init() {
    log_info "Generating cloud-init configuration..."
    
    local snippets_dir="/var/lib/vz/snippets"
    local user_data_file="${snippets_dir}/user-data-${VMID}.yaml"
    
    # Create snippets directory
    mkdir -p "$snippets_dir" || {
        log_error "Failed to create snippets directory"
        return 1
    }
    
    # Ensure SSH key exists
    ensure_ssh_key || return 1
    
    # Start building cloud-init config
    cat > "$user_data_file" << 'EOF'
#cloud-config
locale: en_US.UTF-8
timezone: UTC

users:
  - name: ${VM_USERNAME}
    plain_text_passwd: ${VM_PASSWORD}
    lock_passwd: false
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [adm, sudo]
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}
EOF
    
    # Add additional SSH keys if provided
    if [[ ${#SSH_KEYS[@]} -gt 0 ]]; then
        for key in "${SSH_KEYS[@]}"; do
            echo "      - $key" >> "$user_data_file"
        done
    fi
    
    # Add package installation
    if [[ ${#PACKAGES[@]} -gt 0 ]]; then
        echo "" >> "$user_data_file"
        echo "packages:" >> "$user_data_file"
        for pkg in "${PACKAGES[@]}"; do
            echo "  - $pkg" >> "$user_data_file"
        done
    fi
    
    # Add files to copy
    log_debug "FILES_TO_COPY array has ${#FILES_TO_COPY[@]} elements"
    if [[ ${#FILES_TO_COPY[@]} -gt 0 ]]; then
        echo "" >> "$user_data_file"
        echo "write_files:" >> "$user_data_file"
        
        for file_spec in "${FILES_TO_COPY[@]}"; do
            log_debug "Processing file spec: $file_spec"
            IFS=':' read -r src_path dest_path perms <<< "$file_spec"
            
            # Set default permissions if not specified
            [[ -z "$perms" ]] && perms="0644"
            
            if [[ ! -f "$src_path" ]]; then
                log_error "Source file not found: $src_path"
                return 1
            fi
            
            log_debug "Adding file: $src_path -> $dest_path (perms: $perms)"
            
            # Read file content and encode it
            local content=$(cat "$src_path" | sed 's/^/      /')
            
            cat >> "$user_data_file" << EOF
  - path: $dest_path
    permissions: '$perms'
    content: |
${content}
EOF
        done
    fi
    
    # Add scripts to run
    if [[ ${#SCRIPTS_TO_RUN[@]} -gt 0 ]]; then
        echo "" >> "$user_data_file"
        echo "runcmd:" >> "$user_data_file"
        
        for script in "${SCRIPTS_TO_RUN[@]}"; do
            echo "  - $script" >> "$user_data_file"
        done
    fi
    
    # Perform variable substitution
    local temp_file="${user_data_file}.tmp"
    envsubst < "$user_data_file" > "$temp_file" || {
        log_error "Failed to substitute variables in cloud-init config"
        rm -f "$temp_file"
        return 1
    }
    mv "$temp_file" "$user_data_file"
    
    chmod 644 "$user_data_file"
    log_info "Cloud-init configuration generated successfully"
    log_debug "Cloud-init file: $user_data_file"
    
    return 0
}

# Create VM
create_vm() {
    local image_name="ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
    
    log_info "Creating VM with ID ${VMID}..."
    
    # Create base VM
    if ! qm create "$VMID" \
        --name "$VM_NAME" \
        --memory "$VM_MEMORY" \
        --cores "$VM_CORES" \
        --cpu host \
        --net0 "virtio,bridge=${BRIDGE}" \
        --scsihw virtio-scsi-pci \
        --onboot 1 \
        --ostype l26; then
        log_error "Failed to create VM"
        return 1
    fi
    
    log_info "Importing disk image..."
    
    # Import disk
    local import_output
    if ! import_output=$(qm importdisk "$VMID" "$image_name" "$STORAGE" 2>&1); then
        log_error "Failed to import disk: $import_output"
        qm destroy "$VMID" &>/dev/null
        return 1
    fi
    
    # Attach disk
    log_debug "Attaching disk to VM..."
    if ! qm set "$VMID" --scsi0 "${STORAGE}:vm-${VMID}-disk-0" &>/dev/null; then
        log_error "Failed to attach disk"
        qm destroy "$VMID" &>/dev/null
        return 1
    fi
    
    # Resize disk if needed
    if [[ "$VM_DISK_SIZE" != "0" ]]; then
        log_info "Resizing disk to $VM_DISK_SIZE..."
        if ! qm resize "$VMID" scsi0 "$VM_DISK_SIZE" &>/dev/null; then
            log_error "Failed to resize disk"
            qm destroy "$VMID" &>/dev/null
            return 1
        fi
    fi
    
    # Configure VM settings
    log_info "Configuring VM settings..."
    
    # Add cloud-init drive
    if ! qm set "$VMID" --ide2 "${STORAGE}:cloudinit" &>/dev/null; then
        log_error "Failed to add cloud-init drive"
        qm destroy "$VMID" &>/dev/null
        return 1
    fi
    
    # Set boot order
    if ! qm set "$VMID" --boot c --bootdisk scsi0 &>/dev/null; then
        log_error "Failed to set boot order"
        qm destroy "$VMID" &>/dev/null
        return 1
    fi
    
    # Set serial console
    if ! qm set "$VMID" --serial0 socket --vga serial0 &>/dev/null; then
        log_error "Failed to set serial console"
        qm destroy "$VMID" &>/dev/null
        return 1
    fi
    
    # Configure network
    if ! qm set "$VMID" --ipconfig0 "ip=${STATIC_IP}/24,gw=${GATEWAY}" &>/dev/null; then
        log_error "Failed to configure network"
        qm destroy "$VMID" &>/dev/null
        return 1
    fi
    
    # Set cloud-init user data
    if ! qm set "$VMID" --cicustom "user=local:snippets/user-data-${VMID}.yaml" &>/dev/null; then
        log_error "Failed to set cloud-init user data"
        qm destroy "$VMID" &>/dev/null
        return 1
    fi
    
    log_info "VM created successfully"
    return 0
}

# Start VM
start_vm() {
    log_info "Starting VM..."
    
    if ! qm start "$VMID"; then
        log_error "Failed to start VM"
        return 1
    fi
    
    log_info "VM started successfully"
    return 0
}

# Clean up downloaded image
cleanup() {
    local image_name="ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
    
    # Only remove the symlink/copy, not the cached version
    if [[ -L "$image_name" ]] || [[ -f "$image_name" ]]; then
        rm -f "$image_name"
    fi
}

# Main function
main() {
    log_info "==================================="
    log_info "Generic Ubuntu VM Creation Script"
    log_info "==================================="
    log_info "VM ID: $VMID"
    log_info "VM Name: $VM_NAME"
    log_info "Ubuntu Version: $UBUNTU_VERSION"
    log_info "Memory: ${VM_MEMORY}MB"
    log_info "Cores: $VM_CORES"
    log_info "Disk Size: $VM_DISK_SIZE"
    log_info "Network: $STATIC_IP via $GATEWAY"
    log_info "==================================="
    
    # Run checks
    if ! check_prerequisites; then
        return 2
    fi
    
    if ! validate_configuration; then
        return 3
    fi
    
    # Download image
    if ! download_image; then
        return 1
    fi
    
    # Generate cloud-init
    if ! generate_cloud_init; then
        cleanup
        return 1
    fi
    
    # Create VM
    if ! create_vm; then
        cleanup
        return 4
    fi
    
    # Start VM
    if ! start_vm; then
        cleanup
        return 4
    fi
    
    # Clean up
    cleanup
    
    log_info "==================================="
    log_info "VM Creation Completed Successfully!"
    log_info "==================================="
    log_info "Access Information:"
    log_info "  SSH: ssh ${VM_USERNAME}@${STATIC_IP}"
    log_info "  Username: ${VM_USERNAME}"
    log_info "  Password: ${VM_PASSWORD}"
    log_info "  Console: qm terminal ${VMID}"
    log_info "==================================="
    
    return 0
}

# Run main function
main "$@"
exit $?