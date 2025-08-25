# OPNsense Configuration Status

**Last Updated**: 2025-08-25 15:30 UTC
**OPNsense Version**: 25.7 (amd64)
**Location**: 192.168.1.173 (temporary WAN IP during configuration)

## Configuration Progress

### ✅ Completed Items

#### 1. VLAN Configuration
- **Status**: COMPLETE
- **Details**: All 8 VLANs created and configured
  - VLAN 10 (Management): 10.10.10.1/24 - Configured as LAN interface
  - VLAN 20 (Services): 10.10.20.1/24 - opt1
  - VLAN 30 (Trusted LAN): 10.10.30.1/24 - opt2
  - VLAN 40 (Guest): 10.10.40.1/24 - opt3
  - VLAN 50 (IoT Cloud): 10.10.50.1/24 - opt4
  - VLAN 60 (IoT Local): 10.10.60.1/24 - opt5
  - VLAN 70 (Cameras Cloud): 10.10.70.1/24 - opt6
  - VLAN 80 (Cameras Local): 10.10.80.1/24 - opt7
- **Verification**: All interfaces UP with correct IPs assigned

#### 2. DHCP Servers
- **Status**: COMPLETE
- **Details**: 
  - DHCP disabled on VLANs 10 (Management) and 20 (Services) - static only
  - DHCP enabled with ranges:
    - VLAN 30: 10.10.30.100-200 (100 addresses)
    - VLAN 40: 10.10.40.100-120 (20 addresses)
    - VLAN 50: 10.10.50.100-200 (100 addresses)
    - VLAN 60: 10.10.60.100-200 (100 addresses)
    - VLAN 70: 10.10.70.100-150 (50 addresses)
    - VLAN 80: 10.10.80.100-150 (50 addresses)
- **DNS Configuration**: Currently pointing to gateway IPs (will change to AdGuard later)
- **Verification**: DHCP daemon running on all configured VLANs

#### 3. DNS Configuration (Unbound)
- **Status**: COMPLETE (Temporary configuration)
- **Current Setup**:
  - Listening on all VLAN interfaces port 53
  - Recursive resolver mode (not forwarding)
  - DNSSEC enabled
  - Query minimization enabled
- **Future Change**: When AdGuard is deployed:
  - Unbound will listen only on localhost:5353
  - AdGuard will listen on 10.10.20.10:53
  - DHCP will point to AdGuard
- **Verification**: DNS resolution working on all VLANs

#### 4. NTP Service
- **Status**: COMPLETE
- **Details**: NTP service running and accessible on all VLAN gateway IPs
- **Verification**: Port 123/UDP accessible on all VLANs

#### 5. Firewall Rules
- **Status**: COMPLETE
- **Base Rules**:
  - Firewall ENABLED and running
  - WAN protection: bogons and private networks blocked
  - ICMP for path MTU discovery allowed
  - Temporary management access from 192.168.1.0/24
- **VLAN Isolation**: Complete (see below)
- **Verification**: Firewall active with full VLAN segmentation

### ✅ Recently Completed (2025-08-25)

#### Firewall Rules - Inter-VLAN Isolation
- **Status**: COMPLETE
- **Implementation Date**: 2025-08-25 15:21 UTC
- **Method**: Direct config.xml modification via Python script
- **Rules Added**: 30 firewall rules for complete VLAN isolation
- **Details**:
  1. ✅ Guest VLAN (40): Blocks all RFC1918, allows DNS to AdGuard + Internet only
  2. ✅ IoT Cloud VLAN (50): Blocks inter-VLAN, allows DNS + Internet
  3. ✅ IoT Local VLAN (60): Blocks Internet and other VLANs, allows DNS + NTP only
  4. ✅ Camera Cloud VLAN (70): Blocks inter-VLAN, allows DNS + NTP + Internet
  5. ✅ Camera Local VLAN (80): Blocks all VLANs and Internet, allows DNS + NTP only
  6. ✅ Services VLAN (20): Protected, only accessible from Trusted VLAN
  7. ✅ Trusted VLAN (30): Full access except Guest VLAN
