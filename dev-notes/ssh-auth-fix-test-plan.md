# SSH Authentication Fix Test Plan

## Date: 2025-07-21

## Problem Summary
AdGuard deployment via Semaphore fails with SSH authentication error because:
1. Inventory not associated with SSH key during bootstrap
2. Missing `ansible_user` in inventory
3. SSH key has wrong login user ("root" instead of "ubuntuadmin")

## Code Changes Made

### 1. Added SSH Key Lookup Function
```bash
get_ssh_key_id_by_name() {
    # Retrieves SSH key ID by name from Semaphore API
    # Returns the key ID to stdout
}
```

### 2. Enhanced Inventory Creation
```bash
create_default_inventory() {
    # Now accepts optional SSH key ID parameter
    # Includes ansible_user: ubuntuadmin
    # Associates inventory with SSH key if provided
}
```

### 3. Modified SSH Key Creation
```bash
create_semaphore_ssh_key() {
    # Now accepts ssh_login parameter (default: root)
    # Returns the created/found key ID
    # Handles existing keys by looking up their ID
}
```

### 4. Reordered Project Setup Flow
Old order:
1. Create project
2. Create inventory
3. Create SSH keys

New order:
1. Create project
2. Create SSH keys (capture IDs)
3. Create inventory with SSH key ID

## Test Procedure

### Step 1: Clean Environment
```bash
# On Proxmox host (192.168.1.10)
qm stop 999 2>/dev/null || true
qm destroy 999 2>/dev/null || true
rm -rf /var/lib/vz/images/999/
```

### Step 2: Run Bootstrap
```bash
# Fresh bootstrap with latest code
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash
```

### Step 3: Monitor Key Creation
Watch for these log messages:
- "Creating SSH key 'proxmox-host' for project ID 1 (login: root)..."
- "Creating SSH key 'vm-container-host' for project ID 1 (login: ubuntuadmin)..."
- "SSH key 'vm-container-host' created successfully with ID: [number]"
- "Default inventory created for project 'PrivateBox' with ID: [number]"
- "Inventory is associated with SSH key ID: [number]"

### Step 4: Verify Setup
```bash
# SSH into the VM
ssh ubuntuadmin@192.168.1.20
# Password: Changeme123

# Check services
sudo systemctl status portainer semaphore-ui

# Check SSH key exists
sudo ls -la /root/.credentials/semaphore_vm_key*
```

### Step 5: Test via Semaphore UI
1. Access http://192.168.1.20:3000
2. Login as admin (check /root/.credentials/semaphore_credentials.txt)
3. Go to PrivateBox project → Key Store
4. Verify:
   - "proxmox-host" key exists (login: root)
   - "vm-container-host" key exists (login: ubuntuadmin)
5. Go to Inventory
6. Edit "Default Inventory" and verify:
   - SSH Key is set to "vm-container-host"
   - Content includes `ansible_user: ubuntuadmin`

### Step 6: Test AdGuard Deployment
1. In Semaphore UI, go to Task Templates
2. Run "Deploy: adguard"
3. Expected output:
   ```
   PLAY [Deploy AdGuard Home] ***
   
   TASK [Gathering Facts] ***
   ok: [container-host]
   ```
   
4. Should NOT see:
   - "Permission denied (publickey,password)"
   - "UNREACHABLE!"
   - Connection errors

### Step 7: Verify AdGuard Running
```bash
# On the VM
sudo podman ps | grep adguard
# Should show adguard container running

# Access AdGuard UI
curl -I http://192.168.1.20:3001
# Should return HTTP 200 or redirect
```

## Success Criteria

✅ Bootstrap completes without errors
✅ SSH keys created with correct login users
✅ Inventory associated with SSH key ID
✅ No manual configuration needed in Semaphore UI
✅ AdGuard deployment succeeds on first try
✅ No SSH authentication errors

## Troubleshooting

If deployment still fails:

1. **Check SSH key association**:
   ```bash
   # In Semaphore container
   sudo podman exec semaphore-ui cat /root/.credentials/semaphore_vm_key
   # Should match the key in VM's authorized_keys
   ```

2. **Check inventory via API**:
   ```bash
   # Get inventory details
   curl -H "Cookie: semaphore=$SESSION" \
        http://localhost:3000/api/project/1/inventory/1
   # Should show ssh_key_id field
   ```

3. **Manual fix if needed**:
   - Edit inventory in UI
   - Select "vm-container-host" as SSH Key
   - Save and retry deployment

## Rollback Plan

If issues persist:
```bash
git revert HEAD
git push
# Then re-run bootstrap
```