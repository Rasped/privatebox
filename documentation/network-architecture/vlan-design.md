# PrivateBox VLAN Architecture Design

## Overview

This document defines the VLAN segmentation strategy for PrivateBox, designed to provide network isolation for privacy and security while maintaining ease of use for consumers. The same configuration works for both basic and advanced users - the only difference is which VLANs are actively used.

## Design Principles

1. **Consumer-Friendly**: No complex authentication or jump boxes required
2. **Privacy-Focused**: Separate untrusted devices from trusted ones
3. **Scalable**: Room for growth in each network segment
4. **Simple Management**: Trusted devices can access management interfaces
5. **Flexible Deployment**: Same configuration works with any router setup

## VLAN Assignments

### VLAN 10 - Management Network (10.10.10.0/24)

**Purpose**: Infrastructure management and administration

**IP Assignments**:
- 10.10.10.1 - OPNsense (VLAN gateway)
- 10.10.10.2 - Proxmox host (SSH port 22, Web UI port 8006)
- 10.10.10.3-20 - Reserved for managed switches and access points

**Configuration**:
- DHCP: Disabled (static IPs only)
- DNS: Points to Services VLAN (10.10.20.10)

**Access Policy**:
- Accessible from Trusted LAN only
- No access from Guest or IoT VLANs

**Rationale**: 
- Separating infrastructure reduces attack surface
- Static IPs prevent unauthorized devices
- VLAN 10 is a common convention for management networks
- Avoiding VLAN 1 prevents default VLAN security issues

### VLAN 20 - Services Network (10.10.20.0/24)

**Purpose**: PrivateBox containerized services

**IP Assignments**:
- 10.10.20.1 - OPNsense (VLAN gateway)
- 10.10.20.10 - Management VM hosting all containers:
  - Portainer (port 9000) - Container management UI
  - Semaphore (port 3000) - Ansible automation UI
  - AdGuard Home (port 8080 web, port 53 DNS) - Ad blocking and DNS
  - Consumer Dashboard (port 80/443) - Future user interface
- 10.10.20.11-20 - Reserved for additional VMs if needed

**Configuration**:
- DHCP: Disabled (static IPs only)
- All services run as containers sharing the VM's IP

**Access Policy**:
- DNS (port 53) accessible from all VLANs
- Management ports accessible from Trusted LAN only
- No access from Guest or IoT to management ports

**Rationale**:
- Containers sharing one IP simplifies networking
- Isolated VLAN prevents lateral movement from compromised IoT devices
- Central DNS ensures all devices benefit from ad blocking

### VLAN 30 - Trusted LAN (10.10.30.0/24)

**Purpose**: Family devices and trusted computers

**IP Assignments**:
- 10.10.30.1 - OPNsense (VLAN gateway)
- 10.10.30.2-99 - Static IP reservations
- 10.10.30.100-200 - DHCP pool (100 addresses)

**Configuration**:
- DHCP: Enabled
- DNS: 10.10.20.10 (AdGuard Home)
- Gateway: 10.10.30.1

**Access Policy**:
- Full access to Management VLAN (ports 22, 8006)
- Full access to Services VLAN (all service ports)
- Can control IoT devices
- Full internet access

**Rationale**:
- 100 DHCP addresses accommodate large households and growth
- Full access to management enables easy administration
- This is YOUR network - convenience over strict security

### VLAN 40 - Guest Network (10.10.40.0/24)

**Purpose**: Visitor devices with internet-only access

**IP Assignments**:
- 10.10.40.1 - OPNsense (VLAN gateway)
- 10.10.40.100-120 - DHCP pool (20 addresses)

**Configuration**:
- DHCP: Enabled
- DNS: 10.10.20.10 (AdGuard Home)
- Gateway: 10.10.40.1

**Access Policy**:
- Internet access only
- DNS to Services VLAN allowed
- No access to any other VLANs
- Isolated from all local resources