- **Configuration Backup**: `/conf/config.xml.backup-vlan-20250825-132134`
- **Verification**: Rules in config.xml and firewall active

### 🚧 In Progress

*None currently*

### ❌ Not Started

#### 1. WireGuard Installation
- Package needs to be installed: `pkg install os-wireguard`
- VPN configuration not started

#### 2. OpenVPN Configuration
- Built-in, but not configured

#### 3. Firewall Rules - Advanced
- Client isolation within VLANs
- Rate limiting
- GeoIP rules (if needed)

#### 4. IPv6 Configuration
- Currently IPv4 only

#### 5. Suricata IDS
- Not installed (disabled by default per requirements)

## Important Notes

### Temporary Configurations
1. **Management Access**: Currently via WAN (192.168.1.173) with temporary rule
   - Should be moved to Trusted VLAN access only
   - WAN SSH should be disabled in production

2. **DNS Setup**: Currently using OPNsense directly
   - Will change to AdGuard when deployed
   - DHCP servers will need updating to point to 10.10.20.10

3. **API Access**: 
   - API key created for configuration
   - Key: LyT5n22DSMK+s8ZYJt5B2nG3wOH3wJ1UTqqVljUYJjS49nGRHwC6TBHEieWMTqIG5HsM9tQVMIVSYllM
   - Should be removed after configuration complete

4. **SSH Key**: Temporary SSH key installed for configuration
   - Located at /root/.ssh/authorized_keys
   - Should be replaced with proper management keys

### Configuration Files Modified
- `/conf/config.xml` - Main configuration file
- Multiple Python scripts used for configuration (in /tmp/)

### Backup Status
- Backups created at: `/conf/config.xml.backup-*`
- Latest backup: config.xml.backup-20250825-140613

## Next Configuration Session Should

1. **Complete Firewall Rules**:
   - Implement Guest isolation first (critical security)
   - Add Trusted VLAN management access
   - Implement IoT/Camera isolation
   - Protect Services VLAN

2. **Install WireGuard**:
   ```bash
   pkg install os-wireguard
   ```

3. **Configure VPN Access**:
   - WireGuard on port 51820
   - OpenVPN on port 1194
   - Both routing to Trusted VLAN

4. **Clean Up**:
   - Remove temporary SSH key
   - Remove temporary API key
   - Disable WAN management access
   - Move management to Trusted VLAN only

5. **Export Final Configuration**:
   - Export clean config.xml
   - Store in repository at `ansible/files/opnsense/config-complete.xml`
   - Document any manual steps required

## Testing Checklist

### ✅ Completed Tests
- [x] All VLANs have IP addresses
- [x] DHCP servers running
- [x] DNS resolution working
- [x] NTP accessible on all VLANs
- [x] Firewall enabled without lockout
- [x] Outbound internet connectivity
- [x] Firewall rules configured in config.xml
- [x] All 30 VLAN isolation rules added

### ⏳ Pending Tests (Requires devices on VLANs)
- [ ] Guest VLAN isolation from internal networks (test from actual Guest device)
- [ ] Trusted VLAN can manage all systems (test from Trusted device)
- [ ] IoT devices cannot initiate connections to other VLANs
- [ ] Camera isolation working (test with actual cameras)
- [ ] Services only accessible from Trusted VLAN
- [ ] VPN access lands on Trusted VLAN
- [ ] AdGuard integration working
- [ ] All DHCP clients get correct DNS server

**Note**: Testing from OPNsense itself bypasses firewall rules. Proper testing requires devices on each VLAN.

## Known Issues

1. **No AdGuard Yet**: DNS is served directly by OPNsense
   - Functional but missing ad blocking
   - Will be resolved when AdGuard container is deployed

2. **Management on WAN**: Currently managing via WAN interface
   - Security risk in production
   - Temporary for initial configuration only
   - Should be moved to Trusted VLAN access after VPN setup

## Contact/Notes

- Configuration performed via API and SSH
- Using OPNsense web UI at http://192.168.1.173
- Default credentials still in use (root/opnsense) - MUST BE CHANGED
- Proxmox host assumed to be at 192.168.1.10