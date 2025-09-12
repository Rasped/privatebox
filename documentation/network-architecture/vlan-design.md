# PrivateBox VLAN Architecture Design

## Overview

This document defines the VLAN segmentation strategy for PrivateBox, designed to provide network isolation for privacy and security while maintaining ease of use for consumers. The same configuration works for both basic and advanced users - the only difference is which VLANs are actively used.

## Design Principles

1. **Consumer-Friendly**: No complex authentication or jump boxes required
2. **Privacy-Focused**: Separate untrusted devices from trusted ones
3. **Scalable**: Room for growth in each network segment
4. **Simple Management**: Trusted devices can access management interfaces
5. **Flexible Deployment**: Same configuration works with any router setup

## Network Architecture

**Default LAN**: Trusted network (untagged) for maximum compatibility
**VLANs**: 6 additional networks for segmentation (Services, Guest, IoT Cloud, IoT Local, Cameras Cloud, Cameras Local)

### Network Mapping

| Interface | Network | Purpose | SSID (if wireless) | Type |
|-----------|---------|---------|-------------------|------|
| LAN (Default) | 10.10.10.0/24 | Trusted | Home-WiFi | Untagged |
| VLAN 20 | 10.10.20.0/24 | Services (Proxmox, Semaphore, Portainer, AdGuard) | (No WiFi - wired only) | Tagged |
| VLAN 30 | 10.10.30.0/24 | Guest | Home-Guest | Tagged |
| VLAN 40 | 10.10.40.0/24 | IoT Cloud | Home-IoT | Tagged |
| VLAN 50 | 10.10.50.0/24 | IoT Local | Home-NoCloud | Tagged |
| VLAN 60 | 10.10.60.0/24 | Cameras Cloud | Home-Cameras-Cloud | Tagged |
| VLAN 70 | 10.10.70.0/24 | Cameras Local | Home-Cameras-Local | Tagged |

**Note**: The default LAN uses 10.10.10.0/24 untagged for maximum compatibility with consumer routers. All VLANs use tags that match their third octet for perfect alignment and easy memorization (VLAN 20 = 10.10.20.x, VLAN 30 = 10.10.30.x, etc.).

### Default LAN - Trusted Network (10.10.10.0/24)

**Purpose**: Family devices and trusted computers

**IP Assignments**:
- 10.10.10.1 - OPNsense (LAN interface)
- 10.10.10.2-99 - Static IP reservations
- 10.10.10.100-200 - DHCP pool (100 addresses)

**Configuration**:
- DHCP: Enabled
- DNS: 10.10.20.10 (AdGuard Home)
- Gateway: 10.10.10.1

**Access Policy**:
- Full access to Services VLAN (all ports)
- Can control IoT devices
- Full internet access

**Rationale**:
- Default untagged LAN ensures compatibility with all consumer routers
- No VLAN configuration needed for basic deployments
- 100 DHCP addresses accommodate large households and growth
- Full access to services enables easy administration
- This is YOUR network - convenience over strict security

### VLAN 20 - Services Network (10.10.20.0/24)

**Purpose**: All PrivateBox services and infrastructure

**IP Assignments**:
- 10.10.20.1 - OPNsense (VLAN gateway, firewall management)
- 10.10.20.10 - Management VM (Debian 13 running all containerized services)
  - AdGuard Home: Port 53 (DNS), Port 3080 (Web UI)
  - Portainer: Port 9000 (Web UI)
  - Semaphore: Port 3000 (Web UI)
- 10.10.20.20 - Proxmox (Hypervisor - SSH port 22, Web UI port 8006)
- 10.10.20.30-99 - Reserved for future services

**Configuration**:
- DHCP: Disabled (all static IPs for stability)
- No DHCP server - critical services require predictable addresses

**Access Policy**:
- DNS (port 53) accessible from all VLANs
- Management ports accessible from Trusted LAN only
- No access from Guest or IoT to management ports

**Rationale**: 
- Static IPs ensure services are always at known addresses
- No DHCP prevents IP hijacking or conflicts
- All services on Management VM simplifies backup/restore
- OPNsense management accessible at .1 on this VLAN
- Proxmox at .20 for management access via Services VLAN

### VLAN 30 - Guest Network (10.10.30.0/24)

**Purpose**: Visitor devices with internet-only access

**IP Assignments**:
- 10.10.30.1 - OPNsense (VLAN gateway)
- 10.10.30.100-120 - DHCP pool (20 addresses)

**Configuration**:
- DHCP: Enabled
- DNS: 10.10.20.10 (AdGuard Home)
- Gateway: 10.10.30.1

**Access Policy**:
- Internet access only
- DNS to Services VLAN allowed
- No access to any other VLANs
- Isolated from all local resources

**Rationale**:
- 20 addresses sufficient for typical home guest usage
- Complete isolation protects home network
- Guests still benefit from ad blocking via DNS