**Rationale**:
- 20 addresses sufficient for typical home guest usage
- Complete isolation protects home network
- Guests still benefit from ad blocking via DNS

### VLAN 50 - IoT Cloud (10.10.50.0/24)

**Purpose**: IoT devices requiring internet connectivity

**IP Assignments**:
- 10.10.50.1 - OPNsense (VLAN gateway)
- 10.10.50.100-200 - DHCP pool (100 addresses)

**Configuration**:
- DHCP: Enabled
- DNS: 10.10.20.10 (AdGuard Home)
- Gateway: 10.10.50.1

**Access Policy**:
- Internet access allowed
- DNS to Services VLAN allowed
- Can respond to connections from Trusted LAN
- Cannot initiate connections to other VLANs
- Isolated from other IoT devices

**Devices Examples**:
- Smart TVs and streaming devices
- Voice assistants (Alexa, Google Home)
- Cloud security cameras
- Smart thermostats
- Weather stations

**Rationale**:
- 100 addresses accommodate modern smart homes
- Internet access required for cloud services
- Isolation prevents compromised devices from attacking home network
- Separate from local IoT improves privacy

### VLAN 60 - IoT Local (10.10.60.0/24)

**Purpose**: IoT devices operating without internet access

**IP Assignments**:
- 10.10.60.1 - OPNsense (VLAN gateway)
- 10.10.60.100-200 - DHCP pool (100 addresses)

**Configuration**:
- DHCP: Enabled
- DNS: 10.10.20.10 (AdGuard Home)
- Gateway: 10.10.60.1

**Access Policy**:
- NO internet access (blocked at firewall)
- DNS to Services VLAN allowed (for local resolution)
- Can respond to connections from Trusted LAN
- Cannot initiate connections to other VLANs
- NTP allowed from OPNsense

**Device Examples**:
- Zigbee/Z-Wave hubs
- Local security cameras with NVR
- Smart switches/bulbs with local hub
- Printers
- Local media servers

**Rationale**:
- Blocking internet prevents data collection and phoning home
- Improves privacy and security significantly
- Local control is more reliable
- 100 addresses support extensive home automation

## Firewall Rules Summary

### Trusted LAN → Other VLANs
- ✅ Management: Allow SSH (22), HTTPS (8006)
- ✅ Services: Allow DNS (53), HTTP (80), HTTPS (443), Semaphore (3000), AdGuard (8080), Portainer (9000)
- ✅ IoT Cloud/Local: Allow all (to control devices)
- ❌ Guest: Deny all

### Guest → Other VLANs
- ✅ Internet: Allow all
- ✅ Services: Allow DNS (53) only
- ❌ All others: Deny all

### IoT Cloud → Other VLANs
- ✅ Internet: Allow all
- ✅ Services: Allow DNS (53) only
- ❌ All others: Deny all (stateful responses to Trusted allowed)

### IoT Local → Other VLANs
- ❌ Internet: Deny all
- ✅ Services: Allow DNS (53) and NTP (123) only
- ❌ All others: Deny all (stateful responses to Trusted allowed)

### Services → Other VLANs
- ✅ Internet: Allow (for updates)
- ❌ All others: Deny all

### Management → Other VLANs
- ✅ All: Allow all (infrastructure needs full access)

## Implementation Notes

1. **OPNsense Configuration**:
   - Configure as router-on-a-stick with VLAN subinterfaces
   - Enable DHCP server on appropriate VLANs
   - Configure firewall rules as specified
   - All 6 VLANs configured regardless of usage

2. **Proxmox Configuration**:
   - Make vmbr0 VLAN-aware
   - Tag VM interfaces with appropriate VLAN IDs
   - Management VM on VLAN 20
   - OPNsense with trunk port (all VLANs)

3. **DNS Configuration**:
   - All DHCP servers point to 10.10.20.10
   - AdGuard Home forwards to upstream DNS or Unbound
   - Local DNS resolution for *.privatebox.local

