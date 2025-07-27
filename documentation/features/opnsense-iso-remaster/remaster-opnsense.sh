#!/usr/bin/env bash
#
# OPNsense ISO Remastering Script - REFERENCE ONLY
# 
# NOTE: This script is provided for understanding the remastering process.
# Production deployments use pure Ansible tasks executing on Proxmox.
# 
# Creates custom OPNsense ISO with embedded configuration for 100% hands-off deployment
#
# Usage: ./remaster-opnsense.sh config.xml [iso-url] [output-iso]
#
# Author: PrivateBox Project
# License: MIT

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions for colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Validate requirements
check_requirements() {
    local missing_tools=()
    
    for tool in xorriso rsync xmllint curl bzip2; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Install with: sudo apt-get install xorriso genisoimage bzip2 rsync xmllint curl"
        exit 1
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    if mountpoint -q /mnt/opnsense-orig 2>/dev/null; then
        sudo umount /mnt/opnsense-orig || true
    fi
    if [ -n "${WORK_DIR:-}" ] && [ -d "$WORK_DIR" ]; then
        sudo rm -rf "$WORK_DIR"
    fi
}

# Set trap for cleanup
trap cleanup EXIT

# Arguments
CONFIG_FILE="${1:?Error: Please provide config.xml path as first argument}"
ISO_URL="${2:-https://mirror.dns-root.de/opnsense/releases/25.7/OPNsense-25.7-OpenSSL-dvd-amd64.iso.bz2}"
OUTPUT_ISO="${3:-opnsense-custom.iso}"

# Validate config exists
if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Config file $CONFIG_FILE not found"
    exit 1
fi

# Check requirements
check_requirements

# Validate XML
log_info "Validating configuration XML..."
if ! xmllint --noout "$CONFIG_FILE" 2>/dev/null; then
    log_error "Invalid XML in config file"
    exit 1
fi

# Setup working directory
WORK_DIR=$(mktemp -d -p "${TMPDIR:-/tmp}" opnsense-remaster.XXXXXX)
log_info "Working directory: $WORK_DIR"
cd "$WORK_DIR"

# Download ISO if needed
ISO_NAME=$(basename "$ISO_URL" .bz2)
ISO_BZ2="${ISO_NAME}.bz2"

if [ -f "$HOME/Downloads/$ISO_NAME" ]; then
    log_info "Using existing ISO from ~/Downloads/"
    cp "$HOME/Downloads/$ISO_NAME" .
elif [ -f "$HOME/Downloads/$ISO_BZ2" ]; then
    log_info "Extracting existing ISO from ~/Downloads/"
    cp "$HOME/Downloads/$ISO_BZ2" .
    bzip2 -d "$ISO_BZ2"
else
    log_info "Downloading OPNsense ISO..."
    log_info "URL: $ISO_URL"
    curl -L "$ISO_URL" -o "$ISO_BZ2" --progress-bar
    log_info "Extracting ISO..."
    bzip2 -d "$ISO_BZ2"
fi

# Verify ISO exists
if [ ! -f "$ISO_NAME" ]; then
    log_error "ISO file not found after download/extraction"
    exit 1
fi

# Mount original ISO
log_info "Mounting original ISO..."
sudo mkdir -p /mnt/opnsense-orig
if ! sudo mount -t iso9660 -o loop,ro "$ISO_NAME" /mnt/opnsense-orig; then
    log_error "Failed to mount ISO"
    exit 1
fi

# Copy ISO contents
log_info "Copying ISO contents (this may take a minute)..."
mkdir -p iso-contents
if ! sudo rsync -a /mnt/opnsense-orig/ iso-contents/; then
    log_error "Failed to copy ISO contents"
    exit 1
fi

# Ensure config directory exists
sudo mkdir -p iso-contents/usr/local/etc

# Inject custom config
log_info "Injecting custom configuration..."
sudo cp "$CONFIG_FILE" iso-contents/usr/local/etc/config.xml
sudo chmod 644 iso-contents/usr/local/etc/config.xml

# Validate injected config
log_info "Validating injected configuration..."
if ! xmllint --noout iso-contents/usr/local/etc/config.xml; then
    log_error "Failed to validate injected config"
    exit 1
fi

# Extract key configuration values for display
HOSTNAME=$(xmllint --xpath "string(//system/hostname)" "$CONFIG_FILE" 2>/dev/null || echo "unknown")
LAN_IP=$(xmllint --xpath "string(//interfaces/lan/ipaddr)" "$CONFIG_FILE" 2>/dev/null || echo "DHCP")
SSH_ENABLED=$(xmllint --xpath "string(//system/ssh/enabled)" "$CONFIG_FILE" 2>/dev/null || echo "disabled")

# Get boot parameters from original ISO
log_info "Analyzing original ISO boot structure..."
xorriso -indev "$ISO_NAME" -report_el_torito cmd 2>/dev/null > boot_params.txt || true

# Create new ISO using xorriso
log_info "Creating custom ISO..."
log_info "Output: $(realpath "$OUTPUT_ISO")"

if ! xorriso -as mkisofs \
    -quiet \
    -R -J -joliet-long \
    -b boot/cdboot \
    -c boot.catalog \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -o "$OUTPUT_ISO" \
    iso-contents 2>/dev/null; then
    log_error "Failed to create ISO"
    exit 1
fi

# Move ISO to original working directory
mv "$OUTPUT_ISO" "$OLDPWD/"
cd "$OLDPWD"

# Calculate checksums
log_info "Calculating checksums..."
ISO_SIZE=$(stat -c%s "$OUTPUT_ISO" 2>/dev/null || stat -f%z "$OUTPUT_ISO" 2>/dev/null)
ISO_SIZE_MB=$((ISO_SIZE / 1024 / 1024))
ISO_SHA256=$(sha256sum "$OUTPUT_ISO" | cut -d' ' -f1)

# Success message
log_info "================== SUCCESS =================="
log_info "Custom ISO created: $OUTPUT_ISO"
log_info "Size: ${ISO_SIZE_MB} MB"
log_info "SHA256: $ISO_SHA256"
log_info ""
log_info "Configuration Summary:"
log_info "  Hostname: $HOSTNAME"
log_info "  LAN IP: $LAN_IP"
log_info "  SSH: $SSH_ENABLED"
log_info ""
log_info "Next steps:"
log_info "1. Upload to Proxmox: scp $OUTPUT_ISO root@proxmox:/var/lib/vz/template/iso/"
log_info "2. Create VM with this ISO"
log_info "3. Boot VM - configuration will be applied automatically!"
log_info "============================================"