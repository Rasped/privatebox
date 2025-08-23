# OPNsense Deployment Architecture

## Overview

This document describes the network topology and deployment strategy for OPNsense router instances in the PrivateBox environment. The solution is designed to work on consumer networks while supporting batch production of up to 10 units simultaneously.

## Network Topology

### Production Environment (10 units)
- **Switch**: 24-port managed or unmanaged switch (tested with HP ProCurve 2810)
- **Proxmox Hosts**: 10 physical boxes, each with 2 NICs
  - NIC 1: Management network (Proxmox access, initial setup)
  - NIC 2: Will become LAN after OPNsense takes over
- **IP Assignment**: DHCP from existing network infrastructure
- **Network Assumption**: Standard consumer /24 subnet (192.168.1.0/24 or similar)

### Per-Unit Architecture

Each physical unit contains:

1. **Proxmox Host**
   - Bridge vmbr0: Connected to NIC 1 (WAN/Management)
   - Bridge vmbr1: Connected to NIC 2 (Future LAN)
   - Accessible initially via DHCP-assigned IP on vmbr0

2. **Management VM** (Debian 13)
   - Runs on Proxmox
   - Static IP assigned during creation
   - Hosts Semaphore (port 3000) and Portainer (port 9000)
   - Orchestrates OPNsense deployment

3. **OPNsense VM**
   - Created by Semaphore automation
   - Restored from known backup image
   - Two virtual interfaces:
     - vtnet0 (WAN): Connected to vmbr0, gets DHCP from network
     - vtnet1 (LAN): Connected to vmbr1, will serve DHCP later

## Deployment Workflow

### Phase 1: Initial Setup
1. Physical units connected to switch
2. Proxmox hosts get DHCP addresses
3. Bootstrap script creates Management VM with known IP
4. Semaphore and Portainer containers start

### Phase 2: OPNsense Creation
1. Semaphore runs playbook to create OPNsense VM
2. VM created with specific or known MAC address
3. OPNsense backup restored
4. VM starts and WAN interface requests DHCP

### Phase 3: Discovery Challenge
**Problem**: OPNsense gets unknown DHCP IP on WAN. Semaphore needs to find it to complete configuration.

**Solution**: MAC-based ARP discovery

### Phase 4: Network Takeover
1. OPNsense configured via discovered IP
2. LAN side activated with DHCP server
3. Management VM switches to LAN network
4. OPNsense becomes primary router for the unit

## IP Discovery Mechanism

### Primary Method: ARP Scanning

Since we control the VM creation process, we know the MAC address of the OPNsense WAN interface. The discovery process:

1. **Wait for DHCP**: Allow 30-60 seconds for OPNsense to boot and obtain DHCP lease

2. **Network Detection**: From Management VM, identify local network:
   - Detect current subnet from Semaphore's own IP
   - Determine network range to scan

3. **Trigger ARP Population**: 
   - Perform network scan to populate ARP tables
   - This sends ARP requests to all hosts in the subnet

4. **MAC Lookup**:
   - Query local ARP table for the known MAC address
   - Extract corresponding IP address

5. **Verification**:
   - Attempt SSH connection to discovered IP
   - Verify it's the correct OPNsense instance

### Why This Works

- **Consumer Networks**: Typically single flat /24 network without VLANs
- **ARP is Fundamental**: Every IPv4 network maintains ARP mappings
- **No Special Access**: Doesn't require router/switch management access
- **Broadcast Domain**: Consumer networks allow broadcast/multicast traffic

### Limitations and Fallbacks

**Works Reliably (80% of cases)**:
- Standard home networks
- Single subnet configurations  
- Networks up to /24 size (256 addresses)
- Same broadcast domain for all VMs

**May Fail**:
- Enterprise networks with VLANs
- Networks larger than /24 (scanning becomes slow)
- Isolated network segments
- Security policies blocking ARP scanning

**Fallback Options**:
1. Manual discovery via router's DHCP client list
2. User provides IP after checking router interface
3. Physical console access for initial configuration

## Network Requirements

### Minimum Requirements
- DHCP server on network (consumer router)
- Single broadcast domain
- Network allows ARP traffic
- Subnet size /24 or smaller

### Recommended Setup
- Static DHCP reservations for predictable IPs
- Management access to DHCP server (for troubleshooting)
- Documented MAC addresses for each unit

## Security Considerations

### During Deployment
- OPNsense has default credentials during setup
- Should be on isolated or trusted network
- Change credentials immediately after discovery

### Post-Deployment  
- OPNsense becomes the security boundary
- Management VM moves behind OPNsense firewall
- WAN side properly firewalled

## Scalability Notes

### Batch Production (10 units)
- Sequential or parallel discovery supported
- Each unit has unique MAC prefix
- Semaphore can track multiple deployments
- Network scan time increases with subnet size

### Consumer Friendliness
- No router configuration required
- Works with ISP-provided equipment
- Simple enough for customer self-service
- Clear fallback instructions for edge cases

## Alternative Approaches Considered

1. **DHCP Reservations**: Requires router access, not consumer friendly
2. **Phone Home**: Would require modifying OPNsense backup
3. **mDNS/Bonjour**: Often blocked by consumer routers
4. **Static IPs**: Too complex for consumer deployment
5. **DHCP Option 61**: Requires DHCP server support

The ARP scanning approach provides the best balance of reliability, simplicity, and consumer friendliness for our target market.