# PrivateBox Network Architecture Plan

**Created**: 2025-07-24  
**Status**: Implementation Planning  
**Version**: 1.0

## Executive Summary

This document outlines the network architecture implementation plan for PrivateBox, focusing on creating a secure, segmented network with proper DNS filtering and recursive resolution. The plan addresses current issues, defines the target architecture, and provides a phased implementation approach with clear dependencies and risk mitigation strategies.

### Key Goals
1. Deploy OPNsense as the primary router/firewall
2. Establish AdGuard Home for DNS filtering  
3. Configure Unbound for recursive DNS resolution
4. Implement VLAN-based network segmentation
5. Create a secure, maintainable DNS chain

### Critical Success Factors
- Zero network downtime during migration
- Maintain management access throughout
- DNS resolution working end-to-end
- Proper network isolation between VLANs
- All services accessible post-migration

## Current State Analysis

### Recent Discoveries (2025-07-24)

During implementation attempts, we discovered:

1. **AdGuard Container Networking**:
   - Container successfully binds to VM IP (192.168.1.21) on ports 53, 853, 3001, 8080
   - Health checks fail because they expect localhost (127.0.0.1)
   - This is due to Quadlet PublishPort directive: `PublishPort={{ ansible_default_ipv4.address }}:{{ port }}`

2. **systemd-resolved Conflict**:
   - Successfully disabled by playbook to free port 53
   - Temporary DNS servers configured (1.1.1.1, 8.8.8.8, 9.9.9.9)
   - VM has working DNS resolution

3. **VM Configuration Issues**:
   - Hostname resolution error: `sudo: unable to resolve host ubuntu`
   - Missing entry in /etc/hosts for local hostname
   - Does not affect functionality but clutters output

4. **AdGuard Initial State**:
   - Web UI redirects to `/control/install.html` (expected)
   - API endpoint `/control/status` returns 302 redirect
   - Service is running but awaits manual configuration
   - DNS port 53 not functional until setup complete

5. **Semaphore Execution Issues**:
   - Tasks fail with DNS resolution errors in Semaphore container
   - Semaphore container cannot resolve github.com
   - This may be related to systemd-resolved being disabled

### What's Working
- **Proxmox Host**: Operational on 192.168.1.10
- **Management VM**: Successfully deployed at 192.168.1.21
- **Container Services**: 
  - Portainer running on port 9000
  - Semaphore running on port 3000
- **Basic Infrastructure**: Bootstrap phase completed successfully

### What Needs Fixing
1. **AdGuard Container Issues**:
   - Binding to external IP (192.168.1.21) instead of all interfaces
   - Health check failing due to checking 127.0.0.1:8080
   - DNS port 53 non-functional until manual setup complete
   - Playbook fails due to incorrect health check

2. **Network Architecture**:
   - No network segmentation (everything on flat network)
   - No firewall/router VM deployed
   - No VLAN configuration
   - DNS services not properly integrated

3. **Security Concerns**:
   - All services exposed on management network
   - No traffic filtering between services
   - No DNS security (DNSSEC, DoT)

## Target Architecture

### Network Topology

```
Internet
    ↓
[ISP Router/Modem] (Bridge Mode)
    ↓
[Proxmox Host - 192.168.1.10]
    ↓
[vmbr0] - WAN Bridge
    ↓
[OPNsense VM]
  - WAN: DHCP from ISP
  - LAN: Multiple VLANs
    ↓
[vmbr1] - VLAN-Aware Bridge
    ↓
    ├── Management VLAN (10) - 10.0.10.0/24
    │   └── Proxmox Host (10.0.10.10)
    │
    ├── Services VLAN (20) - 10.0.20.0/24
    │   ├── Management VM (10.0.20.21)
    │   ├── AdGuard Container
    │   └── Future Services
    │
    ├── LAN VLAN (30) - 10.0.30.0/24
    │   └── Client Devices (DHCP)
    │
    └── IoT VLAN (40) - 10.0.40.0/24
        └── Smart Home Devices (DHCP)
```

### DNS Architecture

```
Client Device (10.0.30.x)
    ↓ DNS Query (port 53)
AdGuard Home (10.0.20.21:53)
    ↓ Filtered Query (port 5353)
Unbound on OPNsense (10.0.20.1:5353)
    ↓ Recursive Query (DoT/DNSSEC)
Public DNS Servers (1.1.1.1, 9.9.9.9)
```

