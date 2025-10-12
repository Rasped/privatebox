# PrivateBox Naming Convention Proposal

**Purpose:** Establish consistent, logical naming that reflects how components fit together.

**Status:** PROPOSAL - Not yet implemented

---

## Current Problems

### Inconsistency 1: VM Names
- ✅ `privatebox-management` (has prefix)
- ❌ `opnsense` (no prefix - breaks pattern)
- ✅ `privatebox-subnet-router` (has prefix)

### Inconsistency 2: SSH Keys Don't Match VMs
- VM: `privatebox-management` → SSH Key: `container-host` (why different?)
- VM: `opnsense` → SSH Key: `opnsense-internal` (why add qualifier?)
- VM: `privatebox-subnet-router` → SSH Key: `subnet-router` (missing prefix)
- Proxmox host → SSH Key: `proxmox` (ok, but should be `pb-proxmox`?)

### Inconsistency 3: Inventories vs Keys
- Sometimes match: `proxmox` key → `proxmox` inventory
- Sometimes don't: `container-host` key → `container-host` inventory (but VM is `privatebox-management`)
- Added qualifiers: `opnsense-internal` (why "internal"?)

### Inconsistency 4: Environment Naming
- All use CamelCase (good consistency)
- But: `SemaphoreAPI`, `ServicePasswords`, `ProxmoxAPI` don't indicate scope
- No clear pattern for "what does this environment configure?"

---

## Design Principles

### 1. Hierarchical Consistency
```
Component Type → Instance Name → Purpose
    ↓                ↓              ↓
   pb-vm       →   mgmt         → (hosts services)
   pb-key      →   mgmt         → (accesses mgmt VM)
   pb-inv      →   mgmt         → (targets mgmt VM)
```

### 2. Self-Documenting Names
Names should answer:
- **What is it?** (VM, key, inventory, environment)
- **What does it do?** (manage, route, filter, store)
- **Where does it fit?** (infrastructure, services, security)

### 3. Pattern Matching
If `A` accesses `B`, their names should clearly show the relationship:
- VM `pb-mgmt` ← accessed by → SSH Key `pb-key-mgmt` → used in → Inventory `pb-inv-mgmt`

### 4. Avoid Redundancy
- Don't use qualifiers unless they add meaning (`opnsense-internal` → just `pb-firewall`)
- Don't duplicate context (`ServicePasswords` → `pb-env-passwords`)

---

## Proposed Naming Convention

### Prefix Strategy

**Primary Prefix:** `pb-` (short for PrivateBox, lowercase, easy to type)

**Secondary Prefixes** (by resource type):
- VMs: `pb-vm-{role}`
- SSH Keys: `pb-key-{target}`
- Inventories: `pb-inv-{target}`
- Environments: `pb-env-{purpose}`

**Alternative (flatter):**
- VMs: `pb-{role}` (simpler, still clear)
- SSH Keys: `pb-key-{role}` (explicit type)
- Inventories: `pb-inv-{role}` (explicit type)
- Environments: `pb-env-{purpose}` (explicit type)

### Recommended: Flatter Structure

Reasoning:
- VMs don't need `vm-` prefix (context is obvious: VM 9000 is a VM)
- Keys/inventories DO need type prefix (less obvious what `pb-mgmt` means in Semaphore)
- Environments DO need type prefix (could be confused with inventories)

---

## Proposed Naming Scheme

### VMs (Proxmox)

| Current Name | Proposed Name | VMID | Rationale |
|--------------|---------------|------|-----------|
| `privatebox-management` | `pb-mgmt` | 9000 | Shorter, clear role |
| `opnsense` | `pb-firewall` | 100 | Adds prefix, describes function (not brand) |
| `privatebox-subnet-router` | `pb-router` | 101 | Shorter, role-focused |

**Alternative consideration:**
- `pb-services` instead of `pb-mgmt` (describes what it hosts)
- `pb-gateway` instead of `pb-firewall` (broader term)
- `pb-vpn` instead of `pb-router` (more specific)

**Recommended:** `pb-mgmt`, `pb-firewall`, `pb-router` (balanced between brevity and clarity)