4. **Future Considerations**:
   - Consumer Dashboard will run on Management VM
   - Additional services deploy as containers
   - Room for growth in all networks

## Deployment Options

### Option 1: Standard Consumer Router Setup
For users with typical home WiFi routers:

**What to use**:
- VLAN 30 (Trusted LAN) - Connect router here, ALL devices use this network
- VLANs 40, 50 & 60 - Not accessible without VLAN-capable equipment

**Setup**:
1. Connect router (in AP mode) to OPNsense VLAN 30 port
2. All devices (family, IoT, and guests) share the same network
3. Router's "guest network" feature provides wireless-only isolation

**Limitations**:
- No true guest isolation (guests can potentially access wired devices)
- No IoT segmentation (all devices on same network)
- Router "guest network" only isolates wireless clients from each other

**What you still get**:
- ✅ Ad blocking for all devices via DNS
- ✅ Malware/tracker protection
- ✅ Service protection (management/services on separate VLANs)
- ✅ Better than typical home network
- ⚠️ Limited guest isolation (wireless only)

**Upgrade Path**: For true network segmentation, consider PrivateBox-compatible access points (see recommended hardware)

### Option 2: VLAN-Capable Access Points
For users with UniFi, Omada, or similar APs:

**What to use**:
- All 6 VLANs as designed
- Create separate SSIDs mapped to appropriate VLANs

**Setup**:
1. Configure multiple SSIDs:
   - "Home-WiFi" → VLAN 30 (Trusted)
   - "Home-Guest" → VLAN 40 (Guest)
   - "Home-IoT" → VLAN 50 (IoT Cloud)
   - "Home-NoCloud" → VLAN 60 (IoT Local)
2. Trunk port from OPNsense to AP

**Result**: Full network segmentation with maximum privacy

### Key Point: One Configuration
The same OPNsense/PrivateBox configuration handles both setups. Users can start with Option 1 and naturally upgrade to Option 2 by simply:
1. Replacing their router with VLAN-capable APs
2. Moving devices to appropriate VLANs
3. No reconfiguration of PrivateBox needed

## Security Benefits

1. **Isolation**: Compromised IoT devices cannot access trusted devices
2. **Privacy**: Local IoT devices cannot phone home
3. **Guest Protection**: Visitors cannot access home resources
4. **Service Protection**: Critical services isolated from user devices
5. **Management Security**: Infrastructure accessible only from trusted devices

## User Experience Benefits

1. **Simple Access**: No VPNs or jump boxes needed from trusted devices
2. **Transparent**: Services "just work" from home network
3. **Guest Convenience**: Easy guest access with automatic isolation
4. **IoT Flexibility**: Choose between local and cloud operation (when using VLAN APs)
5. **Growth Ready**: Plenty of IP space in each segment
6. **Easy Upgrade Path**: Start simple, add segmentation when ready

## Recommended Hardware

### For Full Network Segmentation
To utilize all security features of PrivateBox, we recommend:

**Budget Option**: TP-Link Omada
- EAP225 (~$60) - WiFi 5, sufficient for most homes
- EAP610 (~$90) - WiFi 6, better performance
- Supports 16 SSIDs with VLAN tagging

**Premium Option**: Ubiquiti UniFi
- U6-Lite (~$99) - WiFi 6, compact design
- U6-Pro (~$159) - WiFi 6, higher performance
- U6-Enterprise (~$249) - WiFi 6E, maximum performance

**PrivateBox Certified Bundle** (Coming Soon)
- Pre-configured access point
- Plug-and-play with PrivateBox
- Automatic VLAN configuration
- Premium support included

### Why Upgrade?
With VLAN-capable access points, you get:
- True guest isolation (complete network separation)
- IoT device segregation (compromised devices can't access your data)
- Local-only IoT option (devices that can't phone home)
- Full privacy protection as designed
- Same PrivateBox configuration - just more features enabled