### Service Communication Matrix

| From / To | Management | Services | LAN | IoT | Internet |
|-----------|------------|----------|-----|-----|----------|
| Management| ✓ | ✓ | ✓ | ✓ | ✓ |
| Services | ✗ | ✓ | ✗ | ✗ | ✓ |
| LAN | ✗ | DNS only | ✓ | ✗ | ✓ |
| IoT | ✗ | DNS only | ✗ | ✓ | Limited |

## Implementation Phases

### Phase 0: Prerequisites & Information Gathering (Days 1-2)

#### 0.1 Fix VM Configuration Issues
- **Fix hostname resolution**: `sudo: unable to resolve host ubuntu` error
  - Add `127.0.1.1 ubuntu` to `/etc/hosts`
  - Verify with `hostname -f`
  
#### 0.2 Understand AdGuard Container Networking
- **Current behavior**: Container binds to VM IP (192.168.1.21) not localhost
- **Investigation needed**:
  - Review Podman Quadlet network configuration
  - Understand why health checks fail on 127.0.0.1
  - Document container network mode (bridge vs host)
  
#### 0.3 AdGuard API Documentation
- **Research automatic setup process**:
  - Test `/install/get_addresses` endpoint
  - Document `/install/configure` payload structure
  - Create example JSON for automatic configuration
- **Authentication flow**:
  - Initial setup requires no auth
  - Post-setup requires username/password
  
#### 0.4 Create Supporting Scripts
- **AdGuard automatic setup script**
- **DNS validation test suite**
- **Network connectivity verification**

### Phase 1: Fix Current Issues (Days 3-4)

#### 1.1 Fix AdGuard Container Binding
- **Problem**: Container binds to specific IP, health check expects localhost
- **Root Cause**: Podman Quadlet PublishPort directive binds to specific IP
- **Solution**: 
  - Option A: Modify Quadlet template to bind to 0.0.0.0
  - Option B: Update health check to use actual IP ✓
  - Option C: Use host networking mode
- **Decision**: Option B (least invasive, maintains security)
- **Tasks**:
  - ✓ Update health check in playbook to use `ansible_default_ipv4.address`
  - Create AdGuard automatic configuration playbook
  - Handle initial setup state in health checks
  - Fix DNS port availability check

#### 1.2 Stabilize DNS Service
- Configure AdGuard for automatic startup
- Implement proper health monitoring
- Document manual setup requirements
- Create recovery procedures

### Phase 2: Network Design & Planning (Days 5-7)

#### 2.1 Detailed Network Design
- **IP Addressing Scheme**:
  ```
  Management: 10.0.10.0/24
    Gateway: 10.0.10.1 (OPNsense)
    Proxmox: 10.0.10.10
    
  Services: 10.0.20.0/24  
    Gateway: 10.0.20.1 (OPNsense)
    Management VM: 10.0.20.21
    AdGuard: 10.0.20.21 (container)
    Reserved: 10.0.20.30-50 (future services)
    
  LAN: 10.0.30.0/24
    Gateway: 10.0.30.1 (OPNsense)
    DHCP Pool: 10.0.30.100-200
    
  IoT: 10.0.40.0/24
    Gateway: 10.0.40.1 (OPNsense)
    DHCP Pool: 10.0.40.100-200
  ```

#### 2.2 Firewall Rules Planning
- Default deny all inter-VLAN traffic
- Allow specific services (documented per VLAN)
- DNS exceptions for all VLANs to Services VLAN
- Management access only from Management VLAN

### Phase 3: OPNsense Deployment (Days 8-10)

#### 3.1 Create OPNsense VM
- **Specifications**:
  - vCPU: 2 cores minimum
  - RAM: 2GB minimum (4GB recommended)
  - Storage: 20GB
  - Network: 2+ interfaces (WAN + LAN)

#### 3.2 OPNsense Playbook Development
```yaml
# Key tasks:
- Create VM via SSH to Proxmox
- Attach to WAN bridge (vmbr0)
- Create VLAN-aware LAN bridge (vmbr1)
- Configure initial network settings
- Enable required services
```