### SSH Keys (Semaphore)

| Current Name | Proposed Name | Target | Rationale |
|--------------|---------------|--------|-----------|
| `proxmox` | `pb-key-proxmox` | Proxmox host | Explicit type, consistent prefix |
| `container-host` | `pb-key-mgmt` | VM 9000 (pb-mgmt) | Matches VM role, clear purpose |
| `subnet-router` | `pb-key-router` | VM 101 (pb-router) | Matches VM role |
| `opnsense-internal` | `pb-key-firewall` | VM 100 (pb-firewall) | Matches VM role, removes qualifier |

**Pattern:** `pb-key-{target-role}`
- If target is a VM, use the VM's role name
- If target is infrastructure (Proxmox), use infrastructure name

### Inventories (Semaphore)

| Current Name | Proposed Name | Target Host(s) | Rationale |
|--------------|---------------|----------------|-----------|
| `container-host` | `pb-inv-mgmt` | 10.10.20.10 (pb-mgmt) | Matches VM role |
| `localhost` | `pb-inv-local` | localhost (Semaphore container) | More explicit |
| `proxmox` | `pb-inv-proxmox` | Proxmox host | Consistent prefix |
| `subnet-router` | `pb-inv-router` | 10.10.20.11 (pb-router) | Matches VM role |
| `opnsense-internal` | `pb-inv-firewall` | 10.10.20.1 (pb-firewall) | Matches VM role |

**Pattern:** `pb-inv-{target-role}`
- Inventory name should match the SSH key name (minus `key-`)
- Makes it obvious which key to use with which inventory

### Environments (Semaphore)

| Current Name | Proposed Name | Contains | Rationale |
|--------------|---------------|----------|-----------|
| `SemaphoreAPI` | `pb-env-semaphore` | Semaphore API token | Describes what system it configures |
| `ServicePasswords` | `pb-env-passwords` | Admin & service passwords | Describes content |
| `ProxmoxAPI` | `pb-env-proxmox` | Proxmox API credentials | Describes what system it configures |
| `DynamicDNS` | `pb-env-dns` | DNS provider credentials | Shorter, clear purpose |
| `OPNsenseAPI` | `pb-env-firewall` | OPNsense API credentials | Matches VM role (not brand) |

**Alternative patterns:**
- By scope: `pb-env-infra`, `pb-env-services`, `pb-env-security`
- By function: `pb-env-api-semaphore`, `pb-env-api-proxmox`, `pb-env-api-firewall`
- By content: `pb-env-creds-passwords`, `pb-env-creds-proxmox`, `pb-env-creds-dns`

**Recommended:** `pb-env-{system}` (simple, matches target system or content type)

---

## Complete Naming Matrix

### Infrastructure Layer

| Component | Type | Current | Proposed | Maps To |
|-----------|------|---------|----------|---------|
| Proxmox host | Host | (varies) | `pb-proxmox` | Physical/VM host |
| Proxmox SSH key | SSH Key | `proxmox` | `pb-key-proxmox` | `pb-proxmox` |
| Proxmox inventory | Inventory | `proxmox` | `pb-inv-proxmox` | `pb-proxmox` |
| Proxmox environment | Environment | `ProxmoxAPI` | `pb-env-proxmox` | Proxmox API |

### Management VM (VMID 9000)

| Component | Type | Current | Proposed | Maps To |
|-----------|------|---------|----------|---------|
| VM | VM | `privatebox-management` | `pb-mgmt` | VMID 9000 |
| SSH key | SSH Key | `container-host` | `pb-key-mgmt` | `pb-mgmt` VM |
| Inventory | Inventory | `container-host` | `pb-inv-mgmt` | `pb-mgmt` VM |
| Hosts | Playbook | `container-host` | `pb-mgmt` | Inventory group |

### Firewall VM (VMID 100)

