# OPNsense Network Architecture for PrivateBox

## Overview

This document explains the network architecture for manufacturing and deploying PrivateBox units with OPNsense as the router. The key challenge is maintaining internet connectivity during setup while preparing for a completely different network configuration at the customer site.

## The Problem

During manufacturing, we need:
1. Internet access for downloading packages, updates, and configurations
2. Access to local network resources (repositories, files)
3. Ability to configure the final customer network

This creates a chicken-and-egg problem: we need the internet to build the router that will provide internet.

## The Solution: Phased Network Configuration

### Phase 1: Initial Setup (Starting Point)

```
┌─────────────────────────────────────────────────────────────────┐
│                        YOUR NETWORK                              │
│                     192.168.1.0/24                              │
│                    Gateway: 192.168.1.3                         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ Internet Access
                             │
                    ┌────────┴────────┐
                    │    Proxmox      │
                    │                 │
                    │ IP: 192.168.1.10│ ← Has internet via .3 gateway
                    │ GW: 192.168.1.3 │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │  Bootstrap VM   │
                    │    (9000)       │
                    │ IP: 192.168.1.22│ ← Can download packages
                    │ GW: 192.168.1.3 │ ← Can access internet
                    └─────────────────┘

All VMs have internet access for initial setup and downloads
```

### Phase 2: OPNsense Deployment (Transition)

```
┌─────────────────────────────────────────────────────────────────┐
│                        YOUR NETWORK                              │
│                     192.168.1.0/24                              │
│                    Gateway: 192.168.1.3                         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                ┌────────────┼────────────┐
                │            │            │
       ┌────────┴────────┐   │   ┌────────┴────────┐
       │    Proxmox      │   │   │    OPNsense     │
       │                 │   │   │   VM (8001)     │
       │ IP: 192.168.1.10│   │   │                 │
       │ GW: 192.168.1.3 │   │   │ WAN: 192.168.1.23│ ← DHCP from your network
       └─────────────────┘   │   │ LAN: 10.0.1.1   │ ← Future gateway
                             │   └────────┬────────┘
                             │            │
                    ┌────────┴────────┐   │
                    │  Bootstrap VM   │   │ vmbr1 (LAN bridge)
                    │    (9000)       │   │ 10.0.1.0/24
                    │ IP: 192.168.1.22│   │ (Not yet active)
                    └─────────────────┘   │
                                         │
                                    Isolated
                                    
During this phase:
- Proxmox still uses your network for internet
- OPNsense VM is deployed and configured
- Both networks exist but don't interfere
```

### Phase 3: Dual-Homed Configuration (Testing)

```
┌─────────────────────────────────────────────────────────────────┐
│                        YOUR NETWORK                              │
│                     192.168.1.0/24                              │
│                    Gateway: 192.168.1.3                         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────┴────────┐
                    │     vmbr0       │ WAN Bridge
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │    OPNsense     │
                    │   VM (8001)     │
                    │                 │
                    │ WAN: 192.168.1.23│ ← Internet via your network
                    │ LAN: 10.0.1.1   │ ← Gateway for internal network
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │     vmbr1       │ LAN Bridge  
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
┌────────┴────────┐ ┌────────┴────────┐ ┌───────┴────────┐
│    Proxmox      │ │  Bootstrap VM   │ │   Future VMs   │
│  (Dual-Homed)   │ │ (Dual-Homed)    │ │                │
│                 │ │                 │ │                │
│ eth0:           │ │ eth0:           │ │ IP: 10.0.1.x   │
│  192.168.1.10   │ │  192.168.1.22  │ │ GW: 10.0.1.1   │
│                 │ │                 │ │                │
│ eth1:           │ │ eth1:           │ │ Internet via   │
│  10.0.1.10      │ │  10.0.1.22     │ │ OPNsense NAT   │
└─────────────────┘ └─────────────────┘ └────────────────┘

Key Points:
- Proxmox has IPs on BOTH networks temporarily
- Can still access internet directly via 192.168.1.x
- Can test OPNsense routing via 10.0.1.x
- Bootstrap VM can be reconfigured gradually
```

### Phase 4: Final Configuration (Ready to Ship)

