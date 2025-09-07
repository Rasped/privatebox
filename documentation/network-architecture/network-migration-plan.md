# Network Migration Plan

## Purpose
Migrate PrivateBox from flat network to OPNsense-routed VLAN architecture. 100% automated, 100% hands-off.

## Current State → Target State

### Now (Development)
```
Home Router (192.168.1.3)
    ├── vmbr0 → Proxmox (192.168.1.10)
    ├── vmbr0 → Management VM (192.168.1.x)
    └── Both NICs connected to same router
```

### Target (Production)
```
Customer ISP
    └── vmbr0 → OPNsense WAN (DHCP)
                    └── vmbr1 → OPNsense LAN
                                 ├── Default LAN (untagged) → Trusted (10.10.10.0/24)
                                 ├── VLAN 20 → Services (Proxmox 10.10.20.30, Management VM 10.10.20.20)
                                 └── VLANs 30-70 → Guest, IoT, and Camera networks
```

## Migration Phases

### Phase 0: Prerequisites
- enp1s0 activated and persistent
- vmbr1 configured (no IP)
- OPNsense template available

### Phase 1: Deploy OPNsense
- Deploy VM with WAN=vmbr0, LAN=vmbr1
- WAN gets DHCP from development router
- LAN configured as 10.10.10.1 (Trusted network, untagged)
- **Checkpoint**: OPNsense accessible at WAN IP

### Phase 2: Configure VLANs
- Create 6 VLAN subinterfaces per vlan-design.md
- Configure each VLAN gateway (10.10.x.1)
- Set up DHCP servers (where applicable)
- Implement firewall rules matrix
- **Checkpoint**: Test VM on vmbr1 gets DHCP from OPNsense

### Phase 3: Pre-Migration Validation
- Deploy test VM on each VLAN
- Verify routing between VLANs per policy
- Confirm internet access through OPNsense
- Test DNS resolution via Services VLAN
- **Checkpoint**: All test VMs functional

### Phase 4: The Migration
Execute in this exact order:

1. **Record current IPs** (for rollback)
2. **Update Proxmox**:
   - Add VLAN 20 interface: 10.10.20.30/24
   - Gateway: 10.10.20.1
   - Remove IP from vmbr0
3. **Update Management VM**:
   - Change network to vmbr1 + VLAN 20 tag
   - Static IP: 10.10.20.20/24
   - Gateway: 10.10.20.1
4. **Update service configs**:
   - All services bind to 10.10.20.20
   - Update Semaphore inventory
5. **Update OPNsense**:
   - Remove any dev-specific routes

### Phase 5: Health Check
- From OPNsense console:
  - Ping Proxmox (10.10.20.30)
  - Ping Management VM (10.10.20.20)
  - Curl Semaphore API
  - Verify DNS resolution
- If ANY fail → execute rollback

### Phase 6: Cleanup
- Remove test VMs
- Clear DHCP leases
- Document final state

## Rollback Plan

If health check fails:
1. Restore Proxmox IP on vmbr0
2. Move Management VM back to vmbr0
3. Restore original service bindings
4. OPNsense remains (but unused)

Trigger: Any service unreachable after 5 minutes

## Critical Success Factors

1. **IP Address Reservations**:
   - Document every static IP before migration
   - No DHCP for infrastructure

2. **Order Matters**:
   - Proxmox first (it's the hypervisor)
   - Management VM second (it runs services)
   - Services last (they depend on VM)

3. **Gateway Changes**:
   - Every migrated system needs new gateway
   - Old: 192.168.1.3
   - New: 10.10.x.1 (VLAN-specific)

4. **Firewall Rules**:
   - Trusted LAN (default) → VLAN 20 (services) must work
   - Required for customer to access Proxmox and services

## Automation Requirements

- Single playbook: `network-migrate.yml`
- Idempotent (can run multiple times)
- Health checks after each step
- Automatic rollback on failure
- Progress logging to Semaphore

## Post-Migration

- vmbr0 only used for OPNsense WAN
- All infrastructure on VLANs
- Customer ready: unplug and ship