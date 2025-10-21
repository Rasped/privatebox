#!/bin/bash
#
# PrivateBox Bootstrap - OPNsense Deployment
# Deploy OPNsense firewall from GitHub template
#
# This script:
# 1. Downloads OPNsense template from GitHub releases
# 2. Restores VM from template
# 3. Configures and starts OPNsense
# 4. Applies custom configuration
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/privatebox-opnsense-deploy.log"
CONFIG_FILE="/tmp/privatebox-config.conf"
CLEANUP_DONE_MARKER="/tmp/.opnsense_cleanup_done"

# Parse command line arguments
VERBOSE="--verbose"  # Default to verbose during development
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --quiet     Minimal output"
    echo "  --verbose   Detailed output (default)"
    echo "  --help      Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  OPNSENSE_VMID         VM ID (default: 100)"
    echo "  OPNSENSE_VM_NAME      VM name (default: privatebox-opnsense)"
    echo "  OPNSENSE_VM_STORAGE   Storage pool (default: local-lvm)"
    echo "  OPNSENSE_START        Start after restore (default: true)"
}

for arg in "$@"; do
    case $arg in
        --quiet) VERBOSE="--quiet" ;;
        --verbose) VERBOSE="--verbose" ;;
        --help) show_usage; exit 0 ;;
        *) echo "Unknown option: $arg"; show_usage; exit 1 ;;
    esac
done

# Source configuration if exists (do this early)
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# VM Configuration (after sourcing config)
VMID="${OPNSENSE_VMID:-100}"
VM_NAME="${OPNSENSE_VM_NAME:-privatebox-opnsense}"
VM_STORAGE="${OPNSENSE_VM_STORAGE:-local-lvm}"
START_AFTER_RESTORE="${OPNSENSE_START:-true}"
WAN_BRIDGE="${WAN_BRIDGE:-vmbr0}"  # From prepare-host.sh config

# Template Configuration
TEMPLATE_URL="https://github.com/Rasped/privatebox/releases/download/v1.0.2-opnsense/vzdump-qemu-105-opnsense.vma.zst"
TEMPLATE_FILENAME="vzdump-qemu-105-opnsense.vma.zst"
TEMPLATE_MD5="c6d251e1c62f065fd28d720572f8f943"
TEMPLATE_SIZE_MB=767
CACHE_DIR="/var/tmp/opnsense-template"
REQUIRED_SPACE_MB=5120  # 5GB for compressed + extracted

# OPNsense Configuration
OPNSENSE_LAN_IP="10.10.10.1"
OPNSENSE_SERVICES_IP="10.10.20.1"  # Services VLAN IP for management access
OPNSENSE_DEFAULT_USER="root"
OPNSENSE_DEFAULT_PASSWORD="opnsense"
OPNSENSE_CONFIG="${SCRIPT_DIR}/configs/opnsense/config.xml"

# Markers and logs
DEPLOYMENT_MARKER_DIR="/var/log/privatebox"
DEPLOYMENT_INFO_FILE="${DEPLOYMENT_MARKER_DIR}/opnsense-${VMID}-deployment.log"

# Timeouts
DOWNLOAD_TIMEOUT=600
VM_START_TIMEOUT=300
SSH_CONNECT_TIMEOUT=300

# Logging functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

display() {
    if [[ "$VERBOSE" == "--verbose" ]] || [[ "$2" == "always" ]]; then
        echo "$1"
    fi
    log "$1"
}

display_always() {
    echo "$1"
    log "$1"
}

# Display spinner (in-place update, no newline)
# Usage: display_spinner "spinner_char" "elapsed_seconds" "message"
display_spinner() {
    if [[ "$VERBOSE" == "--quiet" ]]; then
        local spinner_char="$1"
        local elapsed="$2"
        local message="${3:-Waiting...}"
        # Clear line and print spinner without newline
        printf "\r\033[K   %s %s %ss elapsed" "$spinner_char" "$message" "$elapsed"
    fi
}

# Clear spinner line (before printing permanent message)
clear_spinner() {
    if [[ "$VERBOSE" == "--quiet" ]]; then
        printf "\r\033[K"
    fi
}

error_exit() {
    echo "ERROR: $1" >&2
    log "ERROR: $1"
    cleanup_on_failure
    exit 1
}

