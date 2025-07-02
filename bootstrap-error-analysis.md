# PrivateBox Bootstrap Error Analysis

## Problem Summary

The PrivateBox bootstrap process fails during the cloud-init phase with the error `trap: ERR: bad trap`. This prevents the VM from completing its post-installation setup, causing the entire bootstrap process to fail.

## Error Details

### Symptoms
- Bootstrap fails after VM creation and initial SSH setup
- Error occurs at approximately 4-5 minutes into the process
- Exit code 1 at line 969 of create-ubuntu-vm.sh (the closing brace of main execution block)
- Cloud-init status shows: `INSTALLATION_STATUS=failed` with `ERROR_STAGE=post-install-setup`

### Root Cause
The error occurs in the `setup_cloud_init_error_handling()` function in `/bootstrap/lib/error_handler.sh`. Specifically, this line:

```bash
trap 'write_error_status "Script failed at line $LINENO" $?; exit 1' ERR
```

The `ERR` trap is a bash-specific feature that is not supported by POSIX-compliant shells. Cloud-init typically executes scripts using `/bin/sh`, which on Ubuntu systems is often `dash` - a minimal POSIX shell that doesn't support the `ERR` signal for trap commands.

### Error Flow
1. `bootstrap.sh` sets `WAIT_FOR_CLOUD_INIT=true` (line 79)
2. `create-ubuntu-vm.sh` creates the VM and waits for cloud-init completion
3. Cloud-init runs the embedded post-installation script
4. The script sources `initial-setup.sh` which attempts to set up error handling
5. `setup_cloud_init_error_handling()` is called, which tries to set the `ERR` trap
6. The shell returns `trap: ERR: bad trap` and the script fails
7. Cloud-init marks the installation as failed
8. The bootstrap process times out waiting for successful completion

## Steps to Fix

### Option 1: Ensure Bash Execution (Recommended)
1. Modify the cloud-init user data generation in `create-ubuntu-vm.sh` to explicitly use bash for script execution
2. Change the runcmd entries to use `/bin/bash -c` instead of relying on the default shell
3. Ensure all embedded scripts have proper bash shebangs

### Option 2: Make Error Handling POSIX-Compliant
1. Modify `setup_cloud_init_error_handling()` in `/bootstrap/lib/error_handler.sh` to remove the `ERR` trap
2. Replace with POSIX-compliant error handling using only supported signals:
   - Use `trap '...' EXIT` for cleanup
   - Use `trap '...' INT TERM` for interruption handling
   - Implement explicit error checking after each command instead of relying on `ERR` trap

### Option 3: Conditional Error Handling
1. Modify `setup_cloud_init_error_handling()` to detect the shell type
2. Only set the `ERR` trap if running under bash
3. Fall back to simpler error handling for other shells

### Option 4: Simplify Cloud-Init Scripts
1. Remove the dependency on the common library during cloud-init execution
2. Implement minimal, self-contained error handling in the cloud-init scripts
3. Keep the sophisticated error handling only for scripts run directly on the Proxmox host

## Recommended Fix Implementation

The most robust solution would be **Option 1** combined with **Option 3**:

1. Ensure all cloud-init scripts explicitly use bash
2. Make the error handling detect and adapt to the shell environment
3. Add fallback error handling for non-bash environments

This would involve:
- Modifying the cloud-init user data template to use `#!/bin/bash` and execute with `/bin/bash -c`
- Updating `setup_cloud_init_error_handling()` to check if ERR trap is supported before using it
- Adding explicit error checking as a fallback when ERR trap is not available

## Testing the Fix

After implementing the fix:
1. Deploy to a test Proxmox server
2. Monitor `/var/log/cloud-init-output.log` on the created VM
3. Verify no "bad trap" errors appear
4. Confirm post-installation setup completes successfully
5. Check that Portainer and Semaphore services are running

## Prevention

To prevent similar issues in the future:
1. Test all scripts in the target execution environment (cloud-init/dash)
2. Avoid bash-specific features in scripts that might run in other shells
3. Always specify the interpreter explicitly in cloud-init configurations
4. Add shell compatibility checks to the CI/CD pipeline