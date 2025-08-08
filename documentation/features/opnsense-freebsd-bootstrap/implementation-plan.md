# OPNsense FreeBSD Bootstrap Implementation Plan

## Overview

Deploy OPNsense using Ansible playbooks executed via Semaphore with staged, testable approach.

**Goal**: Zero-touch OPNsense deployment with automated verification  
**Method**: Ansible playbooks → FreeBSD 14.3 → OPNsense bootstrap → API configuration  
**Target Version**: OPNsense 25.7 (based on FreeBSD 14.3)  
**Duration**: ~45 minutes total  
**Execution**: Semaphore UI (container) → SSH → Proxmox host  
**Environment**: vmbr0 (WAN) and vmbr1 (LAN) bridges must exist

## Architecture

```
[Semaphore UI on Management VM]
    ↓ SSH to Proxmox host
[Stage 1: FreeBSD VM Creation]
    ↓ Test: VM responds
[Stage 2: OPNsense Bootstrap]
    ↓ Test: API responds
[Stage 3: Network Configuration]
    ↓ Test: LAN accessible
[Stage 4: VLAN Configuration]
    ↓ Test: All VLANs up
[Stage 5: Security Rules]
    ↓ Test: Rules enforced
[Production Firewall]
```

## Deployment Stages

### Stage 1: FreeBSD VM Creation
**Start State**: Proxmox host (existing VM ID 963 will be destroyed)  
**End State**: FreeBSD 14.3 VM running via DHCP, accessible via SSH  
**Requirements**:
- Check and destroy existing VM ID 963 if present
- Download FreeBSD 14.3 BASIC-CLOUDINIT image
- Create VM: 4GB RAM, 2 cores, 32GB disk
- Two NICs: WAN (vmbr0), LAN (vmbr1)
- VM boots with DHCP (cloud-init NOT functional in this image)
- Extract VM MAC address from config
- Discover IP via MAC-based ARP scanning
**Test**: VM discovered via MAC, responds to ping, SSH accessible with default credentials

### Stage 2: OPNsense Bootstrap
**Start State**: FreeBSD 14.3 VM running with DHCP IP  
**End State**: OPNsense 25.7 running with API enabled  
**Requirements**:
- Load VM IP from `/tmp/opnsense-vm-ip`
- SSH to VM using default credentials (freebsd/freebsd)
- Install required packages (python39, sudo)
- Copy bootstrap script to VM
- Convert FreeBSD to OPNsense (~20 min download/install)
- Generate API credentials
- System reboots into OPNsense
**Test**: API endpoint responds at https://VM_IP/api

### Stage 3: Basic Network Configuration
**Start State**: OPNsense with default config  
**End State**: LAN configured at 192.168.100.1/24 with DHCP  
**Requirements**:
- Configure LAN interface via API
- Enable DHCP server (100-200 range)
- Apply configuration
**Test**: LAN gateway accessible at 192.168.100.1

### Stage 4: VLAN Configuration
**Start State**: Basic LAN configured  
**End State**: Six VLANs configured with DHCP  
**Requirements**:
- Create VLANs 10,20,30,40,50,60 on LAN interface
- Assign IP ranges (10.10.X.0/24)
- Configure DHCP for each VLAN
**Test**: All VLAN interfaces up and configured

### Stage 5: Security Rules
**Start State**: All VLANs configured  
**End State**: Production firewall rules enforced  
**Requirements**:
- Apply inter-VLAN firewall rules
- Restrict access based on zones
- Disable WAN management access
**Test**: Guest cannot reach Management, IoT restricted

## File Structure

```
ansible/playbooks/services/
├── opnsense-stage1-create-vm.yml      # Stage 1: FreeBSD VM creation
├── opnsense-stage2-bootstrap.yml      # Stage 2: OPNsense bootstrap
├── opnsense-stage3-configure.yml      # Stage 3: Basic network via API
├── opnsense-stage4-vlans.yml          # Stage 4: Add VLANs via API
├── opnsense-stage5-security.yml       # Stage 5: Security rules via API
├── opnsense-full-deploy.yml           # Orchestrator: runs all stages
└── opnsense-test-connectivity.yml     # Test playbook for verification

ansible/files/opnsense/
├── cloud-init-freebsd.yml.j2          # FreeBSD cloud-init template
├── bootstrap-opnsense.sh              # OPNsense conversion script
├── config-minimal.xml.j2              # Initial OPNsense config
└── generate-api-keys.py               # API key generation helper
```

## Implementation Details

### Stage 1: FreeBSD VM Creation

**Playbook**: `opnsense-stage1-create-vm.yml`  
**Host**: proxmox (via SSH)  
**Method**: Ansible using qm commands

**Tasks**:
1. Check if VM ID 963 exists (destroy if present)
2. Verify network bridges (vmbr0, vmbr1) exist
3. Download FreeBSD 14.3 BASIC-CLOUDINIT image to cache
4. Extract .xz compressed image
5. Create VM with qm (4GB RAM, 2 cores, 2 NICs)
6. Import and attach disk (32GB)
7. Start VM (boots with DHCP by default)
8. Wait for VM to boot (~60 seconds)
9. Extract MAC address from VM config (`qm config 963 | grep net0`)
10. Discover IP via ARP scan: ping subnet range, check ARP for MAC
11. Save discovered IP to `/tmp/opnsense-vm-ip`

