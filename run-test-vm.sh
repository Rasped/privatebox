#!/bin/bash
# Test wrapper for create-generic-vm.sh with proper array handling

echo "==================================="
echo "Testing Generic VM Creation Script"
echo "==================================="

# Set basic variables
export VMID="9100"
export VM_NAME="test-generic-vm"
export STATIC_IP="192.168.1.150"
export VM_USERNAME="testuser"
export VM_PASSWORD="testpass123"
export DEBUG="true"

# Use string format for arrays (semicolon-separated)
export FILES_TO_COPY_STR="/root/test-setup.sh:/opt/test-setup.sh:0755"
export SCRIPTS_TO_RUN_STR="/opt/test-setup.sh"

# Show what we're going to do
echo "Configuration:"
echo "  VMID: $VMID"
echo "  VM_NAME: $VM_NAME"
echo "  STATIC_IP: $STATIC_IP"
echo "  USERNAME: $VM_USERNAME"
echo "  FILES_TO_COPY_STR: $FILES_TO_COPY_STR"
echo "  SCRIPTS_TO_RUN_STR: $SCRIPTS_TO_RUN_STR"
echo ""

# Run the script
cd /root
./create-generic-vm.sh