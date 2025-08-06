# OPNsense Template Configuration Plan

## Overview
This document outlines the plan for creating a fully-configured OPNsense template that deploys production-ready routers with minimal post-deployment steps.

## Phase 1: Bootstrap Enhancement
### 1.1 Add vmbr1 to Bootstrap Process
- Modify `bootstrap/scripts/fix-proxmox-network.sh` (new file)
- Auto-detect enp1s0 interface
- Create vmbr1 bridge (VLAN-aware, no IP)
- Update `/etc/network/interfaces` for persistence
- Run during quickstart.sh after VM creation

### 1.2 Password Management
**KEY POINT**: Bootstrap-generated passwords will be used
- Read from `/tmp/privatebox-quickstart/bootstrap/config/privatebox.conf`
- Admin password: Used for OPNsense root
- Store in `/opt/privatebox/secrets/opnsense-password`
- Pass via Ansible extra-vars or environment

## Phase 2: OPNsense Configuration (on 192.168.1.47)
### 2.1 Access Strategy
- **WAN remains on DHCP** throughout configuration
- All changes via WAN IP (192.168.1.47)
- SSH and Web UI accessible via WAN
- No lock-out risk during VLAN setup

### 2.2 Base Configuration
1. Enable SSH on WAN (temporary, for setup)
2. Enable SSH on LAN 
3. Change root password to bootstrap password
4. Enable API access
5. Configure hostname: opnsense.privatebox.local

### 2.3 Network Interfaces
- **vtnet0 (WAN)**: DHCP from customer router
- **vtnet1 (LAN)**: Tagged VLANs only, no untagged
  - VLAN 10: Management
  - VLAN 20: Services  
  - VLAN 30: Trusted
  - VLAN 40: Guest
  - VLAN 50: IoT Cloud
  - VLAN 60: IoT Local

### 2.4 VLAN Configuration
Each VLAN gets:
- Gateway IP (10.10.x.1)
- Firewall rules per matrix
- DHCP server (where applicable)
- DNS pointing to 10.10.20.10

### 2.5 Firewall Rules Matrix
**Trusted (VLAN 30) → Other VLANs**:
- ✅ Management: SSH (22), HTTPS (8006)
- ✅ Services: All ports
- ✅ IoT: All ports (control devices)
- ❌ Guest: Blocked

**Guest/IoT → Other VLANs**:
- ✅ Internet: Allowed
- ✅ Services: DNS (53) only
- ❌ All others: Blocked

**Services (VLAN 20)**:
- ✅ Internet: Allowed (updates)
- ❌ Other VLANs: Blocked (except responses)

### 2.6 Additional Services
- NTP server for local networks
- DNS forwarder to AdGuard
- DDNS client (disabled by default)
- Anti-lockout rule on WAN (temporary)

## Phase 3: Template Creation
### 3.1 Pre-Template Cleanup
1. Clear DHCP leases
2. Clear logs
3. Remove SSH host keys (regenerate on boot)
4. Remove specific MAC addresses
5. Set WAN to DHCP (ensure compatibility)

### 3.2 Shutdown and Convert
```bash
qm shutdown 100
qm template 100
```

### 3.3 Template Verification
- Document SHA256 of template disk
- Store in version control
- Verify before each deployment

## Phase 4: Deployment Process
### 4.1 Deploy from Template
- Use existing `opnsense-deploy.yml`
- VM starts with WAN DHCP
- All VLANs pre-configured

### 4.2 Post-Deploy Automation
New playbook: `opnsense-post-deploy.yml`
1. Wait for boot
2. Get WAN IP from router DHCP
3. Change root password (from bootstrap config)
4. Generate new SSH host keys
5. Create API credentials
6. Update Semaphore inventory
7. Remove WAN SSH access (security)
8. Test all VLAN gateways respond

### 4.3 Service Verification Tests
- Ping each VLAN gateway (10.10.x.1)
- DNS resolution via 10.10.20.10
- DHCP lease obtainable on VLANs 30,40,50,60
- Firewall blocks per matrix
- Internet accessible from Trusted VLAN

## Phase 5: Documentation Updates
### 5.1 Update Deployment Guide
- New OPNsense deployment process
- Password management procedure
- Troubleshooting VLAN access

### 5.2 Create Operator Runbook
- How to access OPNsense (WAN then LAN)
- VLAN assignment guide
- Common tasks (add firewall rule, etc)

## Implementation Order
1. Create vmbr1 fix script
2. Configure OPNsense manually (document each step)
3. Test configuration thoroughly
4. Create template
5. Test deployment
6. Create post-deploy automation
7. Update documentation

## Risk Mitigation
- Keep WAN SSH during development
- Test on isolated Proxmox first
- Backup current OPNsense config
- Document rollback procedure
- Verify no internet disruption

## Success Criteria
- [ ] Template deploys in <5 minutes
- [ ] All VLANs accessible
- [ ] Services respond on correct IPs
- [ ] No manual configuration needed
- [ ] Internet remains stable
- [ ] Can manage via Trusted VLAN

---
Document created: 2025-08-05
Target completion: Before first production unit