# Factory Setup - Network Migration Architecture

## Overview

Factory setup for parallel production of PrivateBox routers using network bridge migration. No physical cable moves required - pure software reconfiguration transforms factory network into production network.

## Key Concept: Software-Defined Network Migration

Both WAN and LAN cables remain plugged throughout entire process. Network ownership transfers through bridge reassignment:
1. Proxmox initially owns both bridges
2. OPNsense takes control progressively
3. Final state: OPNsense owns both physical ports

## Hardware Configuration

### Factory Switch Setup (ProCurve 2810)
```
VLAN Configuration for 10 Parallel Builds:
├── VLAN 101: Router 1 (Ports 1 & 11)
├── VLAN 102: Router 2 (Ports 2 & 12)
├── VLAN 103: Router 3 (Ports 3 & 13)
...
└── VLAN 110: Router 10 (Ports 10 & 20)

Port Assignment Pattern:
- Ports 1-10: WAN ports (vmbr0 on each Proxmox)
- Ports 11-20: LAN ports (vmbr1 on each Proxmox)
```

### Physical Connections (Per Router)
```
Router Hardware
├── WAN Port → Switch Port N → vmbr0 (Proxmox bridge)
└── LAN Port → Switch Port N+10 → vmbr1 (Proxmox bridge)

Both cables connected before power-on and remain connected
```

## Network Migration Stages

### Stage 0: PXE Boot & Initial Setup
```
State:
- Proxmox PXE boots from LAN port (vmbr1)
- Gets DHCP: 192.168.10X.10 (where X = router number)
- Quickstart auto-runs after Proxmox installation

Network:
- vmbr0: Connected to WAN port (unused)
- vmbr1: Connected to LAN port (Proxmox management here)
```

### Stage 1: Bootstrap Creates VMs
```
State:
- Management VM created on vmbr1 (gets 192.168.10X.20)
- Semaphore & Portainer deployed
- OPNsense VM created but not started

Network:
- Proxmox: 192.168.10X.10 (on vmbr1)
- Management VM: 192.168.10X.20 (on vmbr1)
- Everything on factory network
```

### Stage 2: OPNsense Takes WAN
```
State:
- OPNsense VM starts
- WAN interface (vtnet0) connects to vmbr0
- LAN interface (vtnet1) configured as 10.10.10.1
- OPNsense now "owns" WAN port

Network:
OPNsense VM:
├── WAN (vtnet0) → vmbr0 → Physical WAN (gets factory DHCP)
└── LAN (vtnet1) → Internal bridge (10.10.10.1/24)

Still Accessible:
- Proxmox: 192.168.10X.10 (on vmbr1)
- Management VM: 192.168.10X.20 (on vmbr1)
```

### Stage 3: Migrate VMs to OPNsense LAN
```
State:
- Management VM network changed from vmbr1 to OPNsense LAN bridge
- VM gets new IP from OPNsense DHCP (10.10.20.20)
- Other service VMs follow same pattern

Network:
- Management VM: 10.10.20.20 (behind OPNsense)
- Services: 10.10.20.X (behind OPNsense)
- Proxmox still accessible: 192.168.10X.10 (on vmbr1)
```

### Stage 4: Migrate Proxmox Management
```
State:
- Proxmox management interface moved from vmbr1 to OPNsense LAN
- Gets new IP from OPNsense (10.10.20.10)
- OPNsense now owns both physical ports

Final Network:
OPNsense VM:
├── WAN (vtnet0) → vmbr0 → Physical WAN port
└── LAN (vtnet1) → vmbr1 → Physical LAN port
    ├── Proxmox mgmt: 10.10.20.10
    ├── Management VM: 10.10.20.20
    └── Other services: 10.10.20.X
```

## Critical Implementation Details

### Network Detection Requirements
- Quickstart must work with ANY factory network (192.168.X.X, 10.X.X.X, etc.)
- No hardcoded IPs in bootstrap phase
- Save detected network for later stages

