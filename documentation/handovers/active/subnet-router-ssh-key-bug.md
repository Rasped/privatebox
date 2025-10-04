# Handover: Subnet Router SSH Key Bug

**Status**: Blocker for VPN Testing
**Created**: 2025-10-04
**Context**: Subnet router deployment works, but SSH key registration prevents subsequent runs

---

## Current State

### What Works ✅
1. **Subnet Router VM deployment (Debian 13)**
   - VM 101 creates successfully
   - Cloud-init completes without errors
   - Tailscale installed via APT repository
   - Network connectivity works (DNS, internet)
   - SSH key generated on VM

2. **All previous orchestration steps**
   - AdGuard, OPNsense, Headscale all deploy successfully
   - HeadscalePreauthKey environment works correctly
   - Ansible variables (not env lookup) work for secrets

### What's Broken ❌
**Subnet Router 2 template cannot SSH to the VM after re-runs**

**Root Cause**: SSH key management bug in `subnet-router-deploy.yml`

---

## The Bug Explained

### Current Behavior
```yaml
# Lines 278-289 in subnet-router-deploy.yml
- name: Check if SSH key already exists in Semaphore
  uri:
    url: "{{ semaphore_url }}/api/project/{{ project_id }}/keys"
    ...
  register: existing_keys

- name: Parse existing key ID
  set_fact:
    existing_key_id: "{{ (existing_keys.json | selectattr('name', 'equalto', 'subnet-router') | first).id | default(0) }}"

- name: Register SSH key in Semaphore
  ...
  when: existing_key_id | int == 0  # ← ONLY creates if doesn't exist
```

### The Problem
1. **First run (Alpine)**: Creates SSH key, registers as "subnet-router" in Semaphore ✅
2. **Delete VM 101, redeploy with Debian**:
   - VM generates **new** SSH key (different from Alpine)
   - Playbook checks Semaphore: "subnet-router" key exists (ID != 0)
   - Playbook **skips** registration (`when: existing_key_id | int == 0`)
   - Semaphore still has **old Alpine key**
3. **Subnet Router 2 runs**: Uses old Alpine key → authentication fails ❌

### Symptoms
- Subnet Router 1 succeeds
- Subnet Router 2 fails with SSH authentication error
- Inventory "subnet-router" exists and looks correct
- But SSH key in Semaphore doesn't match VM's actual key

---

## The Fix

### Recommended Approach
**Replace "create if missing" with "delete + create" pattern**

```yaml
# After retrieving the new SSH key from VM...

- name: Check if SSH key already exists in Semaphore
  uri:
    url: "{{ semaphore_url }}/api/project/{{ project_id }}/keys"
    method: GET
    headers:
      Authorization: "Bearer {{ SEMAPHORE_API_TOKEN }}"
    status_code: [200]
  register: existing_keys

- name: Parse existing key ID
  set_fact:
    existing_key_id: "{{ (existing_keys.json | selectattr('name', 'equalto', 'subnet-router') | first).id | default(0) }}"

- name: Delete existing SSH key if present
  uri:
    url: "{{ semaphore_url }}/api/project/{{ project_id }}/keys/{{ existing_key_id }}"
    method: DELETE
    headers:
      Authorization: "Bearer {{ SEMAPHORE_API_TOKEN }}"
    status_code: [204, 404]
  when: existing_key_id | int != 0

- name: Register SSH key in Semaphore (using jq for proper JSON types)
  shell: |
    jq -n \
      --arg name "subnet-router" \
      --arg type "ssh" \
      --argjson pid {{ project_id }} \
      --arg key "{{ private_key_file.content | b64decode }}" \
      '{name: $name, type: $type, project_id: $pid, ssh: {private_key: $key}}' | \
    curl -sS -f \
      -H "Authorization: Bearer {{ SEMAPHORE_API_TOKEN }}" \
      -H "Content-Type: application/json" \
      -d @- \
      "{{ semaphore_url }}/api/project/{{ project_id }}/keys"
  register: ssh_key_response
  changed_when: true
```

**Key change**: Remove the `when: existing_key_id | int == 0` condition from the final create task, and add DELETE step before it.