| Component | Type | Current | Proposed | Maps To |
|-----------|------|---------|----------|---------|
| VM | VM | `opnsense` | `pb-firewall` | VMID 100 |
| SSH key | SSH Key | `opnsense-internal` | `pb-key-firewall` | `pb-firewall` VM |
| Inventory | Inventory | `opnsense-internal` | `pb-inv-firewall` | `pb-firewall` VM |
| Inventory host | Inventory YAML | `opnsense` | `pb-firewall` | Ansible host name |
| Environment | Environment | `OPNsenseAPI` | `pb-env-firewall` | Firewall API |

### Router VM (VMID 101)

| Component | Type | Current | Proposed | Maps To |
|-----------|------|---------|----------|---------|
| VM | VM | `privatebox-subnet-router` | `pb-router` | VMID 101 |
| SSH key | SSH Key | `subnet-router` | `pb-key-router` | `pb-router` VM |
| Inventory | Inventory | `subnet-router` | `pb-inv-router` | `pb-router` VM |
| Inventory host | Inventory YAML | `subnet-router` | `pb-router` | Ansible host name |

### Semaphore Container

| Component | Type | Current | Proposed | Maps To |
|-----------|------|---------|----------|---------|
| Inventory | Inventory | `localhost` | `pb-inv-local` | Semaphore container |
| Environment | Environment | `SemaphoreAPI` | `pb-env-semaphore` | Semaphore API |

### Service Credentials

| Component | Type | Current | Proposed | Maps To |
|-----------|------|---------|----------|---------|
| Environment | Environment | `ServicePasswords` | `pb-env-passwords` | Admin/service passwords |
| Environment | Environment | `DynamicDNS` | `pb-env-dns` | DNS provider API |

---

## Naming Patterns Summary

### Pattern 1: Role-Based Matching
```
VM: pb-{role}
  ↓
SSH Key: pb-key-{role}
  ↓
Inventory: pb-inv-{role}
  ↓
Inventory Host: pb-{role}
```

**Example:**
```
VM: pb-mgmt (VMID 9000)
  → SSH Key: pb-key-mgmt
  → Inventory: pb-inv-mgmt
    → Inventory YAML host: pb-mgmt
```

### Pattern 2: API Environment Matching
```
VM: pb-{role}
  ↓
Environment: pb-env-{role}
```

**Example:**
```
VM: pb-firewall
  → Environment: pb-env-firewall (contains OPNsense API creds)

Infrastructure: Proxmox
  → Environment: pb-env-proxmox (contains Proxmox API creds)
```

### Pattern 3: Scope-Based Environments
```
Scope: {system or content type}
  ↓
Environment: pb-env-{system}
```

**Examples:**
```
pb-env-passwords     → Service/admin passwords
pb-env-dns           → DNS provider credentials
pb-env-semaphore     → Semaphore API token
```

---

## Playbook Usage After Renaming

### Current Pattern
```yaml
- name: "Service Deploy"
  hosts: container-host              # Inventory host name

  vars:
    template_config:
      semaphore_environment: "ServicePasswords"
      semaphore_inventory: "container-host"
```

### Proposed Pattern
```yaml
- name: "Service Deploy"
  hosts: pb-mgmt                     # Clearer role reference

  vars:
    template_config:
      semaphore_environment: "pb-env-passwords"
      semaphore_inventory: "pb-inv-mgmt"
```

**Benefits:**
1. `hosts: pb-mgmt` immediately shows this runs on management VM
2. `pb-inv-mgmt` clearly indicates inventory targeting mgmt VM
3. `pb-env-passwords` shows environment contains password credentials
4. All use consistent `pb-` prefix for easy searching

---

## Migration Impact Analysis

### Low Impact (Easy to Change)
✅ **VM names** - Cosmetic, rarely referenced in code
- Only affects `qm create --name` commands
- Update in 3 files: `bootstrap/create-vm.sh`, `deploy-opnsense.sh`, `subnet-router-deploy.yml`

### Medium Impact (Semaphore UI + Code)
⚠️ **SSH Key names** - Must update in Semaphore + creation code
- Update creation scripts (4 locations)
- Manual rename in Semaphore UI OR recreate keys
- Impact: ~5 files

⚠️ **Environment names** - Must update in Semaphore + many playbooks
- Update creation scripts (5 locations)
- Manual rename in Semaphore UI OR recreate environments
- Update ALL playbooks referencing them (20+ files)
- Impact: High file count, but automated with search/replace

