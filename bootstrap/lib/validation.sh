#!/bin/bash
# =============================================================================
# Validation Library for PXE Scripts
# Provides comprehensive input validation functions
# =============================================================================

# This library is meant to be sourced by common.sh or other scripts
# It should not set -euo pipefail as it may be sourced in different contexts

# Ensure we have logging functions available
if ! declare -f log_info >/dev/null 2>&1; then
    # Basic fallback logging if not available
    log_info() { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*"; }
fi

# =============================================================================
# GENERIC INPUT VALIDATION
# =============================================================================

# /**
#  * Validate user input based on specified type
#  *
#  * @param $1 - Input value to validate
#  * @param $2 - Type of validation (ip, vmid, port, path, file, directory, hostname, cidr, mac)
#  * @return 0 if valid, 1 if invalid
#  * @example
#  *   validate_input "192.168.1.1" "ip"
#  *   validate_input "9001" "vmid"
#  *   validate_input "/etc/config" "path"
#  */
validate_input() {
    local input="$1"
    local type="$2"
    
    case "$type" in
        "ip")
            validate_ip "$input" || return 1
            ;;
        "vmid")
            validate_vmid "$input" || return 1
            ;;
        "port")
            validate_port "$input" || return 1
            ;;
        "path")
            validate_path "$input" || return 1
            ;;
        "file")
            validate_file "$input" || return 1
            ;;
        "directory")
            validate_directory "$input" || return 1
            ;;
        "hostname")
            validate_hostname "$input" || return 1
            ;;
        "cidr")
            validate_cidr "$input" || return 1
            ;;
        "mac")
            validate_mac_address "$input" || return 1
            ;;
        "url")
            validate_url "$input" || return 1
            ;;
        "email")
            validate_email "$input" || return 1
            ;;
        "alphanumeric")
            validate_alphanumeric "$input" || return 1
            ;;
        "integer")
            validate_integer "$input" || return 1
            ;;
        "boolean")
            validate_boolean "$input" || return 1
            ;;
        *)
            log_error "Unknown validation type: $type"
            return 1
            ;;
    esac
    return 0
}

# =============================================================================
# NETWORK VALIDATION FUNCTIONS
# =============================================================================

