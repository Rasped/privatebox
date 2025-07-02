#!/bin/bash
# Create Ubuntu VM Script
# Creates an Ubuntu VM on Proxmox with PrivateBox services pre-installed
#
# Exit codes:
#   0 - Success
#   1 - General error
#   2 - Missing dependencies
#   3 - Invalid configuration
#   4 - VM operations failed

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh" || {
    echo "ERROR: Cannot source common library" >&2
    exit 1
}

# Setup standardized error handling
setup_error_handling

# Check required commands
require_command "qm" "qm command is required (Proxmox VE)"
require_command "wget" "wget is required for downloading images"
require_command "pvesm" "pvesm command is required (Proxmox storage)"
require_command "cat" "cat command is required"
require_command "sed" "sed is required for text processing"

# --- Locale Configuration ---
# Description: Configures the script's locale to ensure consistent output.
# ---
# Configure locales
export LANGUAGE="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export LANG="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

# Define image cache directory
IMAGE_CACHE_DIR="/var/cache/privatebox/images"

# Ensure locale is available and generated
if [ -f /etc/locale.gen ]; then
    sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    locale-gen
fi

# --- Script Configuration ---
# Description: Loads configuration and defines parameters for the Proxmox VM.
# ---

# Parse command line arguments
AUTO_DISCOVER=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto-discover)
            AUTO_DISCOVER=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --auto-discover  Automatically discover network configuration"
            echo "  --help, -h       Show this help message"
            echo ""
            echo "The script creates an Ubuntu VM on Proxmox with PrivateBox services."
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit ${EXIT_ERROR}
            ;;
    esac
done

# Load configuration file
CONFIG_FILE="$(dirname "${BASH_SOURCE[0]}")/../config/privatebox.conf"

# Run network discovery if requested or if config doesn't exist
if [[ "$AUTO_DISCOVER" == "true" ]] || [[ ! -f "$CONFIG_FILE" ]]; then
    log_info "Running network discovery..."
    NETWORK_DISCOVERY_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/network-discovery.sh"
    
    if [[ -f "$NETWORK_DISCOVERY_SCRIPT" ]]; then
        # Run network discovery to generate config
        "$NETWORK_DISCOVERY_SCRIPT" --auto || check_result $? "Network discovery failed"
        log_info "Network discovery completed successfully"
    else
        log_error "Network discovery script not found: $NETWORK_DISCOVERY_SCRIPT"
        exit ${EXIT_ERROR}
    fi
fi

if [[ -f "$CONFIG_FILE" ]]; then
    log_info "Loading configuration from: $CONFIG_FILE"
    # shellcheck source=../config/privatebox.conf
    source "$CONFIG_FILE"
else
    log_warn "Configuration file not found, using defaults: $CONFIG_FILE"
    # Default configuration values
    VMID=9000
    UBUNTU_VERSION="24.04"
    VM_USERNAME="ubuntuadmin"
    VM_PASSWORD="Changeme123"
    VM_MEMORY=4096
    VM_CORES=2
    STATIC_IP="192.168.1.22"
    GATEWAY="192.168.1.3"
    NET_BRIDGE="vmbr0"
    STORAGE="local-lvm"
fi

# Allow environment variables to override config file
VMID="${VMID:-9000}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
VM_USERNAME="${VM_USERNAME:-ubuntuadmin}"
VM_PASSWORD="${VM_PASSWORD:-Changeme123}"

# Generate Semaphore admin password if not already set
if [[ -z "${SEMAPHORE_ADMIN_PASSWORD:-}" ]]; then
    SEMAPHORE_ADMIN_PASSWORD=$(generate_password)
    log_info "Generated Semaphore admin password"
    
    # Save to config file if it exists
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "SEMAPHORE_ADMIN_PASSWORD=\"${SEMAPHORE_ADMIN_PASSWORD}\"" >> "$CONFIG_FILE"
        log_info "Saved Semaphore password to config file"
    fi
fi

# Fixed values
OSTYPE="l26" # l26 corresponds to a modern Linux Kernel (5.x +)

# Validate Ubuntu version format
if [[ ! $UBUNTU_VERSION =~ ^[0-9]+\.[0-9]+$ ]]; then
    log_error "Invalid Ubuntu version format: $UBUNTU_VERSION"
    exit ${EXIT_INVALID_CONFIG:-3}
fi

# Construct URLs based on version
CLOUD_IMG_URL="${CLOUD_IMG_BASE_URL:-https://cloud-images.ubuntu.com/releases}/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
IMAGE_NAME="ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"

# Validate configuration
if ! validate_config; then
    log_error "Configuration validation failed. Please fix the errors above."
    exit ${EXIT_INVALID_CONFIG:-3}
fi

