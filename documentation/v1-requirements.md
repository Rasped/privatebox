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
- **Homer dashboard** ✅ (deployed at http://10.10.20.10:8081 with service registry)

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

#### 3. Container Auto-Updates ✅ COMPLETED
**Current State**: All containers have auto-update enabled
**Implementation**:
- All containers have `io.containers.autoupdate=registry` labels
- Weekly Sunday 2:30 AM schedule with 30min randomization
- Podman auto-update timer configured via systemd drop-in files
- Fixed TTY issue in cloud-init environment

#### 4. Update Playbooks 🔄 IN PROGRESS
**Required**: Automatic updates for all system components
**Scope**: Proxmox host, OPNsense firewall, Debian management VM

**Implementation Plan**:
- **OPNsense**: Native automatic updates via config.xml cron entry (NEXT)
- **Debian**: Native unattended-upgrades package configuration
- **Proxmox**: Ansible playbook for security updates only
- **Coordination**: Batch playbook to orchestrate all updates via Semaphore

**Decisions Made**:
- Default state: auto-updates ON
- Schedule: Weekly Sunday 2:00 AM (before container updates at 2:30 AM)
- Auto-reboot: Enabled at 2:30 AM if required
- Strategy: All systems updated in sequence (OPNsense → Debian → Proxmox)

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
10. Configure update schedules
11. Run initial backups
12. Display access information

### Post-Bootstrap State
- All services running and accessible
- DNS filtering active (AdGuard → Unbound)
- VPNs ready for client connections
- Backups scheduled
- Updates configured (on/off per user preference)
- Dashboard showing all services

## Critical Decisions - ANSWERED

### Decisions Made:
1. **AdGuard blocklists**: OISD and Steven Black hosts
2. **Dashboard choice**: Homer (static, simple, YAML config)
3. **Backup encryption password**: Use the generated long password from config.env
4. **Update default state**: ON by default, weekly at 2 AM
5. **VPN DNS**: Route through AdGuard for filtering
6. **Backup partition timing**: Create right after OPNsense creation (critical restore point)
7. **TLS/HTTPS**: Implement where possible
8. **Update reboots**: Auto-reboot at scheduled time (2:30 AM, 30 min after updates)

### Implementation Details Confirmed:
1. VPN ports (use defaults - OpenVPN 1194, WireGuard 51820)
2. Backup partition size (start with 5GB)
3. Update intervals (weekly 2 AM default, user can modify)
4. Container update mechanism (Podman auto-update with systemd timers)

## Implementation Priority Order

1. ✅ **COMPLETED: AdGuard-Unbound integration** (core functionality)
2. ✅ **COMPLETED: Deploy dashboard** (user visibility)
3. ✅ **COMPLETED: Container auto-updates** (container maintenance)
4. 🔄 **IN PROGRESS: System update automation** (OS/firmware maintenance)
5. **NEXT: Setup encrypted backup partition** (data safety)
6. **Implement VPNs** (remote access)

## Success Criteria for v1

- Single command deployment with zero interaction
- All services accessible via dashboard
- DNS filtering functional (ads blocked)
- VPN access working
- Configs backed up automatically
- Update mechanism in place (even if disabled by default)

## Update Reboot Best Practices (Research Summary)

Common practice for production servers:
- **Default behavior**: Most systems do NOT auto-reboot by default
- **Recommended**: Schedule reboots during maintenance windows
- **Best practice**: Auto-reboot with scheduled time (like 2:30 AM) rather than immediate
- **Key requirement**: Need "update-notifier-common" package for auto-reboot to work

For PrivateBox v1: **Auto-reboot at 2:30 AM** (30 min after updates at 2 AM) to ensure clean state.

## Ready for Implementation

All critical decisions have been made. The system can now be implemented with 100% hands-off deployment following the priority order:

1. **AdGuard-Unbound integration** with OISD and Steven Black blocklists
2. **Homer dashboard** deployment
3. **Encrypted backup partition** (LUKS, using generated password)
4. **VPN services** (OpenVPN + WireGuard with AdGuard DNS)
5. **Update playbooks** (weekly 2 AM, auto-reboot 2:30 AM)