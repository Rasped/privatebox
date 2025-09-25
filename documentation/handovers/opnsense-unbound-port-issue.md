# OPNsense Unbound DNS Port Configuration Issue

## Executive Summary
The OPNsense Unbound DNS service is not listening on the expected port 5353 as configured by AdGuard. The root cause is that OPNsense uses `unboundplus` module which overrides legacy `unbound` settings, and our template has port 53 hardcoded.

## Investigation Findings

### 1. Configuration Discrepancy
- **Expected**: Unbound listening on port 5353 (as configured in AdGuard fallback DNS)
- **Actual**: Unbound listening on port 53 (standard DNS port)
- **Impact**: AdGuard cannot reach Unbound fallback, relies solely on Quad9

### 2. Root Cause Analysis

#### Dual Configuration Sections
OPNsense has TWO Unbound configuration sections in `/conf/config.xml`:

1. **`<unboundplus>`** (Active - OPNsense custom module):
   - Location: Lines ~691-772
   - Port: 53
   - Interfaces: lan, opt1
   - This is what OPNsense actually uses

2. **`<unbound>`** (Legacy - ignored):
   - Location: Line 1555+
   - Port: 5353
   - Interfaces: 127.0.0.1, ::1
   - This section is not used by OPNsense

#### Why the Legacy Section Exists
- The `<unbound>` section appears to be added by OPNsense during initial setup
- It's a remnant from pfSense compatibility
- OPNsense's `unboundplus` module completely overrides it

### 3. Template Configuration Issue
Our template at `/Users/rasped/privatebox/ansible/templates/opnsense/config-template.xml`:
- Line 694: Has `<port>53</port>` in the `unboundplus` section
- No `<unbound>` section exists in the template
- The template correctly uses `unboundplus` but with wrong port

### 4. Current Network Status
- Unbound is running (PID 940) and healthy
- Listening on all expected interfaces at port 53:
  - 10.10.20.1:53 (Services VLAN - correct interface)
  - 10.10.10.1:53 (Management VLAN)
  - 127.0.0.1:53 (localhost)
- No service listening on port 5353

## Recommended Fixes

### Option 1: Update OPNsense Template (Preferred)
**File**: `/Users/rasped/privatebox/ansible/templates/opnsense/config-template.xml`
**Change**: Line 694
```xml
<!-- Current -->
<port>53</port>

<!-- Should be -->
<port>5353</port>
```

**Also need to update**:
- Line 696: Set `<active_interface>lan,opt1</active_interface>` to ensure it binds to Services VLAN

### Option 2: Update AdGuard Configuration
**File**: `/Users/rasped/privatebox/ansible/playbooks/services/adguard-deploy.yml`
**Change**: Line containing upstream DNS
```yaml
# Current
- "10.10.20.1:5353"  # Unbound fallback on OPNsense Services VLAN

# Should be
- "10.10.20.1:53"    # Unbound fallback on OPNsense Services VLAN
```

### Option 3: Configure Port Forwarding
Add NAT rule in OPNsense to forward 10.10.20.1:5353 → 10.10.20.1:53
(Not recommended - adds complexity)

## Recommended Approach

1. **Use Option 1** - Fix the template to use port 5353 in `unboundplus`
   - This aligns with original design intent
   - Keeps Unbound on non-standard port to avoid conflicts
   - Maintains separation between services

2. **Implementation Steps**:
   - Update the OPNsense config template
   - Rebuild OPNsense VM from updated template
   - Verify Unbound listening on port 5353
   - Test AdGuard fallback connectivity

3. **Testing**:
   ```bash
   # From Proxmox host
   ssh root@192.168.1.10 "nc -zv 10.10.20.1 5353"

   # Test DNS resolution
   ssh root@192.168.1.10 "dig @10.10.20.1 -p 5353 google.com"
   ```

## Additional Considerations

1. **Port Conflict Risk**: Port 53 might conflict with other services
2. **Security**: Non-standard port (5353) provides minor security through obscurity
3. **Future Updates**: Ensure OPNsense updates don't revert the configuration

## Validation Commands

After implementing the fix:

```bash
# Check Unbound is listening on 5353
ssh root@10.10.20.1 "sockstat -l | grep 5353"

# Test from AdGuard's perspective
curl -X GET "http://10.10.20.10:3000/control/test_upstream_dns" \
  -H "Cookie: $ADGUARD_COOKIE" \
  -d '{"upstream": "10.10.20.1:5353"}'

# Verify in Semaphore logs
ssh root@192.168.1.10 "curl -sS --cookie /tmp/sem.cookies \
  http://10.10.20.10:3000/api/project/1/tasks | \
  jq '.[] | select(.template_name == \"Deploy AdGuard Home\")'
```

## Conclusion

The issue stems from OPNsense using its custom `unboundplus` module with port 53, while our AdGuard deployment expects port 5353. The fix requires updating our OPNsense template to configure `unboundplus` with port 5353, then redeploying the OPNsense VM.