#!/bin/bash
# Bootstrap Logger - Minimal logging functions for early bootstrap phase
# 
# This module provides lightweight logging functions that can be used
# before common.sh is available. It's designed to be sourced by scripts
# that need logging during early initialization.

# Note: This file expects constants.sh to be sourced before it
# Color definitions should come from constants.sh via common.sh

# Core logging function
bootstrap_log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        ERROR)
            echo -e "${RED}[$timestamp] [ERROR]${NC} $message" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[$timestamp] [WARN]${NC} $message" >&2
            ;;
        INFO)
            echo -e "${GREEN}[$timestamp] [INFO]${NC} $message"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[$timestamp] [DEBUG]${NC} $message"
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

# Success log function (same as info but sometimes used separately)
log_success() {
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
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message" >&2
            ;;
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        DEBUG)
            if [[ "${DEBUG:-false}" == "true" ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
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