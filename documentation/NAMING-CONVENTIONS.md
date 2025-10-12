# PrivateBox Naming Conventions

**Purpose:** Official naming standard for all VMs, Semaphore resources, and infrastructure components.

**Last Updated:** 2025-10-12

**Status:** ✅ IMPLEMENTED

---

## Naming Philosophy

### Core Principles

1. **Consistent Branding:** All resources use `privatebox-` prefix to reinforce product identity
2. **Unified Names:** VMs, SSH keys, and inventories share the same base name (no unnecessary prefixes)
3. **Explicit Environment Names:** Environments use `privatebox-env-` prefix to distinguish them from other resources
4. **Self-Documenting:** Names clearly indicate purpose and relationships

### Pattern Summary

```
VMs:              privatebox-{role}
SSH Keys:         privatebox-{role}      (matches VM name)
Inventories:      privatebox-{role}      (matches VM/key name)
Environments:     privatebox-env-{purpose}
```

---

## Complete Naming Reference

### VMs (Proxmox)

| VM ID | VM Name | Purpose | IP Addresses |
|-------|---------|---------|--------------|
| **9000** | `privatebox-management` | Services host (Portainer, Semaphore, AdGuard, etc.) | 10.10.20.10 |
| **100** | `privatebox-opnsense` | Firewall/Router | 10.10.20.1, 10.10.10.1 |
| **101** | `privatebox-subnet-router` | Tailscale subnet router | 10.10.20.11, 10.10.10.10 |

### SSH Keys (Semaphore)

| SSH Key Name | Accesses | Used In Inventory |
|--------------|----------|-------------------|
| `privatebox-management` | Management VM (9000) | `privatebox-management` |
| `privatebox-opnsense` | OPNsense VM (100) | `privatebox-opnsense` |
| `privatebox-subnet-router` | Subnet router VM (101) | `privatebox-subnet-router` |
| `privatebox-proxmox` | Proxmox hypervisor host | `privatebox-proxmox` |

### Inventories (Semaphore)

| Inventory Name | Target Host | Ansible Host Name | Purpose |
|----------------|-------------|-------------------|---------|
| `privatebox-management` | 10.10.20.10 | `privatebox-management` | Run playbooks on management VM |
| `privatebox-opnsense` | 10.10.20.1 | `privatebox-opnsense` | Manage OPNsense firewall |
| `privatebox-subnet-router` | 10.10.20.11 | `privatebox-subnet-router` | Manage Tailscale router |
| `privatebox-proxmox` | Proxmox host | `privatebox-proxmox` | Access Proxmox for VM management |
| `privatebox-local` | localhost | `localhost` | Run tasks inside Semaphore container |

### Environments (Semaphore)

| Environment Name | Variables (JSON) | Secrets | Purpose |
|------------------|------------------|---------|---------|
| `privatebox-env-semaphore` | `SEMAPHORE_URL` | `SEMAPHORE_API_TOKEN` | Semaphore API authentication |
| `privatebox-env-passwords` | — | `ADMIN_PASSWORD`<br>`SERVICES_PASSWORD` | Centralized service credentials |
| `privatebox-env-proxmox` | — | `PROXMOX_TOKEN_ID`<br>`PROXMOX_TOKEN_SECRET`<br>`PROXMOX_API_HOST`<br>`PROXMOX_NODE` | Proxmox API access |
| `privatebox-env-dns` | `DNS_PROVIDER`<br>`DDNS_DOMAIN`<br>`LETSENCRYPT_EMAIL` | `DNS_API_TOKEN` | Dynamic DNS configuration |
| `privatebox-env-opnsense` | — | `OPNSENSE_API_URL`<br>`OPNSENSE_API_KEY`<br>`OPNSENSE_API_SECRET` | OPNsense API access |

---

## Usage Patterns

### Standard Service Deployment

Most service deployment playbooks follow this pattern:

```yaml
- name: "Service Deploy"
  hosts: privatebox-management

  vars:
    template_config:
      semaphore_environment: "privatebox-env-passwords"
      semaphore_inventory: "privatebox-management"
```

**Resources used:**
- **Hosts:** `privatebox-management` (management VM)
- **Inventory:** `privatebox-management` (automatically uses matching SSH key)
- **Environment:** `privatebox-env-passwords` (for service credentials)

### Template Generation

Template generator runs inside Semaphore container:

```yaml
- name: "Generate Templates"
  hosts: localhost

  vars:
    template_config:
      semaphore_environment: "privatebox-env-semaphore"
      semaphore_inventory: "privatebox-local"
```

