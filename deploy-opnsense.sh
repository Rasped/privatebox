#!/bin/bash
#
# OPNsense Router Assembly Line Deployment Script
# Converts OPNsense nano images to full installations on Proxmox
#
# Usage: ./deploy-opnsense.sh [VM_ID] [SERIAL_NUMBER] [CONFIG_PATH]
#
# All parameters are optional. Script uses sane defaults if not provided.
#

set -euo pipefail

# ================================
# CONFIGURABLE VARIABLES
# ================================

# Proxmox settings
PROXMOX_NODE="${PROXMOX_NODE:-$(hostname)}"
STORAGE="${STORAGE:-local-lvm}"
BRIDGE_WAN="${BRIDGE_WAN:-vmbr0}"
BRIDGE_LAN="${BRIDGE_LAN:-vmbr1}"

# VM settings
DEFAULT_RAM_BOOT="4096"      # RAM during installation (MB)
DEFAULT_RAM_PROD="2048"      # RAM for production (MB)
DEFAULT_CORES="2"
DEFAULT_DISK_SIZE="32"  # Size in GB for disk creation
VM_NAME_PREFIX="${VM_NAME_PREFIX:-opnsense}"

# OPNsense settings
OPNSENSE_VERSION="${OPNSENSE_VERSION:-25.7}"
NANO_IMAGE_URL="${NANO_IMAGE_URL:-https://mirror.dns-root.de/opnsense/releases/${OPNSENSE_VERSION}/OPNsense-${OPNSENSE_VERSION}-nano-amd64.img.bz2}"
IMAGE_CACHE_DIR="${IMAGE_CACHE_DIR:-/var/tmp/opnsense-images}"
DEFAULT_ROOT_PASSWORD="${DEFAULT_ROOT_PASSWORD:-opnsense}"

# Network settings
LAN_IP="${LAN_IP:-192.168.1.1}"
LAN_NETMASK="${LAN_NETMASK:-24}"
LAN_NETWORK="${LAN_NETWORK:-192.168.1.0/24}"
DHCP_START="${DHCP_START:-192.168.1.100}"
DHCP_END="${DHCP_END:-192.168.1.200}"
DNS1="${DNS1:-8.8.8.8}"
DNS2="${DNS2:-8.8.4.4}"

# Timeouts and retries
BOOT_TIMEOUT="${BOOT_TIMEOUT:-120}"
SSH_TIMEOUT="${SSH_TIMEOUT:-300}"
CONVERSION_TIMEOUT="${CONVERSION_TIMEOUT:-1800}"
MAX_RETRIES="${MAX_RETRIES:-3}"

# Logging
LOG_DIR="${LOG_DIR:-/var/log/opnsense-deploy}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
NANO_IMAGE_PATH=""

# ================================
# SCRIPT PARAMETERS
# ================================

VM_ID="${1:-}"
SERIAL_NUMBER="${2:-router-$(date +%Y%m%d%H%M%S)}"
CONFIG_PATH="${3:-}"

# ================================
# FUNCTIONS
# ================================

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
    
    if [[ "${level}" == "ERROR" ]]; then
        echo "[${timestamp}] [${level}] ${message}" >&2
    fi
}

# Error handler
error_exit() {
    log "ERROR" "$1"
    cleanup_on_error
    exit 1
}

# Cleanup on error
cleanup_on_error() {
    if [[ -n "${VM_ID:-}" ]] && qm status "${VM_ID}" &>/dev/null; then
        log "INFO" "Cleaning up VM ${VM_ID} after error"
        qm stop "${VM_ID}" --skiplock 1 &>/dev/null || true
        qm destroy "${VM_ID}" --skiplock 1 &>/dev/null || true
    fi
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites"
    
    # Check if running on Proxmox
    if ! command -v qm &>/dev/null; then
        error_exit "This script must be run on a Proxmox host"
    fi
    
    # Check for required tools
    local tools=("wget" "bzip2" "jq" "expect")
    for tool in "${tools[@]}"; do
        if ! command -v "${tool}" &>/dev/null; then
            log "WARN" "${tool} not found, installing..."
            apt-get update &>/dev/null
            apt-get install -y "${tool}" &>/dev/null || error_exit "Failed to install ${tool}"
        fi
    done
    
    # Check storage exists
    if ! pvesm status | grep -q "^${STORAGE}"; then
        error_exit "Storage '${STORAGE}' not found"
    fi
    
    # Check bridges exist
    for bridge in "${BRIDGE_WAN}" "${BRIDGE_LAN}"; do
        if ! ip link show "${bridge}" &>/dev/null; then
            error_exit "Bridge '${bridge}' not found"
        fi
    done
    
    log "INFO" "Prerequisites check passed"
}