**Important Notes**:
- FreeBSD BASIC-CLOUDINIT image does NOT have cloud-init installed
- VM uses default FreeBSD credentials (user: freebsd, password: freebsd)
- Network defaults to DHCP on vtnet0
- No cloud-init configuration is applied
- IP discovery via MAC address is required

### Stage 2: OPNsense Bootstrap

**Playbook**: `opnsense-stage2-bootstrap.yml`  
**Host**: proxmox (via SSH)  
**Method**: Ansible copies script, executes on VM

**Tasks**:
1. Load VM IP from `/tmp/opnsense-vm-ip`
2. Copy `bootstrap-opnsense.sh` to VM
3. Execute bootstrap script (async, ~20 min)
4. Wait for VM reboot
5. Wait for OPNsense to come online (port 443)
6. Retrieve generated API credentials
7. Save credentials to `/tmp/opnsense-api-creds`
8. Test API endpoint

**Bootstrap Script** (`bootstrap-opnsense.sh`):
- Downloads official OPNsense bootstrap from GitHub
- Runs conversion (FreeBSD 14.3 → OPNsense 25.7)
- Process takes ~20 minutes (package downloads)
- Requires internet connectivity
- Generates API key/secret
- Saves to `/root/api-credentials`
- Reboots system

### Stage 3: Basic Network Configuration

**Playbook**: `opnsense-stage3-configure.yml`  
**Host**: localhost  
**Method**: Ansible using OPNsense API (uri module)

**Tasks**:
1. Load VM IP and API credentials from files
2. Configure LAN interface (192.168.100.1/24)
3. Enable DHCP server
4. Apply interface changes
5. Apply DHCP changes
6. Test LAN gateway connectivity

### Stage 4: VLAN Configuration

**Playbook**: `opnsense-stage4-vlans.yml`  
**Host**: localhost  
**Method**: Ansible using OPNsense API

**Tasks**:
1. Create VLAN interfaces (tags 10-60)
2. Assign VLANs to interfaces
3. Configure DHCP for each VLAN
4. Apply all changes
5. Verify interfaces are up

**VLAN Structure**:
- VLAN 10: Management (10.10.10.0/24)
- VLAN 20: Services (10.10.20.0/24)
- VLAN 30: Trusted (10.10.30.0/24)
- VLAN 40: Guest (10.10.40.0/24)
- VLAN 50: IoT-Cloud (10.10.50.0/24)
- VLAN 60: IoT-Local (10.10.60.0/24)

### Stage 5: Security Configuration

**Playbook**: `opnsense-stage5-security.yml`  
**Host**: localhost  
**Method**: Ansible using OPNsense API

**Tasks**:
1. Add firewall rules via API
2. Apply firewall configuration
3. Disable WAN SSH access
4. Apply system changes

**Security Zones**:
- Management: Full access to all
- Services: Accessible for DNS/services
- Trusted: Full access to all
- Guest: Internet only, no inter-VLAN
- IoT: Internet only, no inter-VLAN

## Full Deployment

**Playbook**: `opnsense-full-deploy.yml`  
**Purpose**: Orchestrate all stages sequentially  
**Runtime**: ~45 minutes

**Features**:
- Runs all 5 stages in sequence
- Logs progress to `/tmp/opnsense-deployment.log`
- Can stop on first failure
- Generates deployment summary

## Testing

**Playbook**: `opnsense-test-connectivity.yml`  
**Purpose**: Validate deployment at any stage

**Tests**:
- Stage 1: VM exists and responds
- Stage 2: API endpoint accessible
- Stage 3: LAN gateway configured
- Stage 4: All VLANs present
- Stage 5: Firewall rules applied

## Semaphore Integration

### Required Templates
1. **Individual Stages** (5 templates) - Run each stage independently
2. **Full Deployment** (1 template) - Complete automation
3. **Test Suite** (1 template) - Validation tests

### Variables Required
- `admin_password` - From Semaphore environment
- `service_password` - From Semaphore environment
- Proxmox SSH key - Already configured in Semaphore
- `VMID` - Default 963, configurable
- `FREEBSD_VERSION` - Default 14.3
- `OPNSENSE_VERSION` - Default 25.7

### Files Created During Deployment
- `/tmp/opnsense-vm-ip` - VM IP address (Stage 1)
- `/tmp/opnsense-api-creds` - API credentials (Stage 2)
- `/tmp/opnsense-deployment.log` - Deployment log

### Default VM Configuration
- **VMID**: 963 (chosen to avoid conflicts)
- **RAM**: 4096 MB
- **Cores**: 2
- **Disk**: 32GB
- **NICs**: 2 (vmbr0 for WAN, vmbr1 for LAN)

## Error Handling

### Rollback Strategy
- **Pre-Stage 1**: VM ID 963 automatically destroyed
- **Stage 1**: Destroy VM if creation fails
- **Stage 2**: VM remains in FreeBSD state if bootstrap fails
- **Stage 3-5**: Previous configuration remains
- **Network Issues**: Timeout handling for downloads

### Recovery Points
- After each stage, state is stable
- Can restart from any stage
- API credentials persist across runs

## Success Metrics

✅ All operations via Ansible playbooks  
✅ Full Semaphore UI integration  
✅ Each stage independently testable  
✅ Rollback possible at any stage  
✅ Total deployment < 45 minutes  
✅ Zero manual intervention required

---
*Document updated: 2025-01-08*  
*Approach: Ansible-first with minimal shell scripts*  
*Target: OPNsense 25.7 on FreeBSD 14.3*