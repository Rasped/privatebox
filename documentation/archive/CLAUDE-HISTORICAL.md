# CLAUDE Historical Notes

This file contains historical lessons learned and detailed notes that were previously in CLAUDE.md but removed to keep it concise.

## Lessons Learned - Phase 0 (2025-07-24)

### Key Fixes and Discoveries

#### 1. Hostname Resolution Fix
- **Problem**: "sudo: unable to resolve host ubuntu" errors after VM creation
- **Fix**: Added hostname configuration to cloud-init in `create-ubuntu-vm.sh`:
  ```yaml
  hostname: ubuntu
  manage_etc_hosts: true
  ```

#### 2. Container Binding Behavior
- **Discovery**: Podman Quadlet containers bind to VM's specific IP, not localhost
- **Impact**: Health checks and API calls must use `ansible_default_ipv4.address`
- **Not a bug**: This is correct security behavior for systemd services

#### 3. AdGuard Port Configuration
- **Problem**: AdGuard switches from port 3000 to configured port after setup
- **Fix**: Configure AdGuard to keep using port 3000 internally:
  ```yaml
  web:
    port: 3000  # Keep internal port consistent
    ip: "0.0.0.0"
  ```

#### 4. Password File Detection
- **Problem**: `lookup('file', path, errors='ignore')` returns empty string, not error
- **Fix**: Use stat module to check file existence before lookup:
  ```yaml
  - name: Check if password file exists
    stat:
      path: /etc/privatebox-adguard-password
    register: password_file_stat
  ```

#### 5. Semaphore Task Execution
- **Problem**: Ansible running inside Semaphore cannot restart Semaphore
- **Fix**: Removed Semaphore restart task from playbooks
- **Lesson**: Consider execution context when designing automation

#### 6. API Authentication Timing
- **Discovery**: AdGuard API requires different endpoints pre/post configuration
- **Solution**: Check `/control/status` redirect to determine configuration state
- **Implementation**: Conditional logic based on HTTP 302 vs 200 responses

### Best Practices Established

1. **Always Test End-to-End**: Run from quickstart.sh to validate entire flow
2. **Use VM IP for Services**: Never assume localhost binding in containers
3. **Handle API State Changes**: Services may behave differently during/after setup
4. **Check File Existence Explicitly**: Don't rely on lookup error handling
5. **Consider Execution Context**: Automation running inside services it manages needs special handling