# --- Cloud-Init Configuration ---
# Description: Sets up the directory for cloud-init snippets.
# ---
# Ensure persistent storage location for snippets
SNIPPETS_DIR="/var/lib/vz/snippets" # Proxmox's default snippet location
USER_DATA_FILE="${SNIPPETS_DIR}/user-data-${VMID}.yaml"
mkdir -p "${SNIPPETS_DIR}" || check_result $? "Failed to create snippets directory"

# --- Prerequisite Checks ---
# Description: Verifies that required commands are available.
# ---
log_info "Starting PrivateBox VM creation script"

# Check for root permissions
check_root

# Verify we're on Proxmox
if ! is_proxmox; then
    log_error "This script must be run on a Proxmox VE host"
    exit ${EXIT_NOT_PROXMOX}
fi

# Validate inputs
if [[ ! $VMID =~ ^[0-9]+$ ]]; then
    log_error "VMID must be a number: $VMID"
    exit ${EXIT_INVALID_CONFIG:-3}
fi

# Validate IP addresses using common library
if ! validate_ip "$STATIC_IP"; then
    log_error "Invalid static IP address format: $STATIC_IP"
    exit ${EXIT_INVALID_CONFIG:-3}
fi

if ! validate_ip "$GATEWAY"; then
    log_error "Invalid gateway IP address format: $GATEWAY"
    exit ${EXIT_INVALID_CONFIG:-3}
fi

# --- Function Definitions ---

# --- check_and_remove_vm ---
# Description: Checks if a VM with the specified VMID already exists. If it does,
#              the function stops and removes it to prevent conflicts.
# ---
# Check for existing VM and remove if found
function check_and_remove_vm() {
    log_info "Checking for existing VM with ID ${VMID}..."
    if qm status "${VMID}" >/dev/null 2>&1; then
        log_warn "Found existing VM with ID ${VMID}"
        log_info "Stopping existing VM..."
        if ! qm stop "${VMID}" >/dev/null 2>&1; then
            log_warn "Failed to stop VM cleanly, forcing stop..."
            qm stop "${VMID}" -skiplock >/dev/null 2>&1
        fi
        
        log_info "Waiting for VM to stop..."
        for i in {1..30}; do
            if ! qm status "${VMID}" | grep -q running; then
                break
            fi
            sleep 1
        done
        
        log_info "Removing existing VM..."
        if ! qm destroy "${VMID}" >/dev/null 2>&1; then
            log_error "Failed to remove existing VM"
            exit ${EXIT_VM_OPERATION_FAILED:-4}
        fi
        log_info "Existing VM removed successfully."
    else
        log_info "No existing VM found with ID ${VMID}"
    fi
}

# --- download_image ---
# Description: Downloads the Ubuntu cloud image. It includes checks for an
#              existing, complete image and retries on failure.
# ---
# Download Ubuntu cloud image
function download_image() {
    echo "Downloading Ubuntu ${UBUNTU_VERSION} cloud image..."
    
    # Create cache directory if it doesn't exist
    if [[ ! -d "${IMAGE_CACHE_DIR}" ]]; then
        log_info "Creating image cache directory: ${IMAGE_CACHE_DIR}"
        mkdir -p "${IMAGE_CACHE_DIR}" || check_result $? "Failed to create cache directory"
    fi
    
    # Define cached image path
    local cached_image="${IMAGE_CACHE_DIR}/${IMAGE_NAME}"
    
    # Check if image already exists in cache
    if [ -f "${cached_image}" ]; then
        echo "Found existing image in cache, checking if it's complete..."
        if wget --spider -q -show-progress "${CLOUD_IMG_URL}" 2>/dev/null; then
            REMOTE_SIZE=$(wget --spider "${CLOUD_IMG_URL}" 2>&1 | grep Length | awk '{print $2}')
            LOCAL_SIZE=$(stat -f%z "${cached_image}" 2>/dev/null || stat -c%s "${cached_image}")
            
            if [ "${REMOTE_SIZE}" = "${LOCAL_SIZE}" ]; then
                echo "Cached image is complete, using cached version"
                # Create a symlink or copy to current directory for VM creation
                ln -sf "${cached_image}" "${IMAGE_NAME}" || cp "${cached_image}" "${IMAGE_NAME}"
                return 0
            fi
        fi
        echo "Cached image is incomplete or corrupted, re-downloading..."
        rm -f "${cached_image}"
    fi
    
    # Download with progress and retry support
    for i in {1..3}; do
        echo "Downloading ${IMAGE_NAME} to cache..."
        if wget -q --continue -O "${cached_image}" "${CLOUD_IMG_URL}"; then
            echo "Download completed."
            break
        fi
        if [ $i -eq 3 ]; then
            echo "Error: Failed to download cloud image after 3 attempts"
            exit 1
        fi
        echo "Download failed, retrying in 5 seconds..."
        sleep 5
    done
    
    if [ ! -f "${cached_image}" ]; then
        echo "Error: Failed to download cloud image"
        exit 1
    fi
    
    echo "Ubuntu cloud image downloaded successfully to cache."
    
    # Create a symlink or copy to current directory for VM creation
    ln -sf "${cached_image}" "${IMAGE_NAME}" || cp "${cached_image}" "${IMAGE_NAME}"
}

