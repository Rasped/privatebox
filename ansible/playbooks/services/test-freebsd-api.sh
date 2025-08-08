#!/bin/bash
# Test script for FreeBSD API deployment
# Run from privatebox root directory

set -e

echo "=== FreeBSD API Deployment Test ==="

# Configuration
PLAYBOOK="ansible/playbooks/services/freebsd-autoinstall-api.yml"
INVENTORY="ansible/inventory.yml"
TEST_VMID="${TEST_VMID:-9999}"
TEST_VM_NAME="${TEST_VM_NAME:-freebsd-test}"
TEST_VM_IP="${TEST_VM_IP:-192.168.1.59}"

# Check required environment variables
echo "Checking environment variables..."

if [[ -z "$PROXMOX_HOST" ]]; then
    echo "ERROR: PROXMOX_HOST not set"
    echo "Example: export PROXMOX_HOST=192.168.1.10"
    exit 1
fi

if [[ -z "$PROXMOX_USER" ]]; then
    echo "ERROR: PROXMOX_USER not set"  
    echo "Example: export PROXMOX_USER=root@pam"
    exit 1
fi

# Check authentication method
if [[ -n "$PROXMOX_TOKEN_ID" && -n "$PROXMOX_TOKEN_SECRET" ]]; then
    echo "✓ Using API token authentication"
    AUTH_METHOD="token"
elif [[ -n "$PROXMOX_PASSWORD" ]]; then
    echo "✓ Using password authentication"
    AUTH_METHOD="password"
else
    echo "ERROR: No authentication configured"
    echo "Set either:"
    echo "  PROXMOX_TOKEN_ID + PROXMOX_TOKEN_SECRET (recommended)"
    echo "  or PROXMOX_PASSWORD"
    exit 1
fi

echo "✓ Environment configuration valid"

# Test Proxmox API connectivity
echo ""
echo "Testing Proxmox API connectivity..."

if [[ "$AUTH_METHOD" == "token" ]]; then
    AUTH_HEADER="Authorization: PVEAPIToken=${PROXMOX_USER}!${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"
else
    # Base64 encode user:password for basic auth
    CREDENTIALS=$(echo -n "${PROXMOX_USER}:${PROXMOX_PASSWORD}" | base64)
    AUTH_HEADER="Authorization: Basic ${CREDENTIALS}"
fi

API_TEST=$(curl -k -s -H "$AUTH_HEADER" \
    "https://${PROXMOX_HOST}:8006/api2/json/version" || echo "FAILED")

if [[ "$API_TEST" == "FAILED" || ! "$API_TEST" =~ '"success":true' ]]; then
    echo "ERROR: Proxmox API connectivity test failed"
    echo "Response: $API_TEST"
    echo ""
    echo "Troubleshooting:"
    echo "- Check PROXMOX_HOST is correct and reachable"
    echo "- Verify credentials are correct"
    echo "- Ensure Proxmox web interface is accessible"
    exit 1
fi

echo "✓ Proxmox API connectivity successful"

# Check if test VM already exists and clean it up
echo ""
echo "Checking for existing test VM..."

VM_EXISTS=$(curl -k -s -H "$AUTH_HEADER" \
    "https://${PROXMOX_HOST}:8006/api2/json/nodes/localhost/qemu/${TEST_VMID}/status/current" \
    2>/dev/null | grep -o '"success":true' || echo "")

if [[ -n "$VM_EXISTS" ]]; then
    echo "⚠ VM ${TEST_VMID} already exists, will be destroyed during playbook run"
fi

# Run syntax check
echo ""
echo "Running Ansible syntax check..."
if ! ansible-playbook --syntax-check "$PLAYBOOK"; then
    echo "ERROR: Playbook syntax check failed"
    exit 1
fi
echo "✓ Playbook syntax is valid"

# Check required dependencies
echo ""
echo "Checking dependencies..."

# Check if community.general collection is available
if ! ansible-doc community.general.proxmox_kvm >/dev/null 2>&1; then
    echo "ERROR: community.general collection not found"
    echo "Install with: ansible-galaxy collection install community.general"
    exit 1
fi
echo "✓ community.general collection available"

# Check genisoimage
if ! command -v genisoimage >/dev/null 2>&1; then
    echo "WARNING: genisoimage not found, playbook will try to install it"
    echo "Manual install: apt install genisoimage (Debian/Ubuntu) or equivalent"
else
    echo "✓ genisoimage available"
fi

# Check sshpass
if ! command -v sshpass >/dev/null 2>&1; then
    echo "WARNING: sshpass not found, SSH testing may fail"
    echo "Manual install: apt install sshpass (Debian/Ubuntu) or equivalent"
else
    echo "✓ sshpass available"
fi

# Run the playbook in check mode first
echo ""
echo "Running playbook in check mode (dry run)..."

EXTRA_VARS="vmid=${TEST_VMID} vm_name=${TEST_VM_NAME} vm_static_ip=${TEST_VM_IP}"

if ! ansible-playbook -i "$INVENTORY" "$PLAYBOOK" \
    --check \
    --diff \
    -e "$EXTRA_VARS" \
    -v; then
    echo "ERROR: Playbook check mode failed"
    exit 1
fi

echo "✓ Playbook check mode successful"

# Prompt for actual deployment
echo ""
echo "=== Test Configuration ==="
echo "VM ID: ${TEST_VMID}"
echo "VM Name: ${TEST_VM_NAME}"  
echo "VM IP: ${TEST_VM_IP}"
echo "Proxmox Host: ${PROXMOX_HOST}"
echo "Auth Method: ${AUTH_METHOD}"
echo ""

if [[ "${SKIP_PROMPT}" != "true" ]]; then
    read -p "Do you want to proceed with actual deployment? [y/N]: " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Test completed - deployment skipped"
        exit 0
    fi
fi

# Run the actual deployment
echo ""
echo "=== Starting FreeBSD VM Deployment ==="
echo ""

# Add tags to run only specific parts if desired
TAGS="${DEPLOY_TAGS:-all}"

START_TIME=$(date +%s)

if ansible-playbook -i "$INVENTORY" "$PLAYBOOK" \
    -e "$EXTRA_VARS" \
    --tags "$TAGS" \
    -v; then
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo "=== Deployment Successful ==="
    echo "Duration: ${DURATION} seconds"
    echo "VM ID: ${TEST_VMID}"
    echo "VM IP: ${TEST_VM_IP}"
    echo "SSH Command: ssh freebsd@${TEST_VM_IP}"
    echo ""
    echo "Deployment info saved to: /tmp/freebsd-${TEST_VMID}-api-deployment-info.txt"
    
else
    echo ""
    echo "=== Deployment Failed ==="
    echo "Check the error messages above for troubleshooting guidance"
    exit 1
fi

echo ""
echo "=== Test Complete ==="