### VLAN 40 - IoT Cloud (10.10.40.0/24)

**Purpose**: IoT devices requiring internet connectivity

**IP Assignments**:
- 10.10.40.1 - OPNsense (VLAN gateway)
- 10.10.40.100-200 - DHCP pool (100 addresses)

**Configuration**:
- DHCP: Enabled
- DNS: 10.10.20.10 (AdGuard Home)
- Gateway: 10.10.40.1

**Access Policy**:
- Internet access allowed
- DNS to Services VLAN allowed
- Can respond to connections from Trusted LAN
- Cannot initiate connections to other VLANs
- Isolated from other IoT devices

**Devices Examples**:
- Smart TVs and streaming devices
- Voice assistants (Alexa, Google Home)
- Smart thermostats
- Weather stations
- Cloud-connected appliances

**Rationale**:
- 100 addresses accommodate modern smart homes
- Internet access required for cloud services
- Isolation prevents compromised devices from attacking home network
- Separate from local IoT improves privacy

### VLAN 50 - IoT Local (10.10.50.0/24)

**Purpose**: IoT devices that work locally without cloud

**IP Assignments**:
- 10.10.50.1 - OPNsense (VLAN gateway)
- 10.10.50.100-200 - DHCP pool (100 addresses)

**Configuration**:
- DHCP: Enabled
- DNS: 10.10.20.10 (AdGuard Home)
- Gateway: 10.10.50.1

**Access Policy**:
- NO internet access (blocked at firewall)
- DNS to Services VLAN allowed
- NTP to Services VLAN allowed
- Can respond to connections from Trusted LAN
- Cannot initiate connections to other VLANs
- Isolated from other IoT devices

**Devices Examples**:
- Home Assistant controlled devices
- Zigbee/Z-Wave devices
- Local-only smart plugs
- Offline automation devices
- Devices flashed with Tasmota/ESPHome

**Rationale**:
- Blocking internet prevents data collection and phoning home
- Improves privacy and security significantly
- Local control is more reliable
- 100 addresses support extensive home automation

### VLAN 60 - Cameras Cloud (10.10.60.0/24)

**Purpose**: Security cameras requiring cloud connectivity

**IP Assignments**:
- 10.10.60.1 - OPNsense (VLAN gateway)
- 10.10.60.100-150 - DHCP pool (50 addresses)

**Configuration**:
- DHCP: Enabled
- DNS: 10.10.20.10 (AdGuard Home)
- Gateway: 10.10.60.1

**Access Policy**:
- Internet access allowed (for cloud services)
- DNS to Services VLAN allowed
- NTP to Services VLAN allowed (critical for timestamps)
- Can respond to connections from Trusted LAN
- Cannot initiate connections to other VLANs
- Isolated from other cameras (no camera-to-camera)

**Device Examples**:
- Ring cameras and doorbells
- Nest/Google cameras
- Arlo cameras
- Wyze cameras
- Blink cameras
- Any camera with cloud recording/AI features

**Rationale**:
- Separate from IoT due to privacy implications
- Cloud access enables mobile notifications and AI detection
- Isolation prevents compromised camera from network scanning
- 50 addresses sufficient for typical home camera deployments

### VLAN 70 - Cameras Local (10.10.70.0/24)

**Purpose**: Security cameras with local-only recording

**IP Assignments**:
- 10.10.70.1 - OPNsense (VLAN gateway)
- 10.10.70.100-150 - DHCP pool (50 addresses)

**Configuration**:
- DHCP: Enabled
- DNS: 10.10.20.10 (AdGuard Home)
- Gateway: 10.10.70.1

**Access Policy**:
- NO internet access (blocked at firewall)
- DNS to Services VLAN allowed (for local resolution)
- NTP to Services VLAN allowed (critical for timestamps)
- Can respond to connections from Trusted LAN
- Cannot initiate connections to other VLANs
- Isolated from other cameras (no camera-to-camera)

**Device Examples**:
- IP cameras with local NVR (Blue Iris, Frigate, Synology)
- ONVIF/RTSP cameras
- Reolink cameras (local mode)
- Amcrest cameras (local mode)
- UniFi Protect cameras (local mode)
- Any camera used purely for local recording

**NVR Connection Note**:
- NVR devices/software connect to Trusted LAN (10.10.10.0/24)
- From Trusted LAN, NVRs have full access to camera streams
- Services VLAN is for PrivateBox infrastructure only, not user NVRs

**Rationale**:
- Maximum privacy - no data leaves your network
- NVR access via Trusted LAN maintains proper separation
- Prevents any telemetry or firmware auto-updates
- 50 addresses sufficient for home deployments

## Firewall Rules Summary