**Resources used:**
- **Hosts:** `localhost` (Semaphore container)
- **Inventory:** `privatebox-local` (local execution)
- **Environment:** `privatebox-env-semaphore` (API token)

### Infrastructure Management

Subnet router deployment uses Proxmox:

```yaml
- name: "Subnet Router Deploy"
  hosts: privatebox-proxmox

  vars:
    template_config:
      semaphore_environment: "privatebox-env-semaphore"
      semaphore_inventory: "privatebox-proxmox"
```

**Resources used:**
- **Hosts:** `privatebox-proxmox` (Proxmox hypervisor)
- **Inventory:** `privatebox-proxmox` (with privatebox-proxmox SSH key)
- **Environment:** `privatebox-env-semaphore` (for Semaphore API calls)

### OPNsense Management

OPNsense firewall configuration:

```yaml
- name: "OPNsense Configure"
  hosts: privatebox-opnsense

  vars:
    template_config:
      semaphore_environment: "privatebox-env-opnsense"
      semaphore_inventory: "privatebox-opnsense"
```

**Resources used:**
- **Hosts:** `privatebox-opnsense` (OPNsense VM)
- **Inventory:** `privatebox-opnsense` (with privatebox-opnsense SSH key)
- **Environment:** `privatebox-env-opnsense` (OPNsense API credentials)

---

## Relationship Matrix

### Name Matching Pattern

```
VM: privatebox-management
  ├─ SSH Key: privatebox-management  ← Same name!
  ├─ Inventory: privatebox-management  ← Same name!
  │   └─ Host: privatebox-management  ← Same name!
  └─ Used in playbooks with: hosts: privatebox-management
```

### Environment Mapping

```
Purpose: Semaphore API access
  └─ Environment: privatebox-env-semaphore
      └─ Contains: SEMAPHORE_API_TOKEN

Purpose: Service passwords
  └─ Environment: privatebox-env-passwords
      └─ Contains: ADMIN_PASSWORD, SERVICES_PASSWORD

Purpose: Proxmox API
  └─ Environment: privatebox-env-proxmox
      └─ Contains: PROXMOX_TOKEN_ID, PROXMOX_TOKEN_SECRET

Purpose: Dynamic DNS
  └─ Environment: privatebox-env-dns
      └─ Contains: DNS_API_TOKEN, DNS_PROVIDER, DDNS_DOMAIN

Purpose: OPNsense API
  └─ Environment: privatebox-env-opnsense
      └─ Contains: OPNSENSE_API_KEY, OPNSENSE_API_SECRET
```

---

## Implementation Files

### Bootstrap Scripts

**VMs:**
- `bootstrap/create-vm.sh:238` - `privatebox-management`
- `bootstrap/deploy-opnsense.sh:54` - `privatebox-opnsense`

**SSH Keys:**
- `bootstrap/lib/semaphore-api.sh:1111` - Creates `privatebox-proxmox`
- `bootstrap/lib/semaphore-api.sh:1142` - Creates `privatebox-management`

**Inventories:**
- `bootstrap/lib/semaphore-api.sh:1028` - Creates `privatebox-management`
- `bootstrap/lib/semaphore-api.sh:1039` - Creates `privatebox-local`
- `bootstrap/lib/semaphore-api.sh:1056` - Creates `privatebox-proxmox`

**Environments:**
- `bootstrap/lib/semaphore-api.sh:139` - Creates `privatebox-env-semaphore`
- `bootstrap/lib/semaphore-api.sh:417` - Creates `privatebox-env-passwords`
- `bootstrap/lib/semaphore-api.sh:323` - Creates `privatebox-env-proxmox`

### Ansible Playbooks

**SSH Key Creation:**
- `ansible/playbooks/infrastructure/subnet-router-deploy.yml:304` - Creates `privatebox-subnet-router`
- `ansible/playbooks/services/opnsense-semaphore-integration.yml:31` - Creates `privatebox-opnsense`

**Inventory Creation:**
- `ansible/playbooks/infrastructure/subnet-router-deploy.yml:349` - Creates `privatebox-subnet-router`
- `ansible/playbooks/services/opnsense-semaphore-integration.yml:32` - Creates `privatebox-opnsense`

**Environment Creation:**
- `ansible/playbooks/services/ddns-1-setup-environment.yml:73` - Creates `privatebox-env-dns`
- `ansible/playbooks/services/opnsense-semaphore-integration.yml:103` - Creates `privatebox-env-opnsense`

