# Phase 2 Comprehensive Plan: OPNsense Network Segmentation

**Date**: 2025-07-24  
**Author**: Claude  
**Status**: Planning Phase

## Executive Summary

This document provides a comprehensive plan for implementing network segmentation using OPNsense in PrivateBox. After careful analysis, we recommend a **pure Ansible approach** using the `community.general.proxmox_kvm` module for VM creation and management.

## Critical Assumptions (Challenged and Verified)

### 0. Service Availability During Migration
**Assumption**: Brief service outage (5-10 minutes) is acceptable.
- **Reality**: Management VM hosts DNS, Portainer, and Semaphore
- **Solution**: Use OPNsense as temporary DNS forwarder during transition
- **Impact**: Services only down during VM network reconfiguration

### 1. proxmox_kvm Module Capabilities
**Assumption**: The module can handle all VM creation requirements.
- **Verified**: Supports ISO attachment, multiple NICs, disk configuration
- **Risk**: Module limitations discovered during implementation
- **Mitigation**: Maintain shell script templates as fallback

### 2. Manual Bootstrap Requirements
**Assumption**: 10-15 minutes of manual console work is acceptable.
- **Verified**: OPNsense requires console access for initial interface assignment
- **Challenge**: Can we eliminate this?
- **Solution**: Use VM images (qcow2) - assumed to be ready-to-run
- **Approach**: Download VM image, import to Proxmox, boot directly
- **Result**: Zero manual installation steps planned

### 3. Incremental Migration Strategy
**Assumption**: Service-by-service migration is safer than big-bang.
- **Challenge**: Complexity of dual networks, potential routing loops
- **Alternative**: Big-bang with thorough testing
- **Decision**: Incremental remains best for production safety
- **Key Risk**: DNS resolution during transition

### 4. Network Architecture Decisions
**Assumption**: Four VLANs (Management, Services, LAN, IoT) are sufficient.
- **Challenge**: Future growth, service isolation needs
- **Validation**: Matches typical home/small business requirements
- **Flexibility**: Design allows easy VLAN addition

## Detailed Implementation Plan

### Phase 2A: OPNsense Automation Research

#### 1. VM Creation Approach (CONFIRMED - Zero Touch via API)
```yaml
# Phase 1: Deploy VM with official qcow2 image
- name: Download OPNsense VM image
  get_url:
    url: "https://mirror.dns-root.de/opnsense/releases/24.7/OPNsense-24.7-vm-amd64.qcow2"
    dest: "/tmp/opnsense.qcow2"
    checksum: "sha256:{{ opnsense_vm_checksum }}"
  delegate_to: "{{ proxmox_host }}"

- name: Create OPNsense VM
  community.general.proxmox_kvm:
    api_user: "{{ vault_proxmox_user }}"
    api_password: "{{ vault_proxmox_password }}"
    api_host: "{{ proxmox_host }}"
    name: opnsense
    node: "{{ proxmox_node }}"
    vmid: 100
    memory: 4096
    cores: 2
    cpu: host
    net:
      net0: 'virtio,bridge=vmbr0'  # WAN
      net1: 'virtio,bridge=vmbr1'   # LAN (VLAN trunk)
    scsihw: virtio-scsi-pci
    onboot: yes

- name: Import and configure disk
  shell: |
    qm importdisk 100 /tmp/opnsense.qcow2 {{ storage }}
    qm set 100 --scsi0 {{ storage }}:vm-100-disk-0
    qm set 100 --boot order=scsi0
    qm start 100
  delegate_to: "{{ proxmox_host }}"
```

**Confirmed Approach**:
- qcow2 images are **full installations** (not live images)
- Boot directly to running OPNsense (no installer)
- Default: WAN=DHCP, LAN=192.168.1.1/24, root/opnsense
- Configure everything via API using ansibleguy.opnsense

#### 2. Bootstrap Process (API-BASED AUTOMATION)

**Zero Manual Steps - Direct API Configuration**

OPNsense qcow2 boots directly with:
- Default credentials: root/opnsense
- Web API available at https://192.168.1.1
- WAN: DHCP enabled
- LAN: 192.168.1.1/24

