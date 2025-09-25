#!/bin/bash
#
# Validate Bootstrap v2 files before deployment
#

echo "Validating Bootstrap v2 files..."
echo ""

# Check required files exist
REQUIRED_FILES=(
    "bootstrap.sh"
    "prepare-host.sh"
    "deploy-opnsense.sh"
    "create-vm.sh"
    "setup-guest.sh"
    "verify-install.sh"
    "lib/semaphore-api.sh"
    "configs/opnsense/config.xml"
)

MISSING=0
for file in "${REQUIRED_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        echo "✓ Found: $file"
    else
        echo "✗ Missing: $file"
        MISSING=$((MISSING + 1))
    fi
done

echo ""

# Check for API integration in files
echo "Checking API integration..."

# Check create-vm.sh has SSH key and API library inclusion
if grep -q "proxmox_private_key" create-vm.sh && \
   grep -q "semaphore_api_content" create-vm.sh; then
    echo "✓ create-vm.sh includes SSH keys and API library"
else
    echo "✗ create-vm.sh missing SSH key or API library inclusion"
    MISSING=$((MISSING + 1))
fi

# Check setup-guest.sh has API configuration
if grep -q "create_default_projects" setup-guest.sh && \
   grep -q "generate_vm_ssh_key_pair" setup-guest.sh; then
    echo "✓ setup-guest.sh has API configuration"
else
    echo "✗ setup-guest.sh missing API configuration"
    MISSING=$((MISSING + 1))
fi

# Check verify-install.sh has API verification
if grep -q "Semaphore API" verify-install.sh && \
   grep -q "PrivateBox project" verify-install.sh; then
    echo "✓ verify-install.sh has API verification"
else
    echo "✗ verify-install.sh missing API verification"
    MISSING=$((MISSING + 1))
fi

# Check semaphore-api.sh has embedded logging
if grep -q "^log_info()" lib/semaphore-api.sh && \
   grep -q "^log_error()" lib/semaphore-api.sh; then
    echo "✓ semaphore-api.sh has embedded logging functions"
else
    echo "✗ semaphore-api.sh missing embedded logging"
    MISSING=$((MISSING + 1))
fi

echo ""

# Summary
if [[ $MISSING -eq 0 ]]; then
    echo "✅ All validations passed! Bootstrap v2 is ready for testing."
    echo ""
    echo "To test on Proxmox:"
    echo "1. Copy bootstrap2/ directory to Proxmox host"
    echo "2. Run: cd bootstrap2 && chmod +x *.sh"
    echo "3. Run: ./test-bootstrap.sh"
    echo ""
    echo "Or run the full bootstrap:"
    echo "   ./bootstrap.sh"
else
    echo "❌ Found $MISSING issues. Please fix before testing."
    exit 1
fi