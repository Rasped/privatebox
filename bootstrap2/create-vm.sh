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
DEBIAN_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
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
    
    local image_name="debian-12-generic-amd64.qcow2"
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
EOF
    
    # Copy setup script (Phase 3)
    if [[ -f "${SCRIPT_DIR}/setup-guest.sh" ]]; then
        cp "${SCRIPT_DIR}/setup-guest.sh" "$WORK_DIR/privatebox-setup/"
        chmod +x "$WORK_DIR/privatebox-setup/setup-guest.sh"
    else
        # Create minimal placeholder for now
        cat > "$WORK_DIR/privatebox-setup/setup-guest.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

# Source configuration
source /etc/privatebox/config.env

# Log start
echo "PrivateBox guest setup started at $(date)" > /var/log/privatebox-setup.log

# TODO: Install Portainer
echo "Installing Portainer..." >> /var/log/privatebox-setup.log

# TODO: Install Semaphore
echo "Installing Semaphore..." >> /var/log/privatebox-setup.log

# Signal completion
echo "SUCCESS" > /etc/privatebox-install-complete
echo "Setup completed at $(date)" >> /var/log/privatebox-setup.log
EOF
        chmod +x "$WORK_DIR/privatebox-setup/setup-guest.sh"
    fi
    
    # Create tarball
    cd "$WORK_DIR"
    tar -czf privatebox-setup.tar.gz privatebox-setup/
    
    # Encode for cloud-init
    SETUP_TARBALL_B64=$(base64 -w0 < "$WORK_DIR/privatebox-setup.tar.gz")
    
    log "Setup package created: $(du -h $WORK_DIR/privatebox-setup.tar.gz | cut -f1)"
    display "  ✓ Setup package created"
}

# Generate cloud-init configuration
generate_cloud_init() {
    display "Generating cloud-init configuration..."
    
    # Get host SSH public key if available
    local ssh_key=""
    if [[ -f /root/.ssh/id_rsa.pub ]]; then
        ssh_key=$(cat /root/.ssh/id_rsa.pub)
        log "Including host SSH public key"
    else
        log "No SSH public key found, password auth only"
    fi
    
    # Create minimal cloud-init user-data
    cat > "$WORK_DIR/user-data" <<EOF
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

  - path: /tmp/privatebox-setup.tar.gz
    permissions: '0644'
    encoding: b64
    content: $SETUP_TARBALL_B64

  - path: /usr/local/bin/bootstrap-phase3.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      set -euo pipefail
      
      # Create marker directory
      mkdir -p /etc/privatebox
      
      # Extract setup package
      cd /tmp
      tar -xzf privatebox-setup.tar.gz
      
      # Run setup
      /tmp/privatebox-setup/setup-guest.sh
      
      # Cleanup
      rm -rf /tmp/privatebox-setup*

runcmd:
  - [mkdir, -p, /etc/privatebox]
  - [mkdir, -p, /var/log]
  - [/usr/local/bin/bootstrap-phase3.sh]

final_message: "PrivateBox bootstrap phase 3 initiated"
EOF

    # Create meta-data
    cat > "$WORK_DIR/meta-data" <<EOF
instance-id: privatebox-${VMID}
local-hostname: privatebox-management
EOF

    # Create ISO
    cd "$WORK_DIR"
    if command -v genisoimage &>/dev/null; then
        genisoimage -output cloud-init.iso -volid cidata -joliet -rock user-data meta-data &>/dev/null
    elif command -v mkisofs &>/dev/null; then
        mkisofs -output cloud-init.iso -volid cidata -joliet -rock user-data meta-data &>/dev/null
    else
        error_exit "No ISO creation tool found (genisoimage or mkisofs)"
    fi
    
    log "Cloud-init ISO created"
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
    
    # Configure cloud-init network settings and SSH key
    local ssh_pub_key=""
    if [[ -f /root/.ssh/id_rsa.pub ]]; then
        ssh_pub_key=$(cat /root/.ssh/id_rsa.pub)
    fi
    
    qm set $VMID \
        --ipconfig0 ip=${STATIC_IP}/${NETMASK},gw=${GATEWAY} \
        --nameserver ${GATEWAY} \
        ${ssh_pub_key:+--sshkey /root/.ssh/id_rsa.pub} \
        || error_exit "Failed to configure cloud-init"
    
    # Attach custom cloud-init ISO
    cp "$WORK_DIR/cloud-init.iso" "/var/lib/vz/template/iso/cloud-init-${VMID}.iso" 2>/dev/null || \
        cp "$WORK_DIR/cloud-init.iso" "/tmp/cloud-init-${VMID}.iso"
    
    if [[ -f "/var/lib/vz/template/iso/cloud-init-${VMID}.iso" ]]; then
        qm set $VMID --ide1 local:iso/cloud-init-${VMID}.iso,media=cdrom || \
            error_exit "Failed to attach cloud-init ISO"
    else
        qm set $VMID --ide1 /tmp/cloud-init-${VMID}.iso,media=cdrom || \
            error_exit "Failed to attach cloud-init ISO"
    fi
    
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

# Run main
main "$@"