# --- ensure_ssh_key ---
# Description: Ensures an SSH key exists for the Proxmox host to access VMs
# ---
function ensure_ssh_key() {
    local SSH_KEY_PATH="/root/.ssh/id_rsa"
    local SSH_PUB_KEY_PATH="${SSH_KEY_PATH}.pub"
    
    # Check if SSH key already exists
    if [ -f "${SSH_PUB_KEY_PATH}" ]; then
        log_info "Using existing SSH key: ${SSH_PUB_KEY_PATH}"
        SSH_PUBLIC_KEY=$(cat "${SSH_PUB_KEY_PATH}")
    else
        log_info "Generating new SSH key pair for VM access..."
        
        # Create .ssh directory if it doesn't exist
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        
        # Generate SSH key with no passphrase
        ssh-keygen -t rsa -b 4096 -f "${SSH_KEY_PATH}" -N "" -C "privatebox@$(hostname)" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log_success "SSH key generated successfully"
            SSH_PUBLIC_KEY=$(cat "${SSH_PUB_KEY_PATH}")
        else
            log_error "Failed to generate SSH key"
            exit 1
        fi
    fi
    
    # Export for use in cloud-init
    export SSH_PUBLIC_KEY
}

# --- generate_cloud_init ---
# Description: Creates a cloud-init user-data file. This file configures the new VM,
#              including user setup, package installation, and running setup scripts.
# ---
# Generate cloud-init configuration
function generate_cloud_init() {
    echo "Generating cloud-init configuration..."
    
    # Ensure SSH key exists
    ensure_ssh_key
    
    # Read all lib files and setup scripts into variables to ensure they're available
    local initial_setup_content
    local portainer_setup_content
    local semaphore_setup_content
    local common_lib_content
    local bootstrap_logger_content
    local constants_content
    local validation_content
    local error_handler_content
    local service_manager_content
    local ssh_manager_content
    local config_manager_content
    
    # Read lib files
    if [[ -f "${SCRIPT_DIR}/../lib/common.sh" ]]; then
        common_lib_content=$(cat "${SCRIPT_DIR}/../lib/common.sh" | sed 's/^/      /')
    else
        log_error "Cannot find common.sh"
        return 1
    fi
    
    if [[ -f "${SCRIPT_DIR}/../lib/bootstrap_logger.sh" ]]; then
        bootstrap_logger_content=$(cat "${SCRIPT_DIR}/../lib/bootstrap_logger.sh" | sed 's/^/      /')
    else
        log_error "Cannot find bootstrap_logger.sh"
        return 1
    fi
    
    if [[ -f "${SCRIPT_DIR}/../lib/constants.sh" ]]; then
        constants_content=$(cat "${SCRIPT_DIR}/../lib/constants.sh" | sed 's/^/      /')
    else
        log_error "Cannot find constants.sh"
        return 1
    fi
    
    if [[ -f "${SCRIPT_DIR}/../lib/validation.sh" ]]; then
        validation_content=$(cat "${SCRIPT_DIR}/../lib/validation.sh" | sed 's/^/      /')
    else
        log_error "Cannot find validation.sh"
        return 1
    fi
    
    if [[ -f "${SCRIPT_DIR}/../lib/error_handler.sh" ]]; then
        error_handler_content=$(cat "${SCRIPT_DIR}/../lib/error_handler.sh" | sed 's/^/      /')
    else
        log_error "Cannot find error_handler.sh"
        return 1
    fi
    
    if [[ -f "${SCRIPT_DIR}/../lib/service_manager.sh" ]]; then
        service_manager_content=$(cat "${SCRIPT_DIR}/../lib/service_manager.sh" | sed 's/^/      /')
    else
        log_error "Cannot find service_manager.sh"
        return 1
    fi
    
    if [[ -f "${SCRIPT_DIR}/../lib/ssh_manager.sh" ]]; then
        ssh_manager_content=$(cat "${SCRIPT_DIR}/../lib/ssh_manager.sh" | sed 's/^/      /')
    else
        log_error "Cannot find ssh_manager.sh"
        return 1
    fi
    
    if [[ -f "${SCRIPT_DIR}/../lib/config_manager.sh" ]]; then
        config_manager_content=$(cat "${SCRIPT_DIR}/../lib/config_manager.sh" | sed 's/^/      /')
    else
        log_error "Cannot find config_manager.sh"
        return 1
    fi
    
    # Read setup scripts
    if [[ -f "${SCRIPT_DIR}/initial-setup.sh" ]]; then
        initial_setup_content=$(cat "${SCRIPT_DIR}/initial-setup.sh" | sed 's/^/      /')
    else
        log_error "Cannot find initial-setup.sh at ${SCRIPT_DIR}/initial-setup.sh"
        return 1
    fi
    
    if [[ -f "${SCRIPT_DIR}/portainer-setup.sh" ]]; then
        portainer_setup_content=$(cat "${SCRIPT_DIR}/portainer-setup.sh" | sed 's/^/      /')
    else
        log_error "Cannot find portainer-setup.sh at ${SCRIPT_DIR}/portainer-setup.sh"
        return 1
    fi
    
    if [[ -f "${SCRIPT_DIR}/semaphore-setup.sh" ]]; then
        semaphore_setup_content=$(cat "${SCRIPT_DIR}/semaphore-setup.sh" | sed 's/^/      /')
    else
        log_error "Cannot find semaphore-setup.sh at ${SCRIPT_DIR}/semaphore-setup.sh"
        return 1
    fi
    
    cat > "${USER_DATA_FILE}" <<EOF
#cloud-config
locale: en_US.UTF-8
locale_configfile: /etc/default/locale
shell: ['/bin/bash', '-c']
users:
  - name: ${VM_USERNAME}
    plain_text_passwd: ${VM_PASSWORD}
    lock_passwd: false
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: [adm, sudo]
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}

