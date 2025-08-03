#!/bin/sh
# Generic VM Self-Registration Script for Semaphore
# Works across multiple Linux distributions
# Usage: vm-self-register.sh <semaphore-api-token> [vm-name] [vm-username] [vm-ip]

set -e

# Configuration
MARKER_FILE="$HOME/.semaphore-registered"
LOG_FILE="/tmp/vm-self-register.log"
SEMAPHORE_URL="${SEMAPHORE_URL:-http://192.168.1.20:3000}"

# Arguments
API_TOKEN="$1"
VM_NAME="${2:-$(hostname)}"
VM_USERNAME="${3:-$(whoami)}"
VM_IP="${4:-}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Error handler
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if already registered
if [ -f "$MARKER_FILE" ]; then
    log "VM already registered (marker file exists)"
    exit 0
fi

# Validate inputs
if [ -z "$API_TOKEN" ]; then
    error_exit "Usage: $0 <semaphore-api-token> [vm-name] [vm-username] [vm-ip]"
fi

log "Starting VM self-registration"
log "VM Name: $VM_NAME"
log "Username: $VM_USERNAME"
log "Semaphore URL: $SEMAPHORE_URL"

# Detect distribution and package manager
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="$ID"
        log "Detected distribution: $DISTRO"
    else
        DISTRO="unknown"
        log "WARNING: Could not detect distribution"
    fi

    # Detect package manager
    if command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
        PKG_INSTALL="apk add --no-cache"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MGR="apt"
        PKG_INSTALL="apt-get update && apt-get install -y"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MGR="yum"
        PKG_INSTALL="yum install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MGR="dnf"
        PKG_INSTALL="dnf install -y"
    else
        error_exit "No supported package manager found"
    fi
    
    log "Package manager: $PKG_MGR"
}

# Install missing dependencies
install_deps() {
    NEED_INSTALL=""
    
    if ! command -v curl >/dev/null 2>&1; then
        log "curl not found, will install"
        NEED_INSTALL="$NEED_INSTALL curl"
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log "jq not found, will install"
        NEED_INSTALL="$NEED_INSTALL jq"
    fi
    
    if [ -n "$NEED_INSTALL" ]; then
        log "Installing dependencies: $NEED_INSTALL"
        if [ "$PKG_MGR" = "apt" ]; then
            sudo apt-get update >/dev/null 2>&1 || true
            sudo apt-get install -y $NEED_INSTALL || error_exit "Failed to install dependencies"
        else
            eval "sudo $PKG_INSTALL $NEED_INSTALL" || error_exit "Failed to install dependencies"
        fi
    else
        log "All dependencies already installed"
    fi
}

# Find SSH key
find_ssh_key() {
    # Check common locations for SSH keys
    SSH_KEY_PATH=""
    SSH_PUB_KEY_PATH=""
    
    # User's home directory
    USER_HOME=$(getent passwd "$VM_USERNAME" | cut -d: -f6)
    
    # Try common key locations
    for key_type in id_ed25519 id_rsa id_ecdsa; do
        if [ -f "$USER_HOME/.ssh/$key_type" ] && [ -f "$USER_HOME/.ssh/$key_type.pub" ]; then
            SSH_KEY_PATH="$USER_HOME/.ssh/$key_type"
            SSH_PUB_KEY_PATH="$USER_HOME/.ssh/$key_type.pub"
            log "Found SSH key: $SSH_KEY_PATH"
            break
        fi
    done
    
    # Also check root's keys if running as root
    if [ "$VM_USERNAME" != "root" ] && [ "$(id -u)" = "0" ]; then
        for key_type in id_ed25519 id_rsa id_ecdsa; do
            if [ -f "/root/.ssh/$key_type" ] && [ -f "/root/.ssh/$key_type.pub" ]; then
                SSH_KEY_PATH="/root/.ssh/$key_type"
                SSH_PUB_KEY_PATH="/root/.ssh/$key_type.pub"
                log "Found SSH key (root): $SSH_KEY_PATH"
                break
            fi
        done
    fi
    
    if [ -z "$SSH_KEY_PATH" ]; then
        error_exit "No SSH key found for user $VM_USERNAME"
    fi
}