# Get next available VM ID
get_next_vmid() {
    local next_id=100
    while qm status "${next_id}" &>/dev/null; do
        ((next_id++))
    done
    echo "${next_id}"
}

# Download and cache nano image
download_nano_image() {
    log "INFO" "Downloading OPNsense nano image"
    
    mkdir -p "${IMAGE_CACHE_DIR}"
    
    local image_filename=$(basename "${NANO_IMAGE_URL}")
    local image_path="${IMAGE_CACHE_DIR}/${image_filename}"
    local extracted_path="${image_path%.bz2}"
    
    # Check if already cached
    if [[ -f "${extracted_path}" ]]; then
        local age=$(($(date +%s) - $(stat -c %Y "${extracted_path}")))
        if [[ ${age} -lt 86400 ]]; then  # Less than 24 hours old
            log "INFO" "Using cached image: ${extracted_path}"
            NANO_IMAGE_PATH="${extracted_path}"
            return 0
        fi
    fi
    
    # Download image with retries and resume support
    log "INFO" "Downloading from ${NANO_IMAGE_URL}"
    local retry_count=0
    while [[ ${retry_count} -lt ${MAX_RETRIES} ]]; do
        if wget --continue \
               --timeout=30 \
               --tries=3 \
               --retry-connrefused \
               --show-progress \
               -O "${image_path}" \
               "${NANO_IMAGE_URL}"; then
            log "INFO" "Download completed successfully"
            break
        else
            ((retry_count++))
            if [[ ${retry_count} -ge ${MAX_RETRIES} ]]; then
                error_exit "Failed to download nano image after ${MAX_RETRIES} attempts"
            fi
            log "WARN" "Download failed, retrying (${retry_count}/${MAX_RETRIES})..."
            sleep 5
        fi
    done
    
    # Extract image if compressed
    log "INFO" "Extracting image"
    if [[ -f "${image_path}" ]]; then
        if ! bunzip2 -f "${image_path}"; then
            error_exit "Failed to extract nano image"
        fi
        # Note: bunzip2 automatically removes the .bz2 file
    fi
    
    log "INFO" "Image ready: ${extracted_path}"
    NANO_IMAGE_PATH="${extracted_path}"
}

# Create VM
create_vm() {
    local vmid="$1"
    local name="${VM_NAME_PREFIX}-${SERIAL_NUMBER}"
    
    log "INFO" "Creating VM ${vmid} (${name})"
    
    # Create VM with basic settings
    qm create "${vmid}" \
        --name "${name}" \
        --memory "${DEFAULT_RAM_BOOT}" \
        --cores "${DEFAULT_CORES}" \
        --sockets 1 \
        --cpu host \
        --net0 "virtio,bridge=${BRIDGE_WAN}" \
        --net1 "virtio,bridge=${BRIDGE_LAN}" \
        --serial0 socket \
        --vga serial0 \
        --boot order=scsi0 \
        --ostype l26 \
        --agent 1 \
        --onboot 0 \
        --description "OPNsense Router - Serial: ${SERIAL_NUMBER} - Deployed: $(date '+%Y-%m-%d %H:%M:%S')"
    
    # Skip disk creation here - will be created during import
    # Disk will be imported from nano image and then resized
    
    # Enable QEMU Guest Agent
    qm set "${vmid}" --agent 1,fstrim_cloned_disks=1
    
    log "INFO" "VM ${vmid} created successfully"
}

