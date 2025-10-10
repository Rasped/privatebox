# PrivateBox v1 Requirements & Implementation Status

## Document Purpose
This document captures the complete requirements for PrivateBox v1.0 release, current implementation status, and questions requiring answers for 100% hands-off deployment.

## V1 Core Requirements

### Primary Goal
Transform a Proxmox host into a comprehensive privacy-focused network appliance with one-command deployment that requires zero user interaction after initiation.

### Target Hardware
- Intel N100 mini PC (or similar)
- 8GB+ RAM
- 20GB+ storage for VMs and containers
- Additional storage for encrypted backups

## Current Implementation Status

### ✅ COMPLETED Features

#### Infrastructure
- **One-command bootstrap** (`quickstart.sh`)
- **Debian 13 Management VM** with cloud-init
- **Network auto-detection** and configuration
- **Portainer** (port 9000) - Container management UI
- **Semaphore** (port 3000) - Ansible automation UI
- **Automatic template synchronization** from Ansible playbooks ✅
- **Service orchestration automation** ✅ (auto-deploys OPNsense, AdGuard, Homer)
- **SSH key management** for Proxmox and containers
- **Password generation** and storage in `/etc/privatebox/config.env`
- **Semaphore API integration** with cookie-based auth
- **VLAN configuration and segmentation** (per user confirmation)