# Enable SSH and configure it
ssh_pwauth: True
ssh:
  install-server: true
  allow_pw_auth: true
  ssh_quiet_keygen: true
  allow_agent_forwarding: true
  allow_tcp_forwarding: true

# Ensure the password doesn't expire
chpasswd:
  expire: False
packages:
  - language-pack-en
  - podman
  - buildah
  - skopeo
  - openssh-server

# Post-installation setup script
write_files:
  - path: /etc/privatebox-semaphore-password
    permissions: '0600'
    content: |
      SEMAPHORE_ADMIN_PASSWORD="${SEMAPHORE_ADMIN_PASSWORD}"
  - path: /usr/local/lib/constants.sh
    permissions: '0644'
    content: |
${constants_content}
  - path: /usr/local/lib/bootstrap_logger.sh
    permissions: '0644'
    content: |
${bootstrap_logger_content}
  - path: /usr/local/lib/validation.sh
    permissions: '0644'
    content: |
${validation_content}
  - path: /usr/local/lib/common.sh
    permissions: '0644'
    content: |
${common_lib_content}
  - path: /usr/local/lib/error_handler.sh
    permissions: '0644'
    content: |
${error_handler_content}
  - path: /usr/local/lib/service_manager.sh
    permissions: '0644'
    content: |
${service_manager_content}
  - path: /usr/local/lib/ssh_manager.sh
    permissions: '0644'
    content: |
${ssh_manager_content}
  - path: /usr/local/lib/config_manager.sh
    permissions: '0644'
    content: |
${config_manager_content}
  - path: /usr/local/bin/post-install-setup.sh
    permissions: '0755'
    content: |
${initial_setup_content}
  - path: /usr/local/bin/portainer-setup.sh
    permissions: '0755'
    content: |
${portainer_setup_content}
  - path: /usr/local/bin/semaphore-setup.sh
    permissions: '0755'
    content: |