# Cleanup function (idempotent)
cleanup_on_failure() {
    # Check if cleanup already done
    [[ -f "$CLEANUP_DONE_MARKER" ]] && return 0
    touch "$CLEANUP_DONE_MARKER"
    
    display_always "Cleaning up after failure..."
    
    # Stop VM if running
    if qm status $VMID &>/dev/null; then
        display "  Stopping VM $VMID..."
        qm stop $VMID --timeout 30 2>/dev/null || true
        
        display "  Destroying VM $VMID..."
        qm destroy $VMID --purge 2>/dev/null || true
    fi
    
    # Log failure
    if [[ -n "${DEPLOYMENT_INFO_FILE:-}" ]]; then
        echo "[$(date +%T)] DEPLOYMENT FAILED - Cleanup performed" >> "$DEPLOYMENT_INFO_FILE" 2>/dev/null || true
    fi
}

# Version comparison function (no bc required)
version_compare() {
    local ver1=$1
    local ver2=$2
    # Use sort -V (version sort) to compare
    if [[ "$(printf '%s\n' "$ver1" "$ver2" | sort -V | head -n1)" == "$ver2" ]]; then
        return 0  # ver1 >= ver2
    else
        return 1  # ver1 < ver2
    fi
}

# Pre-flight checks
run_preflight_checks() {
    display_always "Running pre-flight checks..."
    
    # Check root user
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root"
    fi
    display "  ✓ Running as root"
    
    # Check if VM ID already exists (improved message)
    if qm status $VMID &>/dev/null; then
        display_always ""
        display_always "VM ID $VMID already exists!"
        display_always ""
        display_always "Options:"
        display_always "  1. Remove it: qm stop $VMID && qm destroy $VMID --purge"
        display_always "  2. Use different ID: OPNSENSE_VMID=102 $0"
        display_always "  3. If OPNsense is already deployed, you can skip this step"
        error_exit "VM ID $VMID is in use"
    fi
    display "  ✓ VM ID $VMID is available"
    
    # Check Proxmox version (using version_compare)
    local pve_version=$(pveversion | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+' || echo "0.0")
    if ! version_compare "$pve_version" "7.0"; then
        error_exit "This script requires Proxmox VE 7.0 or later (found: $pve_version)"
    fi
    display "  ✓ Proxmox version $pve_version"
    
    # Check storage pool exists
    if ! pvesm status --enabled 2>/dev/null | grep -q "^$VM_STORAGE "; then
        local available_pools=$(pvesm status --enabled 2>/dev/null | awk 'NR>1 {print $1}' | tr '\n' ' ')
        error_exit "Storage pool '$VM_STORAGE' not found! Available: $available_pools"
    fi
    display "  ✓ Storage pool $VM_STORAGE exists"
    
    # Check available disk space
    local available_space=$(df -BM /var/tmp | awk 'NR==2 {print $4}' | sed 's/M//')
    if [[ $available_space -lt $REQUIRED_SPACE_MB ]]; then
        error_exit "Insufficient disk space! Need ${REQUIRED_SPACE_MB}MB, have ${available_space}MB"
    fi
    display "  ✓ Sufficient disk space: ${available_space}MB"
    
    # Check network bridges (use configured WAN bridge)
    if ! ip link show "$WAN_BRIDGE" &>/dev/null; then
        error_exit "WAN bridge $WAN_BRIDGE not found!"
    fi
    if ! ip link show vmbr1 &>/dev/null; then
        error_exit "LAN bridge vmbr1 not found!"
    fi
    display "  ✓ Network bridges $WAN_BRIDGE (WAN) and vmbr1 (LAN) exist"
    
    # Check VLAN 20 configuration
    if ip link show vmbr1.20 &>/dev/null 2>&1; then
        display "  ✓ VLAN 20 interface exists"
        
        # Check if Proxmox has IP on VLAN 20
        if ip addr show vmbr1.20 2>/dev/null | grep -q "10.10.20.20/24"; then
            display "  ✓ Proxmox has IP 10.10.20.20 on VLAN 20"
        else
            display "  ⚠ VLAN 20 exists but Proxmox IP not configured"
        fi
    else
        display "  ⚠ VLAN 20 not configured (will be available after OPNsense starts)"
    fi
    
    # Check and install required tools
    display "  Checking required tools..."
    local tools_to_install=()
    local required_tools=("zstd" "sshpass" "wget" "md5sum" "nc")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            tools_to_install+=("$tool")
            display "    Missing: $tool"
        fi
    done
    
    if [[ ${#tools_to_install[@]} -gt 0 ]]; then
        display "  Installing missing tools: ${tools_to_install[*]}"
        apt-get update >/dev/null 2>&1 || error_exit "Failed to update package lists"
        
        # Map commands to package names
        for tool in "${tools_to_install[@]}"; do
            local package="$tool"
            case "$tool" in
                nc) package="netcat-traditional" ;;
                md5sum) package="coreutils" ;;
            esac
            apt-get install -y "$package" >/dev/null 2>&1 || error_exit "Failed to install $package"
        done
    fi
    display "  ✓ All required tools are available"
    
    # Check if custom config exists
    if [[ ! -f "$OPNSENSE_CONFIG" ]]; then
        display "  ⚠ Custom config not found at $OPNSENSE_CONFIG"
        display "    OPNsense will use default configuration"
    else
        display "  ✓ Custom config found at $OPNSENSE_CONFIG"
    fi
    
    display_always "  ✓ All pre-flight checks passed"
}

# Download template
download_template() {
    display_always "Managing template..."
    
    # Create cache directory
    mkdir -p "$CACHE_DIR"
    mkdir -p "$DEPLOYMENT_MARKER_DIR"
    
    local template_path="${CACHE_DIR}/${TEMPLATE_FILENAME}"
    
    # Check for local template first (for testing/offline deployment)
    if [[ -f "/tmp/${TEMPLATE_FILENAME}" ]]; then
        display "  Found local template at /tmp/${TEMPLATE_FILENAME}"
        display "  Copying to cache directory..."
        cp "/tmp/${TEMPLATE_FILENAME}" "$template_path"
        
        # Still verify MD5
        local local_md5=$(md5sum "$template_path" 2>/dev/null | awk '{print $1}')
        if [[ "$local_md5" == "$TEMPLATE_MD5" ]]; then
            display_always "  ✓ Local template MD5 verified"
            return 0
        else
            display "  ⚠ Local template MD5 mismatch, will download from GitHub"
            rm -f "$template_path"
        fi
    fi
    
    # Check if template is cached
    if [[ -f "$template_path" ]]; then
        display "  Checking cached template..."
        local cached_md5=$(md5sum "$template_path" 2>/dev/null | awk '{print $1}')
        
        if [[ "$cached_md5" == "$TEMPLATE_MD5" ]]; then
            display_always "  ✓ Using cached template (MD5 verified)"
            return 0
        else
            display "  Cached template MD5 mismatch, re-downloading..."
            rm -f "$template_path"
        fi
    fi
    
    # Download template
    display_always "  Downloading OPNsense template (${TEMPLATE_SIZE_MB}MB)..."
    display "    URL: $TEMPLATE_URL"
    display "    This may take several minutes..."
    
    local attempts=3
    local attempt=1
    
    while [[ $attempt -le $attempts ]]; do
        display "    Download attempt $attempt of $attempts..."
        
        # Simpler progress display
        if [[ "$VERBOSE" == "--verbose" ]]; then
            wget --progress=bar:force \
                 --timeout=$DOWNLOAD_TIMEOUT \
                 -O "${template_path}.tmp" \
                 "$TEMPLATE_URL" 2>&1 | tee -a "$LOG_FILE"
        else
            wget --quiet \
                 --timeout=$DOWNLOAD_TIMEOUT \
                 -O "${template_path}.tmp" \
                 "$TEMPLATE_URL"
        fi
        
        if [[ -f "${template_path}.tmp" ]]; then
            # Verify download
            local downloaded_md5=$(md5sum "${template_path}.tmp" | awk '{print $1}')
            if [[ "$downloaded_md5" == "$TEMPLATE_MD5" ]]; then
                mv "${template_path}.tmp" "$template_path"
                display_always "  ✓ Template downloaded and verified"
                return 0
            else
                display "    MD5 mismatch! Expected: $TEMPLATE_MD5, Got: $downloaded_md5"
                rm -f "${template_path}.tmp"
            fi
        else
            display "    Download failed"
        fi
        
        ((attempt++))
        if [[ $attempt -le $attempts ]]; then
            display "    Waiting 30 seconds before retry..."
            sleep 30
        fi
    done
    
    error_exit "Failed to download template after $attempts attempts"
}

# Restore VM from template
restore_vm() {
    display_always "Restoring VM from template..."
    
    local template_path="${CACHE_DIR}/${TEMPLATE_FILENAME}"
    local restore_file="$template_path"
    local temp_template_id=9999  # Temporary ID for the restored template
    
    # Check if qmrestore supports zst directly
    if ! qmrestore --help 2>&1 | grep -q "\.zst"; then
        display "  Decompressing template for older qmrestore..."
        local decompressed_file="${template_path%.zst}"
        
        if [[ ! -f "$decompressed_file" ]]; then
            zstd -d -k "$template_path" || error_exit "Failed to decompress template"
        fi
        restore_file="$decompressed_file"
    fi
    
    # Start deployment logging
    cat > "$DEPLOYMENT_INFO_FILE" <<EOF
======================================
OPNsense Deployment Log
======================================
Date: $(date -Iseconds)
VM ID: $VMID
VM Name: $VM_NAME
Storage: $VM_STORAGE
Template: $TEMPLATE_FILENAME
======================================
EOF
    
    # Restore as template first (using temporary ID)
    display "  Restoring template with temporary ID $temp_template_id..."
    echo "[$(date +%T)] Starting template restoration..." >> "$DEPLOYMENT_INFO_FILE"
    
    if qmrestore "$restore_file" $temp_template_id \
                 --storage $VM_STORAGE \
                 --unique 1 2>&1 | tee -a "$DEPLOYMENT_INFO_FILE"; then
        echo "[$(date +%T)] Template restoration completed" >> "$DEPLOYMENT_INFO_FILE"
        display_always "  ✓ Template restored successfully"
    else
        error_exit "Failed to restore template"
    fi
    
    # Clone template to final VM
    display "  Cloning template to VM $VMID..."
    echo "[$(date +%T)] Cloning template to VM $VMID..." >> "$DEPLOYMENT_INFO_FILE"
    
    if qm clone $temp_template_id $VMID \
                --name "$VM_NAME" \
                --full 1 \
                --storage $VM_STORAGE 2>&1 | tee -a "$DEPLOYMENT_INFO_FILE"; then
        echo "[$(date +%T)] VM cloning completed" >> "$DEPLOYMENT_INFO_FILE"
        display_always "  ✓ VM cloned successfully"
    else
        # Clean up template on failure
        qm destroy $temp_template_id --purge 2>/dev/null || true
        error_exit "Failed to clone template to VM"
    fi
    
    # Delete the temporary template
    display "  Cleaning up temporary template..."
    if qm destroy $temp_template_id --purge 2>&1 | tee -a "$DEPLOYMENT_INFO_FILE"; then
        display_always "  ✓ Temporary template removed"
    else
        display "  ⚠ Warning: Could not remove temporary template $temp_template_id"
    fi
    
    # Configure VM settings
    display "  Configuring VM settings..."
    
    # Set correct network bridges (in case template had different ones)
    qm set $VMID --net0 "virtio,bridge=${WAN_BRIDGE}" 2>&1 | tee -a "$DEPLOYMENT_INFO_FILE"
    qm set $VMID --net1 "virtio,bridge=vmbr1" 2>&1 | tee -a "$DEPLOYMENT_INFO_FILE"
    
    # Enable auto-start
    qm set $VMID --onboot 1 2>&1 | tee -a "$DEPLOYMENT_INFO_FILE"
    
    # Set startup order (firewall starts first)
    qm set $VMID --startup order=1,up=60 2>&1 | tee -a "$DEPLOYMENT_INFO_FILE"
    
    # Add description
    qm set $VMID --description "OPNsense Firewall
Deployed: $(date -Iseconds)
Template: $TEMPLATE_FILENAME
LAN: ${OPNSENSE_LAN_IP}/24
Default credentials: ${OPNSENSE_DEFAULT_USER}/${OPNSENSE_DEFAULT_PASSWORD}" \
        2>&1 | tee -a "$DEPLOYMENT_INFO_FILE"
    
    display_always "  ✓ VM configuration complete"
}

# Start VM
start_vm() {
    if [[ "$START_AFTER_RESTORE" != "true" ]]; then
        display_always "  Skipping VM start (START_AFTER_RESTORE=false)"
        return 0
    fi
    
    display_always "Starting VM..."
    
    echo "[$(date +%T)] Starting VM $VMID..." >> "$DEPLOYMENT_INFO_FILE"
    qm start $VMID 2>&1 | tee -a "$DEPLOYMENT_INFO_FILE" || error_exit "Failed to start VM"
    
    # Wait for VM to be running
    local max_wait=30
    local waited=0
    display "  Waiting for VM to enter running state..."

    local spinner_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local spinner_index=0

    while [[ $waited -lt $max_wait ]]; do
        if qm status $VMID 2>/dev/null | grep -q "status: running"; then
            echo "[$(date +%T)] VM status: running" >> "$DEPLOYMENT_INFO_FILE"
            clear_spinner
            display_always "  ✓ VM is running"
            break
        fi

        display_spinner "${spinner_chars[$spinner_index]}" "$waited" "Waiting for VM to start..."
        spinner_index=$(( (spinner_index + 1) % ${#spinner_chars[@]} ))

        sleep 1
        ((waited+=1))
    done

    if [[ $waited -ge $max_wait ]]; then
        clear_spinner
        error_exit "VM failed to start within ${max_wait} seconds"
    fi

    # Give OPNsense time to boot
    display "  Waiting for OPNsense to initialize..."
    local init_wait=45
    waited=0
    spinner_index=0

    while [[ $waited -lt $init_wait ]]; do
        display_spinner "${spinner_chars[$spinner_index]}" "$waited" "OPNsense initializing..."
        spinner_index=$(( (spinner_index + 1) % ${#spinner_chars[@]} ))
        sleep 1
        ((waited+=1))
    done

    clear_spinner
    display_always "  ✓ OPNsense initialized"
}

# Test SSH connectivity
test_ssh_connectivity() {
    display_always "Testing connectivity..."
    
    # Wait for SSH to be available on Services VLAN
    display "  Waiting for SSH on ${OPNSENSE_SERVICES_IP}:22 (Services VLAN)..."
    local max_wait=300
    local waited=0

    local spinner_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local spinner_index=0
    local check_interval=5
    local seconds_since_check=0

    while [[ $waited -lt $max_wait ]]; do
        # Check SSH port every 5 seconds
        if [[ $seconds_since_check -ge $check_interval ]]; then
            if nc -zv $OPNSENSE_SERVICES_IP 22 &>/dev/null; then
                clear_spinner
                display_always "  ✓ SSH port is open on Services VLAN"
                break
            fi
            seconds_since_check=0
        fi

        # Update spinner every second
        display_spinner "${spinner_chars[$spinner_index]}" "$waited" "Waiting for SSH..."
        spinner_index=$(( (spinner_index + 1) % ${#spinner_chars[@]} ))

        sleep 1
        ((waited+=1))
        ((seconds_since_check+=1))
    done

    if [[ $waited -ge $max_wait ]]; then
        clear_spinner
        error_exit "SSH not available after ${max_wait} seconds"
    fi
    
    # Test SSH login via Services VLAN
    display "  Testing SSH authentication via Services VLAN..."
    if sshpass -p "$OPNSENSE_DEFAULT_PASSWORD" \
       ssh -o StrictHostKeyChecking=no \
           -o ConnectTimeout=5 \
           -o UserKnownHostsFile=/dev/null \
           ${OPNSENSE_DEFAULT_USER}@${OPNSENSE_SERVICES_IP} \
           "uname -a" &>/dev/null; then
        display_always "  ✓ SSH authentication successful via Services VLAN"
        echo "[$(date +%T)] SSH connectivity verified via Services VLAN" >> "$DEPLOYMENT_INFO_FILE"
        return 0
    else
        display "  ⚠ SSH authentication failed (may need more time)"
        echo "[$(date +%T)] WARNING: SSH test failed" >> "$DEPLOYMENT_INFO_FILE"
        return 1
    fi
}

# Apply custom configuration
apply_custom_config() {
    if [[ ! -f "$OPNSENSE_CONFIG" ]]; then
        display_always "  Skipping custom config (file not found)"
        return 0
    fi
    
    display_always "Applying custom configuration..."
    
    # Backup existing config
    display "  Backing up current config..."
    if sshpass -p "$OPNSENSE_DEFAULT_PASSWORD" \
       ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           ${OPNSENSE_DEFAULT_USER}@${OPNSENSE_SERVICES_IP} \
           "cp /conf/config.xml /conf/config.xml.backup.$(date +%Y%m%d-%H%M%S)"; then
        display "  ✓ Config backed up"
    else
        display "  ⚠ Could not backup config"
    fi
    
    # Copy new config
    display "  Uploading new configuration..."
    if sshpass -p "$OPNSENSE_DEFAULT_PASSWORD" \
       scp -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           "$OPNSENSE_CONFIG" \
           ${OPNSENSE_DEFAULT_USER}@${OPNSENSE_SERVICES_IP}:/conf/config.xml; then
        display_always "  ✓ Configuration uploaded"
    else
        error_exit "Failed to upload configuration"
    fi
    
    # Reboot OPNsense for VLAN changes to take effect
    display_always "  Rebooting OPNsense for VLAN configuration..."
    display "    This is required for VLAN interfaces to be properly configured"
    
    # Use Proxmox qm command to reboot the VM cleanly
    display "  Sending reboot command via Proxmox..."
    qm reboot $VMID || error_exit "Failed to send reboot command"
    
    # Wait for OPNsense to complete full reboot cycle (UP -> DOWN -> UP)
    display "  Waiting for OPNsense to complete reboot cycle..."
    local max_wait=180
    local waited=0
    local state="waiting_for_down"  # States: waiting_for_down, waiting_for_up

    local spinner_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local spinner_index=0

    while [[ $waited -lt $max_wait ]]; do
        if ping -c 1 -W 1 $OPNSENSE_SERVICES_IP &>/dev/null; then
            # OPNsense is responding
            if [[ "$state" == "waiting_for_down" ]]; then
                display_spinner "${spinner_chars[$spinner_index]}" "$waited" "Waiting for shutdown..."
                display "  OPNsense still up, waiting for shutdown (${waited}s)..."
            elif [[ "$state" == "waiting_for_up" ]]; then
                # Now check if SSH is also available
                if nc -zv $OPNSENSE_SERVICES_IP 22 &>/dev/null; then
                    clear_spinner
                    display_always "  ✓ OPNsense is back online with SSH available"
                    echo "[$(date +%T)] Custom configuration applied and OPNsense rebooted" >> "$DEPLOYMENT_INFO_FILE"
                    break
                else
                    display_spinner "${spinner_chars[$spinner_index]}" "$waited" "Waiting for SSH..."
                    display "  Ping OK but SSH not ready yet..."
                fi
            fi
        else
            # OPNsense is NOT responding
            if [[ "$state" == "waiting_for_down" ]]; then
                clear_spinner
                display_always "  ✓ OPNsense has gone down for reboot"
                state="waiting_for_up"
            elif [[ "$state" == "waiting_for_up" ]]; then
                display_spinner "${spinner_chars[$spinner_index]}" "$waited" "Waiting for OPNsense to come back up..."
                display "  Waiting for OPNsense to come back up (${waited}s)..."
            fi
        fi

        spinner_index=$(( (spinner_index + 1) % ${#spinner_chars[@]} ))
        sleep 1
        ((waited+=1))
    done

    clear_spinner
    if [[ $waited -ge $max_wait ]]; then
        if [[ "$state" == "waiting_for_down" ]]; then
            display_always "  ⚠ OPNsense never went down - reboot may have failed"
        else
            display_always "  ⚠ OPNsense reboot timeout after ${max_wait}s"
        fi
        display_always "    You may need to check the console"
    fi

    # Give services time to fully start
    display "  Waiting for services to stabilize..."
    local stabilize_wait=30
    waited=0
    spinner_index=0

    while [[ $waited -lt $stabilize_wait ]]; do
        display_spinner "${spinner_chars[$spinner_index]}" "$waited" "Services stabilizing..."
        spinner_index=$(( (spinner_index + 1) % ${#spinner_chars[@]} ))
        sleep 1
        ((waited+=1))
    done

    clear_spinner
    display_always "  ✓ Services stabilized"
    
    # Wait for VLAN interfaces to come up
    display "  Checking for VLAN interfaces..."
    local vlan_wait=0
    local vlan_max_wait=180
    local vlans_found=false

    local spinner_chars=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local spinner_index=0
    local check_interval=5
    local seconds_since_check=0

    while [[ $vlan_wait -lt $vlan_max_wait ]]; do
        # Check VLAN interfaces every 5 seconds
        if [[ $seconds_since_check -ge $check_interval ]]; then
            local vlan_output=$(sshpass -p "$OPNSENSE_DEFAULT_PASSWORD" \
                ssh -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o ConnectTimeout=5 \
                    -o LogLevel=ERROR \
                    ${OPNSENSE_DEFAULT_USER}@${OPNSENSE_SERVICES_IP} \
                    "ifconfig | grep -E 'vlan: (20|30|40|50|60|70)'" 2>/dev/null || true)

            if [[ -n "$vlan_output" ]]; then
                clear_spinner
                display_always "  ✓ VLAN interfaces are configured"
                vlans_found=true
                echo "[$(date +%T)] VLAN interfaces confirmed active" >> "$DEPLOYMENT_INFO_FILE"
                break
            fi
            seconds_since_check=0
        fi

        # Update spinner every second
        display_spinner "${spinner_chars[$spinner_index]}" "$vlan_wait" "Waiting for VLAN interfaces..."
        spinner_index=$(( (spinner_index + 1) % ${#spinner_chars[@]} ))

        sleep 1
        ((vlan_wait+=1))
        ((seconds_since_check+=1))
    done

    clear_spinner
    if [[ "$vlans_found" == "false" ]]; then
        display_always "  ⚠ VLAN interfaces did not come up after ${vlan_max_wait}s"
        display_always "    Configuration may need manual verification"
    fi
}

# Validate final setup
validate_deployment() {
    display_always "Validating deployment..."
    
    local all_good=true
    
    # Check VM is running
    if qm status $VMID 2>/dev/null | grep -q "status: running"; then
        display "  ✓ VM is running"
    else
        display "  ✗ VM is not running"
        all_good=false
        return 1  # No point checking further if VM isn't running
    fi
    
    # Check Services VLAN connectivity (management access)
    if ping -c 1 -W 2 $OPNSENSE_SERVICES_IP &>/dev/null; then
        display "  ✓ Services VLAN interface responding at $OPNSENSE_SERVICES_IP"
    else
        display "  ✗ Cannot ping Services VLAN interface"
        all_good=false
    fi
    
    # Check SSH access via Services VLAN
    if nc -zv $OPNSENSE_SERVICES_IP 22 &>/dev/null; then
        display "  ✓ SSH port is open on Services VLAN"
        
        # Test from OPNsense perspective
        display "  Testing OPNsense connectivity..."
        
        # Can OPNsense reach internet?
        if sshpass -p "$OPNSENSE_DEFAULT_PASSWORD" \
           ssh -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=5 \
               ${OPNSENSE_DEFAULT_USER}@${OPNSENSE_SERVICES_IP} \
               "ping -c 1 -W 2 8.8.8.8" &>/dev/null; then
            display "  ✓ OPNsense has internet connectivity"
        else
            display "  ✗ OPNsense cannot reach internet (check WAN)"
            all_good=false
        fi
        
        # Check if VLAN interfaces are configured
        local vlan_output=$(sshpass -p "$OPNSENSE_DEFAULT_PASSWORD" \
            ssh -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -o ConnectTimeout=5 \
                ${OPNSENSE_DEFAULT_USER}@${OPNSENSE_SERVICES_IP} \
                "ifconfig | grep -E 'vlan: (20|30|40|50|60|70)'" 2>/dev/null || true)
        
        if [[ -n "$vlan_output" ]]; then
            display "  ✓ VLAN interfaces are configured"
            
            # Specifically check VLAN 20
            if echo "$vlan_output" | grep -q "vlan 20"; then
                display_always "  ✓ Services VLAN (20) is configured"
            else
                display "  ✗ Services VLAN (20) not found"
                all_good=false
            fi
        else
            display "  ✗ No VLAN interfaces found"
            display "    Config may not have been applied correctly"
            all_good=false
        fi
    else
        display "  ✗ SSH port not accessible"
        all_good=false
    fi
    
    # Check Services VLAN gateway from Proxmox
    if ping -I vmbr1.20 -c 1 -W 2 10.10.20.1 &>/dev/null; then
        display_always "  ✓ Services VLAN gateway (10.10.20.1) responding"
    else
        display "  ⚠ Services VLAN gateway not responding from Proxmox"
        display "    This is expected if VLAN 20 isn't trunked to Proxmox"
    fi
    
    # Check web interface via Services VLAN
    if nc -zv $OPNSENSE_SERVICES_IP 443 -w 5 &>/dev/null; then
        display "  ✓ Web interface available on port 443 via Services VLAN"
    else
        display "  ⚠ Web interface not yet available on port 443"
    fi
    
    if [[ "$all_good" == "true" ]]; then
        display_always "  ✓ All validations passed"
    else
        display_always "  ⚠ Some validations failed"
        display_always "    Check /var/log/privatebox/opnsense-${VMID}-deployment.log for details"
    fi
}

# Display summary
display_summary() {
    # Update deployment log
    cat >> "$DEPLOYMENT_INFO_FILE" <<EOF

======================================
Deployment Summary
======================================
VM ID: $VMID
VM Name: $VM_NAME
Status: $(qm status $VMID 2>/dev/null | grep -o "status: [a-z]*" || echo "unknown")

Network Configuration:
- WAN: Bridge vmbr0 (DHCP)
- LAN: Bridge vmbr1 (${OPNSENSE_LAN_IP}/24)
- Services VLAN: 10.10.20.1/24 on VLAN 20

Access Information:
- SSH (LAN): ssh ${OPNSENSE_DEFAULT_USER}@${OPNSENSE_LAN_IP}
- SSH (Services): ssh ${OPNSENSE_DEFAULT_USER}@${OPNSENSE_SERVICES_IP}
- Web UI (LAN): https://${OPNSENSE_LAN_IP}
- Web UI (Services): https://${OPNSENSE_SERVICES_IP}
- Username: ${OPNSENSE_DEFAULT_USER}
- Password: ${OPNSENSE_DEFAULT_PASSWORD}

Deployment completed: $(date -Iseconds)
======================================
EOF
    
    # Display to console
    display_always ""
    display_always "=========================================="
    display_always "OPNsense Deployment Complete!"
    display_always "=========================================="
    display_always ""
    display_always "VM ID: $VMID"
    display_always "VM Name: $VM_NAME"
    display_always "Status: Running"
    display_always ""
    display_always "Network Configuration:"
    display_always "  WAN: DHCP on vmbr0"
    display_always "  LAN: ${OPNSENSE_LAN_IP}/24 on vmbr1"
    display_always "  Services: 10.10.20.1/24 on VLAN 20"
    display_always ""
    display_always "Access Methods:"
    display_always "  SSH (Services VLAN): ssh ${OPNSENSE_DEFAULT_USER}@${OPNSENSE_SERVICES_IP}"
    display_always "  SSH (LAN): ssh ${OPNSENSE_DEFAULT_USER}@${OPNSENSE_LAN_IP}"
    display_always "  Web (Services VLAN): https://${OPNSENSE_SERVICES_IP}"
    display_always "  Web (LAN): https://${OPNSENSE_LAN_IP}"
    display_always "  Credentials: ${OPNSENSE_DEFAULT_USER}/${OPNSENSE_DEFAULT_PASSWORD}"
    display_always ""
    display_always "IMPORTANT: Change the default password immediately!"
    display_always ""
    display_always "Management Commands:"
    display_always "  Console: qm terminal $VMID"
    display_always "  Stop: qm stop $VMID"
    display_always "  Start: qm start $VMID"
    display_always "  Remove: qm stop $VMID && qm destroy $VMID"
    display_always ""
    display_always "Logs: $DEPLOYMENT_INFO_FILE"
    display_always "=========================================="
}

# Main execution
main() {
    display_always "Starting OPNsense deployment..."
    log "OPNsense deployment started"
    
    # Set trap for cleanup on failure
    trap 'cleanup_on_failure' ERR
    
    # Run deployment phases
    run_preflight_checks
    download_template
    restore_vm
    start_vm
    
    # Only test connectivity and apply config if VM was started
    if [[ "$START_AFTER_RESTORE" == "true" ]]; then
        if test_ssh_connectivity; then
            apply_custom_config
        else
            display_always "  Skipping custom config due to SSH issues"
        fi
        validate_deployment
    fi
    
    # Display summary
    display_summary
    
    # Create completion marker
    touch "${DEPLOYMENT_MARKER_DIR}/opnsense-${VMID}.deployed"
    
    # Clean up temporary markers
    rm -f "$CLEANUP_DONE_MARKER"
    
    display_always ""
    display_always "✓ OPNsense deployment complete"
    log "OPNsense deployment completed successfully"
}

# Run main
main "$@"