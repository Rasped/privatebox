#!/bin/bash
# Test template rendering

cd /tmp/privatebox-bootstrap-test

# Source libraries
source lib/common.sh
source lib/password.sh
source lib/network.sh
source config/defaults.conf

# Generate credentials
CREDS=$(generate_all_credentials /tmp/test-creds testuser)
while IFS= read -r line; do
    export "$line"
done <<< "$CREDS"

# Discover network
discover_network > /dev/null 2>&1

# Additional template variables
export TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Show what variables we have
echo "=== Template Variables ==="
echo "VM_USERNAME=$VM_USERNAME"
echo "VM_PASSWORD=$VM_PASSWORD"
echo "VM_PASSWORD_HASH=$VM_PASSWORD_HASH"
echo "PORTAINER_PORT=$PORTAINER_PORT"
echo "SEMAPHORE_PORT=$SEMAPHORE_PORT"
echo "STATIC_IP=$DISCOVERED_IP"
echo "GATEWAY=$DISCOVERED_GATEWAY"
echo ""

# Test with a simple template first
cat > /tmp/test-template.txt <<'EOF'
Username: ${VM_USERNAME}
Password: ${VM_PASSWORD}
Hash: ${VM_PASSWORD_HASH}
IP: ${STATIC_IP}
EOF

echo "=== Simple Template Test ==="
export STATIC_IP=$DISCOVERED_IP
envsubst < /tmp/test-template.txt

echo ""
echo "=== Testing Password Hash Generation ==="
test_hash=$(generate_password_hash "testpass123")
echo "Generated hash: $test_hash"