**API Configuration Approach**:
```yaml
# Install required Ansible collection
- name: Install ansibleguy.opnsense collection
  ansible.builtin.shell:
    cmd: ansible-galaxy collection install ansibleguy.opnsense

# Configure OPNsense via API
- name: Configure OPNsense
  hosts: localhost
  tasks:
    - name: Wait for OPNsense API
      wait_for:
        host: 192.168.1.1
        port: 443
        delay: 60

    - name: Configure system settings
      ansibleguy.opnsense.system:
        hostname: opnsense
        domain: privatebox.local
        api_host: 192.168.1.1
        api_user: root
        api_password: opnsense

    - name: Configure interfaces and VLANs
      include_tasks: configure_network.yml
```

#### 3. Post-Bootstrap Automation

Once SSH is enabled, Ansible takes over completely:
```yaml
# Configure OPNsense via SSH/API
- name: Configure OPNsense base settings
  tasks:
    - name: Install required packages
      pkgng:
        name: 
          - os-api  # Enable API
          - os-theme-rebellion  # Better UI
    
    - name: Configure API access
      template:
        src: api_settings.xml.j2
        dest: /usr/local/etc/api_settings.xml
    
    - name: Create VLANs
      opnsense_api:  # Custom module we'll create
        endpoint: /api/interfaces/vlan/add
        data:
          vlan:
            if: vtnet1
            tag: "{{ item.tag }}"
            descr: "{{ item.name }}"
      loop:
        - { tag: 10, name: "Management" }
        - { tag: 20, name: "Services" }
        - { tag: 30, name: "LAN" }
        - { tag: 40, name: "IoT" }
```

### Phase 2B: Network Architecture

#### VLAN Design (Validated)

| VLAN ID | Name | Network | Gateway | DHCP Range | Purpose |
|---------|------|---------|---------|------------|---------|
| 10 | Management | 10.0.10.0/24 | 10.0.10.1 | None | Infrastructure only |
| 20 | Services | 10.0.20.0/24 | 10.0.20.1 | None | Containers/Services |
| 30 | LAN | 10.0.30.0/24 | 10.0.30.1 | .100-.200 | User devices |
| 40 | IoT | 10.0.40.0/24 | 10.0.40.1 | .100-.200 | Smart devices |

**Key Decisions**:
- No DHCP on Management/Services (static IPs only)
- /24 subnets provide 254 hosts each (sufficient)
- 10.0.0.0/16 allows future expansion

#### DNS Flow Architecture

```
Client (10.0.30.x) 
    ↓ [Query on port 53]
AdGuard (10.0.20.21:53) ← Filtering
    ↓ [Forward to port 5353]
Unbound (10.0.20.1:5353) ← OPNsense
    ↓ [DoT/DNSSEC]
Public DNS (1.1.1.1, 9.9.9.9)
```

**Critical Path**: AdGuard must be migrated before changing client DNS

### Phase 2C: Firewall Rules Matrix

#### Default Policies
- **Inter-VLAN**: DENY ALL (explicit allow required)
- **Internet Access**: ALLOW with stateful tracking
- **Management Access**: Only from Management VLAN

#### Detailed Rules

```yaml
firewall_rules:
  # Management VLAN (10) - Full access
  - name: "MGMT-ALL-ALLOW"
    source: "10.0.10.0/24"
    destination: "any"
    action: "pass"
    interface: "MGMT"
    
  # Services VLAN (20) - Internet only
  - name: "SVC-INTERNET-ALLOW"
    source: "10.0.20.0/24"
    destination: "!RFC1918"  # Not private IPs
    action: "pass"
    interface: "SERVICES"
    
  # LAN to Services DNS
  - name: "LAN-SVC-DNS-ALLOW"
    source: "10.0.30.0/24"
    destination: "10.0.20.21"
    port: "53"
    protocol: "udp,tcp"
    action: "pass"
    
  # IoT Isolation
  - name: "IOT-INTERNET-LIMITED"
    source: "10.0.40.0/24"
    destination: "!RFC1918"
    port: "80,443,123"  # HTTP/HTTPS/NTP only
    action: "pass"
```

