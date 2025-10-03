# HANDOVER: Subnet Router VM Deployment - 2025-10-03

## Executive Summary

**Goal**: Deploy Alpine Linux VM (101) as Headscale VPN subnet router with dual network interfaces and automatic Semaphore registration.

**Status**: Playbook implemented, needs testing from clean slate.

---

## What We're Building

### The Problem
- Headscale VPN server deployed on Management VM (10.10.20.10)
- Need remote devices to access LAN (10.10.10.0/24) via VPN
- Headscale uses "subnet routers" to advertise network routes

### The Solution
- Dedicated Alpine Linux VM (101) on LAN that acts as subnet router
- VM has dual IPs:
  - **LAN (10.10.10.10)**: Primary interface for routing VPN traffic
  - **Services (10.10.20.11)**: Management interface for Semaphore
- VM generates its own SSH key pair
- SSH key registered in Semaphore automatically
- VM added to Semaphore inventory for ongoing management

### Why This Design
1. **Security isolation**: Each VM has its own SSH identity
2. **Clean separation**: Services VLAN ↔ LAN boundary maintained
3. **Semaphore-managed**: VM can be configured via Semaphore after deployment
4. **Scalable pattern**: Can deploy multiple subnet routers for different VLANs

---

## Current Implementation

### Playbook: `ansible/playbooks/infrastructure/subnet-router-deploy.yml`

**What it does:**

1. **Phase 1: Create Alpine VM**
   - Downloads Alpine 3.19 cloud image (nocloud)
   - Creates VM 101: 256MB RAM, 1 CPU, 2GB disk
   - Dual NICs: vmbr1 VLAN 10 (LAN) + vmbr1 VLAN 20 (Services)
   - Cloud-init with simple password "alpine" (temporary)
   - No SSH key injection from Proxmox

2. **Phase 2: Generate SSH Key on Alpine**
   - SSH to Alpine using password "alpine"
   - Generate ed25519 key pair: `/home/alpine/.ssh/id_ed25519`
   - Add public key to authorized_keys
   - Retrieve private key content

3. **Phase 3: Register in Semaphore**
   - Save private key to temp file on Proxmox
   - Call Semaphore API: `POST /api/project/1/keys` with private key
   - Get SSH key ID back
   - Create inventory: `POST /api/project/1/inventory`
   - Inventory points to 10.10.20.11 with SSH key
   - Clean up temp files

**Key features:**
- Idempotent: checks if SSH key/inventory already exist
- Uses `sshpass` for initial password auth
- Ignores known_hosts to avoid conflicts
- Self-contained: VM has its own identity

**Security status after deployment:**
- Password: `alpine` (TEMPORARY - only on internal Services VLAN)
- SSH key auth: enabled
- Registered in Semaphore for management

---

## Environment Requirements

### The Template Needs
- **Environment**: SemaphoreAPI (provides `SEMAPHORE_API_TOKEN`)
- **Inventory**: proxmox
- **Repository**: PrivateBox repository

### Why SemaphoreAPI?
Playbook needs to call Semaphore API to:
- Register SSH key
- Create inventory entry
- No passwords needed (only API token)

**Note**: Template generation may need adjustment to pick up correct environment.

---

## Next Steps (For New Context)

### 1. Clean Slate
```bash
# On Proxmox
qm list
# Delete VMs 100, 101 if they exist
qm stop 100 && qm destroy 100
qm stop 101 && qm destroy 101

# Run quickstart
ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash"
```

Wait ~5-10 minutes for:
- Management VM (100) creation
- Portainer + Semaphore setup
- OPNsense deployment
- AdGuard, Headscale, Homer services

### 2. Verify Bootstrap Complete
```bash
# Check services running
ssh root@192.168.1.10 "ssh debian@10.10.20.10 'podman ps'"

# Should see: semaphore, portainer, adguard, headscale, homer
```

### 3. Test Subnet Router Deployment

**Option A: Via Semaphore UI**
1. Login: http://10.10.20.10:3000 (admin / SERVICES_PASSWORD from config)
2. Run "Generate Templates" task
3. Find "Subnet Router: Create Alpine VM" template
4. **Verify environment is set to "SemaphoreAPI"** (not ServicePasswords)
5. Run template
6. Monitor task output

**Option B: Via API**
```bash
# Get Semaphore cookie
ssh root@192.168.1.10 "curl -sS --cookie-jar /tmp/sem.cookies -X POST \
  -H 'Content-Type: application/json' \
  -d '{\"auth\":\"admin\",\"password\":\"<SERVICES_PASSWORD>\"}' \
  http://10.10.20.10:3000/api/auth/login"

# Generate templates
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies -X POST \
  -H 'Content-Type: application/json' \
  -d '{\"template_id\":1,\"debug\":false,\"dry_run\":false}' \
  http://10.10.20.10:3000/api/project/1/tasks | jq -r '.id'"

# Wait ~10 seconds, then run subnet router template (ID likely 10)
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies -X POST \
  -H 'Content-Type: application/json' \
  -d '{\"template_id\":10,\"debug\":false,\"dry_run\":false}' \
  http://10.10.20.10:3000/api/project/1/tasks | jq -r '.id'"

# Monitor task (replace TASK_ID)
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies \
  http://10.10.20.10:3000/api/project/1/tasks/TASK_ID | jq '.status'"
```

### 4. Verify Success

**Check VM created:**
```bash
ssh root@192.168.1.10 "qm status 101"
# Should show: status: running
```

**Check dual IPs:**
```bash
ssh root@192.168.1.10 "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null alpine@10.10.20.11 'ip a | grep \"inet \"'"
# Should show:
#   inet 10.10.10.10/24 on eth0
#   inet 10.10.20.11/24 on eth1
```