#### Services
- **OPNsense VM template** created and backed up
- **OPNsense with Unbound DNS** configured on port 53
- **AdGuard deployment playbook** ✅ (fully deployed and configured with Quad9 + Unbound fallback, blocklists active)
- **Homer dashboard** ✅ (deployed at https://homer.lan with service registry)

### 🔧 NEEDS FINALIZATION

#### 1. AdGuard-Unbound Integration ✅ COMPLETED
**Current State**: Fully integrated and working
**Required**:
- ✅ Configure AdGuard to use `10.10.20.1:53` as fallback DNS (COMPLETED - configured with Quad9 primary + Unbound fallback)
- ✅ Add blocklists during deployment (COMPLETED - OISD Basic + Steven Black Hosts configured)
- ✅ Test DNS resolution chain: Client → AdGuard → Quad9 → Unbound → Internet (VERIFIED WORKING)

**Questions**:
- Which 2 blocklists should be configured? (OISD? Steven Black? EasyList? AdGuard DNS filter?)
- Should AdGuard listen on all interfaces or just the Services VLAN (10.10.20.x)?
- Fallback DNS servers if Unbound fails?

#### 2. Dashboard Deployment ✅ COMPLETED
**Current State**: Homer deployed and running at 10.10.20.10:8081
**Implementation**:
- Homer container deployed via Semaphore template
- Service registry at /opt/privatebox/services.yml
- Auto-updates services from registry
- Shows all deployed services with status


### 📋 NEEDS IMPLEMENTATION

#### 1. VPN Services (OpenVPN + WireGuard)
**Required**: Road warrior configurations on OPNsense
**Routing**: All traffic through PrivateBox

**Questions**:
- Port assignments for each VPN service?
- How many concurrent clients to support?
- Should VPN clients access all VLANs or restricted?
- Pre-generate client configs or on-demand?
- DNS for VPN clients - use AdGuard or direct to Unbound?

#### 2. Encrypted Backup System
**Required**: LUKS partition on Proxmox bare metal for config backups
**Scope**: OPNsense configurations on schedule

**Questions**:
- Partition size? (1GB? 5GB? 10GB?)
- Where on disk? (end of main disk? separate disk if available?)
- Encryption password source? (generate during bootstrap? prompt user?)
- How to mount to OPNsense VM? (NFS? CIFS? Direct block device?)
- Backup frequency? (daily? weekly? on-change?)
- Retention policy? (keep last 7? 30? unlimited?)
- Should Management VM configs also be backed up?

#### 3. Update Management ✅ COMPLETED
**Current State**: Manual updates via Semaphore with one exception
**Implementation**:
- **Manual updates only**: All systems require user-initiated updates via Semaphore
- **Homer exception**: Dashboard auto-updates (low-risk, display-only)
- **Ansible playbooks**: Available for manual execution of updates
- **User control**: No unexpected system changes or reboots

**Rationale**:
- Respects user agency over their equipment
- Prevents unexpected breakage from automatic updates
- Reduces liability and support burden
- Maintains system stability and predictability

**Update Tools Available**:
- **Proxmox**: Manual update playbooks via Semaphore
- **OPNsense**: Manual firmware updates via web UI or Semaphore
- **Debian**: Manual apt updates via Semaphore
- **Containers**: Manual image pulls/restarts via Portainer or Semaphore

#### 5. TLS/HTTPS Support
**Current State**: All services use HTTP
**User Note**: "I don't know what TLS is"

**Questions**:
- Is HTTPS/secure connections important for v1?
- If yes:
  - Self-signed certificates acceptable?
  - Or skip TLS entirely for v1 since it's LAN-only?
- Services that might need HTTPS:
  - OPNsense (already uses self-signed)
  - Dashboard?
  - Semaphore?

## Deployment Flow Requirements

### Bootstrap Phase (100% Automated)
1. Run quickstart.sh on Proxmox
2. Create Management VM
3. Install Portainer + Semaphore
4. Deploy OPNsense from template/backup
5. Configure VLANs
6. Deploy AdGuard with Unbound integration
7. Deploy Dashboard
8. Configure VPNs
9. Setup encrypted backup partition
10. Run initial backups
11. Display access information

### Post-Bootstrap State
- All services running and accessible
- DNS filtering active (AdGuard → Unbound)
- VPNs ready for client connections
- Backups scheduled
- Update tools available (user-controlled via Semaphore)
- Dashboard showing all services

## Critical Decisions - ANSWERED

### Decisions Made:
1. **AdGuard blocklists**: OISD and Steven Black hosts
2. **Dashboard choice**: Homer (static, simple, YAML config)
3. **Backup encryption password**: Use the generated long password from config.env
4. **Update default state**: Manual updates only (via Semaphore playbooks)
5. **VPN DNS**: Route through AdGuard for filtering
6. **Backup partition timing**: Create right after OPNsense creation (critical restore point)
7. **TLS/HTTPS**: Implement where possible
8. **Update approach**: User-initiated only (respects equipment ownership)

### Implementation Details Confirmed:
1. VPN ports (use defaults - OpenVPN 1194, WireGuard 51820)
2. Backup partition size (start with 5GB)
3. Update intervals (manual execution via Semaphore only)
4. Container update mechanism (manual image pulls via Portainer/Semaphore)

## Implementation Priority Order

1. ✅ **COMPLETED: AdGuard-Unbound integration** (core functionality)
2. ✅ **COMPLETED: Deploy dashboard** (user visibility)
3. ✅ **COMPLETED: Update management strategy** (manual updates with tools)
4. **NEXT: Setup encrypted backup partition** (data safety)
5. **Implement VPNs** (remote access)
6. **Create manual update playbooks** (user-controlled maintenance)

## Success Criteria for v1

- Single command deployment with zero interaction
- All services accessible via dashboard
- DNS filtering functional (ads blocked)
- VPN access working
- Configs backed up automatically
- Manual update playbooks available via Semaphore

## Update Philosophy (Manual Only)

**Decision**: No automatic updates except Homer dashboard

**Rationale**:
- **User agency**: Respects ownership and control over equipment
- **System stability**: Prevents unexpected breakage from automatic updates
- **Predictability**: No surprise reboots or service disruptions
- **Reduced liability**: User controls when/if updates occur

**Exception**: Homer dashboard auto-updates (display-only, minimal risk)

**Available Tools**: Semaphore playbooks for manual updates of all components

## Ready for Implementation

All critical decisions have been made. The system can now be implemented with 100% hands-off deployment following the priority order:

1. **AdGuard-Unbound integration** with OISD and Steven Black blocklists
2. **Homer dashboard** deployment
3. **Encrypted backup partition** (LUKS, using generated password)
4. **VPN services** (OpenVPN + WireGuard with AdGuard DNS)
5. **Manual update playbooks** (user-initiated via Semaphore)