${semaphore_setup_content}
  - path: /etc/privatebox-cloud-init-complete
    permissions: '0644'
    content: |
      # Cloud-init completion marker
      COMPLETED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  - path: /usr/local/bin/wait-for-services.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Helper script to wait for services to be fully operational
      
      wait_for_service() {
          local service="\$1"
          local port="\$2"
          local max_wait="\${3:-120}"  # Default 2 minutes
          local wait_count=0
          
          echo "Waiting for \$service to be active..."
          while [ \$wait_count -lt \$max_wait ]; do
              if systemctl is-active "\$service" >/dev/null 2>&1; then
                  # Service is active, now check if port is listening
                  if [ -n "\$port" ] && command -v nc >/dev/null 2>&1; then
                      if nc -z localhost "\$port" 2>/dev/null; then
                          echo "\$service is active and listening on port \$port"
                          return 0
                      fi
                  else
                      echo "\$service is active"
                      return 0
                  fi
              fi
              sleep 1
              wait_count=\$((wait_count + 1))
              if [ \$((wait_count % 30)) -eq 0 ]; then
                  echo "Still waiting for \$service... (\$wait_count seconds elapsed)"
              fi
          done
          
          echo "Timeout waiting for \$service"
          return 1
      }
      
      # Wait for both services
      PORTAINER_OK=false
      SEMAPHORE_OK=false
      
      if wait_for_service "portainer.service" "9000" 180; then
          PORTAINER_OK=true
      fi
      
      if wait_for_service "semaphore-ui.service" "3000" 180; then
          SEMAPHORE_OK=true
      fi
      
      # Return success only if both services are OK
      if [ "\$PORTAINER_OK" = true ] && [ "\$SEMAPHORE_OK" = true ]; then
          echo "All services are operational!"
          exit 0
      else
          echo "Some services failed to start properly"
          exit 1
      fi
  - path: /usr/local/bin/cloud-init-main.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Main cloud-init execution script
      # This script is executed with bash to ensure proper error handling
      
      # Error handling function
      write_error_status() {
        local stage="\$1"
        local error_msg="\$2"
        local exit_code="\${3:-1}"
        
        echo "INSTALLATION_STATUS=failed" > /etc/privatebox-cloud-init-complete
        echo "ERROR_STAGE=\${stage}" >> /etc/privatebox-cloud-init-complete
        echo "ERROR_MESSAGE=\${error_msg}" >> /etc/privatebox-cloud-init-complete
        echo "ERROR_CODE=\${exit_code}" >> /etc/privatebox-cloud-init-complete
        echo "FAILED_AT=\$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /etc/privatebox-cloud-init-complete
        
        # Also log to cloud-init output
        echo "ERROR: Installation failed at stage '\${stage}': \${error_msg} (exit code: \${exit_code})"
        exit \${exit_code}
      }
      
      # Set error trap - this is bash-specific and now safe to use
      trap 'write_error_status "unknown" "Unexpected error occurred" \$?' ERR
      
      # Start installation tracking
      echo "INSTALLATION_STATUS=running" > /etc/privatebox-cloud-init-complete
      echo "STARTED_AT=\$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> /etc/privatebox-cloud-init-complete
      
      # Locale configuration
      echo "Configuring locale..."
      locale-gen en_US.UTF-8 || write_error_status "locale-gen" "Failed to generate locale" \$?
      update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LANGUAGE=en_US.UTF-8 || write_error_status "update-locale" "Failed to update locale" \$?
      
      # Podman configuration
      echo "Configuring Podman for user ${VM_USERNAME}"
      loginctl enable-linger ${VM_USERNAME} || write_error_status "loginctl" "Failed to enable user linger" \$?
      mkdir -p /etc/containers || write_error_status "mkdir-containers" "Failed to create containers directory" \$?
      echo "unqualified-search-registries = ['docker.io']" > /etc/containers/registries.conf || write_error_status "registries-conf" "Failed to configure registries" \$?
      su - ${VM_USERNAME} -c "podman system migrate || true"
      
      # SSH configuration
      echo "Configuring SSH server..."
      systemctl enable ssh || write_error_status "ssh-enable" "Failed to enable SSH service" \$?
      systemctl start ssh || write_error_status "ssh-start" "Failed to start SSH service" \$?
      ufw allow 22/tcp || write_error_status "ufw-ssh" "Failed to configure firewall for SSH" \$?
      
      # Main setup script
      echo "Executing post-installation setup script..."
      export SEMAPHORE_ADMIN_PASSWORD="${SEMAPHORE_ADMIN_PASSWORD}"
      if ! /usr/local/bin/post-install-setup.sh; then
        write_error_status "post-install-setup" "Post-installation setup script failed" \$?
      fi
      
      # Install netcat for port checking
      apt-get update && apt-get install -y netcat-openbsd || write_error_status "apt-netcat" "Failed to install netcat" \$?
      
      # Use the wait-for-services script to ensure services are fully operational
      echo "Waiting for services to be fully operational..."
      if /usr/local/bin/wait-for-services.sh; then
        echo "All services verified as operational"
        SERVICES_OK=true
      else
        echo "Warning: Some services may not be fully operational"
        SERVICES_OK=false
      fi
      
      # Clear trap for final status writing
      trap - ERR
      
      # Create completion marker with detailed status
      echo "COMPLETED_AT=\$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /etc/privatebox-cloud-init-complete
      echo "PORTAINER_STATUS=\$(systemctl is-active portainer.service 2>/dev/null || echo 'not-found')" >> /etc/privatebox-cloud-init-complete
      echo "SEMAPHORE_STATUS=\$(systemctl is-active semaphore-ui.service 2>/dev/null || echo 'not-found')" >> /etc/privatebox-cloud-init-complete
      
      # Check if ports are actually listening
      if command -v nc >/dev/null 2>&1; then
        nc -z localhost 9000 2>/dev/null && echo "PORTAINER_PORT=listening" >> /etc/privatebox-cloud-init-complete || echo "PORTAINER_PORT=not-listening" >> /etc/privatebox-cloud-init-complete
        nc -z localhost 3000 2>/dev/null && echo "SEMAPHORE_PORT=listening" >> /etc/privatebox-cloud-init-complete || echo "SEMAPHORE_PORT=not-listening" >> /etc/privatebox-cloud-init-complete
      fi
      
      # Only mark as completed if all services are running and verified
      if [ "\$SERVICES_OK" = true ]; then
        echo "INSTALLATION_STATUS=success" >> /etc/privatebox-cloud-init-complete
        echo "SERVICES_STATUS=completed" >> /etc/privatebox-cloud-init-complete
        echo "Cloud-init setup completed successfully with all services running and verified"
      else
        echo "INSTALLATION_STATUS=partial" >> /etc/privatebox-cloud-init-complete
        echo "SERVICES_STATUS=partial" >> /etc/privatebox-cloud-init-complete
        echo "Cloud-init completed but some services may not be fully operational"
      fi

