#!/bin/bash
# Minimal validation library - Only functions actually used in PrivateBox
# Optimized version with bug fixes

# Ensure we have logging functions available
if ! declare -f log_error >/dev/null 2>&1; then
    log_error() { echo "[ERROR] $*" >&2; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*"; }
fi

# Generic input validation wrapper
# Fixed to handle "number" type and pass through additional parameters
validate_input() {
    local input="$1"
    local type="$2"
    shift 2
    local extra_params=("$@")
    
    case "$type" in
        "ip")
            validate_ip "$input"
            ;;
        "port")
            validate_port "$input"
            ;;
        "number"|"integer")
            validate_integer "$input" "${extra_params[@]}"
            ;;
        *)
            log_error "Unknown validation type: $type"
            return 1
            ;;
    esac
}

# Validate IP address
validate_ip() {
    local ip="${1:-}"
    local valid_ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ -z "$ip" ]]; then
        log_debug "IP validation failed: empty input"
        return 1
    fi
    
    if [[ ! "$ip" =~ $valid_ip_regex ]]; then
        log_debug "IP validation failed: invalid format - $ip"
        return 1
    fi
    
    # Check each octet
    local IFS='.'
    read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        octet=$((10#$octet))
        if [[ $octet -gt 255 ]]; then
            log_debug "IP validation failed: octet out of range - $octet"
            return 1
        fi
    done
    
    return 0
}

# Validate port number
validate_port() {
    local port="${1:-}"
    
    if [[ -z "$port" ]]; then
        log_debug "Port validation failed: empty input"
        return 1
    fi
    
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        log_debug "Port validation failed: not numeric - $port"
        return 1
    fi
    
    if [[ $port -lt 1 ]] || [[ $port -gt 65535 ]]; then
        log_debug "Port validation failed: out of range - $port"
        return 1
    fi
    
    return 0
}

# Validate integer with optional min/max
validate_integer() {
    local input="${1:-}"
    local min="${2:-}"
    local max="${3:-}"
    
    if [[ -z "$input" ]]; then
        log_debug "Integer validation failed: empty input"
        return 1
    fi
    
    if [[ ! "$input" =~ ^-?[0-9]+$ ]]; then
        log_debug "Integer validation failed: not an integer - $input"
        return 1
    fi
    
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

# Export functions
export -f validate_input
export -f validate_ip
export -f validate_port
export -f validate_integer