# Import nano image to VM
import_nano_image() {
    local vmid="$1"
    local image_path="$2"
    
    log "INFO" "Importing nano image to VM ${vmid}"
    
    # Import image (redirect progress to log, capture only errors)
    log "INFO" "Starting import from ${image_path} to ${STORAGE}"
    local import_error_file="/tmp/import-error-${vmid}.tmp"
    
    # Run import with progress going to log file, errors to temp file
    if qm importdisk "${vmid}" "${image_path}" "${STORAGE}" --format raw \
        >> "${LOG_FILE}" 2> "${import_error_file}"; then
        
        # Import succeeded, check for errors/warnings
        if [[ -s "${import_error_file}" ]]; then
            log "WARN" "Import had warnings: $(cat ${import_error_file})"
        fi
        rm -f "${import_error_file}"
        
        # Verify import by checking for unused disk
        log "INFO" "Verifying import completion"
        local retry_count=0
        local unused_disk=""
        
        while [[ ${retry_count} -lt 10 ]]; do
            unused_disk=$(qm config "${vmid}" 2>/dev/null | grep '^unused0:' | cut -d' ' -f2)
            
            if [[ -n "${unused_disk}" ]]; then
                log "INFO" "Import successful, found disk: ${unused_disk}"
                break
            fi
            
            sleep 2
            ((retry_count++))
            log "DEBUG" "Waiting for import to complete (${retry_count}/10)"
        done
        
        if [[ -z "${unused_disk}" ]]; then
            # Fallback: Check if disk exists with expected name
            unused_disk="${STORAGE}:vm-${vmid}-disk-0"
            if qm config "${vmid}" 2>/dev/null | grep -q "${unused_disk}"; then
                log "WARN" "Disk found via fallback method: ${unused_disk}"
            else
                error_exit "Import appeared successful but no unused disk found"
            fi
        fi
        
    else
        # Import failed
        local exit_code=$?
        log "ERROR" "Import command failed with exit code: ${exit_code}"
        if [[ -s "${import_error_file}" ]]; then
            log "ERROR" "Import errors: $(cat ${import_error_file})"
        fi
        rm -f "${import_error_file}"
        error_exit "Failed to import disk image"
    fi
    
    # Attach the imported disk
    log "INFO" "Attaching imported disk: ${unused_disk}"
    if ! qm set "${vmid}" --scsi0 "${unused_disk}" 2>&1 | tee -a "${LOG_FILE}"; then
        error_exit "Failed to attach imported disk"
    fi
    
    # Resize disk to target size (nano image is 3GB, we want 32GB)
    log "INFO" "Resizing disk from 3GB to ${DEFAULT_DISK_SIZE}GB"
    if ! qm resize "${vmid}" scsi0 "${DEFAULT_DISK_SIZE}G" 2>&1 | tee -a "${LOG_FILE}"; then
        error_exit "Failed to resize disk"
    fi
    
    log "INFO" "Nano image imported and configured successfully"
}

# Start VM and wait for boot
start_vm() {
    local vmid="$1"
    
    log "INFO" "Starting VM ${vmid}"
    qm start "${vmid}"
    
    # Wait for VM to be running
    local count=0
    while [[ ${count} -lt ${BOOT_TIMEOUT} ]]; do
        if qm status "${vmid}" | grep -q "running"; then
            log "INFO" "VM ${vmid} is running"
            sleep 10  # Give it time to fully boot
            return 0
        fi
        sleep 1
        ((count++))
    done
    
    error_exit "VM ${vmid} failed to start within ${BOOT_TIMEOUT} seconds"
}

# Get VM IP address
get_vm_ip() {
    local vmid="$1"
    local interface="$2"  # 0 for WAN, 1 for LAN
    
    # For LAN, we know the IP
    if [[ "${interface}" == "1" ]]; then
        echo "${LAN_IP}"
        return 0
    fi
    
    # For WAN, get DHCP IP
    local ip=""
    local count=0
    
    while [[ ${count} -lt 60 ]]; do
        ip=$(qm guest cmd "${vmid}" network-get-interfaces 2>/dev/null | \
             jq -r ".[] | select(.name==\"vtnet${interface}\") | .\"ip-addresses\"[] | select(.\"ip-address-type\"==\"ipv4\") | .\"ip-address\"" 2>/dev/null || true)
        
        if [[ -n "${ip}" ]] && [[ "${ip}" != "null" ]]; then
            echo "${ip}"
            return 0
        fi
        
        sleep 2
        ((count++))
    done
    
    # If guest agent fails, try getting from DHCP leases
    log "WARN" "Could not get IP from guest agent, checking DHCP leases"
    local mac=$(qm config "${vmid}" | grep "^net${interface}:" | grep -oP 'virtio=\K[^,]+')
    
    if [[ -n "${mac}" ]]; then
        ip=$(grep -i "${mac}" /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print $3}' | head -1 || true)
        if [[ -n "${ip}" ]]; then
            echo "${ip}"
            return 0
        fi
    fi
    
    return 1
}

