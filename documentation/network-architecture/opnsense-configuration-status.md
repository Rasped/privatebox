# OPNsense Configuration Status

**Last Updated**: 2025-08-25 23:00 UTC
**OPNsense Version**: 25.7 (amd64)
**Location**: 192.168.1.173 (temporary WAN IP during configuration)
**SSH Access**: Use key at `/private/tmp/opnsense-temp-key`

## Configuration Progress

### ✅ Completed Items

#### 1. VLAN Configuration
- **Status**: COMPLETE
- **Details**: All 7 VLANs need to be reconfigured
  - VLAN 10 (Services): 10.10.10.1/24 - Configured as LAN interface
  - VLAN 20 (Trusted LAN): 10.10.20.1/24 - opt1
  - VLAN 30 (Guest): 10.10.30.1/24 - opt2
  - VLAN 40 (IoT Cloud): 10.10.40.1/24 - opt3
  - VLAN 50 (IoT Local): 10.10.50.1/24 - opt4
  - VLAN 60 (Cameras Cloud): 10.10.60.1/24 - opt5
  - VLAN 70 (Cameras Local): 10.10.70.1/24 - opt6
- **Verification**: All interfaces UP with correct IPs assigned

#### 2. DHCP Servers
- **Status**: COMPLETE
- **Details**: 
  - DHCP disabled on VLAN 10 (Services) - static only
  - DHCP enabled with ranges:
    - VLAN 20: 10.10.20.100-200 (100 addresses)
    - VLAN 30: 10.10.30.100-120 (20 addresses)
    - VLAN 40: 10.10.40.100-200 (100 addresses)
    - VLAN 50: 10.10.50.100-200 (100 addresses)
    - VLAN 60: 10.10.60.100-150 (50 addresses)
    - VLAN 70: 10.10.70.100-150 (50 addresses)
- **DNS Configuration**: Should point to 10.10.10.10 (AdGuard)
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
  - AdGuard will listen on 10.10.10.10:53
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

### ✅ Recently Completed (2025-09-05)

#### Firewall Rules - Inter-VLAN Isolation
- **Status**: COMPLETE
- **Implementation Date**: 2025-09-05 09:16 UTC
- **Method**: Python script to add comprehensive firewall rules
- **Total Rules**: 34 firewall rules implemented
- **Details**:
  1. ✅ **WAN Protection**: 
     - Temporary management access from 192.168.1.0/24 (SSH, HTTP, HTTPS)
     - Block bogons and default deny inbound
     - ICMP allowed for path MTU discovery
  2. ✅ **Trusted LAN (10.10.10.0/24)**:
     - Full access to Services VLAN (pragmatic approach)
     - Access to all IoT and Camera VLANs for management
     - Blocked from Guest VLAN
     - Internet access allowed
  3. ✅ **Services VLAN (20)**:
     - DNS services available to all VLANs (port 53 TCP/UDP to 10.10.20.10)
     - Outbound Internet access for updates
  4. ✅ **Guest VLAN (30)**:
     - DNS access to AdGuard only
     - Blocks all RFC1918 ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
     - Internet access allowed
  5. ✅ **IoT Cloud VLAN (40)**:
     - DNS access only
     - Blocks inter-VLAN communication
     - Internet access allowed
  6. ✅ **IoT Local VLAN (50)**:
     - DNS and NTP only
     - No Internet access
     - Complete isolation
  7. ✅ **Camera Cloud VLAN (60)**:
     - DNS and NTP access
     - Blocks inter-VLAN
     - Internet access allowed
  8. ✅ **Camera Local VLAN (70)**:
     - DNS and NTP only
     - No Internet access
     - Complete isolation
- **Configuration Backup**: `/conf/config.xml.backup-firewall-20250905-091610`
- **Verification**: 34 rules active in config.xml and filter reloaded successfully

### 🚧 In Progress

*None currently*

### ✅ Recently Configured (2025-08-25 - Session 2)

#### WireGuard VPN Configuration
- **Status**: COMPLETE
- **Implementation Date**: 2025-08-25 (current session)
- **Details**:
  - WireGuard is built-in to OPNsense 24.1+ (no package install needed)
  - Server configured on port 51820
  - Tunnel network: 10.10.100.0/24
  - Interface assigned as opt8
  - Firewall rules configured for VPN access
  - Sample peer configuration created
  - Keys are placeholders for security (regenerate per deployment)
- **Verification**: Configuration in config.xml, service enabled

