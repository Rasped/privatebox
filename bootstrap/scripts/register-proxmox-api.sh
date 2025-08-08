#!/bin/bash
# Register Proxmox API token in Semaphore
# Run this on the PrivateBox VM to add Proxmox API credentials

set -euo pipefail

# Configuration
SEMAPHORE_URL="${SEMAPHORE_URL:-http://localhost:3000}"
SEMAPHORE_USER="${SEMAPHORE_USER:-admin}"
PROJECT_ID="${PROJECT_ID:-1}"
TOKEN_FILE="${TOKEN_FILE:-/root/.proxmox-api-token}"
COOKIE_FILE="/tmp/semaphore-cookie"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# Clean up on exit
cleanup() {
    rm -f "$COOKIE_FILE"
}
trap cleanup EXIT

# Get Semaphore password
get_semaphore_password() {
    # Try multiple sources
    if [[ -n "${SERVICES_PASSWORD:-}" ]]; then
        echo "$SERVICES_PASSWORD"
    elif [[ -f /root/.credentials/config.env ]]; then
        source /root/.credentials/config.env
        echo "${SERVICES_PASSWORD:-}"
    elif [[ -f /etc/privatebox/config.env ]]; then
        source /etc/privatebox/config.env
        echo "${SERVICES_PASSWORD:-}"
    else
        error "Cannot find SERVICES_PASSWORD"
        exit 1
    fi
}

# Login to Semaphore
semaphore_login() {
    local password="$1"
    
    log "Logging into Semaphore..."
    
    local response=$(curl -s -c "$COOKIE_FILE" -w "\n%{http_code}" -X POST \
        -H 'Content-Type: application/json' \
        -d "{\"auth\": \"${SEMAPHORE_USER}\", \"password\": \"${password}\"}" \
        "${SEMAPHORE_URL}/api/auth/login")
    
    local http_code=$(echo "$response" | tail -n 1)
    local body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "204" ]]; then
        log "✓ Login successful"
        return 0
    else
        error "Login failed (HTTP $http_code): $body"
        return 1
    fi
}

# Check if ProxmoxAPI environment exists
check_environment_exists() {
    log "Checking for existing ProxmoxAPI environment..."
    
    local response=$(curl -s -b "$COOKIE_FILE" -w "\n%{http_code}" \
        "${SEMAPHORE_URL}/api/project/${PROJECT_ID}/environment")
    
    local http_code=$(echo "$response" | tail -n 1)
    local body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "200" ]]; then
        # Check if ProxmoxAPI already exists
        if echo "$body" | grep -q '"name":"ProxmoxAPI"'; then
            local env_id=$(echo "$body" | grep -o '"id":[0-9]*,"name":"ProxmoxAPI"' | grep -o '"id":[0-9]*' | cut -d: -f2)
            log "ProxmoxAPI environment already exists (ID: $env_id)"
            return 0
        fi
    fi
    
    return 1
}

# Load token from file or input
load_token_config() {
    if [[ -f "$TOKEN_FILE" ]]; then
        log "Loading token from $TOKEN_FILE..."
        source "$TOKEN_FILE"
        
        if [[ -z "${PROXMOX_TOKEN_ID:-}" ]] || [[ -z "${PROXMOX_TOKEN_SECRET:-}" ]]; then
            error "Token file missing required variables"
            return 1
        fi
    else
        log "Token file not found. Enter manually:"
        read -p "Proxmox Host (default: 192.168.1.10): " input_host
        PROXMOX_HOST="${input_host:-192.168.1.10}"
        
        read -p "Token ID (e.g., automation@pve!ansible): " PROXMOX_TOKEN_ID
        if [[ -z "$PROXMOX_TOKEN_ID" ]]; then
            error "Token ID is required"
            return 1
        fi
        
        read -sp "Token Secret: " PROXMOX_TOKEN_SECRET
        echo
        if [[ -z "$PROXMOX_TOKEN_SECRET" ]]; then
            error "Token Secret is required"
            return 1
        fi
    fi
    
    # Set default node
    PROXMOX_NODE="${PROXMOX_NODE:-pve}"
    
    return 0
}