```
┌─────────────────────────────────────────────────────────────────┐
│                        YOUR NETWORK                              │
│                     192.168.1.0/24                              │
│                    Gateway: 192.168.1.3                         │
└────────────────────────────┬────────────────────────────────────┘
                             │
                    ┌────────┴────────┐
                    │     vmbr0       │ WAN Bridge
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │    OPNsense     │
                    │   VM (8001)     │
                    │                 │
                    │ WAN: 192.168.1.23│
                    │ LAN: 10.0.1.1   │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │     vmbr1       │ LAN Bridge  
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
┌────────┴────────┐ ┌────────┴────────┐ ┌───────┴────────┐
│    Proxmox      │ │  Bootstrap VM   │ │   Services     │
│                 │ │                 │ │                │
│ IP: 10.0.1.10   │ │ IP: 10.0.1.22   │ │ IP: 10.0.1.x   │
│ GW: 10.0.1.1    │ │ GW: 10.0.1.1    │ │ GW: 10.0.1.1   │
│                 │ │                 │ │                │
│ 192.168.1.x     │ │ Migrated to     │ │ All use        │
│ REMOVED         │ │ 10.0.1.x only   │ │ OPNsense NAT   │
└─────────────────┘ └─────────────────┘ └────────────────┘

Final Steps Before Shipping:
1. Test all services work via 10.0.1.x network
2. Verify internet access through OPNsense NAT
3. Remove 192.168.1.x configuration from Proxmox
4. Disable SSH on OPNsense WAN interface
5. Final security hardening
```

### Phase 5: Customer Deployment (At Customer Site)

```
┌─────────────────────────────────────────────────────────────────┐
│                    CUSTOMER'S ISP                                │
│                  (Any IP range/config)                          │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ DHCP/PPPoE/Static
                             │
                    ┌────────┴────────┐
                    │     vmbr0       │ (Physical NIC 1)
                    │  (WAN Bridge)   │
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │    OPNsense     │
                    │      VM         │
                    │                 │
                    │ WAN: ISP IP     │ ← Gets IP from ISP
                    │ LAN: 10.0.1.1   │ ← Same as during manufacturing
                    └────────┬────────┘
                             │
                    ┌────────┴────────┐
                    │     vmbr1       │ (Physical NIC 2)
                    │  (LAN Bridge)   │
                    └────────┬────────┘
                             │
                             │ 10.0.1.0/24 Network (DHCP Server)
                             │
         ┌───────────────────┼───────────────────────┐
         │                   │                       │
┌────────┴────────┐ ┌────────┴────────┐   ┌─────────┴─────────┐
│    Proxmox      │ │  Bootstrap VM   │   │ Customer Devices  │
│  Management     │ │    (9000)       │   │                   │
│                 │ │                 │   │ IP: 10.0.1.100+   │
│ IP: 10.0.1.10   │ │ IP: 10.0.1.22   │   │ (DHCP)           │
│ GW: 10.0.1.1    │ │ GW: 10.0.1.1    │   └───────────────────┘
└─────────────────┘ └─────────────────┘
        ↑                    ↑
        │                    │
        └────────────────────┴─── Always accessible via LAN!
```

## Key Design Principles

### 1. **Static IPs on LAN Side**
- Proxmox: `10.0.1.10` (ALWAYS)
- Bootstrap VM: `10.0.1.22` (ALWAYS)
- OPNsense LAN: `10.0.1.1` (ALWAYS)

These never change, ensuring management access.

### 2. **WAN Side is Flexible**
- Manufacturing: Gets DHCP from your network (192.168.1.x)
- Customer: Gets IP from their ISP (any range)
- OPNsense handles the translation

### 3. **No IP Conflicts**
- Your network: `192.168.1.0/24`
- PrivateBox LAN: `10.0.1.0/24`
- Different subnets = no conflicts

### 4. **Bridge Separation**
- `vmbr0`: Connected to outside world (WAN)
- `vmbr1`: Internal only (LAN)
- Physical separation prevents loops

## Configuration Steps

### 1. Proxmox Network Configuration

#### During Manufacturing (Dual-Homed)

Edit `/etc/network/interfaces` on Proxmox:

```bash
# Loopback
auto lo
iface lo inet loopback

# Management interface - YOUR NETWORK (temporary)
auto eno1
iface eno1 inet static
    address 192.168.1.10/24
    gateway 192.168.1.3
    dns-nameservers 8.8.8.8 8.8.4.4

# WAN Bridge (for VMs)
auto vmbr0
iface vmbr0 inet manual
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0

# LAN Bridge (internal network)
auto vmbr1
iface vmbr1 inet static
    address 10.0.1.10/24
    # No gateway yet - OPNsense not routing
    bridge-ports eno2
    bridge-stp off
    bridge-fd 0
```