### High Impact (Inventory + Playbook Changes)
❌ **Inventory names** - Must update everywhere
- Update creation scripts (5 locations)
- Manual rename in Semaphore UI OR recreate inventories
- Update `semaphore_inventory` in template_config (15+ playbooks)
- Update `hosts:` declarations in playbooks (15+ playbooks)
- Update inventory YAML host names (5 locations)
- Impact: ~30+ files

**Estimated Total Files to Change:** 40-50 files

---

## Phased Migration Strategy

### Phase 1: New Resources Only (Safest)
- Apply new naming convention ONLY to newly created resources
- Keep existing names unchanged
- Pros: Zero breakage, gradual adoption
- Cons: Inconsistency persists

### Phase 2: VMs Only (Low Risk)
- Rename VMs to `pb-mgmt`, `pb-firewall`, `pb-router`
- Keep all Semaphore resources unchanged
- Pros: Minimal impact, immediate UI improvement
- Cons: VM names still won't match keys/inventories

### Phase 3: Full Migration (High Value, High Effort)
1. **Prepare:**
   - Document all current references
   - Create search/replace script
   - Backup Semaphore database

2. **Rename in Semaphore UI:**
   - SSH Keys: 4 renames
   - Inventories: 5 renames (update internal YAML hosts too)
   - Environments: 5 renames

3. **Update Code:**
   - Bootstrap scripts: ~10 files
   - Playbooks: ~30 files
   - Documentation: ~5 files

4. **Verify:**
   - Run `Generate Templates` task
   - Test each service deployment
   - Validate all playbooks in Semaphore

**Estimated Migration Time:** 3-4 hours (with search/replace automation)

---

## Recommended Action

### Option A: Full Migration (Recommended for Long-Term)
**When:** Before production deployment, during development/testing phase
**Why:** Establishes clean foundation, prevents tech debt
**Effort:** High (40-50 files)
**Risk:** Medium (comprehensive testing required)

### Option B: VM Names Only (Quick Win)
**When:** Immediately
**Why:** Low-hanging fruit, improves Proxmox UI clarity
**Effort:** Low (3 files)
**Risk:** Very low (cosmetic change)

### Option C: New Convention Going Forward
**When:** Now (for new resources)
**Why:** No breaking changes, gradual improvement
**Effort:** Minimal (apply to new additions)
**Risk:** None (existing resources unchanged)

---

## Implementation Checklist

If choosing **Option A (Full Migration)**:

