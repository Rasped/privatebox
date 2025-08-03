# VM Self-Registration Plan

## Problem Summary
Alpine VM (and potentially other VMs) cannot be managed by Semaphore because SSH key registration fails. Need universal solution that bypasses SSH authentication issues.

## Solution Overview
Create generic self-registration script that VMs execute locally to register themselves with Semaphore API.

## Implementation Plan

### 1. Create Generic Registration Script
**File**: `ansible/scripts/vm-self-register.sh`

**Features**:
- Distribution detection (Alpine, Ubuntu, Debian, RHEL, etc.)
- Package manager detection (apk, apt, yum, dnf)
- Dependency installation (curl, jq if missing)
- SSH key reading from standard locations
- Semaphore API registration
- Idempotency (marker file)
- Self-cleanup on success

**Script Structure**:
```bash
#!/bin/sh
# Detect distribution and package manager
# Install missing dependencies (curl, jq)
# Validate inputs (API token, Semaphore URL)
# Read SSH keys from VM
# Create SSH key in Semaphore API
# Create inventory in Semaphore API
# Create marker file to prevent re-runs
# Clean up script and sensitive data
```

### 2. Modify Deployment Playbooks
**Current Issue**: Alpine VM playbook tries to SSH with password (fails)

**New Approach**:
```yaml
- name: Register VM with Semaphore
  script: scripts/vm-self-register.sh "{{ semaphore_api_token }}"
  args:
    creates: /var/lib/semaphore-registered
  when: register_with_semaphore | bool
```

### 3. Key Design Decisions

**Why Generic Script**:
- Future VMs (OPNsense, Ubuntu, etc.) need same functionality
- One script to maintain instead of many
- Distribution-agnostic approach

**Why Script Module**:
- Ansible automatically transfers script
- Executes with proper permissions
- No SSH authentication needed
- Built-in idempotency support

**Security Considerations**:
- API token passed as argument (not stored)
- Script self-destructs after success
- Marker file prevents re-registration
- No sensitive data left on VM

### 4. Testing Plan
1. Deploy Alpine VM with new script
2. Verify registration in Semaphore
3. Run password update playbook
4. Test with other distributions

### 5. Future Benefits
- Any new VM type can use same script
- No more SSH key architecture issues
- Simplified deployment process
- Better security (no embedded passwords)

## Files to Create/Modify

1. **Create**: `ansible/scripts/vm-self-register.sh`
   - Universal registration script
   - Distribution detection
   - Dependency management

2. **Modify**: `ansible/playbooks/services/alpine-vm-deploy.yml`
   - Remove password-based SSH attempts
   - Add script module task
   - Simplify registration block

3. **Update**: Documentation
   - Add script usage to README
   - Document in handover
   - Update work log

## Success Criteria
- Alpine VM deploys and self-registers
- No SSH authentication errors
- Script works on multiple distributions
- Semaphore can manage VM via Ansible