# Execute commands on OPNsense via serial console with proper login
execute_serial() {
    local vmid="$1"
    local command="$2"
    local timeout="${3:-30}"
    
    log "DEBUG" "Executing via serial: ${command}"
    
    # Use expect to interact with serial console
    # First login if needed, then execute command
    expect -c "
        set timeout ${timeout}
        spawn qm terminal ${vmid}
        
        # Handle login and get to shell prompt
        expect {
            timeout { 
                send_user \"Timeout waiting for prompt\n\"
                exit 1 
            }
            \"login:\" {
                send_user \"Saw login prompt, sending root\n\"
                send \"root\r\"
                expect {
                    \"Password:\" {
                        send_user \"Sending password\n\"
                        send \"opnsense\r\"
                        expect {
                            \"Enter an option:\" {
                                # OPNsense menu - enter shell (option 8)
                                send_user \"At OPNsense menu, entering shell\n\"
                                send \"8\r\"
                                expect \"#\"
                            }
                            \"#\" {
                                # Got root shell directly
                                send_user \"Got root shell\n\"
                            }
                        }
                    }
                }
            }
            \"Enter an option:\" {
                # Already logged in, at menu
                send_user \"At OPNsense menu, entering shell\n\"
                send \"8\r\"
                expect \"#\"
            }
            \"#\" {
                # Already at root shell
                send_user \"Already at root shell\n\"
            }
        }
        
        # Now we should have a shell prompt, execute the command
        send_user \"Executing command\n\"
        send -- \"${command}\r\"
        
        # Wait for command completion
        expect {
            timeout { 
                send_user \"Command execution timeout\n\"
            }
            \"#\" {
                send_user \"Command completed\n\"
            }
        }
        
        # Clean exit
        send \"exit\r\"
        expect eof
    " 2>&1 | tee -a "${LOG_FILE}" || true
}

# Convert nano to full installation
convert_nano_to_full() {
    local vmid="$1"
    
    log "INFO" "Converting nano to full OPNsense installation"
    
    # Create conversion script
    local conversion_script=$(cat <<'EOCONVERT'
#!/bin/sh
set -e

echo "Starting nano to full conversion..."

# Remount filesystem as read-write
mount -o rw /

# Update pkg configuration to use full repositories
sed -i '' 's/OPNsense.*-nano/OPNsense/g' /usr/local/etc/pkg/repos/OPNsense.conf

# Force update package catalog
pkg update -f

# Remove nano package and install full package set
pkg remove -y os-OPNsense-nano || true
pkg install -y os-OPNsense

# Install additional packages for full installation
pkg install -y \
    os-OPNsense-update \
    qemu-guest-agent \
    bash \
    nano \
    vim-tiny

# Update boot configuration
echo 'autoboot_delay="3"' >> /boot/loader.conf
echo 'boot_serial="YES"' >> /boot/loader.conf
echo 'console="comconsole"' >> /boot/loader.conf
echo 'comconsole_speed="115200"' >> /boot/loader.conf

# Enable services
sysrc qemu_guest_agent_enable="YES"
sysrc sshd_enable="YES"

# Configure SSH to allow root login with password
sed -i '' 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /usr/local/etc/ssh/sshd_config
sed -i '' 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /usr/local/etc/ssh/sshd_config
sed -i '' 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' /usr/local/etc/ssh/sshd_config

# Start services
service qemu-guest-agent start || true
service sshd restart || true

echo "Conversion complete"
EOCONVERT
    )
    
    # Send script to VM via serial console
    log "INFO" "Sending conversion script to VM"
    
    # Base64 encode the script to avoid quote escaping issues
    local encoded_script=$(echo "${conversion_script}" | base64 -w0)
    execute_serial "${vmid}" "echo '${encoded_script}' | base64 -d > /tmp/convert.sh" 60
    
    execute_serial "${vmid}" "chmod +x /tmp/convert.sh" 10
    
    # Execute conversion
    log "INFO" "Executing conversion (this may take several minutes)"
    execute_serial "${vmid}" "/tmp/convert.sh" "${CONVERSION_TIMEOUT}"
    
    # Reboot to apply changes
    log "INFO" "Rebooting VM to apply changes"
    execute_serial "${vmid}" "reboot" 10
    
    # Wait for VM to stop
    sleep 10
    local count=0
    while [[ ${count} -lt 30 ]]; do
        if ! qm status "${vmid}" | grep -q "running"; then
            break
        fi
        sleep 1
        ((count++))
    done
    
    # Start VM after reboot
    sleep 5
    start_vm "${vmid}"
    
    log "INFO" "Conversion to full installation complete"
}

