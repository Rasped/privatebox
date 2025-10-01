# VPN Implementation Plan - WireGuard Only

**Status**: Planning
**Last Updated**: 2025-10-01
**Target Implementation**: v1.0

---

## Executive Summary

### Goal
Fully automated WireGuard VPN with zero-touch server setup and self-service client creation via Semaphore templates.

### Why WireGuard-Only

**Decision**: Implement only WireGuard, exclude OpenVPN

**Rationale**:
- ✅ **Modern & Fast**: 4,000 lines of code vs OpenVPN's 70,000+
- ✅ **Mobile-Optimized**: Better battery life, built-in roaming support
- ✅ **Superior Performance**: 3-5x faster on Intel N100 hardware
- ✅ **Easier Support**: Fewer moving parts, simpler troubleshooting
- ✅ **No Certificate Complexity**: Public/private keys only, no PKI needed
- ✅ **Industry Momentum**: Built into Linux kernel 5.6+, adopted by Cloudflare, Mullvad, ProtonVPN, Tailscale
- ✅ **Commercial Advantage**: Position as "Modern WireGuard VPN" vs competitors' "Legacy OpenVPN"

### Current State

**What's Already Done**:
- ✅ WireGuard server pre-configured in OPNsense template
- ✅ Firewall rules configured for VPN access
- ✅ Network architecture defined (10.10.100.0/24 for VPN clients)
- ✅ Interface assignments complete (opt8)
- ✅ VPN clients route to Trusted VLAN (10.10.10.0/24)

**What Needs Implementation**:
- ❌ Server key generation during bootstrap (currently placeholder keys)
- ❌ Client creation workflow
- ❌ QR code generation for mobile devices
- ❌ Client management templates (list, revoke, status)

---

## Architecture Decisions

### 1. Key Generation Strategy ⭐ CRITICAL

**Decision**: Generate unique server keys during bootstrap, NOT shared template keys

**Security Requirements**:
- Each appliance must have unique cryptographic material
- Cannot ship products with shared keys (security + commercial)
- Keys generated locally on appliance during first boot
- No key material stored in GitHub repository

**Implementation Pattern**:
- Follow existing SSH key deployment approach (`opnsense-secure-access.yml`)
- PHP script for server key generation (direct OPNsense internal APIs)
- Ansible orchestration during bootstrap Phase 4
- Store generated keys in OPNsense config (persistent)

**Why This Matters**:
- GDPR compliance requirement
- Professional security posture
- Customer trust and product credibility
- Prevents supply chain attack vectors

### 2. Client Management Approach

**Decision**: Semaphore-based self-service templates

**User Workflow**:
```
User → Semaphore Web UI (10.10.20.10:3000)
     → Select "VPN: Create WireGuard Client"
     → Enter client device name
     → Template executes
     → QR code displays in output
     → Config file available for download
```

**Benefits**:
- **Zero vendor involvement**: Customer creates unlimited clients independently
- **Scales infinitely**: No per-client cost or support burden
- **Familiar interface**: Uses existing Semaphore deployment
- **Offline-capable**: No internet connection required
- **Self-documenting**: Template output includes usage instructions

### 3. Client Limits

**Recommended Configuration**:
- **Maximum clients**: 100 (documented limit)
- **Concurrent connections**: 50+ easily supported by N100
- **Typical usage**: 5-10 clients per household

**Technical Capacity**:
- WireGuard scales to 1000+ peers technically
- Intel N100 easily handles 100 concurrent connections
- Limit based on practical usability, not hardware

---

## Network Architecture

### VPN Network Allocation

| Network | CIDR | Gateway | Purpose |
|---------|------|---------|---------|
| VPN Tunnel | 10.10.100.0/24 | 10.10.100.1 | WireGuard client addresses |

### Client Routing

**VPN clients land on Trusted VLAN** (10.10.10.0/24):
- Full access to Services VLAN (10.10.20.0/24) - AdGuard, Semaphore, Portainer
- Can manage IoT devices on respective VLANs
- Blocked from Guest VLAN (security)
- Full internet access via OPNsense
- DNS via AdGuard (10.10.20.10) - ad blocking while traveling

### Traffic Flow