# Get VM IP address
get_vm_ip() {
    # Use provided IP if available
    if [ -n "$VM_IP" ]; then
        log "Using provided VM IP address: $VM_IP"
        return
    fi
    
    # Try to detect primary network interface IP
    log "No IP provided, attempting to detect..."
    
    # Method 1: ip command (most modern)
    if command -v ip >/dev/null 2>&1; then
        VM_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -1)
    fi
    
    # Method 2: ifconfig (fallback)
    if [ -z "$VM_IP" ] && command -v ifconfig >/dev/null 2>&1; then
        VM_IP=$(ifconfig | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -1)
    fi
    
    # Method 3: hostname (last resort)
    if [ -z "$VM_IP" ] && command -v hostname >/dev/null 2>&1; then
        VM_IP=$(hostname -I | awk '{print $1}')
    fi
    
    if [ -z "$VM_IP" ]; then
        VM_IP="DHCP"
        log "WARNING: Could not determine VM IP address, using DHCP"
    else
        log "VM IP address detected: $VM_IP"
    fi
}

# Register with Semaphore
register_with_semaphore() {
    log "Reading SSH keys"
    PRIVATE_KEY=$(cat "$SSH_KEY_PATH")
    PUBLIC_KEY=$(cat "$SSH_PUB_KEY_PATH")
    
    # Create SSH key in Semaphore
    log "Creating SSH key in Semaphore"
    
    KEY_PAYLOAD=$(jq -n \
        --arg name "${VM_NAME}-key" \
        --arg login "$VM_USERNAME" \
        --arg key "$PRIVATE_KEY" \
        '{
            "name": $name,
            "type": "ssh",
            "project_id": 1,
            "ssh": {
                "login": $login,
                "private_key": $key
            }
        }')
    
    KEY_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$KEY_PAYLOAD" \
        "${SEMAPHORE_URL}/api/project/1/keys") || error_exit "Failed to create SSH key"
    
    # Check for error in response
    if echo "$KEY_RESPONSE" | grep -q '"error"'; then
        error_exit "API error creating SSH key: $KEY_RESPONSE"
    fi
    
    KEY_ID=$(echo "$KEY_RESPONSE" | jq -r '.id')
    
    if [ -z "$KEY_ID" ] || [ "$KEY_ID" = "null" ]; then
        error_exit "Failed to get key ID from response: $KEY_RESPONSE"
    fi
    
    log "Created SSH key with ID: $KEY_ID"
    
    # Create inventory
    log "Creating inventory in Semaphore"
    
    INVENTORY_YAML=$(cat <<EOF
${VM_NAME}:
  hosts:
    ${VM_NAME}:
      ansible_host: ${VM_IP}
      ansible_user: ${VM_USERNAME}
      ansible_ssh_private_key_file: /tmp/semaphore/.ssh/id_ed25519
EOF
)
    
    INVENTORY_PAYLOAD=$(jq -n \
        --arg name "${VM_NAME}-inventory" \
        --arg inventory "$INVENTORY_YAML" \
        --argjson key_id "$KEY_ID" \
        '{
            "name": $name,
            "project_id": 1,
            "inventory": $inventory,
            "ssh_key_id": $key_id,
            "type": "static"
        }')
    
    INVENTORY_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$INVENTORY_PAYLOAD" \
        "${SEMAPHORE_URL}/api/project/1/inventory") || error_exit "Failed to create inventory"
    
    # Check for error in response
    if echo "$INVENTORY_RESPONSE" | grep -q '"error"'; then
        error_exit "API error creating inventory: $INVENTORY_RESPONSE"
    fi
    
    INVENTORY_ID=$(echo "$INVENTORY_RESPONSE" | jq -r '.id')
    
    if [ -z "$INVENTORY_ID" ] || [ "$INVENTORY_ID" = "null" ]; then
        error_exit "Failed to get inventory ID from response: $INVENTORY_RESPONSE"
    fi
    
    log "Created inventory with ID: $INVENTORY_ID"
}

# Main execution
main() {
    log "=== VM Self-Registration Starting ==="
    
    # Detect distribution
    detect_distro
    
    # Install dependencies
    install_deps
    
    # Find SSH key
    find_ssh_key
    
    # Get VM IP
    get_vm_ip
    
    # Register with Semaphore
    register_with_semaphore
    
    # Create marker file
    log "Creating marker file"
    cat > "$MARKER_FILE" <<EOF
# VM registered with Semaphore
Date: $(date)
VM Name: $VM_NAME
Username: $VM_USERNAME
VM IP: $VM_IP
Key ID: $KEY_ID
Inventory ID: $INVENTORY_ID
EOF
    
    # Clean up
    log "Cleaning up"
    # Remove this script if it exists in /tmp
    if echo "$0" | grep -q "^/tmp/"; then
        rm -f "$0"
        log "Removed temporary script"
    fi
    
    log "=== VM Self-Registration Complete ==="
}

# Run main function
main "$@"