---

## Verification Commands

### Check VM Names

```bash
# On Proxmox
qm list | grep privatebox

# Expected output:
#   9000 privatebox-management   running
#   100  privatebox-opnsense      running
#   101  privatebox-subnet-router running
```

### Check Semaphore Resources

```bash
# SSH keys
ssh root@192.168.1.10 "curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/project/1/keys | jq -r '.[].name'"

# Expected:
# privatebox-proxmox
# privatebox-management
# privatebox-subnet-router
# privatebox-opnsense

# Inventories
ssh root@192.168.1.10 "curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/project/1/inventory | jq -r '.[].name'"

# Expected:
# privatebox-management
# privatebox-local
# privatebox-proxmox
# privatebox-subnet-router
# privatebox-opnsense

# Environments
ssh root@192.168.1.10 "curl -sSk --cookie /tmp/sem.cookies https://10.10.20.10:2443/api/project/1/environment | jq -r '.[].name'"

# Expected:
# privatebox-env-passwords
# privatebox-env-proxmox
# privatebox-env-semaphore
# privatebox-env-dns
# privatebox-env-opnsense
```

### Check Playbook References

```bash
# Find all inventory references
grep -r 'semaphore_inventory:' ansible/playbooks/ | cut -d'"' -f2 | sort -u

# Expected:
# privatebox-local
# privatebox-management
# privatebox-opnsense
# privatebox-proxmox
# privatebox-subnet-router

# Find all environment references
grep -r 'semaphore_environment:' ansible/playbooks/ | cut -d'"' -f2 | sort -u

# Expected:
# privatebox-env-dns
# privatebox-env-opnsense
# privatebox-env-passwords
# privatebox-env-proxmox
# privatebox-env-semaphore

# Find all hosts declarations
grep -r '^  hosts:' ansible/playbooks/ | awk '{print $3}' | sort -u

# Expected:
# localhost
# privatebox-management
# privatebox-opnsense
# privatebox-proxmox
# privatebox-subnet-router
```

---

## Migration Notes

This naming convention was implemented on 2025-10-12. Changes from previous naming:

### VMs
- ✅ `privatebox-management` (unchanged)
- 📝 `opnsense` → `privatebox-opnsense`
- ✅ `privatebox-subnet-router` (unchanged)

### SSH Keys
- 📝 `container-host` → `privatebox-management`
- 📝 `opnsense-internal` → `privatebox-opnsense`
- 📝 `subnet-router` → `privatebox-subnet-router`
- 📝 `proxmox` → `privatebox-proxmox`

### Inventories
- 📝 `container-host` → `privatebox-management`
- 📝 `localhost` → `privatebox-local`
- 📝 `proxmox` → `privatebox-proxmox`
- 📝 `subnet-router` → `privatebox-subnet-router`
- 📝 `opnsense-internal` → `privatebox-opnsense`

### Environments
- 📝 `SemaphoreAPI` → `privatebox-env-semaphore`
- 📝 `ServicePasswords` → `privatebox-env-passwords`
- 📝 `ProxmoxAPI` → `privatebox-env-proxmox`
- 📝 `DynamicDNS` → `privatebox-env-dns`
- 📝 `OPNsenseAPI` → `privatebox-env-opnsense`

**Total files updated:** ~45 files across bootstrap scripts, ansible playbooks, and documentation

---

## Benefits

### Product Branding
- Every resource reinforces "PrivateBox" brand
- Professional appearance for €399 commercial product
- Clear distinction from DIY/hobbyist setups

### Consistency
- Same name used for VM, SSH key, and inventory
- Easy to remember: "privatebox-management" for everything related to management VM
- Pattern recognition: `privatebox-{role}` for infrastructure, `privatebox-env-{purpose}` for configuration

### Clarity
- `privatebox-env-` prefix immediately identifies environments
- No confusion between `privatebox-opnsense` (VM) and `privatebox-env-opnsense` (credentials)
- Self-documenting in Semaphore UI dropdowns

### Searchability
- `grep privatebox-management` finds all references
- `grep privatebox-env-` finds all environments
- Easy to distinguish resource types

---

## Related Documentation

- `CLAUDE.md` - Quick reference guide
- `documentation/LLM-GUIDE.md` - Detailed architecture
- `documentation/network-architecture/vlan-design.md` - Network topology
- `ansible/README.md` - Playbook conventions
