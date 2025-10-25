---
status: implemented
implemented_in: v1.0.0
category: networking
complexity: medium
dependencies:
  - opnsense
maintenance_priority: high
last_updated: 2025-10-24
---

# OPNsense Configuration Requirements

> **Implementation Status**: See [opnsense-configuration-status.md](./opnsense-configuration-status.md) for current configuration progress and completed items.

## Overview

This document defines the comprehensive OPNsense configuration requirements for PrivateBox. The configuration prioritizes "good enough" security and privacy that significantly improves protection without disrupting normal home network operations.

## Design philosophy

- **Good Enough Security**: 80% protection with 20% complexity
- **Privacy First**: Full tunnel VPN, recursive DNS, ad blocking
- **User Friendly**: No captive portals, sensible defaults
- **Performance Conscious**: Optimized for Intel N100 hardware
- **Maintainable**: Avoid complex rule sets that require constant updates

## Network architecture

### Physical interfaces
- **WAN**: vmbr0 - External internet connection
- **LAN**: vmbr1 - Internal VLAN-aware bridge

### Network configuration
OPNsense uses the default LAN interface for Trusted devices and VLANs for network segmentation:

| Interface | IP Address | Purpose | Type |
|-----------|------------|---------|------|
| LAN (vtnet1) | 10.10.10.1/24 | Trusted | Untagged (Default) |
| VLAN 20 | 10.10.20.1/24 | Services (Proxmox, Semaphore, Portainer, AdGuard) | Tagged |
| VLAN 30 | 10.10.30.1/24 | Guest | Tagged |
| VLAN 40 | 10.10.40.1/24 | IoT Cloud | Tagged |
| VLAN 50 | 10.10.50.1/24 | IoT Local | Tagged |
| VLAN 60 | 10.10.60.1/24 | Cameras Cloud | Tagged |
| VLAN 70 | 10.10.70.1/24 | Cameras Local | Tagged |

## DHCP server configuration

### DHCP disabled (Static Only)
- VLAN 20 (Services) - Static IPs only for infrastructure

### DHCP enabled vlans

All DHCP-enabled VLANs use:
- **DNS Server**: 10.10.20.10 (AdGuard Home)
- **Gateway**: Interface IP for each VLAN
- **Domain**: privatebox.local
- **NTP Server**: Interface IP for each VLAN

Specific IP pools:
- **LAN** (Trusted): 10.10.10.100-200 (100 addresses)
- **VLAN 30** (Guest): 10.10.30.100-120 (20 addresses)
- **VLAN 40** (IoT Cloud): 10.10.40.100-200 (100 addresses)
- **VLAN 50** (IoT Local): 10.10.50.100-200 (100 addresses)
- **VLAN 60** (Cameras Cloud): 10.10.60.100-150 (50 addresses)
- **VLAN 70** (Cameras Local): 10.10.70.100-150 (50 addresses)

## DNS Configuration (Unbound)

### DNS Architecture
- **Flow**: Clients → AdGuard (10.10.20.10) → OPNsense Unbound → Root servers
- **Mode**: Recursive resolver (not forwarder)
- **Local Domain**: privatebox.local

### Unbound settings
- **Enable**: DNSSEC validation
- **Query Name Minimization**: Yes (privacy enhancement)
- **Prefetch Support**: Yes (performance)
- **Cache**: Moderate (respect 1-2 hour TTLs)
- **Logging**: Minimal (privacy)
- **Listen Interface**: Localhost only (AdGuard forwards to it)
- **Private Domains**: privatebox.local
- **Rebind Protection**: Disable for RFC1918 (needed for local DNS)

## VPN Configuration

### WireGuard (Road Warrior)
- **Port**: 51820 (default)
- **Tunnel Network**: 10.10.100.0/24
- **Interface Assignment**: Route to Trusted LAN (10.10.10.0/24)
- **DNS**: Push 10.10.20.10 to clients
- **Allowed IPs**: 0.0.0.0/0 (full tunnel)
- **Keepalive**: 25 seconds (mobile friendly)
- **MTU**: 1420 (optimal for most connections)

### OpenVPN (Road Warrior)
- **Port**: 1194 UDP (default)
- **Tunnel Network**: 10.10.101.0/24
- **Interface Assignment**: Route to Trusted LAN (10.10.10.0/24)
- **DNS**: Push 10.10.20.10 to clients
- **Redirect Gateway**: Yes (full tunnel)
- **Compression**: Disabled (security)
- **Cipher**: AES-256-GCM
- **TLS Version**: 1.2 minimum
- **MTU**: 1500, Fragment at 1300

### VPN user management
- Create individual certificates per user
- No shared credentials
- Reasonable key sizes (2048-bit RSA or Ed25519)

