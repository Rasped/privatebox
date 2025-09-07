# Network Hardcoding Analysis Report

## Problem Statement

A tester encountered a password prompt during Phase 4 of the bootstrap process when running on a 192.168.2.x network. Investigation revealed a broader issue: hardcoded IP addresses throughout the codebase that assume a 192.168.1.x network.

## Tester's Error

```
Phase 4: Installation Verification
debian@192.168.2.20's password:
```

The system prompted for a password instead of using SSH key authentication, indicating the VM at 192.168.2.20 was created but SSH access failed.

## Root Cause Analysis

### How Network Detection Works

The bootstrap process successfully detects the network:
- `prepare-host.sh` line 122: Extracts base network from host IP (e.g., "192.168.2" from "192.168.2.10")
- Line 212: Correctly sets VM IP using detected network: `container_host_ip="${base_network}.20"`
- This detection logic works correctly for any network range

### Where Hardcoding Exists

#### 1. Bootstrap Scripts
- **semaphore-api.sh**
  - Line 128: `vm_ip="${STATIC_IP:-192.168.1.20}"`
  - Line 736: `vm_ip="${STATIC_IP:-192.168.1.20}"`
  - These fallback to 192.168.1.20 when STATIC_IP is not set

#### 2. Static Inventory File
- **ansible/inventory.yml** contains hardcoded addresses:
  - proxmox-host: 192.168.1.10
  - container-host: 192.168.1.22
  - alpine-vm: 192.168.1.102
  - caddy-vm: 192.168.1.23
  - network_subnet: "192.168.1.0/24"
  - network_gateway: "192.168.1.1"

#### 3. OPNsense Configuration
- **ansible/templates/opnsense/config.xml**:
  - Line 298: `<address>192.168.1.173</address>` (SSH rule destination)
  - Line 348: `<network>192.168.1.0/24</network>` (firewall rule)
  - Line 366: `<network>192.168.1.0/24</network>` (firewall rule)

#### 4. Documentation
Multiple documentation files reference specific 192.168.1.x addresses:
- CLAUDE.md
- PROXMOX-API-INTEGRATION.md
- PROXMOX-API-SETUP.md
- OPNSENSE-DEPLOYMENT.md
- DEPLOYMENT-STATUS.md

#### 5. Service Configuration
- **ansible/group_vars/all/services.yml**:
  - Multiple `backend_host: "192.168.1.20"` entries
- **ansible/scripts/vm-self-register.sh**:
  - Line 11: `SEMAPHORE_URL="${SEMAPHORE_URL:-http://192.168.1.20:3000}"`

## Impact Analysis

### What Works
- Network detection correctly identifies the local network
- VM creation uses the detected network for IP assignment
- Cloud-init configuration is generated with correct IPs

### What Breaks
1. **SSH Access**: When fallback IPs don't match detected network, SSH authentication fails
2. **Service Communication**: Hardcoded service endpoints won't resolve on different networks
3. **Firewall Rules**: OPNsense rules target specific IPs that may not exist
4. **Manual Testing**: Static inventory file only works on 192.168.1.x networks

## Discovered Architecture

### Dynamic Inventory System
Investigation revealed that Semaphore creates dynamic inventories during bootstrap:
- Bootstrap detects network and saves to `/tmp/privatebox-config.conf`
- `semaphore-api.sh` creates inventories using detected IPs
- Templates in Semaphore use these dynamic inventories
- The static `ansible/inventory.yml` is not used by the automated flow

### Inventory Creation Flow
1. `prepare-host.sh`: Detects network, sets BASE_NETWORK
2. `create-vm.sh`: Uses BASE_NETWORK for VM IP
3. `semaphore-api.sh`: Creates three inventories in Semaphore:
   - container-host: Using detected VM IP
   - localhost: For local tasks
   - proxmox: Using detected host IP

## Key Findings

1. **Network detection works** - The logic to detect and use the correct network exists and functions
2. **Hardcoded fallbacks cause failures** - When detection values aren't propagated, hardcoded defaults take over
3. **Production flow partially works** - Semaphore's dynamic inventories work, but some components still have hardcoded IPs
4. **Static inventory is technical debt** - The ansible/inventory.yml file is not used by bootstrap but remains in the repo
5. **Documentation assumes 192.168.1.x** - All examples and instructions use this specific network range

## Affected Components Summary

- **Critical**: semaphore-api.sh fallback IPs
- **Important**: OPNsense config.xml firewall rules
- **Moderate**: Service configuration files
- **Low**: Documentation examples
- **Obsolete**: ansible/inventory.yml (not used by bootstrap)

## Testing Implications

Any deployment on networks other than 192.168.1.x will experience:
- Potential SSH authentication failures
- Service connectivity issues
- Incorrect firewall rules
- Documentation that doesn't match reality

This analysis confirms the system is designed to be network-agnostic but implementation details prevent it from achieving that goal.