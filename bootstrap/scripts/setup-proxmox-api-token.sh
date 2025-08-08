#!/bin/bash
# Setup Proxmox API token for automation
# Creates user and token with proper permissions for VM management

set -euo pipefail

# Default values
PROXMOX_HOST="${PROXMOX_HOST:-192.168.1.10}"
API_USER="${API_USER:-automation@pve}"
TOKEN_NAME="${TOKEN_NAME:-ansible}"
TOKEN_FILE="/root/.proxmox-api-token"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# Check if running on Proxmox host
check_proxmox() {
    if ! command -v pveum &> /dev/null; then
        error "pveum command not found. This script must run on Proxmox host."
        exit 1
    fi
    
    if [[ ! -f /etc/pve/pve-root-ca.pem ]]; then
        error "Not a Proxmox VE host. Run this on your Proxmox server."
        exit 1
    fi
}

# Create user if not exists
create_api_user() {
    local username="${1%@*}"  # Extract username without realm
    local realm="${1#*@}"     # Extract realm
    
    log "Checking if user $1 exists..."
    
    if pveum user list | grep -q "^$1"; then
        log "User $1 already exists"
    else
        log "Creating user $1..."
        pveum user add "$1" --comment "Automation user for Ansible/API access"
        log "✓ User created"
    fi
}

# Create API token
create_api_token() {
    local user="$1"
    local token="$2"
    local full_token="${user}!${token}"
    
    log "Creating API token ${full_token}..."
    
    # Check if token already exists
    if pveum user token list "$user" 2>/dev/null | grep -q "│ $token "; then
        warn "Token ${full_token} already exists"
        read -p "Delete and recreate? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "Removing existing token..."
            pveum user token remove "$full_token"
        else
            log "Keeping existing token"
            return 1
        fi
    fi
    
    # Create token with privilege separation
    log "Generating new token..."
    local output=$(pveum user token add "$user" "$token" --privsep 1 --output-format json)
    
    # Extract token value
    local token_value=$(echo "$output" | grep -oP '"value"\s*:\s*"\K[^"]+')
    
    if [[ -z "$token_value" ]]; then
        error "Failed to extract token value"
        return 1
    fi
    
    log "✓ Token created successfully"
    echo "═══════════════════════════════════════════════════════════════════"
    echo "IMPORTANT: Save this token SECRET - it will not be shown again!"
    echo "═══════════════════════════════════════════════════════════════════"
    echo
    echo "Token ID: ${full_token}"
    echo "Token Secret: ${token_value}"
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    
    # Save to file (secure)
    cat > "$TOKEN_FILE" <<EOF
# Proxmox API Token Configuration
# Generated: $(date)
PROXMOX_HOST="${PROXMOX_HOST}"
PROXMOX_TOKEN_ID="${full_token}"
PROXMOX_TOKEN_SECRET="${token_value}"
EOF
    chmod 600 "$TOKEN_FILE"
    log "Token saved to $TOKEN_FILE (mode 600)"
    
    echo "$token_value"  # Return token for use
}

# Set permissions for token
set_token_permissions() {
    local token="$1"
    
    log "Setting permissions for token ${token}..."
    
    # VM Management permissions
    pveum acl modify /vms -token "$token" -role PVEVMAdmin
    log "✓ Added PVEVMAdmin role on /vms"
    
    # Storage permissions (for ISO upload and disk creation)
    pveum acl modify /storage -token "$token" -role PVEDatastoreUser
    log "✓ Added PVEDatastoreUser role on /storage"
    
    # Node permissions (for QEMU operations)
    pveum acl modify /nodes -token "$token" -role PVEAuditor
    log "✓ Added PVEAuditor role on /nodes"
    
    # System permissions (for network info)
    pveum acl modify /system -token "$token" -role PVEAuditor
    log "✓ Added PVEAuditor role on /system"
}

# Test token
test_token() {
    local token_id="$1"
    local token_secret="$2"
    
    log "Testing API token access..."
    
    # Test API access
    local response=$(curl -sk \
        -H "Authorization: PVEAPIToken=${token_id}=${token_secret}" \
        "https://${PROXMOX_HOST}:8006/api2/json/version")
    
    if echo "$response" | grep -q '"version"'; then
        log "✓ API token test successful"
        return 0
    else
        error "API token test failed. Response: $response"
        return 1
    fi
}

# Generate Semaphore environment JSON
generate_semaphore_config() {
    local token_id="$1"
    local token_secret="$2"
    
    cat > /tmp/proxmox-api-env.json <<EOF
{
  "name": "ProxmoxAPI",
  "project_id": 1,
  "secrets": [
    {"name": "PROXMOX_HOST", "secret": "${PROXMOX_HOST}"},
    {"name": "PROXMOX_NODE", "secret": "pve"},
    {"name": "PROXMOX_TOKEN_ID", "secret": "${token_id}"},
    {"name": "PROXMOX_TOKEN_SECRET", "secret": "${token_secret}"}
  ]
}
EOF
    
    log "Semaphore environment config saved to /tmp/proxmox-api-env.json"
}

# Main execution
main() {
    log "Starting Proxmox API token setup..."
    
    # Check environment
    check_proxmox
    
    # Create user
    create_api_user "$API_USER"
    
    # Create token
    local token_secret
    if token_secret=$(create_api_token "$API_USER" "$TOKEN_NAME"); then
        local full_token="${API_USER}!${TOKEN_NAME}"
        
        # Set permissions
        set_token_permissions "$full_token"
        
        # Test token
        if test_token "$full_token" "$token_secret"; then
            log "✓ Token setup complete!"
            
            # Generate Semaphore config
            generate_semaphore_config "$full_token" "$token_secret"
            
            echo
            echo "═══════════════════════════════════════════════════════════════════"
            echo "Next steps:"
            echo "1. Copy token configuration to your Ansible controller:"
            echo "   scp root@${PROXMOX_HOST}:${TOKEN_FILE} ."
            echo
            echo "2. Register token in Semaphore (on VM):"
            echo "   /opt/privatebox/scripts/register-proxmox-api.sh"
            echo
            echo "3. Or manually add to Semaphore environment variables"
            echo "═══════════════════════════════════════════════════════════════════"
        else
            error "Token test failed"
            exit 1
        fi
    else
        warn "Token creation skipped or failed"
        exit 1
    fi
}

# Run main
main "$@"