### Alternative Approach
Use Semaphore's UPDATE endpoint (PUT) if it supports updating SSH keys:
```yaml
- name: Update or create SSH key
  uri:
    url: "{{ semaphore_url }}/api/project/{{ project_id }}/keys/{{ existing_key_id if existing_key_id | int != 0 else '' }}"
    method: "{{ 'PUT' if existing_key_id | int != 0 else 'POST' }}"
    ...
```

*Note: Check Semaphore API docs to confirm if PUT supports updating SSH private keys.*

---

## Testing After Fix

### Test 1: Fresh Deploy
```bash
# Delete all VMs
ssh root@192.168.1.10 "for vmid in 100 101 9000; do qm stop \$vmid 2>/dev/null; qm destroy \$vmid 2>/dev/null; done"

# Run quickstart
ssh root@192.168.1.10 "curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | bash"

# Wait for orchestration, verify all succeed including Subnet Router 2 & 3
```

### Test 2: Re-deploy Subnet Router
```bash
# Delete only VM 101
ssh root@192.168.1.10 "qm stop 101; qm destroy 101"

# Run Subnet Router 1 template via Semaphore UI or API
# Then run Subnet Router 2 template
# Should succeed (SSH key updated in Semaphore)
```

### Test 3: Verify SSH Key
```bash
# Get key from Semaphore
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies http://10.10.20.10:3000/api/project/1/keys | jq -r '.[] | select(.name==\"subnet-router\") | .id'"

# SSH to VM with that key (after extracting from Semaphore)
# Should work
```

---

## Session Progress Summary

### Fixes Implemented ✅
1. **Cloud-init refactor**: All config in cloud-init, wait for completion
2. **DNS resolution**: Add `/etc/resolv.conf` pointing to AdGuard
3. **Just-in-time template lookup**: Refresh template list during orchestration
4. **Headscale pre-auth key**: Use `head -1` to extract only first line
5. **Ansible variable access**: Use `{{ VARIABLE }}` not `lookup('env')`
6. **Debian migration**: Switch from Alpine to Debian 13
7. **Tailscale repository**: Add APT repo + network connectivity checks

### Current Blocker
- SSH key not updated in Semaphore when VM is recreated

### Next Steps
1. Implement SSH key delete+create fix
2. Test complete orchestration end-to-end
3. Run Tests 4-7 from original handover:
   - Test 4: Verify Headscale connection
   - Test 5: Verify route advertisement and approval
   - Test 6: Test VPN client connection and LAN access
   - Test 7: Verify environment cleanup

---

## Files Modified This Session

```
ansible/playbooks/infrastructure/subnet-router-deploy.yml
ansible/playbooks/infrastructure/subnet-router-configure.yml
ansible/playbooks/services/headscale-deploy.yml
tools/orchestrate-services.py
```

## Commits Made

```
af813a8 Add Tailscale APT repository to cloud-init
592182c Switch subnet router from Alpine to Debian 13
bbdd2ac Fix subnet router to use Ansible variables instead of env lookup
bbbf3ac Fix Headscale pre-auth key extraction to get only first line
6ea4192 Implement just-in-time template lookup in orchestration
60bc8da Fix DNS resolution in subnet router cloud-init
eba7049 Refactor subnet router to use cloud-init for all configuration
040a0c1 Update orchestration sequence for subnet router VPN
```

---

## Reference Info

**Services Password** (from last bootstrap): `cL1maTic-AgoN1ziNg-gamB1ing`

**VM Status**:
- VM 100 (OPNsense): Running ✅
- VM 101 (Subnet Router): Running ✅
- VM 9000 (Management): Running ✅

**Semaphore Environments**:
- ServicePasswords ✅
- HeadscalePreauthKey ✅ (contains pre-auth key)
- SemaphoreAPI ✅
- OPNsenseAPI ✅
- HeadscaleAPI ✅

**Semaphore Inventories**:
- container-host ✅
- localhost ✅
- proxmox ✅
- opnsense-internal ✅
- subnet-router ✅ (has OLD SSH key)

**Semaphore Keys**:
- subnet-router ❌ (contains outdated Alpine SSH key, needs replacement)

---

**End of Handover**