# Configure OPNsense base system
configure_base_system() {
    local vmid="$1"
    
    log "INFO" "Configuring base OPNsense system"
    
    # Base configuration script
    local config_script=$(cat <<EOCONFIG
#!/bin/sh
set -e

# Set root password
echo '${DEFAULT_ROOT_PASSWORD}' | pw usermod root -h 0

# Configure LAN interface
ifconfig vtnet1 inet ${LAN_IP}/${LAN_NETMASK}

# Create basic config.xml if not exists
if [ ! -f /conf/config.xml ]; then
    cp /conf.default/config.xml /conf/config.xml
fi

# Configure system via configd
configctl interface newip vtnet1
configctl interface newipv4 vtnet1

# Ensure web GUI is accessible
configctl webgui restart

# Configure firewall to allow SSH and HTTPS on LAN
pfctl -d  # Temporarily disable firewall for configuration
echo "pass in on vtnet1 proto tcp from any to any port {22, 443} keep state" | pfctl -f -
pfctl -e

echo "Base configuration complete"
EOCONFIG
    )
    
    # Send and execute configuration script
    log "INFO" "Applying base configuration"
    execute_serial "${vmid}" "cat > /tmp/configure.sh << 'EOF'
${config_script}
EOF" 60
    
    execute_serial "${vmid}" "chmod +x /tmp/configure.sh" 10
    execute_serial "${vmid}" "/tmp/configure.sh" 120
    
    log "INFO" "Base system configured"
}

# Apply custom configuration if provided
apply_custom_config() {
    local vmid="$1"
    local config_path="$2"
    
    if [[ -z "${config_path}" ]] || [[ ! -f "${config_path}" ]]; then
        log "INFO" "No custom configuration provided, using defaults"
        return 0
    fi
    
    log "INFO" "Applying custom configuration from ${config_path}"
    
    # Read config file (handle both GNU and BSD base64)
    local config_content
    if command -v base64 >/dev/null && base64 --help 2>&1 | grep -q GNU; then
        config_content=$(cat "${config_path}" | base64 -w0)
    else
        config_content=$(cat "${config_path}" | base64)
    fi
    
    # Apply via serial console
    execute_serial "${vmid}" "echo '${config_content}' | base64 -d > /conf/config.xml" 60
    execute_serial "${vmid}" "configctl firmware reload" 30
    
    log "INFO" "Custom configuration applied"
}

# Verify deployment
verify_deployment() {
    local vmid="$1"
    
    log "INFO" "Verifying deployment"
    
    local checks_passed=0
    local total_checks=4
    
    # Check 1: VM is running
    if qm status "${vmid}" | grep -q "running"; then
        log "INFO" "✓ VM is running"
        ((checks_passed++))
    else
        log "ERROR" "✗ VM is not running"
    fi
    
    # Check 2: Guest agent is responding
    if qm guest cmd "${vmid}" network-get-interfaces &>/dev/null; then
        log "INFO" "✓ Guest agent is responding"
        ((checks_passed++))
    else
        log "WARN" "✗ Guest agent not responding (may need more time)"
    fi
    
    # Check 3: SSH is accessible on LAN
    if timeout 5 bash -c "echo > /dev/tcp/${LAN_IP}/22" 2>/dev/null; then
        log "INFO" "✓ SSH is accessible on ${LAN_IP}"
        ((checks_passed++))
    else
        log "ERROR" "✗ SSH is not accessible on ${LAN_IP}"
    fi
    
    # Check 4: Web GUI is accessible
    if timeout 5 bash -c "echo > /dev/tcp/${LAN_IP}/443" 2>/dev/null; then
        log "INFO" "✓ Web GUI is accessible on https://${LAN_IP}"
        ((checks_passed++))
    else
        log "ERROR" "✗ Web GUI is not accessible on https://${LAN_IP}"
    fi
    
    log "INFO" "Verification complete: ${checks_passed}/${total_checks} checks passed"
    
    if [[ ${checks_passed} -lt 3 ]]; then
        error_exit "Deployment verification failed"
    fi
    
    return 0
}

