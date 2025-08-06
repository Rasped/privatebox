#!/bin/bash
#
# Test script for Bootstrap v2 with Semaphore API integration
# Run this on a Proxmox host to test the complete bootstrap
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TEST_LOG="/tmp/bootstrap-v2-test.log"
VMID=9000

echo "====================================="
echo "Bootstrap v2 Test with API Integration"
echo "====================================="
echo ""

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "info")
            echo -e "${NC}[INFO] $message${NC}"
            ;;
        "success")
            echo -e "${GREEN}[✓] $message${NC}"
            ;;
        "warning")
            echo -e "${YELLOW}[⚠] $message${NC}"
            ;;
        "error")
            echo -e "${RED}[✗] $message${NC}"
            ;;
    esac
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$status] $message" >> "$TEST_LOG"
}

# Pre-flight checks
print_status "info" "Starting pre-flight checks..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_status "error" "This script must be run as root"
    exit 1
fi

# Check if on Proxmox
if [[ ! -d /etc/pve ]]; then
    print_status "error" "This script must be run on a Proxmox host"
    exit 1
fi

# Check for existing VM
if qm status $VMID &>/dev/null; then
    print_status "warning" "VM $VMID exists - it will be destroyed"
    read -p "Continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "info" "Test cancelled by user"
        exit 0
    fi
fi

print_status "success" "Pre-flight checks passed"

# Create temporary test directory
TEST_DIR="/tmp/bootstrap-v2-test-$(date +%s)"
mkdir -p "$TEST_DIR"
print_status "info" "Test directory: $TEST_DIR"

# Copy bootstrap v2 files
print_status "info" "Copying bootstrap v2 files..."
cp -r bootstrap2/* "$TEST_DIR/" 2>/dev/null || {
    print_status "error" "Failed to copy bootstrap2 files. Are you in the privatebox directory?"
    exit 1
}

# Make scripts executable
chmod +x "$TEST_DIR"/*.sh
chmod +x "$TEST_DIR"/lib/*.sh 2>/dev/null || true

print_status "success" "Bootstrap files prepared"

# Run bootstrap phases
cd "$TEST_DIR"

print_status "info" "========== PHASE 1: Host Preparation =========="
if ./prepare-host.sh; then
    print_status "success" "Host preparation completed"
else
    print_status "error" "Host preparation failed"
    exit 1
fi

# Check config file was created
if [[ ! -f /tmp/privatebox-config.conf ]]; then
    print_status "error" "Configuration file not created"
    exit 1
fi

# Source config for verification
source /tmp/privatebox-config.conf
print_status "info" "VM will be created at IP: ${STATIC_IP}"

print_status "info" "========== PHASE 2: VM Creation =========="
if ./create-vm.sh; then
    print_status "success" "VM creation completed"
else
    print_status "error" "VM creation failed"
    exit 1
fi

# Verify VM was created
if ! qm status $VMID &>/dev/null; then
    print_status "error" "VM $VMID was not created"
    exit 1
fi

print_status "info" "========== PHASE 3: Guest Setup (via cloud-init) =========="
print_status "info" "This phase runs inside the VM automatically"
print_status "info" "Waiting for cloud-init to complete..."

print_status "info" "========== PHASE 4: Verification =========="
if ./verify-install.sh; then
    print_status "success" "Installation verification completed"
else
    print_status "error" "Installation verification failed"
    exit 1
fi

# Additional API verification
print_status "info" "========== API Configuration Verification =========="

# Wait a bit for API to be fully ready
sleep 10

# Check Semaphore API
VM_IP="${STATIC_IP}"
print_status "info" "Checking Semaphore API at ${VM_IP}:3000..."

# Try to authenticate
AUTH_RESPONSE=$(curl -s -c /tmp/sem-cookie -X POST \
    -H "Content-Type: application/json" \
    -d "{\"auth\": \"admin\", \"password\": \"${SERVICES_PASSWORD}\"}" \
    "http://${VM_IP}:3000/api/auth/login" 2>/dev/null)

if [[ -f /tmp/sem-cookie ]] && grep -q "semaphore" /tmp/sem-cookie; then
    print_status "success" "Semaphore API authentication successful"
    
    # Check projects
    PROJECTS=$(curl -s -b /tmp/sem-cookie "http://${VM_IP}:3000/api/projects" 2>/dev/null)
    if echo "$PROJECTS" | grep -q "PrivateBox"; then
        print_status "success" "PrivateBox project found in Semaphore"
    else
        print_status "warning" "PrivateBox project not found"
        echo "Projects response: $PROJECTS" >> "$TEST_LOG"
    fi
    
    # Check SSH keys
    KEYS=$(curl -s -b /tmp/sem-cookie "http://${VM_IP}:3000/api/project/1/keys" 2>/dev/null)
    if echo "$KEYS" | grep -q "proxmox\|container-host"; then
        print_status "success" "SSH keys configured in Semaphore"
    else
        print_status "warning" "SSH keys not found"
        echo "Keys response: $KEYS" >> "$TEST_LOG"
    fi
    
    # Check inventories
    INVENTORIES=$(curl -s -b /tmp/sem-cookie "http://${VM_IP}:3000/api/project/1/inventory" 2>/dev/null)
    if echo "$INVENTORIES" | grep -q "container-host"; then
        print_status "success" "Inventories configured in Semaphore"
    else
        print_status "warning" "Inventories not found"
        echo "Inventories response: $INVENTORIES" >> "$TEST_LOG"
    fi
    
    rm -f /tmp/sem-cookie
else
    print_status "error" "Failed to authenticate with Semaphore API"
fi

# Check logs inside VM
print_status "info" "Checking VM logs..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "debian@${VM_IP}" \
    "sudo tail -20 /var/log/privatebox-guest-setup.log" 2>/dev/null | \
    grep -E "(ERROR|WARNING|completed|failed)" | tail -5 || true

# Summary
echo ""
echo "====================================="
echo "Test Summary"
echo "====================================="
print_status "info" "VM IP: ${VM_IP}"
print_status "info" "Portainer: http://${VM_IP}:9000"
print_status "info" "Semaphore: http://${VM_IP}:3000"
print_status "info" "Username: admin"
print_status "info" "Password: ${SERVICES_PASSWORD}"
echo ""
print_status "info" "Test log: $TEST_LOG"
print_status "info" "VM logs: ssh debian@${VM_IP} 'sudo cat /var/log/privatebox-guest-setup.log'"
echo ""

# Cleanup
print_status "info" "Test files in: $TEST_DIR"
print_status "info" "To destroy test VM: qm destroy $VMID --purge"

print_status "success" "Bootstrap v2 test completed!"