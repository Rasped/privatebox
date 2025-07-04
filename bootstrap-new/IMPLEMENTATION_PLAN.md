# PrivateBox Bootstrap System - Implementation Plan

## Architecture Overview

The new bootstrap system will be a simplified, modular design focusing on reliability and ease of use:

```
bootstrap/
├── bootstrap.sh              # Main entry point with interactive menu
├── lib/
│   ├── common.sh            # Core functions: logging, error handling, utilities
│   ├── network.sh           # Network discovery and validation
│   └── password.sh          # Password generation utilities
├── scripts/
│   ├── create-vm.sh         # VM creation with cloud-init
│   ├── install-services.sh  # Podman, Portainer, Semaphore setup
│   └── generate-report.sh   # Final credentials and URL report
├── config/
│   └── defaults.conf        # Default configuration values
├── templates/
│   └── cloud-init.yaml.j2   # Cloud-init template
├── cache/                   # Cloud image cache directory
└── README.md               # Documentation
```

## Key Design Decisions

### 1. **Simplified Error Handling**
- Use `set -eEuo pipefail` with proper ERR traps
- Single logging function with severity levels
- Clean error messages without complex stack traces
- Automatic cleanup on failure

### 2. **Interactive Menu System**
- Simple dialog-based menu for configuration
- Options: Full Auto, Custom Network, Advanced Settings, Exit
- Auto mode uses network discovery for zero-config setup
- All values can be overridden via environment variables

### 3. **Network Auto-Discovery**
- Detect default gateway and network
- Find available IP in subnet
- Detect Proxmox bridge (vmbr0, vmbr1, etc.)
- Simple validation without complex parsing

### 4. **Cloud Image Management**
- Cache images in `/var/cache/privatebox/images/`
- Check if image exists before downloading
- Use wget with progress display
- Support Ubuntu 24.04 LTS by default

### 5. **Security Implementation**
- Generate SSH keys on Proxmox host
- Use cloud-init for passwordless sudo user
- Generate phonetic passwords (format: XXXXXX-XXXXXX-XXXXXX)
- Store credentials in encrypted file with GPG
- No passwords in environment variables or logs

### 6. **Service Deployment with Quadlets**
- Use Podman with systemd quadlets for containers
- Portainer as .container quadlet file
- Semaphore as .container quadlet file  
- Enable automatic updates via systemd
- Health checks built into quadlets

### 7. **Final Report Generation**
- Display all URLs and access information
- Show generated passwords once
- Save encrypted credentials file
- Provide SSH connection commands
- Show service health status

## Implementation Steps

1. **Create directory structure and base files** ✓
2. **Implement lib/common.sh with logging and error handling** ✓
3. **Create network discovery in lib/network.sh** ✓
4. **Build interactive menu in bootstrap.sh**
5. **Implement VM creation with cloud-init in scripts/create-vm.sh**
6. **Create service installation with quadlets** ✓ (via cloud-init)
7. **Generate final report with credentials**
8. **Add comprehensive logging throughout** ✓
9. **Test error scenarios and recovery** ✓ (partially)
10. **Document usage and examples**

## Progress Summary

### Completed Components:
- **Directory Structure**: Created all necessary directories
- **lib/common.sh**: Full error handling, logging, and utility functions
  - Color-coded logging (INFO=blue, ERROR=red, WARN=yellow, SUCCESS=green)
  - Logs stored in `/var/log/privatebox/` with timestamps
  - Cleanup function registration system
- **lib/password.sh**: Password generation and credential management
  - Phonetic password format working perfectly (e.g., `Kadif6-Tizar8-Gecoq5`)
  - SHA-512 password hash generation for cloud-init
  - SSH key generation with 4096-bit RSA keys
  - GPG encryption for credentials (auto-generates key if needed)
- **lib/network.sh**: Network discovery and validation
  - Successfully detects Proxmox bridges (vmbr0)
  - Finds available IPs starting from .50
  - Pure bash implementation (no bc dependency)
  - Fixed netmask calculation bug
- **config/defaults.conf**: Default configuration values
- **templates/cloud-init.yaml.j2**: Complete cloud-init configuration with Podman quadlets

### Testing Results (on Proxmox server 192.168.1.10):
- ✅ All libraries load and function correctly
- ✅ Network discovery found: Gateway=192.168.1.3, Bridge=vmbr0, Available IP=192.168.1.50
- ✅ Password generation creates secure phonetic passwords
- ✅ SSH key generation and GPG encryption working
- ✅ Password hash generation compatible with cloud-init

### Next Steps:
1. Create the main bootstrap.sh script with interactive menu
2. Implement the VM creation script
3. Create the report generation script
4. Write comprehensive documentation

