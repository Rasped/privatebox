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

### Current Implementation Status

The OPNsense deployment is now fully automated through Semaphore with four separate playbooks that complete the entire chain:

1. **`opnsense-deploy.yml`** - Creates VM from template backup
2. **`opnsense-discover-ip.yml`** - Discovers IP via MAC verification
3. **`opnsense-setup-ssh.yml`** - Deploys SSH keys for secure access
4. **`opnsense-semaphore-register.yml`** - Registers in Semaphore for management

All playbooks are idempotent and include comprehensive state tracking.

### Phase 1: Initial Setup
1. Physical units connected to switch
2. Proxmox hosts get DHCP addresses
3. Bootstrap script creates Management VM with known IP
4. Semaphore and Portainer containers start
5. Generate Templates task creates Semaphore templates from playbooks

### Phase 2: OPNsense Creation (Automated via Semaphore)
1. Template "OPNsense: Deploy Firewall VM from Template" executed
2. Downloads OPNsense backup from GitHub releases
3. Restores VM with known MAC address (bc:24:11:xx:xx:xx)
4. VM starts and WAN interface requests DHCP
5. Deployment state logged to `/var/log/privatebox/`

### Phase 3: Discovery and SSH Setup (Automated via Semaphore)
1. **Discovery** (`opnsense-discover-ip.yml`):
   - Scans network from Proxmox host
   - SSH tests each host with default credentials
   - MAC verification ensures correct OPNsense instance
   - Results saved to `/tmp/opnsense-discovery.env`

2. **SSH Setup** (`opnsense-setup-ssh.yml`):
   - Generates ED25519 keypair on Proxmox host
   - Deploys public key to OPNsense
   - Verifies key-based authentication
   - Results saved to `/tmp/opnsense-ssh-setup.env`

### Phase 4: Semaphore Integration (Automated)
The `opnsense-semaphore-register.yml` playbook:
1. Reads SSH setup state from Proxmox
2. Uses Bearer token authentication with Semaphore API
3. Uploads private SSH key to Semaphore (becomes SSH Key object)
4. Creates inventory entry with discovered IP
5. Links SSH key to inventory for passwordless access
6. Saves registration state to `/tmp/opnsense-semaphore-registration.env`
7. OPNsense now fully manageable through Semaphore

### Phase 5: Network Takeover (Planned)

**IMPORTANT**: Before switching the network architecture, OPNsense requires configuration:

#### Pre-Switch Configuration Requirements

1. **LAN Interface Setup** (Currently in template):
   - vtnet1 already configured as 10.10.10.1/24
   - Need to verify/enable DHCP server on LAN
   - Configure DHCP range (e.g., 10.10.10.100-10.10.10.200)

2. **VLAN Configuration** (If using VLANs):
   - Create VLANs on vtnet1 as per vlan-design.md
   - VLAN 10: 10.10.10.0/24 (Management)
   - VLAN 20: 10.10.20.0/24 (Services)
   - Configure inter-VLAN routing rules

3. **Firewall Rules**:
   - Allow Management VM to access services
   - Configure NAT for outbound traffic
   - Set up port forwarding if needed

4. **DNS Configuration**:
   - Configure DNS forwarder
   - Set up local domain resolution
   - Point to upstream DNS servers

5. **Critical Services Access**:
   - Ensure Semaphore (port 3000) remains accessible
   - Ensure Portainer (port 9000) remains accessible
   - Plan for emergency access if configuration fails

#### Network Switch Process

1. OPNsense configured via Semaphore using key-based auth
2. LAN side activated with DHCP server
3. Management VM switches to LAN network (gets new IP from OPNsense DHCP)
4. Update Semaphore inventory with new Management VM IP
5. OPNsense becomes primary router for the unit

**TODO**: Create `opnsense-configure-lan.yml` playbook to automate this configuration before network switch.

### Future Enhancement: Unified Deployment

**TODO**: Create a single orchestration playbook that combines all four phases into one streamlined operation. This would:
- Run all steps in sequence with proper error handling
- Provide single-click deployment from Semaphore UI
- Include health checks between phases
- Support batch deployment of multiple units
- Offer rollback capabilities on failure

For now, the four-playbook approach provides modularity and debugging flexibility while the system matures.

## IP Discovery and Onboarding Mechanism

### Primary Method: SSH-Based Discovery with MAC Verification

Since we control the VM creation process, we know the MAC address of the OPNsense WAN interface. The complete onboarding process:

#### Discovery Phase

1. **Wait for DHCP**: Allow 30-60 seconds for OPNsense to boot and obtain DHCP lease

2. **Network Detection**: From Proxmox host, identify local network:
   - Detect current subnet from host's IP configuration
   - Determine network range to scan (/24 required)

3. **Active Host Discovery**: 
   - Use nmap to scan network for live hosts
   - Build list of IP addresses to test

4. **SSH Testing with MAC Verification**:
   - Attempt SSH to each discovered host using default credentials
   - Extract MAC address from vtnet0 interface
   - Compare with known MAC from VM creation
   - Identify correct OPNsense instance (handles multiple OPNsense VMs)
   - Retry logic if initial attempts fail