### Trusted LAN (Default) → Other VLANs
- ✅ Services: Allow all ports (SSH, Proxmox 8006, DNS 53, HTTP 80/443, Semaphore 3000, AdGuard 3080, Portainer 9000)
- ✅ IoT Cloud/Local: Allow all (to control devices)
- ✅ Cameras Cloud/Local: Allow all (to view streams and configure)
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

### Cameras Cloud → Other VLANs
- ✅ Internet: Allow all
- ✅ Services: Allow DNS (53) and NTP (123) only
- ❌ All others: Deny all (stateful responses to Trusted allowed)
- ❌ Other cameras: Deny all (prevent lateral movement)

### Cameras Local → Other VLANs
- ❌ Internet: Deny all
- ✅ Services: Allow DNS (53) and NTP (123) only
- ❌ All others: Deny all (stateful responses to Trusted allowed)
- ❌ Other cameras: Deny all (prevent lateral movement)

### Services → Other VLANs
- ✅ Internet: Allow (for updates)
- ❌ All others: Deny all (Services VLAN is infrastructure only, not for user services)


## Implementation Notes

1. **OPNsense Configuration**:
   - Deployed from template: [v1.0.0-opnsense](https://github.com/Rasped/privatebox/releases/tag/v1.0.0-opnsense)
   - Two physical interfaces: WAN (vmbr0) and LAN (vmbr1)
   - LAN interface (vtnet1) configured as 10.10.10.1/24 (Trusted)
   - VLANs carried as tagged subinterfaces on vtnet1
   - Enable DHCP server on appropriate VLANs
   - Configure firewall rules as specified
   - LAN plus 6 VLANs configured regardless of usage

2. **Proxmox Configuration**:
   - vmbr0: WAN bridge (not VLAN-aware, direct internet connection)
   - vmbr1: LAN bridge (VLAN-aware, carries internal VLANs)
   - Management VM and Proxmox on VLAN 20 (Services)
   - OPNsense VM with two NICs:
     - NIC1: vmbr0 (WAN)
     - NIC2: vmbr1 (LAN trunk with all VLANs)

3. **DNS Configuration**:
   - All DHCP servers point to 10.10.20.10 (Management VM)
   - AdGuard Home running on Management VM handles all DNS
   - Local DNS resolution for *.privatebox.local
   - Upstream DNS to Cloudflare or other providers

4. **Future Considerations**:
   - Consumer Dashboard will run on Management VM
   - Additional services deploy as containers
   - Room for growth in all networks

## Deployment Options

### Option 1: Standard Consumer Router Setup
For users with typical home WiFi routers:

**What to use**:
- Default LAN (Trusted) - Connect router here, ALL devices use this network  
- VLANs - Not accessible without VLAN-capable equipment

**Setup**:
1. Connect router (in AP mode) to OPNsense LAN port
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
- Default LAN plus all 6 VLANs as designed
- Create separate SSIDs mapped to appropriate VLANs

**Setup**:
1. Configure multiple SSIDs:
   - "Home-WiFi" → Default LAN (Trusted)
   - "Home-Guest" → VLAN 30 (Guest)
   - "Home-IoT" → VLAN 40 (IoT Cloud)
   - "Home-NoCloud" → VLAN 50 (IoT Local)
   - "Home-Cameras" → VLAN 60/70 (based on cloud preference)
2. Connect AP to OPNsense LAN port configured as trunk

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

### Access Point VLAN Configuration

When configuring VLAN-capable access points, use these settings:

**Trunk Port Configuration** (AP uplink to switch/OPNsense):
- Native/Untagged VLAN: 10 (maps to Trusted LAN)
- Tagged VLANs: 20, 30, 40, 50, 60, 70
- Management VLAN: 10 (for AP management interface)

**SSID to VLAN Mapping**:
```
SSID: Home-WiFi         → Untagged (Trusted LAN)
SSID: Home-Guest        → VLAN Tag: 30  
SSID: Home-IoT          → VLAN Tag: 40
SSID: Home-NoCloud      → VLAN Tag: 50
SSID: Home-Cameras      → VLAN Tag: 60 or 70
```

**Switch Port Example** (Cisco/HP syntax):
```
interface GigabitEthernet0/1
  description Access-Point-Uplink
  switchport mode trunk
  switchport trunk native vlan 10
  switchport trunk allowed vlan 10,20,30,40,50,60,70
  no shutdown
```

**UniFi Controller Example**:
- Networks: Create networks with VLAN IDs 20, 30, 40, 50, 60, 70 (10 is native/untagged)
- Wireless Networks: Assign each SSID to corresponding network/VLAN
- AP Port Profile: Set to "All" or custom trunk profile

**TP-Link Omada Example**:
- LAN: Create VLANs 20, 30, 40, 50, 60, 70
- Wireless: Create SSIDs and set VLAN ID for each
- Port Config: Set AP port to "Trunk" with all VLANs

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