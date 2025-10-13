# PrivateBox Release Requirements & Status

## Release Strategy

PrivateBox has a two-phase release approach:

### Phase 1: FOSS Release (Current Focus)
Open source release for self-deployment on Proxmox. Goal: Working system that technical users can deploy in their own infrastructure.

**Target**: Public GitHub release, community adoption, testing in production environments

### Phase 2: Product Release (Future)
Commercial appliance for consumers. Adds commercial features, recovery infrastructure, and warranty support on top of FOSS base.

**Target**: Pre-configured Intel N150 hardware, sold to consumers by SubRosa ApS (Denmark), late 2025 launch

---

## FOSS Release Requirements

### ✅ COMPLETED Features

#### Infrastructure
- **One-command bootstrap** - `quickstart.sh` deploys entire system
- **Management VM** - Debian 13 with cloud-init on Proxmox
- **Network auto-detection** - Detects Proxmox network and configures VLANs
- **Portainer** - Container management UI at https://portainer.lan
- **Semaphore** - Ansible automation UI at https://semaphore.lan
- **Template auto-generation** - Ansible playbooks → Semaphore templates automatically
- **SSH key management** - Automated key generation and distribution
- **Password generation** - Random passwords stored in `/etc/privatebox/config.env`
- **VLAN segmentation** - Services VLAN (10.10.20.x) and Trusted LAN (10.10.10.x)

#### Network Services
- **OPNsense VM** - Firewall/router at 10.10.20.1 (Services), 10.10.10.1 (Trusted)
- **Unbound DNS** - Recursive resolver on OPNsense (port 53)
- **AdGuard Home** - DNS filtering at 10.10.20.10:53
  - Upstream: Quad9 (primary) + Unbound (fallback)
  - Blocklists: OISD Basic + Steven Black Hosts
  - DNS rewriting: *.lan → 10.10.20.10
- **Headscale** - Self-hosted VPN coordination server at https://10.10.20.10:4443
- **Headplane** - Headscale management UI at https://headplane.lan

