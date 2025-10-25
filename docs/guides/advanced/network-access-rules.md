# Advanced: Network access rules

This guide explains which services and networks are accessible from each VLAN on your PrivateBox.

---

## Quick reference

| From this VLAN | Can access | Cannot access |
|:---------------|:-----------|:--------------|
| **Trusted** (Default) | Everything - all services, internet, all other devices | Guest network |
| **Guest** | Internet only | Any local services or devices |
| **IoT Cloud** | Internet, IoT devices in same VLAN | Other VLANs, management services |
| **IoT Local** | Local devices only | Internet, other VLANs, management services |
| **Cameras Cloud** | Internet, cameras in same VLAN | Other VLANs, management services, other cameras |
| **Cameras Local** | Local access only | Internet, other VLANs, management services, other cameras |

---

## Access from trusted network (Default LAN)

When you connect to the default network (10.10.10.0/24), you have full access to:

**PrivateBox services:**
- privatebox.lan - PrivateBox dashboard
- portainer.lan - Container management (port 9000)
- semaphore.lan - Automation interface (port 3000)
- adguard.lan - DNS filtering (port 3080)
- OPNsense firewall - https://10.10.10.1

**All IoT devices:**
- Control devices on IoT Cloud (VLAN 40)
- Control devices on IoT Local (VLAN 50)

**All cameras:**
- View streams from Cameras Cloud (VLAN 60)
- View streams from Cameras Local (VLAN 70)

**Internet:**
- Full access with ad blocking

**What you can't access:**
- Guest network devices (intentional isolation)

---

## Access from guest network

When guests connect to your guest network (VLAN 30), they can access:

**Internet only:**
- Full internet access
- DNS filtering via AdGuard (automatic)

**What guests can't access:**
- PrivateBox management interfaces
- Your family computers and phones
- Your IoT devices
- Your cameras
- Any local network resources

This provides complete isolation for visitor devices.

---

## Access from iot cloud network

Devices on the IoT Cloud network (VLAN 40) can access:

**Internet:**
- Full access to cloud services
- DNS filtering via AdGuard (automatic)

**Limited local access:**
- Can respond to control commands from Trusted network
- Can communicate with other devices on same VLAN

**What IoT Cloud devices can't access:**
- PrivateBox management interfaces
- Your computers and phones on Trusted network
- Other VLANs (Guest, IoT Local, Cameras)

---

## Access from iot local network

Devices on the IoT Local network (VLAN 50) can access:

**Local only:**
- DNS resolution (for local domains)
- Time synchronization (NTP)
- Can respond to control commands from Trusted network
- Can communicate with other devices on same VLAN

**What IoT Local devices can't access:**
- Internet (completely blocked)
- PrivateBox management interfaces
- Your computers and phones on Trusted network
- Other VLANs

This network prevents IoT devices from sending data to cloud services.

---

## Access from cameras cloud network

Devices on the Cameras Cloud network (VLAN 60) can access:

**Internet:**
- Full access for cloud recording and notifications
- DNS resolution
- Time synchronization (NTP)

**Limited local access:**
- Can respond to viewing requests from Trusted network
- Can communicate with NVR/recording software on Trusted network

**What cameras can't access:**
- PrivateBox management interfaces
- Other cameras (prevents lateral movement)
- Other VLANs (IoT, Guest)

---

## Access from cameras local network

Devices on the Cameras Local network (VLAN 70) can access:

**Local only:**
- DNS resolution (for local domains)
- Time synchronization (NTP - needed for accurate timestamps)
- Can respond to viewing requests from Trusted network
- Can communicate with NVR/recording software on Trusted network

**What cameras can't access:**
- Internet (completely blocked - maximum privacy)
- PrivateBox management interfaces
- Other cameras (prevents lateral movement)
- Other VLANs

---

## Accessing privatebox services

PrivateBox web interfaces are accessible only from the Trusted network:

- **privatebox.lan** - Main dashboard
- **portainer.lan** - Container management
- **semaphore.lan** - Automation interface
- **adguard.lan** - DNS filtering configuration

To access these services, connect a device to:
- The default WiFi network (Trusted/untagged), or
- A wired port configured for the default LAN

You can't access management interfaces from Guest, IoT, or Camera networks.

---

## NVR and camera recording

If you run Network Video Recorder (NVR) software:

**Where to connect your NVR:**
- Trusted network (10.10.10.0/24)
- Not the Services VLAN (that is for PrivateBox infrastructure only)

**Camera access:**
- From Trusted network, your NVR has full access to all cameras
- Cameras on VLAN 60 (Cloud) can also send to cloud services
- Cameras on VLAN 70 (Local) are completely offline for maximum privacy

**Example setups:**
- Blue Iris, Frigate, Synology Surveillance → Connect to Trusted LAN
- Cameras → Connect to VLAN 60 (if cloud) or VLAN 70 (if local only)

---

## DNS filtering

All networks receive DNS filtering via AdGuard Home running on the Management VM (10.10.20.10):

**What gets filtered:**
- Ad servers
- Tracking domains
- Malware sites
- Phishing sites

**How to access the configuration:**
- From Trusted network: https://adguard.lan
- From other networks: DNS filtering is automatic, but you can't access the web interface

---

## Network isolation benefits

The access rules above provide these security benefits:

**Guest isolation:**
- Visitors can't access your personal devices or data
- Compromised guest devices can't attack your network

**IoT isolation:**
- Smart devices can't scan your network
- Compromised IoT devices are contained
- Local-only IoT prevents data collection

**Camera isolation:**
- Cameras can't communicate with each other
- Compromised cameras can't move laterally
- Local cameras provide maximum privacy

**Service protection:**
- Management interfaces only accessible from trusted devices
- Infrastructure services isolated from user devices