## Firewall rules

### Floating rules (Applied First)
- Allow DNS (port 53) from all VLANs to 10.10.20.10
- Allow NTP (port 123) from VLANs 50, 60, 70 to their gateways
- Block bogon networks on WAN
- Block private networks on WAN

### WAN Rules
- Default deny all inbound
- Allow established connections
- Allow ICMP for path MTU discovery
- Log blocked attempts (for reports)

### Trusted LAN (Default LAN interface, untagged)
- Allow all outbound
- Allow all to Services VLAN (20)
- Allow all to IoT VLANs (control devices)
- Allow all to Camera VLANs (view streams)
- Block to Guest VLAN

### Services VLAN (20)
- Allow all outbound (for updates and infrastructure management)
- Allow DNS (53) from all VLANs
- Allow service ports from Trusted LAN only:
  - Proxmox Web UI (8006)
  - Portainer (9000)
  - Semaphore (3000)
  - AdGuard Admin (8080)
  - SSH to Proxmox (22)
  - Future dashboard (80/443)

### Guest VLAN (30)
- Allow internet (WAN) only
- Allow DNS to Services VLAN
- Block all inter-VLAN traffic
- Enable isolation (clients can't see each other)

### IoT cloud VLAN (40)
- Allow internet (WAN)
- Allow DNS to Services VLAN
- Allow established connections from Trusted LAN
- Block initiated connections to other VLANs
- Block inter-device communication

### IoT local VLAN (50)
- Block internet (WAN)
- Allow DNS to Services VLAN
- Allow NTP to gateway
- Allow established connections from Trusted LAN
- Block initiated connections to other VLANs
- Block inter-device communication

### Cameras cloud VLAN (60)
- Allow internet (WAN)
- Allow DNS and NTP to Services VLAN
- Allow established connections from Trusted LAN
- Block initiated connections to other VLANs
- Block camera-to-camera communication

### Cameras local VLAN (70)
- Block internet (WAN)
- Allow DNS and NTP to Services VLAN
- Allow connections from Services VLAN (for NVR)
- Allow established connections from Trusted LAN
- Block initiated connections to other VLANs
- Block camera-to-camera communication

## NAT Configuration

### Outbound NAT
- **Mode**: Automatic
- **Applies to**: All internal VLANs
- **Translation**: Interface address

### Port forwarding
- **None by default** (all access via VPN)
- Document process for game consoles if needed

### NAT Reflection
- **Enable**: For split-brain DNS scenarios
- **Mode**: Pure NAT

## System configuration

### General settings
- **Hostname**: opnsense
- **Domain**: privatebox.local
- **DNS Servers**: 127.0.0.1 (use local Unbound)
- **Time Zone**: UTC (adjust per deployment)
- **NTP Service**: Enabled for all VLANs

### Performance tuning (N100 Optimized)
- **Firewall Optimization**: Normal
- **State Table Size**: 400,000
- **Firewall Adaptive Timeouts**: Enabled
- **Hardware Offloading**: Enable if available
- **Power Profile**: Balanced
- **Network Interfaces**: Disable LRO, enable VLAN hardware filtering

### IPv6 configuration
- **WAN**: Track interface (get prefix from ISP)
- **LAN VLANs**: DHCPv6 with prefix delegation
- **Privacy Extensions**: Enabled
- **Temporary Address**: Rotate daily
- **Firewall**: Default deny inbound, allow outbound

## Security features

### Intrusion detection (Suricata)
- **Status**: Installed but DISABLED by default
- **Rationale**: Avoid performance impact and false positives
- **Documentation**: Include enablement guide for power users

If enabled by user:
- **Mode**: IDS only (detect, don't block)
- **Interface**: WAN only
- **Rules**: ET Open (emerging-malware, emerging-exploits only)
- **Pattern Matcher**: Hyperscan
- **Max Memory**: 2GB
- **Stream Bypass**: Over 100Mbps

### Access control
- **Web GUI**: HTTPS only from Trusted LAN and Services VLAN
- **SSH**: Disabled on WAN, key-only from Trusted LAN
- **Anti-lockout**: Enabled on LAN interface
- **Login Protection**: 5 attempts, 15-minute lockout

### Logging
- **Firewall Logs**: Enabled for denied packets
- **Retention**: 30 days local
- **Remote Logging**: Optional syslog to Management VM
- **Privacy**: No DNS query logging

## Service integration

### AdGuard integration
- All DHCP servers point to 10.10.20.10
- Unbound listens on localhost only
- AdGuard forwards to 127.0.0.1:5353 (Unbound)
- Allow DNS override by clients (user choice)

### Time service
- OPNsense provides NTP to all VLANs
- Critical for camera timestamps
- Critical for certificate validation

## Backup and recovery

### Configuration management
- **Auto-backup**: Daily to Services VLAN
- **History**: Keep 30 versions
- **Before Changes**: Manual backup reminder
- **Export Format**: Encrypted XML

### Restoration process
1. Install base OPNsense
2. Restore config.xml
3. Regenerate VPN certificates
4. Verify interface assignments

## Package requirements

### Built-in (No installation Required)
- OpenVPN
- Unbound DNS
- DHCP Server
- NTP Server
- WireGuard (built-in since OPNsense 24.1)

### Optional (Documented)
- os-suricata (IDS/IPS - disabled by default)
- os-ddclient (dynamic DNS)
- os-acme-client (Let's Encrypt)

## Implementation notes

### Configuration process flow

#### Phase 1: comprehensive config creation (One-time)
1. Deploy fresh OPNsense from ISO
2. Complete initial wizard (WAN/LAN assignment)
3. Configure all settings per this document manually:
   - All 6 VLANs plus default LAN
   - Firewall rules for each VLAN
   - Unbound DNS recursive resolver
   - DHCP servers
   - VPN configurations
   - System optimizations
4. Export comprehensive config.xml (System → Configuration → Backups)
5. Store this comprehensive config.xml in GitHub repository

#### Phase 2: automated deployment (Per-installation)

1. **Initial Bootstrap**
   - Deploy OPNsense VM (fresh install or from template)
   - Apply minimal config.xml (from GitHub)
   - Minimal config provides:
     - SSH password access on WAN (temporary)
     - Basic network connectivity
     - Admin account for automation

2. **Ansible Playbook Execution**
   - Connect via SSH using temporary WAN access
   - Generate and install SSH keys
   - Create Semaphore inventory entry
   - Create Semaphore environment
   - Configure Semaphore project for OPNsense management

3. **Semaphore Configuration Push**
   - Semaphore applies comprehensive config.xml
   - This replaces minimal config with full configuration:
     - All VLANs activated
     - Firewall rules applied
     - SSH moved to Trusted LAN only (WAN SSH disabled)
     - Key-only authentication enforced
     - All security policies activated
   - System automatically reboots

4. **Post-Configuration Tasks** (via Semaphore/Ansible)
   - Install additional packages if needed
   - Generate VPN certificates (unique per deployment)
   - Create initial admin VPN user
   - Set deployment-specific variables
   - Download Suricata rules (if user enables it later)

#### What's in config.xml (Automated)
- ✅ All VLAN interfaces and IPs
- ✅ Firewall rules and aliases  
- ✅ DHCP server configurations
- ✅ DNS (Unbound) settings
- ✅ NAT configuration
- ✅ VPN server settings (but not certificates)
- ✅ System settings and optimizations
- ✅ User accounts and permissions
- ✅ Package configurations (even if package not yet installed)

#### What requires Post-Configuration
- ⚙️ Optional package installation (Suricata if desired)
- ⚙️ VPN certificate generation (unique per install)
- ⚙️ VPN user creation (deployment-specific)
- ⚙️ Suricata rule downloads (if enabled)
- ⚙️ ACME certificates (if using Let's Encrypt)
- ⚙️ Dynamic DNS setup (if needed)
- ⚙️ Site-specific WAN configuration

### Deployment method
1. Configure OPNsense manually with these settings
2. Export configuration
3. Create VM template
4. Store template and config.xml in repository
5. Automate deployment via API/SSH

### Post-Deployment tasks
- Generate unique VPN certificates
- Create initial VPN user accounts
- Verify VLAN connectivity
- Test firewall rules
- Document any site-specific changes

### Testing checklist
- [ ] Each VLAN can reach its assigned DNS
- [ ] Trusted devices can manage infrastructure
- [ ] Guest devices isolated from local network
- [ ] IoT Local devices cannot reach internet
- [ ] Cameras cannot communicate with each other
- [ ] VPN clients land on Trusted LAN
- [ ] AdGuard receives all DNS queries
- [ ] NTP available to all devices

## Excluded features

These features were considered but excluded for simplicity:

- **Captive Portal**: No login pages for guests
- **Traffic Shaping**: CPU intensive on N100
- **Deep Packet Inspection**: Breaks encrypted traffic
- **GeoIP Blocking**: Can break CDNs and services
- **Suricata IPS Mode**: Too many false positives
- **Complex Bypass Rules**: Maintenance burden

## Future considerations

- High Availability (CARP) for dual router setup
- API automation for rule updates
- Integration with threat intelligence feeds
- Bandwidth monitoring and reporting
- VPN user self-service portal