# /**
#  * Validate IP address format and range
#  *
#  * @param $1 - IP address to validate
#  * @return 0 if valid, 1 if invalid
#  * @example
#  *   validate_ip "192.168.1.1"  # returns 0
#  *   validate_ip "256.1.1.1"    # returns 1
#  *   validate_ip "192.168.1"    # returns 1
#  */
validate_ip() {
    local ip="${1:-}"
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    # Check if empty
    if [[ -z "$ip" ]]; then
        log_debug "IP validation failed: empty input"
        return 1
    fi
    
    # Check format
    if [[ ! "$ip" =~ $valid_ip_regex ]]; then
        log_debug "IP validation failed: invalid format - $ip"
        return 1
    fi
    
    # Check each octet
    local IFS='.'
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        # Remove leading zeros to prevent octal interpretation
        octet=$((10#$octet))
        if [[ $octet -gt 255 ]]; then
            log_debug "IP validation failed: octet out of range - $octet"
            return 1
        fi
    done
    
    # Check for reserved addresses if needed
    if [[ "$ip" == "0.0.0.0" ]] || [[ "$ip" == "255.255.255.255" ]]; then
        log_debug "IP validation failed: reserved address - $ip"
        return 1
    fi
    
    return 0
}

# /**
#  * Validate CIDR notation (IP/mask)
#  *
#  * @param $1 - CIDR notation to validate
#  * @return 0 if valid, 1 if invalid
#  * @example
#  *   validate_cidr "192.168.1.0/24"  # returns 0
#  *   validate_cidr "192.168.1.0/33"  # returns 1
#  *   validate_cidr "192.168.1.0"     # returns 1
#  */
validate_cidr() {
    local cidr="${1:-}"
    local cidr_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'
    
    if [[ -z "$cidr" ]]; then
        log_debug "CIDR validation failed: empty input"
        return 1
    fi
    
    if [[ ! "$cidr" =~ $cidr_regex ]]; then
        log_debug "CIDR validation failed: invalid format - $cidr"
        return 1
    fi
    
    # Split IP and mask
    local ip="${cidr%/*}"
    local mask="${cidr#*/}"
    
    # Validate IP part
    if ! validate_ip "$ip"; then
        return 1
    fi
    
    # Validate mask (0-32 for IPv4)
    if [[ $mask -lt 0 ]] || [[ $mask -gt 32 ]]; then
        log_debug "CIDR validation failed: invalid mask - $mask"
        return 1
    fi
    
    return 0
}

# /**
#  * Validate MAC address format
#  *
#  * @param $1 - MAC address to validate
#  * @return 0 if valid, 1 if invalid
#  * @example
#  *   validate_mac_address "00:11:22:33:44:55"  # returns 0
#  *   validate_mac_address "00-11-22-33-44-55"  # returns 0
#  *   validate_mac_address "00:11:22:33:44"     # returns 1
#  */
validate_mac_address() {
    local mac="${1:-}"
    local mac_regex='^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$'
    
    if [[ -z "$mac" ]]; then
        log_debug "MAC validation failed: empty input"
        return 1
    fi
    
    if [[ ! "$mac" =~ $mac_regex ]]; then
        log_debug "MAC validation failed: invalid format - $mac"
        return 1
    fi
    
    return 0
}

# /**
#  * Validate hostname according to RFC 1123
#  *
#  * @param $1 - Hostname to validate
#  * @return 0 if valid, 1 if invalid
#  * @example
#  *   validate_hostname "server01"       # returns 0
#  *   validate_hostname "my-server.com"  # returns 0
#  *   validate_hostname "-invalid"       # returns 1
#  */
validate_hostname() {
    local hostname="${1:-}"
    local hostname_regex='^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?$'
    
    if [[ -z "$hostname" ]]; then
        log_debug "Hostname validation failed: empty input"
        return 1
    fi
    
    # Check length
    if [[ ${#hostname} -gt 253 ]]; then
        log_debug "Hostname validation failed: too long - ${#hostname} characters"
        return 1
    fi
    
    # Check each label
    local IFS='.'
    read -ra labels <<< "$hostname"
    for label in "${labels[@]}"; do
        if [[ ! "$label" =~ $hostname_regex ]]; then
            log_debug "Hostname validation failed: invalid label - $label"
            return 1
        fi
    done
    
    return 0
}

# =============================================================================
# PROXMOX SPECIFIC VALIDATION
# =============================================================================

# Validate VM ID
validate_vmid() {
    local vmid="${1:-}"
    
    if [[ -z "$vmid" ]]; then
        log_debug "VMID validation failed: empty input"
        return 1
    fi
    
    # Check if numeric
    if [[ ! "$vmid" =~ ^[0-9]+$ ]]; then
        log_debug "VMID validation failed: not numeric - $vmid"
        return 1
    fi
    
    # Check range (Proxmox typically uses 100-999999)
    if [[ $vmid -lt 100 ]] || [[ $vmid -gt 999999 ]]; then
        log_debug "VMID validation failed: out of range - $vmid"
        return 1
    fi
    
    return 0
}

# =============================================================================
# FILE SYSTEM VALIDATION
# =============================================================================

# Validate path (general path validation)
validate_path() {
    local path="${1:-}"
    
    if [[ -z "$path" ]]; then
        log_debug "Path validation failed: empty input"
        return 1
    fi
    
    # Check for dangerous patterns
    if [[ "$path" =~ \.\. ]]; then
        log_debug "Path validation failed: contains .. - $path"
        return 1
    fi
    
    # Check for invalid characters
    if [[ "$path" =~ [[:cntrl:]] ]]; then
        log_debug "Path validation failed: contains control characters"
        return 1
    fi
    
    # Check if path is absolute or relative
    if [[ "$path" =~ ^/ ]]; then
        # Absolute path - check if parent directory exists
        local parent_dir
        parent_dir="$(dirname "$path")"
        if [[ ! -d "$parent_dir" ]] && [[ "$parent_dir" != "/" ]]; then
            log_debug "Path validation failed: parent directory doesn't exist - $parent_dir"
            return 1
        fi
    fi
    
    return 0
}

# Validate file path
validate_file() {
    local file="${1:-}"
    
    if [[ -z "$file" ]]; then
        log_debug "File validation failed: empty input"
        return 1
    fi
    
    # First validate as general path
    if ! validate_path "$file"; then
        return 1
    fi
    
    # Check if file exists (optional based on context)
    if [[ ! -f "$file" ]]; then
        log_debug "File validation warning: file doesn't exist - $file"
        # Don't fail here as file might be created
    fi
    
    return 0
}

# Validate directory path
validate_directory() {
    local dir="${1:-}"
    
    if [[ -z "$dir" ]]; then
        log_debug "Directory validation failed: empty input"
        return 1
    fi
    
    # First validate as general path
    if ! validate_path "$dir"; then
        return 1
    fi
    
    # Check if directory exists (optional based on context)
    if [[ ! -d "$dir" ]]; then
        log_debug "Directory validation warning: directory doesn't exist - $dir"
        # Don't fail here as directory might be created
    fi
    
    return 0
}

# =============================================================================
# STRING VALIDATION
# =============================================================================

# Validate alphanumeric string (with optional extras)
validate_alphanumeric() {
    local input="${1:-}"
    local allow_extras="${2:-}"  # Additional allowed characters
    
    if [[ -z "$input" ]]; then
        log_debug "Alphanumeric validation failed: empty input"
        return 1
    fi
    
    # Build regex based on allowed extras
    local regex="^[a-zA-Z0-9${allow_extras}]+$"
    
    if [[ ! "$input" =~ $regex ]]; then
        log_debug "Alphanumeric validation failed: invalid characters - $input"
        return 1
    fi
    
    return 0
}

# Validate email address
validate_email() {
    local email="${1:-}"
    local email_regex='^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    
    if [[ -z "$email" ]]; then
        log_debug "Email validation failed: empty input"
        return 1
    fi
    
    if [[ ! "$email" =~ $email_regex ]]; then
        log_debug "Email validation failed: invalid format - $email"
        return 1
    fi
    
    return 0
}

# Validate URL
validate_url() {
    local url="${1:-}"
    local url_regex='^https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$'
    
    if [[ -z "$url" ]]; then
        log_debug "URL validation failed: empty input"
        return 1
    fi
    
    if [[ ! "$url" =~ $url_regex ]]; then
        log_debug "URL validation failed: invalid format - $url"
        return 1
    fi
    
    return 0
}

# =============================================================================
# NUMERIC VALIDATION
# =============================================================================

# Validate integer
validate_integer() {
    local input="${1:-}"
    local min="${2:-}"
    local max="${3:-}"
    
    if [[ -z "$input" ]]; then
        log_debug "Integer validation failed: empty input"
        return 1
    fi
    
    # Check if numeric
    if [[ ! "$input" =~ ^-?[0-9]+$ ]]; then
        log_debug "Integer validation failed: not an integer - $input"
        return 1
    fi
    
    # Check range if specified
    if [[ -n "$min" ]] && [[ $input -lt $min ]]; then
        log_debug "Integer validation failed: below minimum - $input < $min"
        return 1
    fi
    
    if [[ -n "$max" ]] && [[ $input -gt $max ]]; then
        log_debug "Integer validation failed: above maximum - $input > $max"
        return 1
    fi
    
    return 0
}

# Validate boolean
validate_boolean() {
    local input="${1:-}"
    
    if [[ -z "$input" ]]; then
        log_debug "Boolean validation failed: empty input"
        return 1
    fi
    
    # Convert to lowercase for comparison
    input="${input,,}"
    
    case "$input" in
        true|false|yes|no|y|n|1|0|on|off)
            return 0
            ;;
        *)
            log_debug "Boolean validation failed: invalid value - $input"
            return 1
            ;;
    esac
}

# =============================================================================
# PARAMETER VALIDATION FRAMEWORK
# =============================================================================

# Validate function parameters
validate_params() {
    local function_name="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        local param_name="$1"
        local param_value="$2"
        local param_type="$3"
        shift 3
        
        case "$param_type" in
            required)
                if [[ -z "$param_value" ]]; then
                    log_error "[$function_name] Missing required parameter: $param_name"
                    return 1
                fi
                ;;
            ip)
                if ! validate_ip "$param_value"; then
                    log_error "[$function_name] Invalid IP for $param_name: $param_value"
                    return 1
                fi
                ;;
            port)
                if ! validate_port "$param_value"; then
                    log_error "[$function_name] Invalid port for $param_name: $param_value"
                    return 1
                fi
                ;;
            file)
                if ! validate_file "$param_value"; then
                    log_error "[$function_name] Invalid file for $param_name: $param_value"
                    return 1
                fi
                ;;
            directory)
                if ! validate_directory "$param_value"; then
                    log_error "[$function_name] Invalid directory for $param_name: $param_value"
                    return 1
                fi
                ;;
            vmid)
                if ! validate_vmid "$param_value"; then
                    log_error "[$function_name] Invalid VMID for $param_name: $param_value"
                    return 1
                fi
                ;;
            hostname)
                if ! validate_hostname "$param_value"; then
                    log_error "[$function_name] Invalid hostname for $param_name: $param_value"
                    return 1
                fi
                ;;
            *)
                log_warn "[$function_name] Unknown parameter type: $param_type"
                ;;
        esac
    done
    
    return 0
}

# =============================================================================
# SANITIZATION FUNCTIONS
# =============================================================================

# Sanitize input for safe shell usage
sanitize_input() {
    local input="$1"
    local allowed_chars="${2:-a-zA-Z0-9._-}"
    
    # Remove any characters not in the allowed set
    echo "$input" | tr -cd "$allowed_chars"
}

# Sanitize filename
sanitize_filename() {
    local filename="$1"
    
    # Remove path components
    filename="$(basename "$filename")"
    
    # Replace dangerous characters with underscore
    filename="${filename//[^a-zA-Z0-9._-]/_}"
    
    # Remove leading dots (hidden files)
    filename="${filename#.}"
    
    # Limit length
    if [[ ${#filename} -gt 255 ]]; then
        filename="${filename:0:255}"
    fi
    
    echo "$filename"
}

# =============================================================================
# EXPORT FUNCTIONS
# =============================================================================

export -f validate_input
export -f validate_ip validate_cidr validate_mac_address validate_hostname
export -f validate_vmid
export -f validate_path validate_file validate_directory
export -f validate_alphanumeric validate_email validate_url
export -f validate_integer validate_boolean
export -f validate_params
export -f sanitize_input sanitize_filename