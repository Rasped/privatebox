#!/bin/bash
# Bootstrap Logger - Minimal logging functions for early bootstrap phase
# 
# This module provides lightweight logging functions that can be used
# before common.sh is available. It's designed to be sourced by scripts
# that need logging during early initialization.

# Determine if we're in a terminal
if [[ -t 1 ]]; then
    # Terminal supports colors
    BOOTSTRAP_RED='\033[0;31m'
    BOOTSTRAP_GREEN='\033[0;32m'
    BOOTSTRAP_YELLOW='\033[1;33m'
    BOOTSTRAP_BLUE='\033[0;34m'
    BOOTSTRAP_NC='\033[0m' # No Color
else
    # No terminal or redirected output - no colors
    BOOTSTRAP_RED=''
    BOOTSTRAP_GREEN=''
    BOOTSTRAP_YELLOW=''
    BOOTSTRAP_BLUE=''
    BOOTSTRAP_NC=''
fi

# Core logging function
bootstrap_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        ERROR)
            echo -e "${BOOTSTRAP_RED}[$timestamp] [ERROR]${BOOTSTRAP_NC} $message" >&2
            ;;
        WARN)
            echo -e "${BOOTSTRAP_YELLOW}[$timestamp] [WARN]${BOOTSTRAP_NC} $message" >&2
            ;;
        INFO)
            echo -e "${BOOTSTRAP_GREEN}[$timestamp] [INFO]${BOOTSTRAP_NC} $message"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BOOTSTRAP_BLUE}[$timestamp] [DEBUG]${BOOTSTRAP_NC} $message"
            fi
            ;;
        *)
            echo "[$timestamp] $message"
            ;;
    esac
}

# Convenience functions
log_error() {
    bootstrap_log "ERROR" "$1"
}

log_warn() {
    bootstrap_log "WARN" "$1"
}

log_info() {
    bootstrap_log "INFO" "$1"
}

log_debug() {
    bootstrap_log "DEBUG" "$1"
}

log() {
    # Default log function for backward compatibility
    bootstrap_log "INFO" "$1"
}

# Error exit function
error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

# Simple log message without timestamp (for compatibility)
log_msg() {
    local level="$1"
    local message="$2"
    
    case "$level" in
        ERROR)
            echo -e "${BOOTSTRAP_RED}[ERROR]${BOOTSTRAP_NC} $message" >&2
            ;;
        WARN)
            echo -e "${BOOTSTRAP_YELLOW}[WARN]${BOOTSTRAP_NC} $message" >&2
            ;;
        INFO)
            echo -e "${BOOTSTRAP_GREEN}[INFO]${BOOTSTRAP_NC} $message"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BOOTSTRAP_BLUE}[DEBUG]${BOOTSTRAP_NC} $message"
            fi
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Check if logging functions are already defined to prevent conflicts
bootstrap_logger_loaded() {
    return 0
}