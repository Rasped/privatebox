# Phase 1 Testing Checklist

## Test Environment
- [ ] Fresh Proxmox installation
- [ ] No existing Semaphore deployment
- [ ] Internet connectivity available

## Bootstrap Deployment
1. [ ] Run quickstart.sh from GitHub:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash
   ```
2. [ ] Note the VM IP address: __________________
3. [ ] Save credentials from `/root/.credentials/`

## Python Auto-Enablement Verification
1. [ ] Access Semaphore UI at http://<VM-IP>:3000
2. [ ] Login with admin credentials
3. [ ] Navigate to Applications menu (bottom of left sidebar)
4. [ ] **CHECK**: Is Python listed and enabled? YES / NO

## If Python is Enabled (Success Path)
1. [ ] Add PrivateBox repository manually:
   - Go to "Key Store" → "Repository"
   - Click "New Repository"
   - Name: `PrivateBox`
   - Git URL: `https://github.com/Rasped/privatebox.git`
   - Branch: `main`
   
2. [ ] Create test Python template:
   - Navigate to "Task Templates"
   - Click "New Template"
   - Select "Python" as template type
   - Name: `Test Template Generator`
   - Script: `tools/generate-templates.py`
   - Repository: `PrivateBox`
   
3. [ ] Run the test:
   - Click "Run" on the template
   - [ ] Task executes successfully
   - [ ] Output shows Python version
   - [ ] Output shows working directory
   - [ ] Repository root check shows `True`

## If Python is NOT Enabled (Failure Path)
1. [ ] Document the Applications menu state
2. [ ] Check container logs:
   ```bash
   ssh privatebox@<VM-IP>
   sudo podman logs semaphore-ui | grep -i python
   sudo podman logs semaphore-ui | grep -i SEMAPHORE_APPS
   ```
3. [ ] Verify environment variable is set:
   ```bash
   sudo podman inspect semaphore-ui | grep SEMAPHORE_APPS
   ```

## Test Results

### Python Auto-Enablement
- **Status**: ⬜ PASS / ⬜ FAIL
- **Notes**: 

### Script Execution
- **Status**: ⬜ PASS / ⬜ FAIL / ⬜ N/A
- **Output**: 

### Environment Variables Detected
- [ ] SEMAPHORE_* variables present
- [ ] ANSIBLE_* variables present
- [ ] Working directory is temporary clone

## Phase 1 Completion Criteria
- [ ] Python can be enabled (automatically or manually documented)
- [ ] Python scripts can execute via Semaphore
- [ ] Environment is suitable for API calls
- [ ] All findings documented

## Next Steps
- If PASS: Proceed to Phase 2 (API token generation)
- If FAIL: Research alternative methods for Python enablement