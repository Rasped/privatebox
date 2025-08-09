#!/bin/bash
#
# PrivateBox Bootstrap v2 - Phase 2: VM Provisioning
# Create VM with minimal cloud-init and tarball payload
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/privatebox-bootstrap.log"
CONFIG_FILE="/tmp/privatebox-config.conf"
WORK_DIR="/tmp/privatebox-vm-creation"
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64-daily.qcow2"
IMAGE_CACHE_DIR="/var/lib/vz/template/cache"

# Source configuration
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: Configuration file not found: $CONFIG_FILE" >&2
    exit 1
fi
source "$CONFIG_FILE"

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

display() {
    echo "$1"
    log "$1"
}

error_exit() {
    echo "ERROR: $1" >&2
    log "ERROR: $1"
    exit 1
}

# Download Debian image
download_image() {
    display "Downloading Debian cloud image..."
    
    local image_name="debian-13-generic-amd64-daily.qcow2"
    local image_path="${IMAGE_CACHE_DIR}/${image_name}"
    
    # Create cache directory if needed
    mkdir -p "$IMAGE_CACHE_DIR"
    
    # Check if image already exists
    if [[ -f "$image_path" ]]; then
        display "  Using cached image"
        log "Using cached image: $image_path"
    else
        display "  Downloading from Debian cloud..."
        if ! wget -q --show-progress -O "$image_path" "$DEBIAN_IMAGE_URL"; then
            rm -f "$image_path"
            error_exit "Failed to download Debian image"
        fi
        log "Downloaded image to $image_path"
    fi
    
    # Verify image
    if [[ ! -f "$image_path" ]] || [[ $(stat -c%s "$image_path") -lt 1000000 ]]; then
        rm -f "$image_path"
        error_exit "Invalid or corrupted image file"
    fi
    
    DEBIAN_IMAGE="$image_path"
    display "  ✓ Debian image ready"
}

# Create setup tarball
create_setup_tarball() {
    display "Creating setup package..."
    
    # Create work directory
    rm -rf "$WORK_DIR"
    mkdir -p "$WORK_DIR/privatebox-setup"
    
    # Create guest config (subset of main config)
    cat > "$WORK_DIR/privatebox-setup/config.env" <<EOF
# PrivateBox Guest Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# User Configuration
VM_USERNAME="$VM_USERNAME"
ADMIN_PASSWORD="$ADMIN_PASSWORD"
SERVICES_PASSWORD="$SERVICES_PASSWORD"

# Network Configuration
STATIC_IP="$STATIC_IP"
GATEWAY="$GATEWAY"
NETMASK="$NETMASK"

# Proxmox API Token
PROXMOX_TOKEN_ID="$PROXMOX_TOKEN_ID"
PROXMOX_TOKEN_SECRET="$PROXMOX_TOKEN_SECRET"
PROXMOX_API_HOST="$PROXMOX_API_HOST"
PROXMOX_NODE="$PROXMOX_NODE"
EOF
    
    # Load setup script content for embedding
    if [[ -f "${SCRIPT_DIR}/setup-guest.sh" ]]; then
        SETUP_SCRIPT_CONTENT=$(cat "${SCRIPT_DIR}/setup-guest.sh" | sed 's/^/      /')
        log "Setup script loaded for cloud-init embedding"
    else
        error_exit "setup-guest.sh not found at ${SCRIPT_DIR}/setup-guest.sh"
    fi
    
    display "  ✓ Setup package prepared"
}

