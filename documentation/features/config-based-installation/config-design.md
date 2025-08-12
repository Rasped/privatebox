# Config-Based Installation Design

## Overview

This document defines the config-driven installation approach for PrivateBox, with sensible defaults and auto-generation capabilities for zero-configuration deployment.

## Current State Analysis

### Existing Config Issues

1. **Mixed Concerns**: Infrastructure settings mixed with service configurations
2. **No Defaults**: Users must configure everything manually
3. **Inconsistent Generation**: Only Semaphore password is auto-generated

### Config Loading Flow

```
network-discovery.sh → creates config with hardcoded values
create-ubuntu-vm.sh → sources config but ignores most values
                    → generates random Semaphore password only
```

## New Config-Based Design

### Minimal User Configuration

```bash
# Infrastructure IPs (auto-generated if not provided)
CONTAINER_HOST_IP="192.168.1.20"    # Ubuntu VM with containers
CADDY_HOST_IP="192.168.1.21"        # Alpine VM with Caddy
OPNSENSE_IP="192.168.1.47"          # OPNsense firewall
GATEWAY="192.168.1.3"               # Network gateway

# Passwords (auto-generated if not provided)
ADMIN_PASSWORD="Eagl3-T0w3r-Silv3r-M0unta1n-Str0ng"
SERVICES_PASSWORD="Spr1ng-M0nk3y-Blu3"

# Optional VM resources (defaults if not provided)
VM_MEMORY="4096"
VM_CORES="2"
```

### Default Network Layout

When auto-detecting network configuration:

1. Detect gateway IP (e.g., 192.168.1.3)
2. Extract base network (e.g., 192.168.1)
3. Apply standard host IPs:
   - `.20` - Container host (Ubuntu VM)
   - `.21` - Caddy host (Alpine VM)
   - `.47` - OPNsense firewall

## Password Generation Strategy

### Phonetic Password Design

Passwords are generated using phonetic words that are:

- Easy to remember
- Easy to type
- Secure through length and complexity

### Services Password (3 words)

- **Format**: `Word1-Word2-Word3`
- **Example**: `Spr1ng-M0nk3y-Blu3`
- **Characteristics**:
  - 3 phonetic words
  - 5-6 characters per word
  - Mixed case (capitalize first letter)
  - Number substitutions
  - Hyphen separators

### Admin Password (5 words)

- **Format**: `Word1-Word2-Word3-Word4-Word5`
- **Example**: `Eagl3-T0w3r-Silv3r-M0unta1n-Str0ng`
- **Characteristics**:
  - 5 phonetic words for higher security
  - Same formatting rules as services
  - Longer for infrastructure access

### Number Substitution Rules

Common letter-to-number substitutions for memorability:

- `e` → `3`
- `o` → `0`
- `i` → `1`
- `a` → `4` (optional)
- `s` → `5` (optional)
- `l` → `1` (when lowercase)

### Word Categories

To ensure variety and memorability:

- **Adjectives**: Swift, Bright, Strong, Clear, Sharp, Quick, Bold
- **Nouns**: Eagle, Tower, River, Mountain, Forest, Thunder, Ocean
- **Colors**: Blue, Green, Silver, Golden, Crimson, Azure, Amber
- **Actions**: Strike, Guard, Watch, Protect, Shield, Defend

## Config Generation Flow

### 1. Check Existing Config

```bash
if [[ -f "privatebox.conf" ]]; then
    source privatebox.conf
    # Validate required fields
    # Generate missing passwords
else
    # Create new config with all defaults
fi
```

### 2. Network Auto-Detection

```bash
# Detect gateway
GATEWAY=$(ip route | grep default | awk '{print $3}')

# Extract base network
BASE_NETWORK=$(echo $GATEWAY | cut -d. -f1-3)

# Apply defaults
CONTAINER_HOST_IP="${BASE_NETWORK}.20"
CADDY_HOST_IP="${BASE_NETWORK}.21"
OPNSENSE_IP="${BASE_NETWORK}.47"
```

### 3. Password Generation

```bash
generate_phonetic_password() {
    local word_count=$1
    local words=()

    # Select random words from categories
    # Apply number substitutions
    # Join with hyphens

    echo "${words[*]}"
}

# Generate if not provided
SERVICES_PASSWORD="${SERVICES_PASSWORD:-$(generate_phonetic_password 3)}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-$(generate_phonetic_password 5)}"
```

### 4. Display and Save

```bash
echo "=== Generated Configuration ==="
echo "Network:"
echo "  Container Host: $CONTAINER_HOST_IP"
echo "  Caddy Host: $CADDY_HOST_IP"
echo "  OPNsense: $OPNSENSE_IP"
echo ""
echo "Passwords:"
echo "  Services: $SERVICES_PASSWORD"
echo "  Admin: $ADMIN_PASSWORD"
echo ""
echo "Configuration saved to: privatebox.conf"
```

## Implementation Plan

### Phase 1: Core Implementation

1. **Create phonetic password generator**

   - Word lists and selection logic
   - Number substitution function
   - Hyphen joining

2. **Update network-discovery.sh**

   - Add IP defaults (.20, .21, .47)
   - Integrate password generation
   - Create complete config

3. **Simplify config template**
   - Remove service-specific settings
   - Keep only infrastructure essentials
   - Add clear comments

### Phase 2: Integration

1. **Update create-ubuntu-vm.sh**

   - Use config passwords consistently
   - Validate password complexity

2. **Update service deployments**

   - Read passwords from config/secrets
   - Remove password generation from services
   - Ensure consistent password usage

3. **Create secure storage**
   - Save passwords to /opt/privatebox/secrets/
   - Set proper permissions (600, root only)
   - Delete config after bootstrap

### Phase 3: Testing

1. **Test auto-generation**

   - No config file scenario
   - Partial config scenario
   - Full config scenario

2. **Test network detection**

   - Various network configurations
   - Gateway detection reliability
   - IP conflict handling

3. **Test password quality**
   - Memorability
   - Typing ease
   - Security strength

## Security Considerations

### Password Storage

- Config file: chmod 600 during bootstrap
- Secure storage: /opt/privatebox/secrets/ after bootstrap
- Environment: Clear passwords after use
- Logs: Never log passwords

### Password Strength

- Services: ~15-18 characters with complexity
- Admin: ~25-30 characters with higher complexity
- Both exceed typical brute-force thresholds
- Phonetic approach aids memorability without sacrificing security

## Benefits

1. **Zero Configuration**: Works out of the box with sensible defaults
2. **Customizable**: Users can override any default
3. **Secure**: Strong auto-generated passwords
4. **Memorable**: Phonetic passwords are easier to remember
5. **Consistent**: Same passwords across all services
6. **Simple**: Minimal required configuration
