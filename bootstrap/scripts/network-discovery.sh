#!/bin/bash
# =============================================================================
# Script Name: network-discovery.sh
# Description: Network discovery and configuration wrapper for config-manager.sh
# Author: PrivateBox Team
# Date: 2024
# Version: 2.0.0
# =============================================================================
# This script is now a wrapper for config-manager.sh to maintain backward
# compatibility. All network detection and configuration logic has been moved
# to config-manager.sh.
# =============================================================================

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common library for logging
source "${SCRIPT_DIR}/../lib/common.sh" || {
    echo "ERROR: Cannot source common library" >&2
    exit 1
}

# Path to config-manager
CONFIG_MANAGER="${SCRIPT_DIR}/../lib/config-manager.sh"

# Check if config-manager exists
if [[ ! -f "$CONFIG_MANAGER" ]]; then
    log_error "config-manager.sh not found at: $CONFIG_MANAGER"
    exit 1
fi

# Parse command line arguments
ACTION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            cat << 'EOF'
Usage: network-discovery.sh [OPTIONS]

This is a compatibility wrapper for config-manager.sh.
Network discovery and configuration is now handled by config-manager.sh.

OPTIONS:
    --auto       Auto-discover and generate configuration
    --help       Show this help message

For more options, use config-manager.sh directly:
    ../lib/config-manager.sh --help

EOF
            exit 0
            ;;
        --auto)
            ACTION="check"
            shift
            ;;
        *)
            log_error "Unknown argument: $1"
            log_error "Use --help for usage information"
            exit 1
            ;;
    esac
done

# If no action specified, show help
if [[ -z "$ACTION" ]]; then
    log_error "No action specified. Use --auto or --help"
    exit 1
fi

# Run config-manager with the appropriate action
log_info "Running network discovery and configuration..."
bash "$CONFIG_MANAGER" "$ACTION"

# Exit with the same code as config-manager
exit $?