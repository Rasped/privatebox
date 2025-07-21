# PrivateBox Naming Refactor Summary

## Date: 2025-07-21

## Overview
We performed a major refactoring of the naming conventions in PrivateBox to create a clearer, more purpose-driven naming scheme.

## Changes Made

### 1. VM Naming
- **Old**: `ubuntu-server-24.04`
- **New**: `container-host`
- **Reason**: The VM hosts all containerized services, not just Ubuntu. The new name clearly indicates its purpose.

### 2. Admin Username
- **Initial**: `ubuntuadmin` (working)
- **Attempted**: `admin` (failed - reserved username in Ubuntu)
- **Attempted**: `operator` (failed - possibly also reserved)
- **Final**: `ubuntuadmin` (reverted to known working)
- **Reason**: Ubuntu reserves certain usernames like "admin". After trying alternatives, we reverted to the original working username.

### 3. Ansible Architecture
- **Old Plan**: Role-based architecture with complex hierarchies
- **Current**: Service-oriented approach with simple playbooks
- **Location**: `ansible/playbooks/services/`
- **Example**: `deploy-adguard.yml` targets `container-host`

### 4. Removed/Deleted
- Entire `ansible/inventories/` directory (not used by Semaphore)
- References to non-existent `privatebox` user
- Old role-based documentation references

## Key Files Updated

### Bootstrap Scripts
- `bootstrap/scripts/create-ubuntu-vm.sh` - VM name and username
- `bootstrap/scripts/network-discovery.sh` - Default username
- `bootstrap/config/privatebox.conf.example` - Example configuration
- `bootstrap/deploy-to-server.sh` - SSH references
- `bootstrap/scripts/privatebox-deploy.sh` - Username defaults

### Documentation
- `README.md` - Access instructions
- `CLAUDE.md` - Architecture guidance for AI assistants
- `ARCHITECTURE.md` - New file documenting actual implementation
- `dev-notes/recommendations.md` - Marked as obsolete

### Ansible Updates
- `ansible/group_vars/all.yml` - Removed hardcoded ansible_user
- `ansible/playbooks/services/adguard.yml` - Changed to target container-host
- `ansible/playbooks/services/test-semaphore-sync.yml` - Updated host target

## Semaphore Integration

### Bootstrap Creates
1. SSH keys: `semaphore_vm_key` for VM self-management
2. Default inventory with container-host entry
3. Automatic template synchronization

### Inventory Configuration
The bootstrap now populates Semaphore's inventory with:
```yaml
all:
  hosts:
    container-host:
      ansible_host: <VM-IP>
      ansible_user: ubuntuadmin
```

### Current Issues
1. SSH key authentication from Semaphore to container-host needs proper configuration
2. Inventory needs SSH key ID association (key 3: vm-container-host)
3. Playbooks work when inventory and SSH keys are properly configured

## Testing Results

### Successful Bootstrap
- VM creation: ✅ (named container-host)
- User creation: ✅ (ubuntuadmin works)
- Service installation: ✅ (Portainer and Semaphore running)
- Network auto-discovery: ✅
- Template sync: ✅

### Pending Issues
- AdGuard deployment via Semaphore needs SSH key configuration
- Inventory needs to specify which SSH key to use
- May need to update bootstrap to properly associate SSH keys

## Lessons Learned

1. **Reserved Usernames**: Ubuntu reserves usernames like "admin" and possibly "operator"
2. **Simple is Better**: Service-oriented playbooks are clearer than complex role hierarchies
3. **Naming Matters**: Purpose-driven names like "container-host" are more meaningful
4. **Test First**: Always test with known working configurations before experimenting

## Next Steps

1. Fix SSH key association in Semaphore inventory during bootstrap
2. Test AdGuard deployment with proper authentication
3. Document the working configuration for future reference
4. Consider implementing other services (OPNsense, Unbound)