# Create ProxmoxAPI environment
create_environment() {
    log "Creating ProxmoxAPI environment..."
    
    local env_json=$(cat <<EOF
{
  "name": "ProxmoxAPI",
  "project_id": ${PROJECT_ID},
  "secrets": [
    {"name": "PROXMOX_HOST", "secret": "${PROXMOX_HOST}"},
    {"name": "PROXMOX_NODE", "secret": "${PROXMOX_NODE}"},
    {"name": "PROXMOX_TOKEN_ID", "secret": "${PROXMOX_TOKEN_ID}"},
    {"name": "PROXMOX_TOKEN_SECRET", "secret": "${PROXMOX_TOKEN_SECRET}"}
  ]
}
EOF
)
    
    local response=$(curl -s -b "$COOKIE_FILE" -w "\n%{http_code}" -X POST \
        -H 'Content-Type: application/json' \
        -d "$env_json" \
        "${SEMAPHORE_URL}/api/project/${PROJECT_ID}/environment")
    
    local http_code=$(echo "$response" | tail -n 1)
    local body=$(echo "$response" | head -n -1)
    
    if [[ "$http_code" == "201" ]] || [[ "$http_code" == "204" ]]; then
        log "✓ ProxmoxAPI environment created successfully"
        
        # Extract environment ID if available
        if [[ -n "$body" ]]; then
            local env_id=$(echo "$body" | grep -o '"id":[0-9]*' | cut -d: -f2)
            if [[ -n "$env_id" ]]; then
                log "Environment ID: $env_id"
            fi
        fi
        
        return 0
    else
        error "Failed to create environment (HTTP $http_code): $body"
        return 1
    fi
}

# Update existing environment
update_environment() {
    local env_id="$1"
    
    log "Updating ProxmoxAPI environment (ID: $env_id)..."
    
    local env_json=$(cat <<EOF
{
  "name": "ProxmoxAPI",
  "project_id": ${PROJECT_ID},
  "secrets": [
    {"name": "PROXMOX_HOST", "secret": "${PROXMOX_HOST}"},
    {"name": "PROXMOX_NODE", "secret": "${PROXMOX_NODE}"},
    {"name": "PROXMOX_TOKEN_ID", "secret": "${PROXMOX_TOKEN_ID}"},
    {"name": "PROXMOX_TOKEN_SECRET", "secret": "${PROXMOX_TOKEN_SECRET}"}
  ]
}
EOF
)
    
    local response=$(curl -s -b "$COOKIE_FILE" -w "\n%{http_code}" -X PUT \
        -H 'Content-Type: application/json' \
        -d "$env_json" \
        "${SEMAPHORE_URL}/api/project/${PROJECT_ID}/environment/${env_id}")
    
    local http_code=$(echo "$response" | tail -n 1)
    
    if [[ "$http_code" == "204" ]] || [[ "$http_code" == "200" ]]; then
        log "✓ Environment updated successfully"
        return 0
    else
        error "Failed to update environment (HTTP $http_code)"
        return 1
    fi
}

# Test the API token
test_api_token() {
    log "Testing Proxmox API token..."
    
    local response=$(curl -sk \
        -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}" \
        "https://${PROXMOX_HOST}:8006/api2/json/version")
    
    if echo "$response" | grep -q '"version"'; then
        log "✓ API token test successful"
        local pve_version=$(echo "$response" | grep -o '"version":"[^"]*"' | cut -d'"' -f4)
        log "Proxmox VE version: $pve_version"
        return 0
    else
        error "API token test failed"
        warn "Response: $response"
        return 1
    fi
}

# Main execution
main() {
    log "Starting Proxmox API registration in Semaphore..."
    
    # Load token configuration
    if ! load_token_config; then
        error "Failed to load token configuration"
        exit 1
    fi
    
    # Test token first
    if ! test_api_token; then
        error "Token validation failed. Check your credentials."
        exit 1
    fi
    
    # Get Semaphore password
    local password
    if ! password=$(get_semaphore_password); then
        error "Failed to get Semaphore password"
        exit 1
    fi
    
    # Login to Semaphore
    if ! semaphore_login "$password"; then
        error "Failed to login to Semaphore"
        exit 1
    fi
    
    # Check if environment exists
    if check_environment_exists; then
        warn "ProxmoxAPI environment already exists"
        read -p "Update existing environment? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # Get environment ID
            local env_id=$(curl -s -b "$COOKIE_FILE" \
                "${SEMAPHORE_URL}/api/project/${PROJECT_ID}/environment" | \
                grep -o '"id":[0-9]*,"name":"ProxmoxAPI"' | \
                grep -o '"id":[0-9]*' | cut -d: -f2)
            
            if update_environment "$env_id"; then
                log "✓ Environment updated"
            else
                error "Failed to update environment"
                exit 1
            fi
        else
            log "Keeping existing environment"
        fi
    else
        # Create new environment
        if create_environment; then
            log "✓ ProxmoxAPI environment registered"
        else
            error "Failed to create environment"
            exit 1
        fi
    fi
    
    echo
    echo "═══════════════════════════════════════════════════════════════════"
    echo "SUCCESS! Proxmox API credentials registered in Semaphore"
    echo
    echo "The ProxmoxAPI environment is now available for use in job templates."
    echo "Update your playbooks to include: environment_id: <ID>"
    echo "═══════════════════════════════════════════════════════════════════"
}

# Run main
main "$@"