runcmd:
  # Execute the main cloud-init script with bash
  - ['/bin/bash', '/usr/local/bin/cloud-init-main.sh']
EOF

    # Ensure proper permissions on the user-data file
    chmod 644 "${USER_DATA_FILE}"
    echo "Cloud-init configuration generated successfully."
}

# --- create_base_vm ---
# Description: Creates a new VM with the basic configuration (memory, cores, network).
# ---
# Create base VM with initial configuration
function create_base_vm() {
    echo "Creating VM with ID ${VMID}..."
    
    # Create the VM with base configuration
    if ! qm create "${VMID}" \
        --name "ubuntu-server-${UBUNTU_VERSION}" \
        --memory 4096 \
        --cores 2 \
        --cpu host \
        --net0 "virtio,bridge=${NET_BRIDGE}" \
        --scsihw virtio-scsi-pci \
        --onboot 1 \
        --ostype "${OSTYPE}"; then
        echo "Error: Failed to create VM"
        exit 1
    fi
    
    echo "Base VM created successfully."
}

# --- import_and_configure_disk ---
# Description: Imports the downloaded cloud image as a disk for the VM,
#              attaches it, and resizes it.
# ---
# Import and configure disk storage
function import_and_configure_disk() {
    echo "Importing disk image..."
    local IMPORT_OUTPUT
    if ! IMPORT_OUTPUT=$(qm importdisk "${VMID}" "${IMAGE_NAME}" "${STORAGE}" 2>&1); then
        echo "Error: Failed to import disk image"
        echo "Details: ${IMPORT_OUTPUT}"
        qm destroy "${VMID}"
        exit 1
    fi
    
    # Configure the imported disk with retries
    echo "Configuring imported disk..."
    local RETRY_COUNT=0
    while [ $RETRY_COUNT -lt 3 ]; do
        if qm set "${VMID}" --scsi0 "${STORAGE}:vm-${VMID}-disk-0" 2>/dev/null; then
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Retry ${RETRY_COUNT}/3: Waiting for disk to be available..."
        sleep 5
    done
    
    if [ $RETRY_COUNT -eq 3 ]; then
        echo "Error: Failed to configure imported disk after 3 attempts"
        qm destroy "${VMID}"
        exit 1
    fi
    
    # Resize disk to add 5GB
    echo "Resizing disk to add 5GB..."
    if ! qm resize "${VMID}" scsi0 +5G; then
        echo "Error: Failed to resize disk"
        qm destroy "${VMID}"
        exit 1
    fi
    
    echo "Disk import and configuration completed successfully."
}

# --- configure_vm_settings ---
# Description: Configures advanced VM settings, such as boot order, cloud-init drive,
#              and network settings.
# ---
# Configure VM settings (boot, cloud-init, network)
function configure_vm_settings() {
    echo "Configuring VM settings..."
    
    local CONFIG_COMMANDS=(
        "qm set ${VMID} --ide2 ${STORAGE}:cloudinit"
        "qm set ${VMID} --boot c --bootdisk scsi0"
        "qm set ${VMID} --serial0 socket --vga serial0"
        "qm set ${VMID} --ipconfig0 ip=${STATIC_IP}/24,gw=${GATEWAY}"
        "qm set ${VMID} --cicustom \"user=local:snippets/user-data-${VMID}.yaml\""
    )
    
    for CMD in "${CONFIG_COMMANDS[@]}"; do
        if ! eval "$CMD"; then
            echo "Error: Failed to execute: $CMD"
            qm destroy "${VMID}"
            exit 1
        fi
    done
    
    echo "VM settings configured successfully."
}