#### SSH Key Setup Phase

5. **Key Generation**:
   - Generate new SSH keypair on Proxmox or Management VM
   - Use strong RSA or ED25519 keys

6. **Key Deployment**:
   - SSH to OPNsense using default password
   - Create .ssh directory with proper permissions
   - Deploy public key to authorized_keys
   - Test key-based authentication

#### Semaphore Integration Phase

7. **API Authentication**:
   - Retrieve Semaphore API credentials from environment/stored variables
   - Login to Semaphore API using cookie-based auth
   - Store session cookie for subsequent API calls

8. **Credential Storage**:
   - Create SSH key object in Semaphore with private key
   - Create inventory entry with discovered IP address (unique per OPNsense instance)
   - Link SSH key to inventory for passwordless access
   - Each OPNsense VM gets its own key/inventory pair

9. **Cleanup and Security**:
   - Remove all temporary key files from filesystem
   - Disable password authentication on OPNsense (mandatory)
   - Save discovery results for audit trail
   - Log all operations for troubleshooting

### Why This Works

- **Consumer Networks**: Typically single flat /24 network without VLANs
- **SSH Default Access**: OPNsense backup has SSH enabled with known credentials
- **No Special Access**: Doesn't require router/switch management access
- **Automation Ready**: Full integration with Semaphore for ongoing management

### Limitations and Fallbacks

**Works Reliably (80% of cases)**:
- Standard home networks
- Single subnet configurations  
- Networks up to /24 size (256 addresses)
- OPNsense SSH accessible on WAN interface

**May Fail**:
- Enterprise networks with VLANs
- Networks larger than /24 (scanning becomes slow)
- Isolated network segments
- Firewalls blocking SSH to new devices
- Changed default credentials in backup

**Fallback Options**:
1. Manual discovery via router's DHCP client list
2. User provides IP after checking router interface
3. Physical console access for initial configuration
4. Manual SSH key setup if automation fails

## Network Requirements

### Minimum Requirements
- DHCP server on network (consumer router)
- Single broadcast domain
- Network allows SSH traffic
- Subnet size must be /24

### Recommended Setup
- Static DHCP reservations for predictable IPs
- Management access to DHCP server (for troubleshooting)
- Documented MAC addresses for each unit

## Security Considerations

### During Deployment
- OPNsense has default credentials during initial discovery only
- Should be on isolated or trusted network
- SSH keys deployed immediately after discovery
- Default password access disabled after key setup (mandatory)
- Temporary key files cleaned up after Semaphore storage

### Post-Deployment  
- All access via SSH keys stored in Semaphore
- No passwords stored or transmitted
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

## Playbook Implementation

The OPNsense automation consists of four fully implemented playbooks:

### 1. `opnsense-deploy.yml` - VM Deployment
- Downloads OPNsense template from GitHub releases
- Validates storage, network bridges, and resources
- Restores VM from backup with predictable MAC address
- Configures VM settings (cores, memory, auto-start)
- Comprehensive logging to `/var/log/privatebox/`
- Full idempotency with pre-flight checks

### 2. `opnsense-discover-ip.yml` - IP Discovery
- VM identification by name (default: "opnsense")
- MAC address extraction from VM configuration
- Network scanning using nmap on /24 networks
- SSH-based discovery with default credentials
- MAC verification to ensure correct OPNsense instance
- Results saved to `/tmp/opnsense-discovery.env`
- Retry logic and comprehensive error messages

### 3. `opnsense-setup-ssh.yml` - SSH Key Setup
- Reads discovery results from previous playbook
- Generates ED25519 keypair on Proxmox host
- Deploys public key via password authentication
- Verifies key-based access works
- Saves state to `/tmp/opnsense-ssh-setup.env`
- Idempotent - safe to run multiple times
- Optional password authentication disable

### 4. `opnsense-semaphore-register.yml` - Semaphore Integration
- Uses Bearer token authentication (from SemaphoreAPI environment)
- Uploads SSH private key to Semaphore
- Creates inventory with discovered IP address
- Links SSH key to inventory for automation
- Handles existing resources gracefully
- State tracking in `/tmp/opnsense-semaphore-registration.env`
- Proper integer type handling for API compatibility

### Key Implementation Details

**State Management**: Each playbook reads state from previous steps and writes its own state file, creating a clear audit trail.

**Error Handling**: Comprehensive error messages with troubleshooting guidance at each failure point.

**Idempotency**: All playbooks can be safely re-run without side effects.

**Security**: SSH keys stored securely, passwords never logged, temporary files cleaned up.

**API Integration**: Fixed Ansible uri module issues with JSON integer types through raw JSON body formatting.

## Alternative Approaches Considered

1. **DHCP Reservations**: Requires router access, not consumer friendly
2. **Phone Home**: Would require modifying OPNsense backup
3. **mDNS/Bonjour**: Often blocked by consumer routers
4. **Static IPs**: Too complex for consumer deployment
5. **DHCP Option 61**: Requires DHCP server support
6. **ARP Cache Lookup**: Unreliable with bridged VMs in Proxmox

The SSH-based discovery with MAC verification provides the best balance of reliability, security, and consumer friendliness for our target market.