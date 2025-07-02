#!/bin/bash
# Constants - Shared constants and default values for PrivateBox bootstrap
# 
# This module contains all shared constants, default values, and configuration
# parameters used across the bootstrap scripts.

# Script information
readonly PRIVATEBOX_VERSION="1.0.0"
readonly SCRIPT_NAME="PrivateBox Bootstrap"

# Color codes (check if already defined to avoid duplication)
if [[ -z "${RED:-}" ]]; then
    # Terminal colors
    if [[ -t 1 ]]; then
        readonly RED='\033[0;31m'
        readonly GREEN='\033[0;32m'
        readonly YELLOW='\033[1;33m'
        readonly BLUE='\033[0;34m'
        readonly PURPLE='\033[0;35m'
        readonly CYAN='\033[0;36m'
        readonly NC='\033[0m' # No Color
    else
        # No colors for non-terminal output
        readonly RED=''
        readonly GREEN=''
        readonly YELLOW=''
        readonly BLUE=''
        readonly PURPLE=''
        readonly CYAN=''
        readonly NC=''
    fi
fi

# VM Configuration Defaults
readonly DEFAULT_VM_ID=9000
readonly DEFAULT_VM_NAME="privatebox-mgmt"
readonly DEFAULT_VM_CORES=2
readonly DEFAULT_VM_MEMORY=2048
readonly DEFAULT_VM_DISK_SIZE="10G"
readonly DEFAULT_VM_BRIDGE="vmbr0"
readonly DEFAULT_STORAGE="local-lvm"

# Ubuntu Cloud Image
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"
UBUNTU_IMAGE_URL="${UBUNTU_IMAGE_URL:-https://cloud-images.ubuntu.com/minimal/releases/${UBUNTU_CODENAME}/release/ubuntu-${UBUNTU_VERSION}-minimal-cloudimg-amd64.img}"
UBUNTU_IMAGE_NAME="${UBUNTU_IMAGE_NAME:-ubuntu-${UBUNTU_VERSION}-minimal-cloudimg-amd64.img}"

# Network Defaults
readonly DEFAULT_NETMASK="255.255.255.0"
readonly DEFAULT_DNS1="1.1.1.1"
readonly DEFAULT_DNS2="8.8.8.8"
readonly DEFAULT_SSH_PORT=22

# User Configuration
readonly DEFAULT_USERNAME="privatebox"
readonly DEFAULT_USER_FULLNAME="PrivateBox Admin"

# Paths
readonly PRIVATEBOX_CONFIG_DIR="/etc/privatebox"
readonly PRIVATEBOX_LOG_DIR="/var/log/privatebox"
readonly PRIVATEBOX_SCRIPTS_DIR="/opt/privatebox/scripts"
readonly PRIVATEBOX_DATA_DIR="/var/lib/privatebox"

# Docker Configuration
DOCKER_COMPOSE_VERSION="${DOCKER_COMPOSE_VERSION:-v2.29.7}"
PORTAINER_VERSION="${PORTAINER_VERSION:-latest}"
PORTAINER_PORT="${PORTAINER_PORT:-9443}"

# Semaphore Configuration
SEMAPHORE_VERSION="${SEMAPHORE_VERSION:-latest}"
SEMAPHORE_PORT="${SEMAPHORE_PORT:-3000}"
SEMAPHORE_DB_NAME="${SEMAPHORE_DB_NAME:-semaphore}"
SEMAPHORE_DB_USER="${SEMAPHORE_DB_USER:-semaphore}"

# Service Timeouts (in seconds)
readonly SERVICE_START_TIMEOUT=300
readonly SERVICE_CHECK_INTERVAL=5
readonly CLOUD_INIT_TIMEOUT=600
readonly SSH_CONNECT_TIMEOUT=10
readonly SSH_CONNECT_RETRIES=60

# Password Generation
readonly PASSWORD_LENGTH=32
readonly PASSWORD_CHARS='A-Za-z0-9!@#%&*+=?'

# File Permissions
readonly CONFIG_FILE_MODE=600
readonly SCRIPT_FILE_MODE=755
readonly LOG_FILE_MODE=644

# Validation Patterns
readonly IP_REGEX='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
readonly HOSTNAME_REGEX='^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$'
readonly PORT_MIN=1
readonly PORT_MAX=65535

# Exit Codes
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR=1
readonly EXIT_INVALID_ARGS=2
readonly EXIT_MISSING_DEPS=3
readonly EXIT_NOT_ROOT=4
readonly EXIT_NOT_PROXMOX=5
readonly EXIT_NETWORK_ERROR=6
readonly EXIT_VM_ERROR=7
readonly EXIT_SERVICE_ERROR=8
readonly EXIT_CONFIG_ERROR=9

# Function to check if constants are loaded
constants_loaded() {
    return 0
}