# --- start_vm ---
# Description: Starts the VM and waits for it to enter a 'running' state.
# ---
# Start VM and wait for it to be running
function start_vm() {
    echo "Starting VM..."
    if ! qm start "${VMID}"; then
        echo "Error: Failed to start VM"
        exit 1
    fi
    
    # Wait for VM to start
    echo "Waiting for VM to start..."
    local START_TIMEOUT=30
    while [ $START_TIMEOUT -gt 0 ]; do
        if qm status "${VMID}" | grep -q running; then
            echo "VM ${VMID} started successfully."
            return 0
        fi
        sleep 1
        START_TIMEOUT=$((START_TIMEOUT - 1))
    done
    
    echo "Warning: VM started but status check timed out"
}

# Wait for cloud-init to complete
function wait_for_cloud_init() {
    log_info "Waiting for cloud-init to complete installation..."
    log_info "This may take 5-10 minutes depending on internet speed..."
    
    local MAX_ATTEMPTS=90  # 15 minutes (10 seconds per attempt)
    local ATTEMPT=0
    local SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR -i /root/.ssh/id_rsa"
    
    # First wait for SSH to be available
    log_info "Waiting for SSH to become available..."
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if ssh $SSH_OPTS "${VM_USERNAME}@${STATIC_IP}" "echo 'SSH is ready'" 2>/dev/null; then
            log_info "SSH is now available"
            break
        fi
        
        ATTEMPT=$((ATTEMPT + 1))
        if [ $((ATTEMPT % 6)) -eq 0 ]; then
            log_info "Still waiting for SSH... (${ATTEMPT}0 seconds elapsed)"
        fi
        sleep 10
    done
    
    if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
        log_error "Timeout waiting for SSH to become available"
        return 1
    fi
    
    # Now wait for cloud-init completion
    log_info "Waiting for cloud-init to finish configuration..."
    ATTEMPT=0
    local SERVICES_READY=false
    
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        # Check for completion marker
        if ssh $SSH_OPTS "${VM_USERNAME}@${STATIC_IP}" "test -f /etc/privatebox-cloud-init-complete" 2>/dev/null; then
            # Read the completion marker to check service status
            local MARKER_CONTENT=$(ssh $SSH_OPTS "${VM_USERNAME}@${STATIC_IP}" "cat /etc/privatebox-cloud-init-complete 2>/dev/null" 2>/dev/null || echo "")
            
            # Check for installation failure first
            if [[ "$MARKER_CONTENT" =~ INSTALLATION_STATUS=failed ]]; then
                log_error "Cloud-init installation failed!"
                
                # Extract error details
                local error_stage=$(echo "$MARKER_CONTENT" | grep "ERROR_STAGE=" | cut -d'=' -f2 || echo "unknown")
                local error_msg=$(echo "$MARKER_CONTENT" | grep "ERROR_MESSAGE=" | cut -d'=' -f2 || echo "No error message")
                local error_code=$(echo "$MARKER_CONTENT" | grep "ERROR_CODE=" | cut -d'=' -f2 || echo "1")
                local post_install_error=$(echo "$MARKER_CONTENT" | grep "POST_INSTALL_ERROR=" | cut -d'=' -f2 || echo "")
                
                log_error "Installation failed at stage: $error_stage"
                log_error "Error message: $error_msg"
                log_error "Exit code: $error_code"
                
                if [[ -n "$post_install_error" ]]; then
                    log_error "Post-install error: $post_install_error"
                fi
                
                # Write error details to config file for bootstrap.sh to read
                if [[ -f "${CONFIG_FILE}" ]]; then
                    echo "INSTALLATION_ERROR_STAGE=$error_stage" >> "${CONFIG_FILE}"
                    echo "INSTALLATION_ERROR_MESSAGE=$error_msg" >> "${CONFIG_FILE}"
                    echo "INSTALLATION_ERROR_CODE=$error_code" >> "${CONFIG_FILE}"
                fi
                
                return 1
            elif [[ "$MARKER_CONTENT" =~ INSTALLATION_STATUS=success ]] && [[ "$MARKER_CONTENT" =~ SERVICES_STATUS=completed ]]; then
                log_info "Cloud-init has completed with all services running!"
                log_success "All services are running successfully!"
                return 0
            elif [[ "$MARKER_CONTENT" =~ SERVICES_STATUS=partial ]]; then
                # Services are partially running, continue checking
                log_info "Cloud-init completed but waiting for all services..."
                
                # Check actual service status
                local portainer_status=$(ssh $SSH_OPTS "${VM_USERNAME}@${STATIC_IP}" "systemctl is-active portainer.service 2>/dev/null || echo 'not-found'" 2>/dev/null || echo "unreachable")
                local semaphore_status=$(ssh $SSH_OPTS "${VM_USERNAME}@${STATIC_IP}" "systemctl is-active semaphore-ui.service 2>/dev/null || echo 'not-found'" 2>/dev/null || echo "unreachable")
                
                # Only show detailed status every 30 seconds
                if [ $((ATTEMPT % 3)) -eq 0 ]; then
                    log_info "Services status:"
                    log_info "  - Portainer: $portainer_status"
                    log_info "  - Semaphore: $semaphore_status"
                fi
                
                # Check if both services are now active
                if [ "$portainer_status" = "active" ] && [ "$semaphore_status" = "active" ]; then
                    log_success "All services are now running successfully!"
                    return 0
                fi
            elif [[ "$MARKER_CONTENT" =~ INSTALLATION_STATUS=running ]]; then
                # Still running
                log_info "Cloud-init is still running installation tasks..."
            else
                # Marker exists but doesn't have expected content, still initializing
                log_info "Cloud-init is still initializing services..."
            fi
        fi
        
        ATTEMPT=$((ATTEMPT + 1))
        if [ $((ATTEMPT % 6)) -eq 0 ]; then
            log_info "Still waiting for cloud-init... (${ATTEMPT}0 seconds elapsed)"
        fi
        sleep 10
    done
    
    log_error "Timeout waiting for cloud-init to complete"
    return 1
}