#### 3.3 Initial Configuration
- WAN: DHCP client
- LAN: VLAN trunk with sub-interfaces
- Basic firewall rules
- Enable Unbound DNS on port 5353

### Phase 4: DNS Chain Configuration (Days 11-12)

#### 4.1 Unbound Configuration on OPNsense
- Move to port 5353 (avoid conflict with AdGuard)
- Enable DNSSEC validation
- Configure DNS over TLS upstream
- Set up local zone for internal resolution
- Configure access control (only from Services VLAN)

#### 4.2 AdGuard Upstream Configuration  
- Set Unbound as upstream: `10.0.20.1:5353`
- Configure local domain resolution: `[/privatebox.local/]10.0.20.1:5353`
- Enable DNSSEC checking (rely on Unbound)
- Configure query logging

#### 4.3 Testing & Validation
- Test DNS resolution from each VLAN
- Verify DNSSEC validation
- Check ad blocking functionality
- Monitor query performance

### Phase 5: Network Migration (Days 13-14)

#### 5.1 Pre-Migration Checklist
- [ ] Document current network settings
- [ ] Backup all configurations
- [ ] Schedule maintenance window
- [ ] Prepare rollback plan
- [ ] Test in isolated environment

#### 5.2 Migration Steps
1. Configure VLANs on physical switches (if applicable)
2. Update Proxmox network configuration
3. Migrate Management VM to Services VLAN
4. Update DNS settings on all devices
5. Test connectivity from each VLAN
6. Apply final firewall rules

#### 5.3 Post-Migration Validation
- All services accessible
- DNS resolution working
- Inter-VLAN routing as designed
- No security policy violations
- Performance acceptable

## Critical Decision Points

### 1. AdGuard Binding Strategy
**Options Evaluated**:
- **Option A**: Bind to all interfaces (0.0.0.0)
  - Pros: Maximum flexibility, works with any IP
  - Cons: Less secure, exposes on all interfaces
- **Option B**: Fix health checks to use correct IP ✓
  - Pros: Maintains security, minimal changes
  - Cons: Requires playbook updates
- **Option C**: Use host networking mode
  - Pros: Simplifies networking
  - Cons: Less isolation, port conflicts

**Decision**: Option B - Fix health checks while maintaining security

### 2. DNS Architecture Model
**Options Evaluated**:
- **Option A**: Client → AdGuard → Unbound → Internet ✓
  - Pros: Filtering first, clean recursive resolution
  - Cons: Single point of failure
- **Option B**: Client → Unbound → AdGuard → Internet
  - Pros: Recursive first, optional filtering
  - Cons: Complex configuration, filtering limitations
- **Option C**: Parallel DNS servers
  - Pros: Redundancy
  - Cons: Complex management, inconsistent results

**Decision**: Option A - AdGuard first for optimal filtering

### 3. Network Complexity
**Options Evaluated**:
- **Option A**: Simple (Management, LAN, DMZ)
  - Pros: Easy to manage
  - Cons: Limited isolation
- **Option B**: Moderate (+ IoT, Guest) ✓
  - Pros: Good balance, practical isolation
  - Cons: More complex than basic
- **Option C**: Complex (per-service VLANs)
  - Pros: Maximum isolation
  - Cons: Management overhead

**Decision**: Option B - Balanced approach for home/small business

## Risk Analysis & Mitigation

### Risk 1: Loss of Network Connectivity
**Probability**: Medium  
**Impact**: High  
**Mitigation**:
- Maintain out-of-band management access
- Test all changes in dev environment first
- Document rollback procedures
- Keep ISP router accessible as fallback

### Risk 2: DNS Service Failure
**Probability**: Medium  
**Impact**: High  
**Mitigation**:
- Configure fallback DNS servers
- Monitor DNS service health
- Implement automatic service restart
- Document manual recovery steps

### Risk 3: Misconfigured Firewall Rules
**Probability**: High  
**Impact**: Medium  
**Mitigation**:
- Start with permissive rules, tighten gradually
- Test each rule change thoroughly
- Log all traffic during testing
- Have console access for recovery

### Risk 4: VLAN Configuration Errors
**Probability**: Medium  
**Impact**: High  
**Mitigation**:
- Validate configuration in test environment
- Implement changes incrementally
- Keep detailed network documentation
- Test from each VLAN after changes