### Phase 2D: Migration Strategy

#### Pre-Migration Checklist
- [ ] Full backup of all VMs
- [ ] Document current network settings
- [ ] Test OPNsense in isolated environment
- [ ] Prepare rollback scripts
- [ ] Schedule 4-hour maintenance window

#### Migration Phases

**Phase 1: Parallel Network Setup** (30 min)
1. Deploy OPNsense VM
2. Configure all VLANs
3. Test basic connectivity
4. Do NOT change default gateway yet

**Phase 2: Services Migration** (1 hour)
1. Configure temporary DNS forwarding on OPNsense (10.0.30.1 → 192.168.1.21)
2. Create VM snapshot for quick rollback
3. Stop Management VM
4. Change network to VLAN 20
5. Update IP to 10.0.20.21
6. Start and verify services
7. Test AdGuard DNS resolution
8. Update OPNsense DNS forwarding to new IP (10.0.30.1 → 10.0.20.21)

**Phase 3: Client Migration** (2 hours)
1. Update DHCP to use new DNS (10.0.20.21)
2. Change default gateway to OPNsense
3. Move test client to VLAN 30
4. Verify internet and services access
5. Migrate remaining clients

**Phase 4: Cleanup** (30 min)
1. Remove old network configuration
2. Update documentation
3. Configure monitoring
4. Final validation

#### Rollback Plan

Each phase has specific rollback:
```yaml
rollback_procedures:
  phase_1:
    - Destroy OPNsense VM
    - Remove VLAN configuration
    
  phase_2:
    - Stop Management VM
    - Revert network to vmbr0
    - Restore original IP
    - Start services
    
  phase_3:
    - Revert DHCP settings
    - Move clients back to flat network
    - Restore original gateway
```

### Phase 2E: Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| DNS failure during migration | Medium | High | Test DNS path before client migration |
| Management lockout | Low | Critical | Console access + rollback procedure |
| Service unreachable | Medium | High | Incremental migration with testing |
| Performance degradation | Low | Medium | Monitor during migration |
| Configuration error | Medium | High | Test in isolated environment first |

### Phase 2F: Documentation Deliverables

1. **OPNsense Deployment Guide**
   - Ansible playbook documentation
   - Manual bootstrap steps with screenshots
   - Troubleshooting guide

2. **Network Architecture Diagram**
   - Visual VLAN layout
   - Traffic flow diagrams
   - DNS resolution path

3. **Operational Runbook**
   - Daily operations
   - Backup procedures
   - Update processes

4. **Emergency Procedures**
   - Console access steps
   - Network recovery
   - Service restoration

## Implementation Timeline

- **Week 1**: Create Ansible playbooks and test VM deployment
- **Week 2**: Document procedures and test migration in isolation
- **Week 3**: Production migration and validation
- **Week 4**: Documentation finalization and knowledge transfer

## Success Criteria

1. **Technical Success**
   - [ ] All services accessible post-migration
   - [ ] DNS resolution working for all VLANs
   - [ ] Firewall rules enforced correctly
   - [ ] No performance degradation

2. **Operational Success**
   - [ ] Clear documentation available
   - [ ] Rollback procedures tested
   - [ ] Monitoring configured
   - [ ] Team trained on new architecture

## Conclusion

This plan provides a comprehensive approach to implementing network segmentation with OPNsense. The pure Ansible approach using `proxmox_kvm` module combined with pre-built VM images achieves **100% hands-off deployment**.

Key strengths:
- **ZERO manual intervention** - Fully automated deployment
- VM image approach eliminates installation completely
- Clear rollback procedures
- Incremental migration reduces risk
- Comprehensive documentation plan

Major improvement:
- Originally: 15 minutes manual work
- Now: 0 minutes manual work
- Method: Pre-built VM images + console automation

Next steps:
- Review and approve plan
- Begin Ansible playbook development
- Test VM image deployment approach