## Git History
- Commit `b5d4902`: Initial refactoring (admin username, container-host)
- Commit `da1e0bf`: Failed attempt with "operator" username
- Commit `254bacc`: Reverted to ubuntuadmin

## Current Working State
- Bootstrap completes successfully
- Services are running
- Inventory is populated
- SSH authentication needs configuration for Ansible playbooks to work

## Detailed Analysis: AdGuard Deployment SSH Authentication Issue

### The Problem
When running AdGuard deployment through Semaphore, the task fails with SSH authentication error:
```
fatal: [container-host]: UNREACHABLE! => changed=false
  msg: |-
    Failed to connect to the host via ssh: Warning: Permanently added '192.168.1.20' (ED25519) to the list of known hosts.
    no such identity: /root/.credentials/semaphore_vm_key: Permission denied
    semaphore@192.168.1.20: Permission denied (publickey,password).
  unreachable: true
```

### Root Cause Analysis

1. **Inventory Configuration Issue**
   - Initial inventory created by bootstrap:
     ```yaml
     all:
       hosts:
         container-host:
           ansible_host: 192.168.1.20
           ansible_ssh_private_key_file: /root/.credentials/semaphore_vm_key
     ```
   - Missing: `ansible_user` specification
   - Missing: SSH key association in Semaphore

2. **SSH Key Configuration**
   - Bootstrap creates SSH keys correctly:
     - Key ID 2: `proxmox-host` - for Proxmox host access
     - Key ID 3: `vm-container-host` - for VM access
   - But inventory doesn't reference the SSH key ID

3. **User Mismatch**
   - Without `ansible_user` specified, Ansible defaults to current user
   - Inside Semaphore container, it tries `semaphore@192.168.1.20`
   - Should be `ubuntuadmin@192.168.1.20`

### Attempted Fix
Updated inventory via API:
```json
{
  "id": 1,
  "name": "Default Inventory",
  "project_id": 1,
  "inventory": "all:\n  hosts:\n    container-host:\n      ansible_host: 192.168.1.20\n      ansible_user: ubuntuadmin",
  "ssh_key_id": 3,
  "type": "static"
}
```

### Current Status
- Even after update, deployment still fails
- Possible issues:
  1. SSH key permissions inside Semaphore container
  2. SSH key path mismatch
  3. Key not properly loaded by Semaphore

### Bootstrap Code That Needs Fixing

In `bootstrap/scripts/semaphore-setup.sh`, the `create_default_inventory` function needs to:
1. Accept the SSH key ID as parameter
2. Include `ansible_user: ubuntuadmin` in inventory
3. Associate the SSH key with the inventory

Current problematic code:
```bash
create_default_inventory() {
    local project_name="$1"
    local project_id="$2"
    local admin_session="$3"
    
    # Get the IP address from the configuration
    local vm_ip="${STATIC_IP:-192.168.1.20}"
    
    # Create the inventory content with the container-host
    local inventory_content="all:
  hosts:
    container-host:
      ansible_host: ${vm_ip}
      ansible_ssh_private_key_file: /root/.credentials/semaphore_vm_key"
```

Should be:
```bash
# Need to get SSH key ID and pass it
# Need to add ansible_user
# Need to set ssh_key_id in the API payload
```

### Workaround Options

1. **Manual Fix via Semaphore UI**
   - Edit inventory to add `ansible_user: ubuntuadmin`
   - Associate SSH key with inventory
   - Test deployment

2. **Use Password Authentication**
   - Create login/password key type
   - Use ubuntuadmin/Changeme123
   - Less secure but works for testing

3. **Fix Bootstrap Script**
   - Update `create_default_inventory` function
   - Properly associate SSH key
   - Include ansible_user in inventory

### Next Steps for Permanent Fix

1. Update `semaphore-setup.sh` to:
   - Get the vm-container-host SSH key ID after creation
   - Pass it to create_default_inventory
   - Include proper ansible_user
   - Set ssh_key_id in inventory creation

2. Test the fix with fresh bootstrap

3. Verify AdGuard deployment works automatically