```
VPN Client (mobile/laptop)
    ↓ Encrypted tunnel to external IP:51820
OPNsense WireGuard (10.10.100.1)
    ↓ Routes to Trusted VLAN
Trusted LAN (10.10.10.0/24)
    ↓ Access granted to:
    ├─ Services VLAN (10.10.20.0/24)
    ├─ IoT VLANs (40, 50)
    ├─ Camera VLANs (60, 70)
    └─ Internet (via NAT)
```

---

## Implementation Phases

### Phase 1: Server Key Generation (Bootstrap-Time)

**Trigger**: During bootstrap Phase 4 (after Semaphore setup, before service deployment)

**Location**: `ansible/playbooks/services/opnsense-vpn-init.yml`

**Execution Context**:
- Runs from Management VM (10.10.20.10)
- Uses OPNsenseAPI Semaphore environment (API credentials)
- Executed as part of orchestration sequence

#### Tasks Overview

1. **Check Current State**
   - Query WireGuard server config via API
   - Detect if placeholder keys still present
   - Set `needs_key_generation` fact

2. **Generate Server Keys** (conditional)
   - Copy PHP script to Proxmox
   - Upload to OPNsense via SCP
   - Execute on OPNsense (generates keypair)
   - Parse JSON response with keys

3. **Update Server Configuration**
   - Call `/api/wireguard/server/set` with real keys
   - Reconfigure service
   - Start WireGuard service

4. **Cleanup**
   - Remove PHP script from OPNsense
   - Remove local copy from Proxmox

#### Key Generation Script

**File**: `ansible/files/opnsense/generate-wireguard-server.php`

**Purpose**: Generate WireGuard keypair using OPNsense internal libraries

**Execution Environment**: OPNsense VM (requires FreeBSD, OPNsense PHP environment)

**Output Format**:
```json
{
  "result": "ok",
  "private_key": "aB3cD4eF...",
  "public_key": "xY9zW8..."
}
```

