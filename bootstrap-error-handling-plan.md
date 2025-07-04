# Error Handling Standardization Plan for PrivateBox Bootstrap

## Overview
This document outlines a detailed, risk-minimized plan for standardizing error handling across all bootstrap scripts. The plan is designed to be implemented incrementally with thorough testing at each phase.

**Test Server**: 192.168.1.10  
**Timeline**: 3 weeks (1 week per major phase)  
**Risk Level**: Low to Medium (mitigated through incremental approach)

## Current State Summary

### Scripts WITH Proper Error Handling:
- `bootstrap.sh` - Uses `setup_error_handling()`
- `create-ubuntu-vm.sh` - Uses `setup_error_handling()`
- `network-discovery.sh` - Uses `setup_error_handling()`
- `deploy-to-server.sh` - Uses `setup_error_handling()`
- `quickstart.sh` - Self-contained with `set -euo pipefail`

### Scripts WITHOUT Error Handling:
- `fix-proxmox-repos.sh` - No error handling
- `portainer-setup.sh` - No error handling
- `semaphore-setup.sh` - No error handling
- `health-check.sh` - No error handling
- `backup.sh` - Uses custom `error_exit()` only

### Scripts with MIXED Approach:
- `initial-setup.sh` - Custom fallback for cloud-init environment

## Phase 1: Preparation and Analysis (Day 1-2)

### 1.1 Create Test Environment
```bash
# Deploy current version to test server
cd /Users/rasped/privatebox
./bootstrap/deploy-to-server.sh 192.168.1.10 root --test

# Document current behavior
ssh root@192.168.1.10 'ls -la /tmp/privatebox-bootstrap/'
```

### 1.2 Create Git Branch and Backup
```bash
# Create feature branch
git checkout -b error-handling-standardization
git tag pre-error-handling-changes

# Create backup of current scripts
tar -czf bootstrap-backup-$(date +%Y%m%d).tar.gz bootstrap/
```

### 1.3 Document Current Exit Codes
Create a test script to verify current behavior:
```bash
#!/bin/bash
# test-current-behavior.sh
echo "Testing current error behavior..."

# Test each script's exit code
for script in bootstrap/scripts/*.sh; do
    echo "Testing: $script"
    # Run with various error conditions
done
```

## Phase 2: Foundation Changes (Day 3-5)

### 2.1 Add Opt-in Error Handling to common.sh

**File**: `bootstrap/lib/common.sh`  
**Change**: Add at the end of file:
```bash
# Auto-setup error handling if requested (opt-in for compatibility)
if [[ "${PRIVATEBOX_AUTO_ERROR_HANDLING:-false}" == "true" ]]; then
    if type -t setup_error_handling &> /dev/null; then
        setup_error_handling
    fi
fi
```

**Testing**:
```bash
# Deploy to test server
./bootstrap/deploy-to-server.sh 192.168.1.10 root --no-execute

# Test that existing scripts still work
ssh root@192.168.1.10 'cd /tmp/privatebox-bootstrap && ./scripts/health-check.sh'

# Test opt-in behavior
ssh root@192.168.1.10 'cd /tmp/privatebox-bootstrap && PRIVATEBOX_AUTO_ERROR_HANDLING=true ./scripts/health-check.sh'
```

### 2.2 Fix Scripts Without Error Handling

#### 2.2.1 fix-proxmox-repos.sh (Lowest Risk)
**Changes**:
1. Add shebang and header
2. Source common.sh with error handling
3. Add error checking

**Test**:
```bash
# Test on server
ssh root@192.168.1.10 '/tmp/privatebox-bootstrap/scripts/fix-proxmox-repos.sh'
# Verify: Check /etc/apt/sources.list.d/ files are updated
```

#### 2.2.2 health-check.sh (Read-only, Low Risk)
**Changes**:
1. Add error handling
2. Use consistent exit codes
3. Improve error reporting

**Test**:
```bash
# Test with services running
ssh privatebox@<VM-IP> 'sudo /opt/privatebox/scripts/health-check.sh'

# Test with services stopped
ssh privatebox@<VM-IP> 'sudo systemctl stop portainer && sudo /opt/privatebox/scripts/health-check.sh; sudo systemctl start portainer'
```

#### 2.2.3 backup.sh (Medium Risk)
**Changes**:
1. Replace `error_exit()` with standard error handling
2. Add proper cleanup for partial backups
3. Use consistent exit codes

**Test**:
```bash
# Test backup creation
ssh privatebox@<VM-IP> 'sudo /opt/privatebox/scripts/backup.sh'

# Test with disk full simulation
ssh privatebox@<VM-IP> 'sudo dd if=/dev/zero of=/tmp/bigfile bs=1M count=1000; sudo /opt/privatebox/scripts/backup.sh; rm /tmp/bigfile'
```

#### 2.2.4 portainer-setup.sh (Higher Risk - Service Installation)
**Changes**:
1. Add error handling
2. Add rollback for failed installation
3. Verify service starts correctly

**Test**:
```bash
# Test fresh installation
ssh root@192.168.1.10 'cd /tmp/privatebox-bootstrap && ./scripts/portainer-setup.sh'

# Test idempotency (run again)
ssh root@192.168.1.10 'cd /tmp/privatebox-bootstrap && ./scripts/portainer-setup.sh'
```

