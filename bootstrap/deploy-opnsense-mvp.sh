#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

#################################################################
# 1. CONFIGURATION - EDIT THESE VARIABLES
#################################################################

# --- VM Settings ---
VM_ID="100"  # Using PrivateBox standard VM ID for OPNsense
VM_NAME="opnsense-firewall"
VM_MEMORY="4096" # In MB
VM_CORES="2"

# --- Storage & Network ---
STORAGE_DISK="local-lvm"
STORAGE_ISO="local"
DISK_SIZE="20G"
NET_WAN="vmbr0"  # Proxmox bridge for WAN
NET_LAN="vmbr1"  # Proxmox bridge for LAN (VLAN-aware)

# --- OPNsense Image Source ---
OPNSENSE_VER="24.7"
OPNSENSE_URL="https://mirror.ams1.nl.leaseweb.net/opnsense/releases/${OPNSENSE_VER}/OPNsense-${OPNSENSE_VER}-nano-amd64.img.bz2"
IMG_NAME=$(basename $OPNSENSE_URL)
IMG_PATH="/tmp/${IMG_NAME}"
IMG_DECOMPRESSED_PATH="/tmp/OPNsense-${OPNSENSE_VER}-nano-amd64.img"

# --- Your Config File ---
# This will be copied from the repo to Proxmox during deployment
CONFIG_XML_PATH="/tmp/opnsense-config.xml"

#################################################################
# 2. SCRIPT LOGIC
#################################################################

echo "### PrivateBox OPNsense Deployment Script (MVP) ###"
echo ""

echo "### 1/8: Checking for required tools..."
for cmd in wget bunzip2 genisoimage qm; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: Required command '$cmd' is not installed. Exiting."
        exit 1
    fi
done

echo "### 2/8: Fetching config.xml from GitHub..."
# Download the config.xml from the PrivateBox repo
wget -q --show-progress -O "$CONFIG_XML_PATH" \
    "https://raw.githubusercontent.com/Rasped/privatebox/main/bootstrap/configs/opnsense/config.xml"

if [ ! -f "$CONFIG_XML_PATH" ]; then
    echo "Error: Failed to download config.xml. Exiting."
    exit 1
fi

echo "### 3/8: Fetching OPNsense nano image..."
if [ -f "$IMG_PATH" ]; then
    echo "Image '$IMG_NAME' already downloaded."
else
    wget -q --show-progress -O "$IMG_PATH" "$OPNSENSE_URL"
fi

echo "### 4/8: Decompressing image..."
if [ -f "$IMG_DECOMPRESSED_PATH" ]; then
    echo "Image '$IMG_DECOMPRESSED_PATH' already decompressed."
else
    bunzip2 -k "$IMG_PATH"
    # The -k flag keeps the original and creates the .img file directly
    # No need to move as bunzip2 creates it in the right place
fi

echo "### 5/8: Creating configuration ISO..."
# Temporary directories for building the ISO
CONFIG_TMP_DIR="/tmp/opnsense_config_$$"  # $$ adds process ID for uniqueness
CONFIG_ISO_PATH="/tmp/config-${VM_ID}.iso"
CONFIG_ISO_NAME_PROXMOX="config-${VM_ID}.iso"
ISO_STORAGE_PATH="/var/lib/vz/template/iso/${CONFIG_ISO_NAME_PROXMOX}"

# Create the required /conf/config.xml structure
mkdir -p "${CONFIG_TMP_DIR}/conf"
cp "$CONFIG_XML_PATH" "${CONFIG_TMP_DIR}/conf/config.xml"

# Create the ISO image
genisoimage -o "$CONFIG_ISO_PATH" -R -J "${CONFIG_TMP_DIR}"
echo "Config ISO created at $CONFIG_ISO_PATH"

# Copy ISO to Proxmox ISO storage
cp "$CONFIG_ISO_PATH" "$ISO_STORAGE_PATH"

echo "### 6/8: Creating VM ${VM_ID}..."
# Destroy VM if it already exists
if qm status $VM_ID &> /dev/null; then
    echo "VM ${VM_ID} already exists. Destroying it."
    qm stop $VM_ID --timeout 30 || true # Ignore error if already stopped
    qm destroy $VM_ID
fi

# Create the VM with VLAN-aware LAN bridge
qm create $VM_ID \
    --name $VM_NAME \
    --memory $VM_MEMORY \
    --cores $VM_CORES \
    --net0 virtio,bridge=$NET_WAN \
    --net1 virtio,bridge=$NET_LAN \
    --scsihw virtio-scsi-pci \
    --ostype l26

echo "VM ${VM_ID} created."

echo "### 7/8: Importing and attaching disks..."
# Import the nano image as the main disk
qm importdisk $VM_ID "$IMG_DECOMPRESSED_PATH" $STORAGE_DISK

# Set the imported disk as the scsi0 boot disk
qm set $VM_ID --scsi0 ${STORAGE_DISK}:vm-${VM_ID}-disk-0
qm set $VM_ID --boot order=scsi0

# Resize the disk
qm resize $VM_ID scsi0 $DISK_SIZE

# Attach the config ISO as a CD-ROM (ide2 is good for CD-ROMs)
qm set $VM_ID --ide2 ${STORAGE_ISO}:iso/${CONFIG_ISO_NAME_PROXMOX},media=cdrom

echo "### 8/8: Starting VM and cleaning up..."
qm start $VM_ID

# Clean up temporary files
rm -rf "$CONFIG_TMP_DIR"
rm -f "$CONFIG_ISO_PATH"
rm -f "$CONFIG_XML_PATH"  # Remove downloaded config
echo "Cleanup complete."

echo ""
echo "========================================================="
echo "SUCCESS: VM ${VM_ID} (${VM_NAME}) is starting."
echo ""
echo "OPNsense will import the configuration and reboot."
echo "After boot, you should be able to access:"
echo "  - Web UI: https://10.10.20.1"
echo "  - SSH: ssh root@10.10.20.1"
echo ""
echo "Note: This is an MVP script. For production use,"
echo "      consider adding checksums, retries, and logging."
echo "========================================================="