# Alpine VM SSH Architecture Fix - Handover Document

## Problem Summary
Alpine VM deployment is completely broken after removing Proxmox SSH access. The playbook cannot retrieve the VM's SSH key to store in Semaphore, making automation impossible.

## Current Status
- **Severity**: P1 Critical Blocker
- **Impact**: Cannot run any Alpine VM automation through Semaphore
- **Root Cause**: Architectural flaw in SSH key management after security changes
- **Status**: RESOLVED - Implemented VM self-registration solution

## Technical Details

### What Changed
1. Removed Proxmox root SSH key from Alpine VM cloud-init (commit c48a37c)
2. Changed all SSH commands to use sshpass with password authentication
3. Expected Alpine VM to accept password auth for key retrieval

### What's Broken
1. Alpine cloud images have `PasswordAuthentication no` in `/etc/ssh/sshd_config` by default
2. Even though cloud-init sets `lock_passwd: false` and `plain_text_passwd`, SSH still denies password auth
3. Playbook fails at "Wait for cloud-init to complete" with:
   ```
   Permission denied, please try again.
   rc: 5
   ```

### Current Code State
File: `ansible/playbooks/services/alpine-vm-deploy.yml`
- Lines 312-325: Uses sshpass to retrieve SSH keys (FAILS)
- Lines 294-302: Uses sshpass to check cloud-init completion (FAILS)
- Lines 415-510: All Caddy installation tasks use sshpass (WOULD FAIL)

## Investigation Done

1. **Verified cloud-init user-data**:
   - Correctly sets `lock_passwd: false`
   - Sets plain text password
   - But Alpine's sshd ignores these settings

2. **Tested SSH access**:
   - Proxmox → Alpine VM with password: FAILS
   - Container host → Alpine VM: No SSH key available
   - Manual password auth: Permission denied

3. **Checked Alpine VM state**:
   - VM creates successfully (ID 102)
   - Gets DHCP IP (192.168.1.134)
   - SSH port 22 is accessible
   - But only accepts key auth (which we don't have)

## Proposed Solutions

### Option 1: Generate Key on Proxmox First (Recommended)
```yaml
# Before VM creation
- name: Generate SSH keypair for Alpine VM
  openssh_keypair:
    path: "/tmp/alpine-vm-{{ vm_id }}"
    type: ed25519
    comment: "{{ vm_name }}@{{ vm_ip | default('dhcp') }}"
  register: alpine_keypair

# In cloud-init users section
ssh_authorized_keys:
  - "{{ alpine_keypair.public_key }}"

# Store private key in Semaphore directly
```

### Option 2: Enable Password Auth via Cloud-init
```yaml
write_files:
  - path: /etc/ssh/sshd_config.d/01-allow-password.conf
    content: |
      PasswordAuthentication yes
      PermitRootLogin yes
    permissions: '0644'

runcmd:
  - rc-service sshd restart
```

### Option 3: Temporary Proxmox Access
- Add Proxmox key back temporarily
- Retrieve Alpine's key
- Remove Proxmox key via Ansible task
- Not clean but works

### Option 4: Use Cloud-init to Write Key
```yaml
write_files:
  - path: /tmp/alpine-ssh-key
    content: "{{ vm_ssh_private_key }}"
    permissions: '0600'
```
Then retrieve via qm guest exec or other method.

## Required Actions

1. **Immediate**: Choose solution approach
2. **Implementation**: 
   - Update alpine-vm-deploy.yml with chosen solution
   - Test full deployment cycle
   - Verify Semaphore can use the key
3. **Testing**:
   - Deploy Alpine VM
   - Run password update playbook
   - Verify SSH key auth works
   - Test Caddy installation

## Files to Modify
- `ansible/playbooks/services/alpine-vm-deploy.yml` - Main deployment playbook
- Possibly `bootstrap/lib/semaphore-api.sh` - If we need different key handling

## Test Commands
```bash
# Deploy Alpine VM
curl -s -b /tmp/semaphore-cookie -X POST -H 'Content-Type: application/json' \
  -d '{"template_id": 4, "project_id": 1}' \
  http://192.168.1.20:3000/api/project/1/tasks

# Check deployment
ssh root@192.168.1.10 "qm list | grep 102"

# Test SSH access
ssh root@192.168.1.10 "sshpass -p 'changeme123' ssh -o StrictHostKeyChecking=no alpineadmin@<IP> 'whoami'"
```

## Success Criteria
1. Alpine VM deploys successfully
2. SSH key is stored in Semaphore with correct login field
3. Inventory is created with proper SSH key reference  
4. Password update playbook runs successfully
5. No Proxmox SSH access to Alpine VM (security requirement)

## Related Issues
- Original issue: SSH key created without login field
- Previous fix attempts: Added public key to authorized_keys (worked with Proxmox key)
- Security requirement: Proxmox should not have SSH access to Alpine VM

## Solution Implemented
Created a generic VM self-registration script that:
1. Enables password auth temporarily via cloud-init
2. VM executes script locally to register with Semaphore API
3. Script installs dependencies, reads SSH keys, creates resources
4. Password auth disabled after successful registration

See `ansible/scripts/vm-self-register.sh` and updated `alpine-vm-deploy.yml`.