# Generate cloud-init configuration
generate_cloud_init() {
    display "Generating cloud-init configuration..."
    
    # Enable snippets on local storage if not already enabled
    local storage_config=$(pvesm status -content | grep "^local " || true)
    if [[ -n "$storage_config" ]] && ! echo "$storage_config" | grep -q "snippets"; then
        log "Enabling snippets on local storage"
        pvesm set local --content vztmpl,iso,backup,snippets || true
    fi
    
    # Create snippets directory if it doesn't exist
    mkdir -p /var/lib/vz/snippets
    
    # Get host SSH public key if available
    local ssh_key=""
    if [[ -f /root/.ssh/id_rsa.pub ]]; then
        ssh_key=$(cat /root/.ssh/id_rsa.pub)
        log "Including host SSH public key"
    else
        log "No SSH public key found, password auth only"
    fi
    
    # Get Proxmox private SSH key for Semaphore
    local proxmox_private_key=""
    if [[ -f /root/.ssh/id_rsa ]]; then
        proxmox_private_key=$(cat /root/.ssh/id_rsa | sed 's/^/      /')
        log "Including Proxmox private SSH key for Semaphore"
    else
        log "No Proxmox private SSH key found"
    fi
    
    # Load Semaphore API library for embedding
    local semaphore_api_content=""
    if [[ -f "${SCRIPT_DIR}/lib/semaphore-api.sh" ]]; then
        semaphore_api_content=$(cat "${SCRIPT_DIR}/lib/semaphore-api.sh" | sed 's/^/      /')
        log "Semaphore API library loaded for cloud-init embedding"
    else
        log "WARNING: Semaphore API library not found at ${SCRIPT_DIR}/lib/semaphore-api.sh"
    fi
    
    # Create custom user-data snippet
    cat > "/var/lib/vz/snippets/privatebox-${VMID}.yml" <<EOF
#cloud-config
hostname: privatebox-management
manage_etc_hosts: true

users:
  - name: $VM_USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(openssl passwd -6 "$ADMIN_PASSWORD")
$(if [[ -n "$ssh_key" ]]; then echo "    ssh_authorized_keys:"; echo "      - $ssh_key"; fi)

ssh_pwauth: true

write_files:
  - path: /etc/privatebox/config.env
    permissions: '0600'
    content: |
$(sed 's/^/      /' < "$WORK_DIR/privatebox-setup/config.env")

  - path: /usr/local/bin/setup-guest.sh
    permissions: '0755'
    content: |
$SETUP_SCRIPT_CONTENT

$(if [[ -n "$proxmox_private_key" ]]; then
echo "  - path: /root/.credentials/proxmox_ssh_key"
echo "    permissions: '0600'"
echo "    owner: root:root"
echo "    content: |"
echo "$proxmox_private_key"
fi)

  - path: /etc/privatebox-proxmox-host
    permissions: '0644'
    owner: root:root
    content: |
      ${PROXMOX_HOST}

$(if [[ -n "$semaphore_api_content" ]]; then
echo "  - path: /usr/local/lib/semaphore-api.sh"
echo "    permissions: '0755'"
echo "    owner: root:root"
echo "    content: |"
echo "$semaphore_api_content"
fi)

runcmd:
  - [mkdir, -p, /etc/privatebox]
  - [mkdir, -p, /var/log]
  - ['/bin/bash', '/usr/local/bin/setup-guest.sh']

final_message: "PrivateBox bootstrap phase 3 initiated"
EOF
    
    log "Cloud-init snippet created at /var/lib/vz/snippets/privatebox-${VMID}.yml"
    display "  ✓ Cloud-init configuration ready"
}

# Create and configure VM
create_vm() {
    display "Creating VM $VMID..."
    
    # Import disk image
    local vm_disk="${VM_STORAGE}:${VM_DISK_SIZE}"
    
    display "  Importing disk image..."
    qm create $VMID \
        --name privatebox-management \
        --memory $VM_MEMORY \
        --cores $VM_CORES \
        --net0 virtio,bridge=$VM_NET_BRIDGE \
        --serial0 socket \
        --vga serial0 \
        --agent enabled=1 \
        || error_exit "Failed to create VM"
    
    # Import the disk image
    qm importdisk $VMID "$DEBIAN_IMAGE" $VM_STORAGE &>/dev/null || error_exit "Failed to import disk"
    
    # Attach the disk
    qm set $VMID \
        --scsihw virtio-scsi-pci \
        --scsi0 ${VM_STORAGE}:vm-${VMID}-disk-0 \
        --boot c --bootdisk scsi0 \
        || error_exit "Failed to attach disk"
    
    # Resize disk to specified size
    qm resize $VMID scsi0 $VM_DISK_SIZE &>/dev/null || error_exit "Failed to resize disk"
    
    # Add cloud-init drive for network configuration
    qm set $VMID --ide2 ${VM_STORAGE}:cloudinit || error_exit "Failed to add cloud-init drive"
    
    # Configure cloud-init with custom user-data snippet
    qm set $VMID \
        --ipconfig0 ip=${STATIC_IP}/${NETMASK},gw=${GATEWAY} \
        --nameserver ${GATEWAY} \
        --cicustom "user=local:snippets/privatebox-${VMID}.yml" \
        || error_exit "Failed to configure cloud-init"
    
    log "VM $VMID created successfully"
    display "  ✓ VM configuration complete"
}

# Start VM
start_vm() {
    display "Starting VM $VMID..."
    
    if ! qm start $VMID; then
        error_exit "Failed to start VM"
    fi
    
    # Wait for VM to be fully started
    local max_wait=30
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if qm status $VMID 2>/dev/null | grep -q "running"; then
            log "VM $VMID is running"
            display "  ✓ VM started successfully"
            return 0
        fi
        sleep 1
        ((waited++))
    done
    
    error_exit "VM failed to start within ${max_wait} seconds"
}

# Cleanup
cleanup() {
    if [[ -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}

# Main execution
main() {
    display "Starting VM provisioning..."
    log "Phase 2: VM provisioning started"
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    # Download Debian image
    download_image
    
    # Create setup tarball
    create_setup_tarball
    
    # Generate cloud-init
    generate_cloud_init
    
    # Create VM
    create_vm
    
    # Start VM
    start_vm
    
    display ""
    display "✓ VM provisioning complete"
    display "  VM ID: $VMID"
    display "  IP Address: $STATIC_IP"
    display "  Cloud-init will configure the system..."
    
    log "Phase 2 completed successfully"
}

# Cleanup function
cleanup() {
    # NOTE: Don't remove snippet file - it's needed by cloud-init when VM boots
    # Snippet will be cleaned up when VM is destroyed
    
    # Remove work directory only
    [[ -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
}

# Set trap for cleanup on exit
trap cleanup EXIT

# Run main
main "$@"