### Bridge Reassignment Commands
```bash
# Stage 2: Create OPNsense with correct bridges
qm set $VMID -net0 virtio,bridge=vmbr0  # WAN
qm set $VMID -net1 virtio,bridge=vmbr1  # LAN (initially unused)

# Stage 3: Move Management VM to OPNsense LAN
qm set $MGMT_VMID -net0 virtio,bridge=opnsense-lan

# Stage 4: Move Proxmox management
# This requires careful network reconfiguration in /etc/network/interfaces
```

### OPNsense DHCP Reservations
Must pre-configure in OPNsense backup:
- 10.10.20.10: Reserved for Proxmox (MAC-based)
- 10.10.20.20: Reserved for Management VM (MAC-based)
- 10.10.20.30-50: Pool for service VMs

### Verification Points
After each stage, verify:
1. Stage 2: OPNsense WAN has factory IP
2. Stage 3: Management VM responds on 10.10.20.20
3. Stage 4: Proxmox accessible on 10.10.20.10

### Semaphore Inventory Updates
**CRITICAL**: After Stage 4 network migration, Semaphore inventories must be updated:
- All inventories created during bootstrap contain factory IPs (192.168.10X.X)
- After migration to OPNsense LAN, actual IPs are 10.10.20.X
- Must update via Semaphore API or UI:
  - container-host: Change from factory IP to 10.10.20.20
  - proxmox: Change from factory IP to 10.10.20.10
  - Any service inventories: Update to new 10.10.20.X addresses
- Without this update, Ansible playbooks will fail to connect

## Factory Process Flow

### Setup (Once per Batch)
1. Configure switch VLANs (101-110)
2. Connect all routers (both ports)
3. Prepare PXE server with custom ISO

### Per Router Process
1. **Label Print**: Serial number (XXX0-XXX9), passwords
2. **Power On**: PXE boot begins
3. **Automated**:
   - Proxmox installs
   - Quickstart runs
   - Management VM deployed
   - OPNsense created and configured
   - Network migration executes
4. **Verification**: Connect to OPNsense LAN, verify services
5. **Completion**: Ready for packaging

### Parallel Execution
- All 10 routers boot simultaneously
- Each isolated in own VLAN
- No IP conflicts possible
- Factory network agnostic (works on any subnet)

## Testing Access

During factory setup, access each router:
```bash
# During Stages 0-3 (factory network)
ssh root@192.168.101.10  # Router 1 Proxmox
ssh root@192.168.102.10  # Router 2 Proxmox

# After Stage 4 (must connect to OPNsense LAN port)
# Physical connection required to verify
ssh root@10.10.20.10  # Proxmox behind OPNsense
```

## Troubleshooting

### Common Issues
1. **Lost access after Stage 4**: Normal - must connect via OPNsense LAN
2. **DHCP timeout**: Check VLAN configuration on switch
3. **Bridge conflict**: Ensure unique bridge names per VM

### Recovery Options
- Stage 0-3: Direct access via factory network
- Stage 4: Physical console or IPMI if available
- Rollback: Revert Proxmox network config to vmbr1

## Implementation Status

### What Exists
- Network detection logic in bootstrap
- VM creation with bridge assignment
- OPNsense deployment playbooks

### What's Needed
1. **PXE Integration**: Auto-call quickstart after Proxmox install
2. **Bridge Migration Scripts**: Automate network reassignment
3. **DHCP Reservations**: Pre-configure in OPNsense backup
4. **Verification Scripts**: Test each stage completion
5. **Rollback Procedures**: Restore factory network if needed

## Security Considerations

### Factory Network
- Isolated VLANs prevent cross-contamination
- No router can see another during build
- Factory passwords temporary (replaced at customer site)

### Production Network  
- OPNsense firewall rules in place
- Management network segregated (10.10.20.0/24)
- SSH keys deployed, password auth disabled

## Next Steps

1. Remove all hardcoded IPs from codebase
2. Test VLAN isolation on ProCurve
3. Create PXE boot image with quickstart hook
4. Develop bridge migration automation
5. Build verification test suite