**Check Semaphore inventory:**
```bash
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies \
  http://10.10.20.10:3000/api/project/1/inventory | jq '.[] | {name, inventory}'"
# Should include: {"name": "subnet-router", "inventory": "subnet-router ansible_host=10.10.20.11 ansible_user=alpine"}
```

**Check SSH key registered:**
```bash
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies \
  http://10.10.20.10:3000/api/project/1/keys | jq '.[] | {name, type}'"
# Should include: {"name": "subnet-router", "type": "ssh"}
```

**Test Semaphore can manage VM:**
Create simple test playbook targeting `subnet-router` inventory via Semaphore.

---

## Known Issues

### Environment ID Confusion
The template generation script may create template with wrong environment ID:
- Expected: `environment_id: 4` (SemaphoreAPI)
- May get: `environment_id: 2` (ServicePasswords)

**Symptom**: Task fails with `'SEMAPHORE_API_TOKEN' is undefined`

**Fix**: Manually update template environment via Semaphore UI or API before running.

### sshpass Dependency
Playbook uses `sshpass` for initial password auth. This should be installed on Proxmox during quickstart, but verify if task fails.

---

## Files Modified

```
ansible/playbooks/infrastructure/subnet-router-deploy.yml
  - Complete Alpine VM deployment with Semaphore registration
  - 344 lines, fully automated

tools/generate-templates.py
  - Added support for infrastructure/ subdirectory
  - Dynamic playbook path construction

.claude/settings.local.json
  - Updated allowed tools (not committed)
```

---

## Architecture Context

### Network Design
```
WAN (vmbr0)
  └─ OPNsense WAN interface

LAN (vmbr1, no VLAN tag)
  ├─ 10.10.10.0/24 - Trusted devices
  └─ Subnet Router: 10.10.10.10

Services VLAN (vmbr1, VLAN 20)
  ├─ 10.10.20.0/24 - Infrastructure services
  ├─ OPNsense: 10.10.20.1
  ├─ Management VM: 10.10.20.10 (Semaphore, Portainer, AdGuard, Headscale, Homer)
  └─ Subnet Router (mgmt): 10.10.20.11
```

### Headscale VPN Flow (Future)
```
Remote Phone
  ↓ (WireGuard, 100.64.0.x)
Subnet Router VM (10.10.10.10)
  ↓ (IP forwarding)
LAN Device (10.10.10.50)
```

### Why Dual IPs?
- **Services IP (10.10.20.11)**: Semaphore management, SSH access from Management VM
- **LAN IP (10.10.10.10)**: VPN traffic routing, advertised as subnet router
- Keeps Services ↔ LAN security boundary intact

---

## Future Work

### After VM Deploys Successfully

1. **Secure VM playbook** (`subnet-router-secure.yml`)
   - Runs on: `subnet-router` inventory
   - Environment: `ServicePasswords`
   - Changes password from "alpine" to `SERVICES_PASSWORD`
   - Disables password auth (SSH key only)

2. **Configure Tailscale** (`subnet-router-configure.yml`)
   - Runs on: `subnet-router` inventory
   - Install Tailscale from Alpine repos
   - Connect to Headscale at 10.10.20.10:8082
   - Advertise 10.10.10.0/24 subnet
   - Enable IP forwarding

3. **Approve routes in Headscale**
   - Run on: `container-host` inventory
   - Enable subnet routes via Headscale API

4. **OPNsense firewall rules**
   - Add WAN → Headscale (10.10.20.10:8082) for remote enrollment
   - Already have: LAN → Services (for management)

5. **Test end-to-end VPN**
   - Connect phone via Headscale
   - Verify can reach 10.10.10.x devices
   - Verify can reach Services VLAN (10.10.20.x) via LAN → Services rule

---

## Passwords Reference

From quickstart output (stored in `/etc/privatebox/config.env` on Management VM):
```
ADMIN_PASSWORD: <generated during quickstart>
SERVICES_PASSWORD: <generated during quickstart>
```

Get them:
```bash
ssh root@192.168.1.10 "ssh debian@10.10.20.10 'source /etc/privatebox/config.env && echo SERVICES=\$SERVICES_PASSWORD'"
```

---

## Debugging Tips

**If template generation fails:**
```bash
# Check playbook syntax
ansible-playbook --syntax-check ansible/playbooks/infrastructure/subnet-router-deploy.yml

# Check template_config is parsed correctly
grep -A 5 "template_config:" ansible/playbooks/infrastructure/subnet-router-deploy.yml
```

**If Semaphore API calls fail:**
```bash
# Verify API token exists
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies \
  http://10.10.20.10:3000/api/project/1/environment/4 | jq '.secrets'"
# Should show SEMAPHORE_API_TOKEN

# Test API manually
ssh root@192.168.1.10 "ssh debian@10.10.20.10 'source /etc/privatebox/config.env && \
  curl -H \"Authorization: Bearer \$SEMAPHORE_API_TOKEN\" \
  http://localhost:3000/api/project/1/keys | jq length'"
```

**If VM boots but SSH fails:**
```bash
# Check VM console
ssh root@192.168.1.10 "qm terminal 101"
# Login as: alpine / alpine
# Check: ip a, cat /etc/network/interfaces, cat /etc/passwd
```

---

## Expected Timeline

- Quickstart: 5-10 minutes
- Generate templates: 10 seconds
- Subnet router deploy: 1-2 minutes
  - Alpine image download: 30 seconds (if not cached)
  - VM creation: 10 seconds
  - Cloud-init boot: 30 seconds
  - SSH key generation: 5 seconds
  - Semaphore registration: 10 seconds

**Total**: ~15-20 minutes from zero to subnet router registered in Semaphore.

---

END HANDOVER
