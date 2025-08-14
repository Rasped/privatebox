#!/usr/bin/env bash
set -euo pipefail

# Test script for FreeBSD auto-installer ISO build
# Run this on the Proxmox host

echo "=== FreeBSD Auto-Installer ISO Test ==="
echo "This will:"
echo "1. Build the auto-installer ISO"
echo "2. Create a test VM (VMID 9998)"
echo "3. Boot and auto-install FreeBSD"
echo "4. Verify the installation"
echo ""

# Configuration
TEST_VMID=9998
ISO_NAME="mfsbsd-freebsd-autoinstaller.iso"

# Check if we're on Proxmox
if ! command -v qm >/dev/null 2>&1; then
    echo "ERROR: This script must be run on a Proxmox host"
    exit 1
fi

# Clean up any existing test VM
if qm status $TEST_VMID >/dev/null 2>&1; then
    echo "Cleaning up existing test VM $TEST_VMID..."
    qm stop $TEST_VMID >/dev/null 2>&1 || true
    sleep 2
    qm destroy $TEST_VMID --purge >/dev/null 2>&1 || true
fi

# Build the ISO
echo ""
echo "=== Building Auto-Installer ISO ==="
cd /root/privatebox || { echo "ERROR: /root/privatebox not found. Clone the repo first."; exit 1; }

if [ ! -f "bootstrap/build_freebsd_autoiso.sh" ]; then
    echo "ERROR: bootstrap/build_freebsd_autoiso.sh not found"
    echo "Make sure you have the latest files from the repo"
    exit 1
fi

# Run the build
bash bootstrap/build_freebsd_autoiso.sh

# Check if ISO was created
if [ ! -f "/var/lib/vz/template/iso/$ISO_NAME" ]; then
    echo "ERROR: ISO was not created at /var/lib/vz/template/iso/$ISO_NAME"
    exit 1
fi

echo "✓ ISO created successfully"

# Create test VM
echo ""
echo "=== Creating Test VM $TEST_VMID ==="
qm create $TEST_VMID \
    --name freebsd-autoinstall-test \
    --memory 2048 \
    --cores 2 \
    --sockets 1 \
    --net0 virtio,bridge=vmbr1 \
    --serial0 socket \
    --vga serial0

# Add disk for installation target
qm set $TEST_VMID --virtio0 local-lvm:32 >/dev/null

# Attach the ISO
qm set $TEST_VMID --ide2 "local:iso/$ISO_NAME,media=cdrom" >/dev/null
qm set $TEST_VMID --boot order=ide2 >/dev/null

echo "✓ Test VM created"

# Start the VM
echo ""
echo "=== Starting Auto-Installation ==="
echo "VM will boot from ISO and auto-install FreeBSD..."
qm start $TEST_VMID

# Monitor installation (should power off when done)
echo "Waiting for installation to complete (VM will power off)..."
TIMEOUT=600  # 10 minutes
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    STATUS=$(qm status $TEST_VMID | awk '{print $2}')
    if [ "$STATUS" = "stopped" ]; then
        echo "✓ Installation complete (VM powered off)"
        break
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    echo -n "."
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo ""
    echo "ERROR: Installation did not complete within 10 minutes"
    echo "Check the VM console for errors: qm terminal $TEST_VMID"
    exit 1
fi

# Remove ISO and set boot to disk
echo ""
echo "=== Configuring for First Boot ==="
qm set $TEST_VMID --delete ide2 >/dev/null
qm set $TEST_VMID --boot order=virtio0 >/dev/null

# Start VM for first boot
echo "Starting VM for first boot..."
qm start $TEST_VMID
sleep 30  # Give it time to boot

# Get VM IP
echo ""
echo "=== Checking VM Network ==="
# Try to get IP from DHCP leases or ARP
VM_MAC=$(qm config $TEST_VMID | grep -E "^net0:" | grep -oE "([0-9A-F]{2}:){5}[0-9A-F]{2}" | tr '[:upper:]' '[:lower:]')
if [ -n "$VM_MAC" ]; then
    # Check dnsmasq leases
    VM_IP=$(grep -i "$VM_MAC" /var/lib/misc/dnsmasq.leases 2>/dev/null | awk '{print $3}' | head -1)
    
    # If not found, try ARP
    if [ -z "$VM_IP" ]; then
        ping -c 1 -W 1 192.168.1.255 >/dev/null 2>&1  # Broadcast ping to populate ARP
        VM_IP=$(arp -n | grep -i "$VM_MAC" | awk '{print $1}' | head -1)
    fi
fi

if [ -n "$VM_IP" ]; then
    echo "✓ VM IP detected: $VM_IP"
    
    echo ""
    echo "=== Testing SSH Access ==="
    echo "Attempting SSH connection (password: privatebox123)..."
    
    # Test SSH (will prompt for password)
    if command -v sshpass >/dev/null 2>&1; then
        if sshpass -p "privatebox123" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$VM_IP "uname -a" 2>/dev/null; then
            echo "✓ SSH access successful!"
        else
            echo "✗ SSH failed - you can try manually:"
            echo "  ssh root@$VM_IP"
            echo "  Password: privatebox123"
        fi
    else
        echo "Test SSH manually:"
        echo "  ssh root@$VM_IP"
        echo "  Password: privatebox123"
    fi
else
    echo "Could not detect VM IP address"
    echo "Check the VM console: qm terminal $TEST_VMID"
fi

echo ""
echo "=== Test Complete ==="
echo "VM $TEST_VMID is running FreeBSD"
echo "Next steps:"
echo "1. SSH into the VM and verify FreeBSD is working"
echo "2. Test opnsense-bootstrap manually"
echo "3. When done testing: qm destroy $TEST_VMID --purge"