#### 2.2.5 semaphore-setup.sh (Highest Risk - Complex Service)
**Changes**:
1. Add comprehensive error handling
2. Add transaction-like behavior for database setup
3. Ensure credentials are saved even on partial failure

**Test**:
```bash
# Full test requires fresh system
# Create new VM and test complete setup
```

## Phase 3: Standardize Existing Scripts (Day 6-8)

### 3.1 Update initial-setup.sh
**Approach**: Preserve cloud-init compatibility
1. Keep fallback error handling
2. Use `setup_cloud_init_error_handling()` when available
3. Test in both environments

**Test**:
```bash
# Test in cloud-init environment (new VM creation)
sudo ./bootstrap/scripts/create-ubuntu-vm.sh --auto-discover

# Monitor cloud-init logs
ssh privatebox@<VM-IP> 'sudo tail -f /var/log/cloud-init-output.log'
```

### 3.2 Verify Existing Scripts
Test each script that already uses `setup_error_handling()`:

```bash
# Test bootstrap.sh
ssh root@192.168.1.10 'cd /tmp/privatebox-bootstrap && ./bootstrap.sh --auto-discover'

# Test create-ubuntu-vm.sh
ssh root@192.168.1.10 'cd /tmp/privatebox-bootstrap && ./scripts/create-ubuntu-vm.sh --help'

# Test network-discovery.sh
ssh root@192.168.1.10 'cd /tmp/privatebox-bootstrap && ./scripts/network-discovery.sh --validate'

# Test deploy-to-server.sh (from local)
./bootstrap/deploy-to-server.sh 192.168.1.10 root --test
```

## Phase 4: Make Error Handling Default (Day 9-12)

### 4.1 Update common.sh Default
**Change**: Switch default from `false` to `true`
```bash
# In common.sh
if [[ "${PRIVATEBOX_AUTO_ERROR_HANDLING:-true}" == "true" ]]; then
    if type -t setup_error_handling &> /dev/null; then
        setup_error_handling
    fi
fi
```

### 4.2 Add Opt-out Documentation
Add to affected scripts that need special handling:
```bash
# For scripts that need custom error handling
export PRIVATEBOX_AUTO_ERROR_HANDLING=false
```

### 4.3 Full Integration Test
```bash
# Run complete bootstrap on test server
ssh root@192.168.1.10 'rm -rf /tmp/privatebox-bootstrap'
./bootstrap/deploy-to-server.sh 192.168.1.10 root

# If successful, run with --test flag
./bootstrap/deploy-to-server.sh 192.168.1.10 root --test --cleanup
```

## Phase 5: Cleanup and Documentation (Day 13-15)

### 5.1 Remove Redundant Code
- Remove all `error_exit()` functions
- Remove custom `handle_error()` implementations
- Update exit statements to use named constants from `constants.sh`

### 5.2 Update Documentation
- Update each script header with exit codes
- Update `bootstrap-improvements.md` to mark this as complete
- Update `CLAUDE.md` with new error handling patterns

### 5.3 Final Testing
```bash
# Full test suite on clean system
./bootstrap/deploy-to-server.sh 192.168.1.10 root --test --cleanup

# Test failure scenarios
# 1. Network failure during download
# 2. Disk full during installation  
# 3. Service startup failures
# 4. Permission errors
```

## Rollback Procedures

### Quick Rollback (Git)
```bash
# Revert to tagged version
git checkout pre-error-handling-changes -- bootstrap/

# Or revert specific files
git checkout pre-error-handling-changes -- bootstrap/lib/common.sh
```

### Emergency Fixes
If a script fails in production:
1. Set `PRIVATEBOX_AUTO_ERROR_HANDLING=false` for that script
2. Re-add the old error handling temporarily
3. Debug and fix the issue
4. Re-enable standardized handling

## Success Criteria

- [ ] All scripts handle errors consistently
- [ ] No regression in functionality
- [ ] Cloud-init deployment works correctly
- [ ] Error messages are clear and actionable
- [ ] Exit codes follow documented standards
- [ ] All tests pass on 192.168.1.10
- [ ] Full bootstrap completes successfully

## Test Commands Reference

```bash
# Deploy to test server (no execution)
./bootstrap/deploy-to-server.sh 192.168.1.10 root --no-execute

# Deploy and execute
./bootstrap/deploy-to-server.sh 192.168.1.10 root

# Deploy, execute, and run tests
./bootstrap/deploy-to-server.sh 192.168.1.10 root --test

# Deploy, test, and cleanup
./bootstrap/deploy-to-server.sh 192.168.1.10 root --test --cleanup

# Check service health on deployed VM
ssh privatebox@<VM-IP> 'sudo /opt/privatebox/scripts/health-check.sh'

# View logs
ssh root@192.168.1.10 'tail -f /var/log/privatebox/*.log'
```

## Risk Matrix

| Script | Risk Level | Impact | Mitigation |
|--------|-----------|---------|------------|
| fix-proxmox-repos.sh | Low | Repo config | Test on non-production |
| health-check.sh | Low | Read-only | No service impact |
| backup.sh | Medium | Data loss | Test backup/restore |
| portainer-setup.sh | High | Service down | Test idempotency |
| semaphore-setup.sh | High | Service down | Full integration test |
| initial-setup.sh | High | VM creation | Test cloud-init |

## Notes

- Always test on 192.168.1.10 before production
- Keep the test server in sync with production Proxmox version
- Document any unexpected behavior immediately
- If in doubt, make changes more gradual