#### Access & Monitoring
- **PrivateBox Dashboard** - Service directory at https://privatebox.lan
- **Caddy Reverse Proxy** - TLS termination for all services
  - Self-signed certificates for .lan domains
  - ACME certificates (Let's Encrypt/ZeroSSL) for custom domains
  - Automatic DNS-01 challenge with deSEC/Dynu/Cloudflare/DuckDNS
- **Dynamic DNS** - Automated setup for custom domains with ACME TLS
- **Split-horizon DNS** - Internal .lan + external custom domains

#### VPN (Headscale-based)
- **Subnet Router VM** - VM 101 at 10.10.20.11 (Services), 10.10.10.10 (Trusted)
- **Tailscale client** - Connects to Headscale for subnet routing
- **Remote access** - VPN clients can access all PrivateBox services

### 🔧 NEEDS VERIFICATION

#### Headscale/Headplane Live Testing
**Status**: Deployed and tested internally, not tested from external network

**Required Testing**:
- Connect Tailscale client from outside network to Headscale
- Verify subnet routes propagate correctly
- Access internal services (portainer.lan, etc.) through VPN
- Test DNS resolution through AdGuard while on VPN

### 📋 OPTIONAL (Nice-to-Have)

#### Manual Update Playbooks
**Status**: Services deployed but no formal update procedures

**Scope**: Semaphore playbooks for user-initiated updates:
- Proxmox host updates (apt)
- OPNsense firmware updates
- Management VM updates (apt)
- Container image updates (Portainer/Semaphore/AdGuard/Homer/Caddy)

**Note**: Can be deferred to post-FOSS release or Product release. Homer auto-updates; others update manually via web UIs.

### ❌ OUT OF SCOPE (Product Release Only)

These features are deferred to Product release:
- Encrypted backup system (LUKS partition)
- Recovery infrastructure (7 partitions, factory reset)
- Offline asset storage
- Golden image creation
- CE marking, WEEE registration, warranty support

---

## FOSS Release Success Criteria

### Core Functionality
- ✅ Single-command deployment (`quickstart.sh`)
- ✅ All services accessible via dashboard (https://privatebox.lan)
- ✅ DNS filtering functional (AdGuard → Quad9 → Unbound)
- ✅ TLS certificates working (.lan self-signed + custom domain ACME)
- ⚠️ VPN access (Headscale deployed, needs live testing)

### User Experience
- ✅ Zero interaction after quickstart command
- ✅ Services accessible at memorable .lan domains
- ✅ Dashboard shows all services with status
- ✅ Custom domain support with Let's Encrypt certificates
- ✅ Semaphore templates available for service management

### Documentation
- ✅ CLAUDE.md (LLM guide for development)
- ✅ Bootstrap execution flow documented
- ⚠️ User deployment guide (minimal, code-focused for FOSS)
- ⚠️ Service access instructions
- ⚠️ Troubleshooting documentation

### Quality
- ⏳ Clean deployment from scratch (needs verification)
- ⏳ No errors in service logs (needs audit)
- ⏳ Live production testing (user's own network)

---

## FOSS Release Checklist

Before tagging FOSS v1.0:

1. **Live VPN Testing**
   - [ ] Deploy Headscale client on external device
   - [ ] Connect to Headscale from outside network
   - [ ] Verify subnet routing works
   - [ ] Access internal services through VPN
   - [ ] Test DNS resolution through AdGuard via VPN

2. **Clean Deployment Test**
   - [ ] Delete all VMs
   - [ ] Run quickstart.sh on fresh Proxmox
   - [ ] Verify all services deploy without errors
   - [ ] Check logs for issues
   - [ ] Test all service access

3. **Production Testing**
   - [ ] Deploy in user's home network
   - [ ] Run for 1+ week without intervention
   - [ ] Verify stability under real use
   - [ ] Document any issues found

4. **Documentation** (Optional but Recommended)
   - [ ] Quick start guide for FOSS users
   - [ ] Service access guide (URLs, default passwords)
   - [ ] Basic troubleshooting guide
   - [ ] Known issues / limitations

5. **Code Quality**
   - [x] All changes committed and pushed
   - [x] No plaintext secrets in repo
   - [x] Ansible playbooks idempotent
   - [ ] Add LICENSE file (AGPL-3.0 or similar)
   - [ ] Add README.md with quick start

---

## Product Release Requirements

*These are deferred until after FOSS release*

### Recovery & Backup
- **Encrypted backup partition** (LUKS on Proxmox bare metal)
- **Automated backup schedule** for OPNsense configs
- **7-partition layout** with recovery, vault, and immutable OS
- **Factory reset capability** (physical console only)
- **Offline asset storage** (no GitHub dependency during recovery)

### Commercial Features
- **Golden image creation** for consistent customer experience
- **Hardware-specific optimizations** for Intel N150
- **CE marking** and regulatory compliance
- **WEEE registration** for EU
- **2-year warranty** infrastructure
- **GDPR compliance** by design

### Support Infrastructure
- **Documentation-first** support (no phone support)
- **Community forums** or support channels
- **Update playbooks** (if not in FOSS)
- **Troubleshooting guides** for common issues

---

## Current Status Summary

### Ready for FOSS Release (Pending Testing)
✅ Core system fully functional
✅ All services deployed and working
✅ TLS certificates automatic
✅ DNS filtering active
⚠️ VPN needs live testing
⏳ Production stability testing needed

### Timeline
- **Now**: Live testing phase (user's home network)
- **1-2 weeks**: Production stability verification
- **Then**: FOSS v1.0 release (public GitHub)
- **Future**: Product release (commercial appliance)

---

## VPN Strategy Change

**Original Plan**: OpenVPN + WireGuard on OPNsense
**Current Plan**: Headscale only (self-hosted Tailscale control server)

**Rationale**:
- Headscale provides modern VPN with minimal configuration
- Tailscale clients available for all platforms
- Easier for users than managing OpenVPN configs
- Subnet routing built-in for accessing all services
- No port forwarding required (NAT traversal automatic)

**Implementation**:
- Headscale server running at https://10.10.20.10:4443
- Headplane UI for management at https://headplane.lan
- VM 101 acts as subnet router (10.10.20.x and 10.10.10.x)
- VPN clients use AdGuard for DNS filtering

---

## Notes

### Update Philosophy
- **Manual updates only** (user-initiated via Semaphore or web UIs)
- **Homer exception**: Auto-updates (display-only, low risk)
- **Rationale**: Respects user agency, prevents unexpected breakage, reduces liability

### Hardware Assumptions (FOSS)
- Proxmox already installed and configured
- Network access to Proxmox host
- Sufficient resources (8GB+ RAM recommended)
- Internet connectivity for pulling images/packages

### Hardware Requirements (Product)
- Intel N150 mini PC
- 16GB RAM (not 8GB)
- 256GB SSD
- Dual NICs
- VGA/HDMI for physical console