### New Findings from Testing:

1. **Library Sourcing**: When sourcing multiple libraries, readonly variable warnings appear but are harmless
2. **Credential Generation Output**: The `generate_all_credentials` function outputs both log messages and variable assignments, requiring careful parsing when using eval
3. **Network Discovery Performance**: IP availability checking is fast, finding available IPs within seconds
4. **GPG Key Generation**: Automatically generates GPG key for root@localhost if not present
5. **Template Rendering**: Simple envsubst works but needs proper variable export
6. **Proxmox Environment**: The test server has proper network configuration with vmbr0 as the main bridge

## Example Usage

```bash
# One-line installation
curl -fsSL https://your-repo/quickstart.sh | sudo bash

# Interactive mode
sudo ./bootstrap/bootstrap.sh

# Fully automated with custom IP
STATIC_IP=192.168.1.50 sudo ./bootstrap/bootstrap.sh --auto

# Resume after failure
sudo ./bootstrap/bootstrap.sh --resume
```

## Technical Details

### Error Handling Pattern
```bash
#!/bin/bash
set -eEuo pipefail
trap 'handle_error $LINENO' ERR

handle_error() {
    local line=$1
    log_error "Script failed at line $line"
    cleanup
    exit 1
}
```

### Password Generation
- Use `/dev/urandom` for randomness
- Generate phonetic-friendly characters
- Format: XXXXXX-XXXXXX-XXXXXX (18 characters)
- Avoid ambiguous characters (0, O, l, 1)

### Network Discovery Algorithm
1. Get default route: `ip route | grep default`
2. Extract gateway and interface
3. Get network from interface: `ip addr show <iface>`
4. Find available IP by pinging range
5. Validate no conflicts

### Cloud-Init User Data Structure
```yaml
#cloud-config
users:
  - name: privatebox
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - <generated-ssh-key>

packages:
  - podman
  - curl
  - gpg

runcmd:
  - [/bin/bash, /usr/local/bin/install-services.sh]
```

### Podman Quadlet Example
```ini
[Unit]
Description=Portainer CE
After=network-online.target

[Container]
Image=docker.io/portainer/portainer-ce:latest
Volume=portainer_data:/data
Volume=/run/podman/podman.sock:/var/run/docker.sock:z
PublishPort=9000:9000
PublishPort=9443:9443

[Service]
Restart=always

[Install]
WantedBy=multi-user.target
```

### Security Considerations
- No hardcoded passwords
- SSH key-only authentication by default
- Encrypted credential storage
- Secure random password generation
- Minimal exposed ports
- Regular security updates via cloud-init

### Logging Strategy
- Log levels: DEBUG, INFO, WARN, ERROR, SUCCESS
- Timestamped entries within the log file
- Simple log file naming: `/var/log/privatebox/scriptname.log`
- Color-coded console output for better visibility
- Falls back to /tmp if /var/log/privatebox cannot be created
- Single log file per script (appends to existing)

## Implementation Considerations (from Testing)

### 1. **Credential Generation Integration**
When using `generate_all_credentials` in scripts, the output needs to be filtered:
```bash
# Capture only the variable assignments
eval $(generate_all_credentials 2>/dev/null | grep "^[A-Z_]*=")
```

### 2. **Template Variable Requirements**
The cloud-init template requires these variables:
- `VM_USERNAME` - The VM user account name
- `VM_PASSWORD_HASH` - SHA-512 hash of the password
- `SSH_PUBLIC_KEY` - RSA public key for SSH access
- `PORTAINER_PORT`, `PORTAINER_HTTPS_PORT` - Portainer ports
- `SEMAPHORE_PORT`, `SEMAPHORE_PASSWORD` - Semaphore configuration
- `STATIC_IP`, `GATEWAY` - Network configuration
- `TIMESTAMP` - ISO 8601 timestamp

### 3. **Network Discovery Behavior**
- Starts checking from .50 by default to avoid common static IPs
- Uses ping with 1-second timeout for fast discovery
- Falls back gracefully if arping is not available
- Validates connectivity to both gateway and internet (8.8.8.8)

### 4. **Error Handling Best Practices**
- Use subshells or separate scripts to avoid readonly variable conflicts
- Always check command existence before using (e.g., openssl, python3)
- Provide fallback options for missing tools
- Log errors but continue when possible (e.g., GPG encryption failure)

### 5. **Podman Quadlet Considerations**
- Quadlets require the systemd directory structure to exist
- User lingering must be enabled for user services
- Container names should be consistent for easy management
- Volume mounts need proper SELinux labels (:z or :Z)

This design prioritizes simplicity, security, and reliability while meeting all requirements.