**Security Considerations**:
- Runs with root privileges on OPNsense
- Keys generated using `wg genkey` (WireGuard's native tool)
- Private key never logged or stored in Ansible output
- Script self-contained, no external dependencies

#### Idempotency

**Check Before Generate**:
```yaml
- name: Get current WireGuard server config
  uri:
    url: "{{ opnsense_api_url }}/api/wireguard/server/get"
  register: wg_server_config

- name: Check if server has placeholder keys
  set_fact:
    needs_key_generation: "{{ 'PLACEHOLDER' in (wg_server_config.json.server.privkey | default('PLACEHOLDER')) }}"

- name: Generate keys
  when: needs_key_generation
  # ... generation tasks
```

**Behavior**:
- First run: Generates and installs keys
- Subsequent runs: Detects real keys, skips generation
- Never overwrites existing configuration
- Safe to re-run during troubleshooting

#### Error Handling

**Failure Scenarios**:
1. **SSH connection fails**: Playbook fails, user notified
2. **Key generation fails**: JSON error returned, task fails
3. **API call fails**: HTTP error captured, retry possible
4. **Service won't start**: Logged, but not fatal (can troubleshoot)

**Recovery**:
- All steps are idempotent
- Re-running playbook attempts failed steps only
- No partial state corruption

---

### Phase 2: WireGuard Client Creation (On-Demand)

**Trigger**: User runs Semaphore template "VPN: Create WireGuard Client"

**Location**: `ansible/playbooks/services/vpn-create-wireguard-client.yml`

**User Interface**: Semaphore web UI with prompts

#### User Input Requirements

**Required**:
- `client_name`: Alphanumeric identifier (e.g., "johns-iphone", "laptop-work")

**Optional**:
- `client_ip`: Specific IP address (default: auto-assigned)

**Validation**:
- Client name must match `^[a-zA-Z0-9-]+$`
- Client name must be unique
- IP address must be in 10.10.100.0/24 range
- IP must not conflict with existing clients

#### Workflow Steps

**1. Validation & IP Assignment**
```yaml
- Validate client name format
- Query existing clients via API
- Check for name conflicts
- Auto-assign IP if not provided: 10.10.100.{10 + client_count}
```

**2. Generate Client Keys**
```yaml
- Create temporary directory /tmp/wg-{client_name}
- Generate private key: wg genkey
- Generate public key: echo {privkey} | wg pubkey
- Store in Ansible facts (no_log: true)
```

**3. Get Server Configuration**
```yaml
- Query /api/wireguard/server/get for server public key
- Detect external IP via https://ifconfig.me/ip
- Store for config file generation
```

**4. Add Peer to OPNsense**
```yaml
- POST /api/wireguard/client/set
  - name: {client_name}
  - pubkey: {client_public_key}
  - tunneladdress: {assigned_ip}/32
  - enabled: 1
- POST /api/wireguard/service/reconfigure
```

**5. Generate Client Configuration**
```ini
[Interface]
PrivateKey = {client_private_key}
Address = {assigned_ip}/24
DNS = 10.10.20.10

[Peer]
PublicKey = {server_public_key}
Endpoint = {external_ip}:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

**6. Generate QR Code**
```bash
# Terminal display (for copy-paste)
qrencode -t ansiutf8 < {client_name}.conf

# PNG file (for download)
qrencode -t png -o {client_name}-qr.png -r {client_name}.conf
```

**7. Present Results to User**
```
Semaphore task output shows:
- Configuration summary
- QR code (ASCII art in terminal)
- Setup instructions for mobile/desktop
- Security reminder
```

**8. Cleanup (Delayed)**
```bash
# Delete sensitive files after 5 minutes
(sleep 300 && rm -rf /tmp/wg-{client_name}) &
```

#### Client Configuration Details

**Interface Section**:
- `PrivateKey`: Unique to this client (never reused)
- `Address`: Assigned IP in 10.10.100.0/24
- `DNS`: AdGuard at 10.10.20.10 (ad blocking + privacy)

**Peer Section**:
- `PublicKey`: OPNsense server's public key
- `Endpoint`: Public IP:51820 (auto-detected)
- `AllowedIPs`: 0.0.0.0/0 = full tunnel (all traffic through VPN)
- `PersistentKeepalive`: 25 seconds (mobile-friendly, maintains NAT)

#### Mobile Setup Process

**iOS/Android**:
1. Open WireGuard app
2. Tap "+" (Add tunnel)
3. Select "Create from QR code"
4. Scan QR code displayed in Semaphore output
5. Tap "Activate"

**Desktop Setup**:
1. Download .conf file from Semaphore task output
2. Open WireGuard application
3. Import tunnel from file
4. Activate

#### Security Considerations

**Private Key Handling**:
- Generated on Management VM (trusted environment)
- Never logged in Ansible output (`no_log: true`)
- Transmitted only to user via secure Semaphore session
- Deleted from server after 5 minutes
- User responsible for securing downloaded files

**Access Control**:
- Only users with Semaphore access can create VPN clients
- Requires authentication to Semaphore (admin password)
- Creation events logged in Semaphore task history
- No public-facing interface for client creation

---

### Phase 3: Client Management Templates

#### Template: "VPN: List Clients"

**Purpose**: Display all configured WireGuard clients

**Location**: `ansible/playbooks/services/vpn-list-clients.yml`

**Output Format**:
```
==========================================
WireGuard VPN Clients
==========================================
Total Clients: 5

1. johns-iphone
   IP: 10.10.100.10
   Status: Enabled
   Public Key: xY9zW8qRtVu7...

2. laptop-work
   IP: 10.10.100.11
   Status: Enabled
   Public Key: aB3cD4eF5gH6...

==========================================
```

**Use Cases**:
- Audit configured clients
- Verify IP assignments
- Check client status before revocation
- Troubleshooting connectivity issues

#### Template: "VPN: Revoke Client"

**Purpose**: Remove client access to VPN

**Location**: `ansible/playbooks/services/vpn-revoke-client.yml`

**User Inputs**:
- `client_name`: Name of client to revoke (required)

**Workflow**:
1. Search for client by name
2. Fail if not found
3. Extract client UUID
4. Call `/api/wireguard/client/del/{uuid}`
5. Reconfigure WireGuard service
6. Display confirmation

**Important Notes**:
- Revocation is immediate (client disconnects)
- Config file on client device still exists (but won't connect)
- User should delete config from revoked devices
- IP address becomes available for reassignment

#### Template: "VPN: Connection Status"

**Purpose**: Show active VPN connections

**Location**: `ansible/playbooks/services/vpn-status.yml`

**Output**:
- WireGuard service status (running/stopped)
- Connected peers (real-time)
- Bandwidth statistics
- Last handshake times

**Use Cases**:
- Verify VPN is operational
- Check if specific client is connected
- Troubleshoot connectivity issues
- Monitor bandwidth usage

---

## File Structure

```
privatebox/
├── ansible/
│   ├── playbooks/services/
│   │   ├── opnsense-vpn-init.yml              # Phase 1: Bootstrap key generation
│   │   ├── vpn-create-wireguard-client.yml    # Phase 2: Client creation
│   │   ├── vpn-list-clients.yml               # Management: List all clients
│   │   ├── vpn-revoke-client.yml              # Management: Remove client
│   │   └── vpn-status.yml                     # Management: Connection status
│   │
│   ├── files/opnsense/
│   │   ├── generate-wireguard-server.php      # Server key generation script
│   │   └── create-apikey.php                  # (existing, for reference)
│   │
│   └── templates/vpn/
│       └── README.md                          # User guide for VPN usage
│
├── tools/
│   └── orchestrate-services.py                # Updated to include VPN init
│
└── documentation/
    ├── vpn-implementation-plan.md             # This document
    └── vpn-user-guide.md                      # End-user documentation
```

---

## Orchestration Integration

### Bootstrap Sequence Update

**Current Sequence**:
```python
self.template_sequence = [
    "OPNsense 1: Establish Secure Access",
    "OPNsense 2: Semaphore Integration",
    "OPNsense 3: Post-Configuration",
    "AdGuard 1: Deploy Container Service",
    "Homer 1: Deploy Dashboard Service"
]
```

**Updated Sequence**:
```python
self.template_sequence = [
    "OPNsense 1: Establish Secure Access",
    "OPNsense 2: Semaphore Integration",
    "OPNsense 3: Post-Configuration",
    "OPNsense 4: VPN Initialization",        # NEW
    "AdGuard 1: Deploy Container Service",
    "Homer 1: Deploy Dashboard Service"
]
```

**Why After Post-Configuration**:
- Requires OPNsense API access (from Semaphore Integration)
- Requires firewall rules (from Post-Configuration)
- Independent of AdGuard/Homer (can run in parallel, but sequenced for clarity)

### Template Registration

**Semaphore Template Metadata**:
```yaml
# opnsense-vpn-init.yml
template_config:
  semaphore_environment: "OPNsenseAPI"
  semaphore_category: "infrastructure"

# vpn-create-wireguard-client.yml
template_config:
  semaphore_environment: "OPNsenseAPI"
  semaphore_category: "vpn"
  semaphore_prompt:
    - name: client_name
      description: "Client device name (e.g., johns-iphone)"
      required: true
    - name: client_ip
      description: "Client IP (e.g., 10.10.100.10, leave blank for auto)"
      required: false
      default_value: ""
```

---

## Technical Specifications

### WireGuard Server Configuration

**Port**: 51820/UDP (default, firewall-friendly)
**Tunnel Network**: 10.10.100.0/24
**Server IP**: 10.10.100.1
**Interface**: opt8 (assigned in OPNsense template)
**MTU**: 1420 (optimal for most connections)

**Cryptography**:
- Key exchange: Curve25519
- Cipher: ChaCha20-Poly1305
- Hash: BLAKE2s

### Client Configuration Parameters

**Full Tunnel** (AllowedIPs = 0.0.0.0/0):
- All client traffic routed through VPN
- Protects on untrusted networks (coffee shops, airports)
- Ad blocking works everywhere (via AdGuard DNS)

**PersistentKeepalive** (25 seconds):
- Maintains NAT mappings
- Essential for mobile devices (network switching)
- Prevents timeout disconnections
- Slight battery impact (acceptable tradeoff)

**DNS Configuration**:
- Push 10.10.20.10 (AdGuard) to all clients
- Ad blocking while traveling
- Privacy protection (no ISP/network DNS snooping)
- Local DNS for privatebox.local domain

### API Endpoints Used

**WireGuard Service**:
- `GET /api/wireguard/server/get` - Retrieve server config
- `POST /api/wireguard/server/set` - Update server config
- `GET /api/wireguard/client/search_client` - List clients
- `POST /api/wireguard/client/set` - Add/update client
- `POST /api/wireguard/client/del/{uuid}` - Delete client
- `POST /api/wireguard/service/reconfigure` - Apply config changes
- `POST /api/wireguard/service/start` - Start service
- `POST /api/wireguard/service/stop` - Stop service
- `GET /api/wireguard/service/show` - Get service status

**External Services**:
- `GET https://ifconfig.me/ip` - Detect public IP (for client configs)

### Dependencies

**Management VM**:
- `qrencode` package (installed via apt)
- `wireguard-tools` package (for `wg` command)

**OPNsense**:
- WireGuard built-in (OPNsense 24.1+, no package needed)
- FreeBSD `wg` command available

**Client Devices**:
- WireGuard application (iOS, Android, Windows, macOS, Linux)

---

## Testing Strategy

### 1. Bootstrap Testing (Phase 1)

**Objective**: Verify server key generation during initial deployment

**Test Procedure**:
```bash
# 1. Fresh deployment
ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash"

# 2. Wait for completion (~10 minutes)

# 3. Verify WireGuard has real keys (not placeholders)
ssh root@192.168.1.10 "ssh -i /root/.credentials/opnsense/id_ed25519 root@10.10.20.1 'configctl wireguard show'"

# Expected output: Shows interface wg0 with real public key
```

**Success Criteria**:
- [ ] Bootstrap completes without errors
- [ ] WireGuard server has public key (not "PLACEHOLDER")
- [ ] WireGuard service is running
- [ ] Firewall shows VPN rules active

**Failure Scenarios**:
- Key generation script fails → Check PHP syntax, OPNsense version
- API calls fail → Verify OPNsenseAPI environment created
- Service won't start → Check config.xml manually, verify interface assignment

### 2. Client Creation Testing (Phase 2)

**Objective**: Verify client creation workflow end-to-end

**Test Procedure**:
```
1. Login to Semaphore (http://10.10.20.10:3000)
   Username: admin
   Password: {SERVICES_PASSWORD}

2. Navigate to "VPN: Create WireGuard Client" template

3. Run with inputs:
   - client_name: test-iphone
   - client_ip: (leave blank for auto-assign)

4. Observe task output

5. Run "VPN: List Clients" to verify
```

**Success Criteria**:
- [ ] Template executes in <30 seconds
- [ ] QR code displays in task output (ASCII art)
- [ ] No errors in task log
- [ ] Client appears in "VPN: List Clients"
- [ ] Client has IP 10.10.100.10 (first auto-assigned)

**QR Code Verification**:
- [ ] QR code is scannable (test with phone camera)
- [ ] QR code contains valid WireGuard config
- [ ] Config includes correct server public key
- [ ] Config includes correct endpoint IP

### 3. Mobile Connection Testing

**Objective**: Verify VPN connectivity from mobile devices

**Test Devices**:
- iOS (iPhone) - WireGuard app from App Store
- Android - WireGuard app from Google Play

**Test Procedure**:
```
1. Create client via Semaphore (e.g., "test-iphone")
2. Open WireGuard app on test device
3. Tap "+" → "Create from QR code"
4. Scan QR code from Semaphore output
5. Activate tunnel
6. Verify connectivity
```

**Connectivity Tests**:
- [ ] IP address assigned (10.10.100.x)
- [ ] Can ping 10.10.20.10 (AdGuard)
- [ ] Can browse to http://10.10.20.10:8080 (AdGuard web UI)
- [ ] Can browse to http://10.10.20.10:3000 (Semaphore)
- [ ] Can access internet (e.g., https://google.com)
- [ ] DNS queries appear in AdGuard logs
- [ ] Ads are blocked (test on ad-heavy site)

**Network Diagnostics**:
```bash
# On mobile device (if accessible):
ping 10.10.20.10          # Should succeed
ping 10.10.10.1           # Should succeed (OPNsense LAN)
nslookup google.com       # Should use 10.10.20.10

# On OPNsense (via SSH):
wg show                   # Should show connected peer
```

### 4. Desktop Connection Testing

**Objective**: Verify config file download and import

**Test Platforms**:
- Windows 10/11 - WireGuard for Windows
- macOS - WireGuard app from App Store
- Linux - wireguard-tools package

**Test Procedure**:
```
1. Create client via Semaphore (e.g., "test-laptop")
2. Download .conf file from task output
3. Import into WireGuard application
4. Activate tunnel
5. Run same connectivity tests as mobile
```

**Success Criteria**:
- [ ] Config file downloads successfully
- [ ] Imports without errors
- [ ] Connects on first try
- [ ] All network access tests pass

### 5. Multi-Client Testing

**Objective**: Verify concurrent connections and IP assignment

**Test Procedure**:
```
1. Create 3 clients:
   - "test-iphone" (auto IP)
   - "test-android" (auto IP)
   - "test-laptop" (manual IP: 10.10.100.50)

2. Connect all three simultaneously

3. Verify:
   - All clients get unique IPs
   - No IP conflicts
   - All can access services
   - All can access internet
```

**Success Criteria**:
- [ ] Auto-assigned IPs are sequential (10.10.100.10, .11, .12)
- [ ] Manual IP is respected (10.10.100.50)
- [ ] All clients show in "VPN: Connection Status"
- [ ] No cross-client interference

### 6. Revocation Testing

**Objective**: Verify client access can be removed

**Test Procedure**:
```
1. Create client "test-revoke"
2. Connect from test device (verify works)
3. Run "VPN: Revoke Client" with name "test-revoke"
4. Observe on test device
5. Verify with "VPN: List Clients"
```

**Success Criteria**:
- [ ] Revocation completes without errors
- [ ] Client disconnects within 30 seconds
- [ ] Reconnection attempts fail
- [ ] Client no longer appears in list
- [ ] IP becomes available for reuse

### 7. Idempotency Testing

**Objective**: Verify playbooks can be safely re-run

**Test Procedure**:
```
# Run bootstrap twice
ssh root@192.168.1.10 "cd /opt/privatebox && ansible-playbook ansible/playbooks/services/opnsense-vpn-init.yml"
# Should skip key generation on second run

# Try to create duplicate client
# Run "VPN: Create WireGuard Client" with same name twice
# Should fail on second attempt with clear error
```

**Success Criteria**:
- [ ] VPN init playbook skips generation if keys exist
- [ ] Duplicate client names are rejected
- [ ] No corruption of existing clients
- [ ] All operations are safe to retry

---

## Success Criteria

### Bootstrap Phase
- [x] WireGuard server pre-configured in template
- [ ] Bootstrap generates unique keys per deployment
- [ ] Service starts automatically
- [ ] Firewall rules allow VPN traffic (51820/UDP)
- [ ] "OPNsense 4: VPN Initialization" template exists in Semaphore

### Client Creation
- [ ] "VPN: Create WireGuard Client" template works
- [ ] QR code generation successful
- [ ] Config file valid and downloadable
- [ ] Client creation completes in <30 seconds
- [ ] Auto IP assignment works correctly
- [ ] Manual IP assignment honored

### Network Access
- [ ] VPN clients receive IP in 10.10.100.0/24
- [ ] Can access Trusted VLAN (10.10.10.0/24)
- [ ] Can access Services VLAN (10.10.20.0/24)
- [ ] DNS resolves through AdGuard (10.10.20.10)
- [ ] Internet access works (full tunnel)
- [ ] Ad blocking active while on VPN

### User Experience
- [ ] Zero manual configuration needed
- [ ] QR codes scan successfully on iOS/Android
- [ ] Works offline (no internet needed for client creation)
- [ ] Clear error messages on failure
- [ ] Success confirmation displayed

### Management
- [ ] "VPN: List Clients" shows all clients
- [ ] "VPN: Revoke Client" removes access
- [ ] "VPN: Connection Status" shows active connections
- [ ] Client limit (100) documented

---

## Implementation Timeline

### Phase 1: Server Key Generation (4 hours)

**Tasks**:
- [ ] Write `generate-wireguard-server.php` (1 hour)
- [ ] Write `opnsense-vpn-init.yml` playbook (2 hours)
- [ ] Test on running system (1 hour)

**Deliverables**:
- PHP script in `ansible/files/opnsense/`
- Ansible playbook in `ansible/playbooks/services/`
- Updated orchestration sequence

### Phase 2: Client Creation (3 hours)

**Tasks**:
- [ ] Write `vpn-create-wireguard-client.yml` playbook (1.5 hours)
- [ ] Integrate qrencode for QR generation (1 hour)
- [ ] Test client creation workflow (0.5 hours)

**Deliverables**:
- Client creation playbook
- QR code generation working
- Config file download working

### Phase 3: Management Templates (1.5 hours)

**Tasks**:
- [ ] Write `vpn-list-clients.yml` (0.5 hours)
- [ ] Write `vpn-revoke-client.yml` (0.5 hours)
- [ ] Write `vpn-status.yml` (0.5 hours)

**Deliverables**:
- Three management playbooks
- All integrated in Semaphore

### Phase 4: Documentation (1 hour)

**Tasks**:
- [ ] Write user guide for VPN usage
- [ ] Update main documentation
- [ ] Add troubleshooting section

**Deliverables**:
- `documentation/vpn-user-guide.md`
- Updated README if needed

### Phase 5: Testing (1.5 hours)

**Tasks**:
- [ ] Full bootstrap test (0.5 hours)
- [ ] Mobile/desktop connection tests (0.5 hours)
- [ ] Multi-client and revocation tests (0.5 hours)

**Deliverables**:
- Test results documented
- Any bugs fixed

**Total Estimated Time**: ~11 hours (~1.5 days)

---

## Commercial Product Considerations

### Marketing Advantages

**vs. Firewalla** ($229-$459):
- ✅ WireGuard + OpenVPN vs. OpenVPN only (Gold model)
- ✅ Modern cryptography vs. legacy protocols
- ✅ Faster VPN performance
- ✅ Better mobile battery life

**vs. Ubiquiti Dream Machine** ($199-$499):
- ✅ No recurring UniFi Protect fees
- ✅ Offline-capable VPN setup
- ✅ Self-service client creation
- ✅ Open source (no vendor lock-in)

**vs. DIY Solutions**:
- ✅ Professional automation
- ✅ Tested workflow
- ✅ QR code convenience
- ✅ Support documentation

### User Documentation Requirements

**Must Include**:
1. **Getting Started Guide**
   - How to access Semaphore
   - Creating first VPN client
   - Scanning QR code on mobile

2. **Client Setup Instructions**
   - iOS setup (screenshots)
   - Android setup (screenshots)
   - Windows setup
   - macOS setup
   - Linux setup

3. **Troubleshooting**
   - VPN won't connect
   - Can't access local services
   - Slow connection
   - Connection drops frequently

4. **Advanced Topics**
   - Split tunnel configuration (if needed)
   - Custom client IPs
   - Managing multiple devices
   - Revoking lost devices

### Support Scalability

**Template-Based = Zero Marginal Cost**:
- Customer creates unlimited clients
- No vendor involvement required
- Self-service reduces support tickets

**QR Codes = Fewer Support Tickets**:
- Mobile setup takes 30 seconds
- No manual key entry
- Fewer typos and mistakes

**Clear Error Messages**:
- Validation prevents common mistakes
- Helpful output guides user
- Reduced confusion

### Compliance Considerations

**GDPR Compliance**:
- ✅ Data processed locally (no cloud)
- ✅ Customer controls all keys
- ✅ No vendor access to VPN traffic
- ✅ Easy client deletion (right to erasure)

**Security Best Practices**:
- ✅ Unique keys per appliance
- ✅ Modern cryptography (WireGuard)
- ✅ No shared credentials
- ✅ Automatic key cleanup

---

## Risk Analysis

### Technical Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Key generation fails | High | Low | PHP script tested, fallback to manual |
| QR codes don't scan | Medium | Low | Use standard qrencode library |
| API authentication breaks | High | Low | Use proven OPNsenseAPI pattern |
| Client IP conflicts | Medium | Low | Auto-assignment with conflict detection |
| Service won't start | High | Low | Idempotent checks, detailed error logs |

### User Experience Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Confusing template prompts | Low | Medium | Clear descriptions, examples |
| QR code hard to find | Low | Medium | Prominent in task output |
| Config download unclear | Low | Medium | Explicit instructions in output |
| Revocation not obvious | Low | Low | Separate template, confirmation message |

### Commercial Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Competitor adds WireGuard | Medium | High | Not a blocker, table stakes feature |
| Support burden too high | Low | Low | Self-service design minimizes tickets |
| Security vulnerability | High | Very Low | WireGuard peer-reviewed, audited |

---

## Future Enhancements (Post-v1.0)

### Potential Features

**Split Tunnel Mode**:
- Allow clients to route only specific traffic through VPN
- Keep local traffic direct
- More complex configuration

**Advanced Client Management**:
- Bandwidth limits per client
- Connection time restrictions
- Client groups/categories

**Monitoring Dashboard**:
- Real-time connection map
- Bandwidth usage graphs
- Historical connection logs

**Automated Key Rotation**:
- Schedule client key regeneration
- Forced rotation on revocation
- Security best practice

**Multi-Server Support**:
- Multiple WireGuard instances
- Region-specific servers
- Load balancing

**Integration with Homer Dashboard**:
- VPN status widget
- Quick client creation link
- Connected clients display

---

## Appendix: Reference Implementation

### Example Client Configuration

```ini
[Interface]
PrivateKey = cPRqX8pKvQr5yL9mN3bV6wA2sD4fG7hJ9k=
Address = 10.10.100.10/24
DNS = 10.10.20.10

[Peer]
PublicKey = xY9zW8qRtVu7sA5bC3dE1fG2hI4jK6lM8n=
Endpoint = 203.0.113.45:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

### Example Server Configuration

```ini
[Interface]
PrivateKey = aB3cD4eF5gH6iJ7kL8mN9oP0qR1sT2uV3w=
Address = 10.10.100.1/24
ListenPort = 51820

[Peer]
# johns-iphone
PublicKey = cPRqX8pKvQr5yL9mN3bV6wA2sD4fG7hJ9k=
AllowedIPs = 10.10.100.10/32

[Peer]
# laptop-work
PublicKey = xY9zW8qRtVu7sA5bC3dE1fG2hI4jK6lM8n=
AllowedIPs = 10.10.100.11/32
```

### API Request Examples

**Create Client**:
```bash
curl -u "$API_KEY:$API_SECRET" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "client": {
      "enabled": "1",
      "name": "johns-iphone",
      "pubkey": "cPRqX8pKvQr5yL9mN3bV6wA2sD4fG7hJ9k=",
      "tunneladdress": "10.10.100.10/32",
      "serveraddress": "10.10.20.1",
      "serverport": "51820"
    }
  }' \
  https://10.10.20.1/api/wireguard/client/set
```

**List Clients**:
```bash
curl -u "$API_KEY:$API_SECRET" \
  https://10.10.20.1/api/wireguard/client/search_client
```

**Delete Client**:
```bash
curl -u "$API_KEY:$API_SECRET" \
  -X POST \
  https://10.10.20.1/api/wireguard/client/del/{uuid}
```

---

## Conclusion

This implementation plan provides a complete, automated WireGuard VPN solution for PrivateBox that:

- ✅ Requires zero manual configuration
- ✅ Generates unique keys per deployment
- ✅ Enables self-service client creation
- ✅ Provides excellent mobile UX (QR codes)
- ✅ Scales infinitely (no vendor involvement)
- ✅ Meets commercial security requirements
- ✅ Follows existing automation patterns

**Status**: Ready for implementation
**Estimated Effort**: 1.5 days
**Risk Level**: Low (builds on proven patterns)
**Commercial Value**: High (key differentiator)

By choosing WireGuard-only, we avoid the complexity of OpenVPN certificate management while delivering a modern, fast, and user-friendly VPN solution that positions PrivateBox as a premium consumer appliance.
