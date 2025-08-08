#!/bin/sh
#
# OPNsense Bootstrap Script
# Converts FreeBSD 14.3 to OPNsense 25.7
#
# Requirements:
# - FreeBSD 14.3 base system
# - Internet connectivity 
# - Root privileges

set -e

# Configuration
OPNSENSE_BOOTSTRAP_URL="https://raw.githubusercontent.com/opnsense/tools/master/bootstrap/opnsense-bootstrap.sh"
OPNSENSE_VERSION="25.7"
API_KEY_FILE="/root/api-credentials"
LOG_FILE="/var/log/opnsense-bootstrap.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log "ERROR: Bootstrap failed with exit code $exit_code"
        log "Check $LOG_FILE for details"
    fi
    exit $exit_code
}
trap cleanup EXIT

# Main bootstrap process
main() {
    log "Starting OPNsense bootstrap conversion"
    log "FreeBSD version: $(freebsd-version)"
    log "Target OPNsense: $OPNSENSE_VERSION"
    
    # Install required packages
    log "Installing required packages..."
    pkg update -f
    pkg install -y python39 sudo curl
    
    # Create python3 symlink if missing
    if [ ! -f /usr/local/bin/python3 ]; then
        ln -sf /usr/local/bin/python3.9 /usr/local/bin/python3
    fi
    
    # Download OPNsense bootstrap script
    log "Downloading OPNsense bootstrap script..."
    fetch -o /tmp/opnsense-bootstrap.sh "$OPNSENSE_BOOTSTRAP_URL"
    chmod +x /tmp/opnsense-bootstrap.sh
    
    # Verify download
    if [ ! -f /tmp/opnsense-bootstrap.sh ]; then
        log "ERROR: Failed to download bootstrap script"
        exit 1
    fi
    
    # Run OPNsense bootstrap (this takes ~20 minutes)
    log "Starting OPNsense bootstrap conversion (this takes ~20 minutes)..."
    log "Bootstrap process includes package downloads and system conversion"
    
    # Execute bootstrap with logging
    /bin/sh /tmp/opnsense-bootstrap.sh -y 2>&1 | tee -a "$LOG_FILE"
    
    # Check if bootstrap succeeded
    if [ $? -ne 0 ]; then
        log "ERROR: OPNsense bootstrap failed"
        exit 1
    fi
    
    log "OPNsense bootstrap completed successfully"
    
    # Generate API credentials for post-reboot configuration
    log "Generating API credentials..."
    generate_api_credentials
    
    log "Bootstrap complete. System will reboot into OPNsense..."
    log "After reboot, API will be available at: https://[VM_IP]/api/"
    log "API credentials saved to: $API_KEY_FILE"
    
    # Reboot into OPNsense
    log "Initiating reboot..."
    shutdown -r now
}

# Generate API key/secret for OPNsense
generate_api_credentials() {
    local api_key=$(openssl rand -hex 20)
    local api_secret=$(openssl rand -hex 40)
    
    # Save credentials to file
    cat > "$API_KEY_FILE" << EOF
# OPNsense API Credentials
# Generated: $(date)
API_KEY=$api_key
API_SECRET=$api_secret

# Usage:
# curl -u "\$API_KEY:\$API_SECRET" https://VM_IP/api/core/firmware/status
EOF
    
    chmod 600 "$API_KEY_FILE"
    log "API credentials generated: $API_KEY_FILE"
    
    # Also create JSON format for Ansible
    cat > "${API_KEY_FILE}.json" << EOF
{
  "api_key": "$api_key",
  "api_secret": "$api_secret",
  "generated": "$(date -I)",
  "endpoint": "https://VM_IP/api/"
}
EOF
    
    chmod 600 "${API_KEY_FILE}.json"
}

# Verify we're running as root
if [ "$(id -u)" != "0" ]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Verify we're on FreeBSD
if [ "$(uname)" != "FreeBSD" ]; then
    echo "ERROR: This script must be run on FreeBSD"
    exit 1
fi

# Start main process
main