### Pre-Migration
- [ ] Backup Semaphore database: `sqlite3 /path/to/semaphore.db .dump > backup.sql`
- [ ] Export all environment secrets (API can't read them)
- [ ] Document current template IDs and task IDs
- [ ] Create git branch: `git checkout -b naming-convention-migration`

### Migration Steps
- [ ] **VMs:** Update VM names in 3 files
- [ ] **SSH Keys:**
  - [ ] Update creation code (4 files)
  - [ ] Rename in Semaphore UI or recreate
- [ ] **Inventories:**
  - [ ] Update creation code (5 files)
  - [ ] Update inventory YAML host names (5 files)
  - [ ] Rename in Semaphore UI or recreate
- [ ] **Environments:**
  - [ ] Update creation code (5 files)
  - [ ] Rename in Semaphore UI or recreate
  - [ ] Update playbook `template_config` blocks (20+ files)
- [ ] **Playbook hosts:**
  - [ ] Update `hosts:` declarations (15+ files)
- [ ] **Documentation:**
  - [ ] Update CLAUDE.md
  - [ ] Update NAMING-CONVENTIONS.md
  - [ ] Update LLM-GUIDE.md
  - [ ] Update playbook README.md

### Verification
- [ ] Run: `grep -r "container-host\|opnsense-internal\|subnet-router" ansible/ bootstrap/`
  - Should find NO matches in active code
- [ ] Run `Generate Templates` task in Semaphore
- [ ] Test deploy one service (AdGuard or Homer)
- [ ] Verify Proxmox UI shows new VM names
- [ ] Check all Semaphore templates created correctly

### Rollback Plan
- [ ] Keep git branch with old names: `git branch naming-convention-old`
- [ ] Keep Semaphore DB backup
- [ ] Document manual Semaphore resource names before changes

---

## Search/Replace Script

To assist with migration, here's a comprehensive search/replace guide:

```bash
# VM names (simple, low risk)
find . -type f \( -name "*.sh" -o -name "*.yml" -o -name "*.md" \) -exec sed -i '' \
  -e 's/privatebox-management/pb-mgmt/g' \
  -e 's/privatebox-subnet-router/pb-router/g' \
  {} +

# OPNsense requires more care (brand name appears in many contexts)
# Manual review recommended for: opnsense → pb-firewall

# SSH Keys (requires careful context checking)
find ansible/ bootstrap/ -type f \( -name "*.sh" -o -name "*.yml" \) -exec sed -i '' \
  -e 's/"container-host"/"pb-key-mgmt"/g' \
  -e 's/"subnet-router"/"pb-key-router"/g' \
  -e 's/"opnsense-internal"/"pb-key-firewall"/g' \
  -e 's/"proxmox"/"pb-key-proxmox"/g' \
  {} +

# Inventories (high impact, verify each change)
find ansible/ bootstrap/ -type f \( -name "*.sh" -o -name "*.yml" \) -exec sed -i '' \
  -e 's/semaphore_inventory: "container-host"/semaphore_inventory: "pb-inv-mgmt"/g' \
  -e 's/semaphore_inventory: "localhost"/semaphore_inventory: "pb-inv-local"/g' \
  -e 's/semaphore_inventory: "proxmox"/semaphore_inventory: "pb-inv-proxmox"/g' \
  -e 's/semaphore_inventory: "subnet-router"/semaphore_inventory: "pb-inv-router"/g' \
  -e 's/semaphore_inventory: "opnsense-internal"/semaphore_inventory: "pb-inv-firewall"/g' \
  {} +

# Hosts declarations
find ansible/playbooks/ -type f -name "*.yml" -exec sed -i '' \
  -e 's/^  hosts: container-host$/  hosts: pb-mgmt/g' \
  -e 's/^  hosts: subnet-router$/  hosts: pb-router/g' \
  -e 's/^- hosts: container-host$/- hosts: pb-mgmt/g' \
  {} +

# Environments
find ansible/ bootstrap/ -type f \( -name "*.sh" -o -name "*.yml" \) -exec sed -i '' \
  -e 's/"SemaphoreAPI"/"pb-env-semaphore"/g' \
  -e 's/"ServicePasswords"/"pb-env-passwords"/g' \
  -e 's/"ProxmoxAPI"/"pb-env-proxmox"/g' \
  -e 's/"DynamicDNS"/"pb-env-dns"/g' \
  -e 's/"OPNsenseAPI"/"pb-env-firewall"/g' \
  {} +
```

**IMPORTANT:** Review all changes with `git diff` before committing!

---

## Questions for Decision

1. **Scope:** Full migration now, or gradual adoption?
2. **VM names:** `pb-mgmt` or `pb-services`? `pb-firewall` or `pb-gateway`?
3. **Environment pattern:** `pb-env-{system}` or `pb-env-api-{system}`?
4. **Timing:** Before or after production deployment?
5. **Inventory hosts:** Keep simple names like `pb-mgmt` or be more explicit like `management`?

---

## Recommendation

**For PrivateBox in current development phase:**

✅ **Implement Full Migration (Option A)**

**Reasons:**
1. You're not in production yet - ideal time for breaking changes
2. Clean foundation prevents tech debt accumulation
3. Self-documenting names reduce cognitive load
4. Easier onboarding for future contributors
5. More professional appearance (consistent branding)

**Naming choices:**
- VMs: `pb-mgmt`, `pb-firewall`, `pb-router` (clear roles)
- Keys: `pb-key-{role}` (explicit type)
- Inventories: `pb-inv-{role}` (explicit type)
- Environments: `pb-env-{system}` (simple, clear)

**Next step:** Create implementation branch and start with VM names (low-risk quick win).