#### Before Shipping (Final Configuration)

```bash
# Loopback
auto lo
iface lo inet loopback

# WAN Bridge (connected to outside network)
auto vmbr0
iface vmbr0 inet manual
    bridge-ports eno1
    bridge-stp off
    bridge-fd 0

# LAN Bridge (internal network) - PRIMARY MANAGEMENT
auto vmbr1
iface vmbr1 inet static
    address 10.0.1.10/24
    gateway 10.0.1.1      # OPNsense is now the gateway
    dns-nameservers 10.0.1.1
    bridge-ports eno2
    bridge-stp off
    bridge-fd 0
```

### 2. OPNsense Template Configuration

When creating OPNsense template:
- WAN (vtnet0): DHCP Client
- LAN (vtnet1): 10.0.1.1/24
- DHCP Server on LAN: 10.0.1.100-200
- DNS: Forward to AdGuard (future: 10.0.1.21)

### 3. Migration Process During Manufacturing

```bash
# Phase 1-2: Everything on your network
ssh root@192.168.1.10  # Proxmox
ssh ubuntuadmin@192.168.1.22  # Bootstrap VM

# Phase 3: Testing dual-homed
# Add secondary IPs
ssh root@192.168.1.10
ip addr add 10.0.1.10/24 dev vmbr1

# Test routing through OPNsense
ping -I vmbr1 8.8.8.8  # Should work via OPNsense NAT

# Phase 4: Switch primary access
# Update /etc/network/interfaces
# Remove 192.168.1.x config
# Reboot to apply

# Access now via OPNsense
ssh root@192.168.1.23  # OPNsense WAN
ssh root@10.0.1.10     # Proxmox via LAN
```

## Critical Notes

1. **Internet Access During Build**
   - Keep 192.168.1.x during manufacturing
   - Required for package downloads and updates
   - Only remove after everything is configured

2. **Proxmox Management Transition**
   - Start with 192.168.1.10 (has internet)
   - Add 10.0.1.10 during testing
   - Switch primary to 10.0.1.10 before shipping
   - Gateway becomes 10.0.1.1 (OPNsense)

3. **Bootstrap VM Migration**
   - Currently on 192.168.1.22
   - Can stay there during manufacturing
   - Migrate to 10.0.1.22 in Phase 3-4
   - Update Ansible inventory accordingly

4. **Service Deployments**
   - During setup: Use 192.168.1.x for downloads
   - Final config: All on 10.0.1.0/24
   - AdGuard: 10.0.1.21
   - Unbound: 10.0.1.23

5. **Order of Operations Matters**
   - Deploy OPNsense first
   - Test routing works
   - Then migrate other services
   - Remove 192.168.1.x last

## Benefits

1. **Predictable IPs**: Every PrivateBox has same internal structure
2. **No conflicts**: Different subnet from your lab
3. **Always accessible**: Management on LAN side
4. **Secure**: WAN/LAN properly separated
5. **Scalable**: Deploy many units simultaneously

## Common Issues and Solutions

### Issue: "No internet during setup"
**Cause**: Removed 192.168.1.x too early  
**Fix**: Keep dual-homed until everything downloaded

### Issue: "Can't access Proxmox after OPNsense deploy"
**Cause**: Proxmox still using 192.168.1.x gateway  
**Fix**: Add 10.0.1.10 IP and test before removing old config

### Issue: "Bootstrap VM can't download packages"
**Cause**: Migrated to 10.0.1.x but OPNsense NAT not working  
**Fix**: Keep on 192.168.1.x until OPNsense verified

### Issue: "Network loops or conflicts"
**Cause**: Both networks on same bridge  
**Fix**: Keep vmbr0 and vmbr1 completely separate

## Fixed IP Address Plan

### Standard IP Assignments (10.0.1.0/24)

Every PrivateBox deployment uses these exact IPs:

