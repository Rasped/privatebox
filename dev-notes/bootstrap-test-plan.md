# Bootstrap Test Plan for Template Synchronization

## Purpose

This document outlines the testing procedure to verify that the template synchronization feature works correctly during a fresh bootstrap installation.

## Prerequisites

- Fresh Proxmox VE installation (7.0 or higher)
- At least 4GB free RAM
- At least 10GB free storage
- Internet connectivity
- No existing PrivateBox VM

## Test Procedure

### 1. Run Bootstrap

```bash
# On the Proxmox host
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash
```

### 2. Monitor Bootstrap Output

Watch for these specific messages related to template sync:
- "Setting up template synchronization infrastructure..."
- "Step 1/5: Creating API token..."
- "Step 2/5: Creating SemaphoreAPI environment..."
- "Step 3/5: Looking up resource IDs..."
- "Step 4/5: Creating Generate Templates task..."
- "Step 5/5: Running initial template generation..."

### 3. Post-Bootstrap Verification

After bootstrap completes:

#### A. SSH into the VM
```bash
ssh admin@<VM-IP>
# Password: Changeme123
```

#### B. Check API Token Creation
```bash
sudo cat /root/.credentials/semaphore_credentials.txt
# Should contain:
# - Admin Password
# - Template Generator API Token
```

#### C. Access Semaphore UI
1. Open browser to `http://<VM-IP>:3000`
2. Login with admin credentials from credentials file
3. Navigate to "Task Templates"

#### D. Verify Template Sync Infrastructure
Check for:
1. **PrivateBox Project** exists
2. **Generate Templates** task exists in the project
3. **SemaphoreAPI** environment exists
4. **PrivateBox** repository exists
5. **Python** application is enabled (check UI footer or apps menu)

#### E. Check Initial Sync Results
1. Go to "Activity" or task history
2. Find the initial run of "Generate Templates"
3. Check output for:
   - "✓ Successfully connected to Semaphore"
   - "✓ Authentication successful!"
   - Any templates created (if test playbooks exist)

### 4. Test Manual Template Sync

#### A. Create Test Playbook
SSH into VM and create a test playbook:
```bash
sudo su -
cd /opt/semaphore/repositories/repository_1_*
cat > ansible/playbooks/services/test-bootstrap.yml << 'EOF'
---
- name: Test Bootstrap Playbook
  hosts: all
  vars_prompt:
    - name: test_variable
      prompt: "Enter test value"
      default: "hello"
      semaphore_type: text
      semaphore_description: "A test variable"
EOF
```

#### B. Run Template Sync
1. In Semaphore UI, go to "Task Templates"
2. Find "Generate Templates" and click "Run"
3. Wait for completion

#### C. Verify Template Creation
1. Go back to "Task Templates"
2. Look for new template "Deploy: test-bootstrap"
3. Click on it and verify survey variable exists

### 5. Expected Results

✅ Bootstrap completes without errors
✅ API token is created and saved
✅ SemaphoreAPI environment exists with credentials
✅ Generate Templates task exists
✅ Initial sync runs automatically
✅ Python app is enabled in Semaphore
✅ Manual sync creates templates correctly

### 6. Common Issues to Check

If template sync fails:
1. **Check Semaphore logs**: 
   ```bash
   sudo podman logs semaphore-ui
   ```

2. **Verify Python is enabled**:
   - Should see Python in Semaphore UI
   - Check Quadlet file has SEMAPHORE_APPS environment

3. **Check repository clone**:
   ```bash
   sudo ls -la /opt/semaphore/repositories/
   ```

4. **Verify API connectivity**:
   ```bash
   sudo podman exec semaphore-ui curl http://localhost:3000/api/ping
   ```

### 7. Cleanup (If Re-testing)

To completely remove PrivateBox for a fresh test:
```bash
# On Proxmox host
qm stop 999
qm destroy 999
rm -rf /var/lib/vz/images/999/
```

## Success Criteria

The bootstrap is considered successful if:
1. All infrastructure is created automatically
2. No manual steps are required in Semaphore UI
3. Initial template sync runs without errors
4. Manual template sync works correctly
5. API token is properly stored and functional

## Notes

- The test-semaphore-sync.yml playbook in the repository is specifically for testing this feature
- Actual service playbooks will be added later and should follow the same annotation pattern
- The Python script handles missing dependencies automatically (PyYAML and requests)