# --- create_vm ---
# Description: Orchestrates the VM creation process by calling the necessary
#              functions in the correct order.
# ---
# Main VM creation orchestration function
function create_vm() {
    generate_cloud_init
    create_base_vm
    import_and_configure_disk
    configure_vm_settings
    start_vm
    
    # Optional: wait for cloud-init if requested
    if [[ "${WAIT_FOR_CLOUD_INIT:-false}" == "true" ]]; then
        wait_for_cloud_init || {
            log_error "Cloud-init failed to complete"
            exit 1
        }
    fi
}

# --- cleanup ---
# Description: Cleans up resources upon script exit. It removes the downloaded
#              image and, on failure, destroys the partially created VM.
# ---
# VM cleanup function
cleanup_vm_on_failure() {
    local exit_code=$?
    
    # Only clean up VM on failure
    if [[ ${exit_code} -ne 0 ]] && [[ -n "${VMID:-}" ]]; then
        if qm status "${VMID}" >/dev/null 2>&1; then
            log_info "Cleaning up failed VM..."
            qm stop "${VMID}" -skiplock >/dev/null 2>&1 || true
            qm destroy "${VMID}" >/dev/null 2>&1 || true
        fi
    fi
}

# Image cleanup function
cleanup_downloaded_image() {
    # Only clean up the local symlink/copy, not the cached image
    if [[ -L "${IMAGE_NAME:-}" ]] || [[ -f "${IMAGE_NAME:-}" ]]; then
        # Check if it's a symlink or a regular file in current directory
        if [[ "$(dirname "${IMAGE_NAME}")" == "." ]] || [[ "$(dirname "${IMAGE_NAME}")" == "$(pwd)" ]]; then
            log_info "Cleaning up local image reference..."
            rm -f "${IMAGE_NAME}" || true
        fi
    fi
    # The cached image in IMAGE_CACHE_DIR is preserved for future use
}

# Register cleanup functions
register_cleanup cleanup_downloaded_image
register_cleanup cleanup_vm_on_failure

# --- Main Execution ---
# Description: The main entry point of the script. It logs the progress and
#              calls the main VM creation function.
# ---
# Main execution
{
    echo "========================================="
    echo "Starting Ubuntu ${UBUNTU_VERSION} VM Creation"
    echo "========================================="
    echo "VM ID: ${VMID}"
    echo "Storage: ${STORAGE}"
    echo "Network Bridge: ${NET_BRIDGE}"
    echo "Static IP: ${STATIC_IP}"
    echo "Gateway: ${GATEWAY}"
    echo "----------------------------------------"
    
    check_and_remove_vm
    download_image
    create_vm
    
    echo "========================================="
    echo "VM Creation Successfully Completed!"
    echo "----------------------------------------"
    echo "Access Information:"
    echo "  Username: ${VM_USERNAME}"
    echo "  Password: ${VM_PASSWORD}"
    echo "  IP Address: ${STATIC_IP}"
    echo "  Gateway: ${GATEWAY}"
    echo ""
    echo "You can access the VM console with:"
    echo "  qm terminal ${VMID}"
    echo "You can access the VM via SSH with:"
    echo "  ssh ${VM_USERNAME}@${STATIC_IP}"
    echo "Podman is installed and ready to use."
    echo "Portainer is accessible at http://${STATIC_IP}:9000"
    echo "========================================="
} 2>&1 | tee vm_creation_${VMID}.log

# Register the log file for cleanup
register_temp_file "vm_creation_${VMID}.log"

exit ${EXIT_SUCCESS}