```
10.0.1.1   - OPNsense (router/firewall/gateway)
10.0.1.10  - Proxmox management interface
10.0.1.20  - Management VM (Bootstrap/Container host)
             :9000  - Portainer (container management)
             :3000  - Semaphore (Ansible UI)
             :8080  - AdGuard Home (web interface)
             :53    - AdGuard Home (DNS service)

10.0.1.100-199 - DHCP range for customer devices
```

### Why These IPs?

- **10.0.1.1**: Traditional gateway address, easy to remember
- **10.0.1.10**: Infrastructure management, gap allows for expansion
- **10.0.1.20**: Application services, gap allows for additional infrastructure

### Network Configuration

```yaml
# OPNsense DHCP Server Configuration
DHCP Range: 10.0.1.100 - 10.0.1.199
DNS Server: 10.0.1.20 (AdGuard)
Gateway: 10.0.1.1
Domain: privatebox.local

# Static DHCP Reservations (if needed)
10.0.1.10 - Proxmox (MAC-based)
10.0.1.20 - Management VM (MAC-based)
```

### Benefits of Fixed IPs

1. **Predictable**: Every deployment identical
2. **Support**: Easy troubleshooting
3. **Documentation**: One guide fits all
4. **Automation**: Ansible playbooks use fixed IPs
5. **Firewall**: Rules are consistent

## Summary

The phased approach solves the chicken-and-egg problem:
1. Start with your existing network for internet
2. Build OPNsense while maintaining connectivity
3. Gradually migrate to final network
4. Test everything before removing old config
5. Ship with clean, predictable network setup

Every PrivateBox ships with the same internal network structure, making support and maintenance straightforward.

## Infrastructure Components

### File Server (VM 7000)
- **OS**: Alpine Linux 3.22.1
- **IP**: 192.168.1.17 (static)
- **Purpose**: Hosts templates and files for deployment
- **Services**: Nginx file server
- **URLs**:
  - Web interface: http://192.168.1.17/
  - OPNsense template: http://192.168.1.17/templates/opnsense-template.qcow2

### Bootstrap/Management VM (VM 9000)
- **OS**: Ubuntu 24.04
- **IP**: 192.168.1.21 (DHCP assigned)
- **Services**:
  - Portainer: http://192.168.1.21:9000
  - Semaphore: http://192.168.1.21:3000
- **Purpose**: Ansible automation and container management

### OPNsense Template (ID 8000)
- **Type**: Proxmox template
- **OS**: OPNsense 25.7 (unconfigured)
- **Specs**: 4GB RAM, 2 cores, 16GB disk
- **Export**: 2.8GB qcow2 image

## Deployment Process

### Template Distribution
1. **Export**: OPNsense template exported as qcow2 image
2. **Host**: File server provides HTTP access to template
3. **Deploy**: Ansible playbook downloads and imports template

### Automated Deployment via Semaphore
```bash
# 1. Login to Semaphore
curl -c /tmp/semaphore-cookie -X POST \
  -H 'Content-Type: application/json' \
  -d '{"auth": "admin", "password": "YOUR_PASSWORD"}' \
  http://192.168.1.21:3000/api/auth/login

# 2. Run template sync
curl -s -b /tmp/semaphore-cookie -X POST \
  -d '{"template_id": 1, "project_id": 1}' \
  http://192.168.1.21:3000/api/project/1/tasks

# 3. Deploy OPNsense VM
curl -s -b /tmp/semaphore-cookie -X POST \
  -d '{"template_id": 4, "project_id": 1}' \
  http://192.168.1.21:3000/api/project/1/tasks
```

### Manual Deployment
```bash
# From ansible directory
./deploy-opnsense.sh [vm_id] [vm_name]

# Or with custom template URL
OPNSENSE_TEMPLATE_URL=http://192.168.1.17/templates/opnsense-template.qcow2 \
  ./deploy-opnsense.sh 101 opnsense-test
```

## Production Workflow

1. **Manufacturing Setup**:
   - Proxmox on 192.168.1.10
   - File server on 192.168.1.17 (hosts templates)
   - Bootstrap VM on 192.168.1.21 (runs automation)

2. **Deployment Steps**:
   - Run quickstart.sh on new Proxmox host
   - Bootstrap VM pulls playbooks from GitHub
   - Semaphore downloads template from file server
   - Creates OPNsense VM from template
   - Ready for network configuration

3. **Hands-Off Features**:
   - Auto-discovery of network settings
   - Automatic template download
   - No manual intervention required
   - Consistent deployments across units