# Finalize deployment
finalize_deployment() {
    local vmid="$1"
    
    log "INFO" "Finalizing deployment"
    
    # Reduce RAM to production level
    log "INFO" "Reducing RAM to production level (${DEFAULT_RAM_PROD}MB)"
    qm stop "${vmid}"
    sleep 5
    qm set "${vmid}" --memory "${DEFAULT_RAM_PROD}"
    qm start "${vmid}"
    
    # Wait for final boot
    sleep 30
    
    # Create deployment record
    local deployment_record="${LOG_DIR}/deployment-${SERIAL_NUMBER}.json"
    cat > "${deployment_record}" <<EOJSON
{
    "serial_number": "${SERIAL_NUMBER}",
    "vm_id": ${vmid},
    "deployment_date": "$(date -Iseconds)",
    "opnsense_version": "${OPNSENSE_VERSION}",
    "lan_ip": "${LAN_IP}",
    "configuration": "${CONFIG_PATH:-default}",
    "status": "deployed"
}
EOJSON
    
    log "INFO" "Deployment record saved to ${deployment_record}"
    
    # Display access information
    cat <<EOACCESS

========================================
 OPNsense Router Deployment Complete
========================================

Serial Number: ${SERIAL_NUMBER}
VM ID: ${vmid}
LAN IP: ${LAN_IP}

Access Methods:
- SSH: ssh root@${LAN_IP}
- Web GUI: https://${LAN_IP}
- Username: root
- Password: ${DEFAULT_ROOT_PASSWORD}

IMPORTANT: Change the default password immediately!

Deployment log: ${LOG_FILE}
========================================

EOACCESS
    
    log "INFO" "Deployment completed successfully"
}

# Main deployment function
main() {
    # Setup logging first (before using log function)
    mkdir -p "${LOG_DIR}"
    LOG_FILE="${LOG_DIR}/deploy-${SERIAL_NUMBER}-$(date +%Y%m%d-%H%M%S).log"
    
    # Initialize log file
    touch "${LOG_FILE}"
    
    log "INFO" "Starting OPNsense deployment for serial: ${SERIAL_NUMBER}"
    
    # Set error trap
    trap 'error_exit "Script failed at line $LINENO"' ERR
    
    # Check prerequisites
    check_prerequisites
    
    # Determine VM ID
    if [[ -z "${VM_ID}" ]]; then
        VM_ID=$(get_next_vmid)
        log "INFO" "Using next available VM ID: ${VM_ID}"
    else
        # Check if VM ID is already in use
        if qm status "${VM_ID}" &>/dev/null; then
            error_exit "VM ID ${VM_ID} is already in use"
        fi
    fi
    
    # Download/cache nano image
    local image_path
    download_nano_image
    image_path="$NANO_IMAGE_PATH"
    
    # Create VM
    create_vm "${VM_ID}"
    
    # Import nano image
    import_nano_image "${VM_ID}" "${image_path}"
    
    # Start VM
    start_vm "${VM_ID}"
    
    # Convert nano to full
    convert_nano_to_full "${VM_ID}"
    
    # Configure base system
    configure_base_system "${VM_ID}"
    
    # Apply custom configuration if provided
    apply_custom_config "${VM_ID}" "${CONFIG_PATH}"
    
    # Verify deployment
    verify_deployment "${VM_ID}"
    
    # Finalize
    finalize_deployment "${VM_ID}"
    
    log "INFO" "Deployment pipeline completed successfully"
}

# ================================
# SCRIPT ENTRY POINT
# ================================

# Run main function
main "$@"