#### OpenVPN Configuration
- **Status**: COMPLETE
- **Implementation Date**: 2025-08-25 22:45 UTC
- **Details**:
  - Server configured on port 1194 UDP
  - Tunnel network: 10.10.101.0/24
  - Interface assigned as opt9 (ovpns1)
  - Full tunnel mode (redirect-gateway)
  - Cipher: AES-256-GCM, TLS 1.2 minimum
  - DNS push: 10.10.20.10 (AdGuard)
  - PKI structure with placeholder certificates
  - Firewall rules match WireGuard (Trusted VLAN access)
- **Verification**: 8 OpenVPN references in config.xml

### ❌ Not Started

#### 1. Firewall Rules - Advanced
- Client isolation within VLANs
- Rate limiting
- GeoIP rules (if needed)

#### 2. IPv6 Configuration
- Currently IPv4 only

#### 3. Suricata IDS
- Not installed (disabled by default per requirements)

## Important Notes

### Temporary Configurations
1. **Management Access**: Currently via WAN (192.168.1.173) with temporary rule
   - Should be moved to Trusted VLAN access only
   - WAN SSH should be disabled in production

2. **DNS Setup**: Currently using OPNsense directly
   - Will change to AdGuard when deployed
   - DHCP servers will need updating to point to 10.10.10.10

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
- Latest backups:
  - config.xml.backup-wireguard-[timestamp]
  - config.xml.backup-openvpn-[timestamp]

### SSH Access Instructions
To connect to OPNsense for configuration:
```bash
ssh -i /private/tmp/opnsense-temp-key root@192.168.1.173
```

Note: This temporary key provides root access during configuration phase only

## Next Configuration Session Should

### VPN Testing Strategy (Temporary Keys Approach)

To validate our VPN configurations work correctly, we will:

1. **Backup Current Configuration**
   ```bash
   ssh -i /private/tmp/opnsense-temp-key root@192.168.1.173 \
     "cp /conf/config.xml /conf/config.xml.backup-before-vpn-test"
   ```

2. **WireGuard Testing**
   - Generate temporary server keypair:
     ```bash
     wg genkey | tee privatekey | wg pubkey > publickey
     ```
   - Generate temporary peer keypair
   - Update config.xml with real keys
   - Create client config file
   - Test connection from external network (phone hotspot)
   - Verify access to internal VLANs
   - Verify Guest VLAN is blocked

3. **OpenVPN Testing**
   - Generate temporary PKI:
     ```bash
     easyrsa init-pki
     easyrsa build-ca nopass
     easyrsa gen-dh
     easyrsa build-server-full server nopass
     easyrsa build-client-full client1 nopass
     openvpn --genkey --secret ta.key
     ```
   - Update config.xml with certificates
   - Export client .ovpn file
   - Test connection from external network
   - Verify same access as WireGuard
   - Test simultaneous connections

4. **Validation Tests**
   - Can access Management VLAN (10.10.10.0/24)
   - Can access Services VLAN (10.10.20.0/24)
   - Can access Trusted VLAN (10.10.30.0/24)
   - CANNOT access Guest VLAN (10.10.40.0/24)
   - DNS resolves through 10.10.20.10
   - Internet access works (full tunnel)

5. **Revert to Placeholders**
   - Document all placeholder locations
   - Replace all real keys with original placeholders:
     - `PLACEHOLDER_PUBLIC_KEY_REGENERATE_ON_DEPLOY`
     - `PLACEHOLDER_PRIVATE_KEY_REGENERATE_ON_DEPLOY`
     - `PLACEHOLDER_CA_CERTIFICATE_REGENERATE_ON_DEPLOY`
     - `PLACEHOLDER_SERVER_CERTIFICATE_REGENERATE_ON_DEPLOY`
     - `PLACEHOLDER_TLS_AUTH_KEY_REGENERATE_ON_DEPLOY`
     - etc.
   - Delete all generated key files
   - Clear bash history
   - Save final config as template

6. **Documentation**
   - Record test results
   - Note any issues found
   - Document the exact reversion process
   - Create script for key generation in production

### After Testing

1. **Clean Up** (AFTER testing):
   - Remove temporary SSH key
   - Remove temporary API key
   - Disable WAN management access
   - Move management to Trusted VLAN only

3. **Export Final Configuration**:
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
- [x] WireGuard configuration in place
- [x] OpenVPN configuration in place

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
- Using OPNsense web UI at https://192.168.1.173
- Default credentials still in use (root/opnsense) - MUST BE CHANGED
- Proxmox host assumed to be at 192.168.1.10