## Success Criteria

### Functional Requirements
- [ ] OPNsense VM deployed and routing traffic
- [ ] All VLANs configured and isolated
- [ ] DNS resolution working for all clients
- [ ] AdGuard filtering active and effective
- [ ] Unbound providing recursive resolution
- [ ] DNSSEC validation operational
- [ ] All services accessible per design

### Performance Requirements  
- [ ] DNS query response < 50ms average
- [ ] Inter-VLAN routing latency < 5ms
- [ ] Service availability > 99.9%
- [ ] No packet loss under normal load

### Security Requirements
- [ ] VLANs properly isolated
- [ ] Firewall rules enforced
- [ ] DNS queries encrypted upstream
- [ ] Management access restricted
- [ ] No unauthorized service exposure

## Rollback Procedures

### Phase 1 Rollback
- Revert AdGuard configuration changes
- Restore original playbook
- Remove AdGuard container and redeploy

### Phase 3 Rollback  
- Shutdown OPNsense VM
- Restore direct Proxmox connectivity
- Revert to flat network

### Phase 5 Rollback
- Remove VLAN configuration
- Restore original IP addresses
- Revert to flat network
- Restore DNS to ISP/public servers

## Documentation Requirements

### To Be Created
1. Network Diagram (Visio/draw.io)
2. IP Address Allocation Spreadsheet
3. Firewall Rules Matrix
4. DNS Configuration Guide
5. Emergency Recovery Procedures
6. User Migration Guide

### To Be Updated  
1. CLAUDE.md with network details
2. README.md with new access information
3. Ansible inventory files
4. Service deployment playbooks

## Appendix A: Command Reference

### Useful Proxmox Commands
```bash
# Create VLAN-aware bridge
pvesh create /nodes/proxmox/network -iface vmbr1 -type bridge -vlan-aware 1

# Create OPNsense VM
qm create 100 --name opnsense --memory 4096 --cores 2 --sockets 1
```

### OPNsense Configuration
```bash
# Configure Unbound on different port
# Via UI: Services → Unbound DNS → General → Listen Port: 5353
```

### Testing Commands
```bash
# Test DNS resolution
dig @10.0.20.21 google.com
dig @10.0.20.1 -p 5353 google.com

# Test VLAN connectivity  
ping -c 4 10.0.30.1
```

## Appendix B: Timeline

| Week | Phase | Key Deliverables |
|------|-------|------------------|
| 1 | Phase 0: Prerequisites | Information gathered, issues documented |
| 1 | Phase 1: Fix Issues | AdGuard operational with automatic setup |
| 1-2 | Phase 2: Planning | Network design complete |
| 2 | Phase 3: OPNsense | VM deployed and configured |
| 3 | Phase 4: DNS Chain | Full DNS path working |
| 3-4 | Phase 5: Migration | VLANs active, services migrated |

## Phase 0 Completion Status (2025-07-24) ✅

Phase 0 has been successfully completed. All prerequisites and information gathering tasks have been accomplished:

### Completed Items:
- ✅ **0.1 Fix VM Configuration Issues**: Hostname resolution fixed in cloud-init
- ✅ **0.2 Understand AdGuard Container Networking**: Documented binding behavior (binds to VM IP for security)
- ✅ **0.3 AdGuard API Documentation**: Created comprehensive test scripts and automatic configuration
- ✅ **0.4 Create Supporting Scripts**: AdGuard deploys 100% hands-off with automatic setup

### Key Achievements:
- AdGuard now deploys and configures automatically via Ansible
- Health checks updated to use VM IP address instead of localhost
- DNS integration completed - system uses AdGuard for resolution
- All manual steps eliminated from deployment process

### Ready for Phase 1:
With Phase 0 complete, the project is ready to proceed with OPNsense deployment and network segmentation as outlined in Phase 1.

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-07-24 | Claude | Initial plan created |
| 1.1 | 2025-07-24 | Claude | Added Phase 0 for prerequisites and discoveries |
| 1.2 | 2025-07-24 | Claude | Updated with Phase 0 completion status |

---

*This is a living document. Updates will be made as implementation progresses and lessons are learned.*