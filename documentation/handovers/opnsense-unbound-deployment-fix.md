# OPNsense Unbound DNS Deployment Fix Plan

## Problem Summary
OPNsense Unbound DNS is running on port 53 instead of the expected port 5353, causing AdGuard's fallback DNS to fail. The deployment needs to be fixed to automatically configure Unbound correctly.

## Architecture Overview

### DNS Service Layout
```
┌─────────────────────────────────────────────────────────┐
│                   Services VLAN (10.10.20.0/24)          │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌─────────────────────┐    ┌─────────────────────┐    │
│  │    AdGuard Home     │    │   OPNsense Unbound  │    │
│  │   10.10.20.10:53    │───▶│   10.10.20.1:5353   │    │
│  │   (Primary DNS)     │    │   (Fallback DNS)    │    │
│  └─────────────────────┘    └─────────────────────┘    │
│           │                           │                  │
│           ▼                           ▼                  │
│    ┌──────────────┐            ┌──────────────┐        │
│    │  Quad9 TLS   │            │ Quad9 Plain  │        │
│    │  External    │            │  External    │        │
│    └──────────────┘            └──────────────┘        │
└─────────────────────────────────────────────────────────┘
```

### Port Strategy
- **Port 53**: Reserved for AdGuard (primary DNS service)
- **Port 5353**: Reserved for Unbound (fallback DNS service)
- **Rationale**: Avoids conflicts, provides clear service separation

## Root Cause Analysis

### Configuration Hierarchy
1. **OPNsense uses `<unboundplus>`** - The active configuration
2. **Template misconfiguration** - Has port 53 instead of 5353
3. **Legacy `<unbound>` section** - Added by OPNsense but ignored

### Current vs Expected
| Component | Current | Expected |
|-----------|---------|----------|
| Template `<unboundplus>` port | 53 | 5353 |
| Template `<unboundplus>` interfaces | (empty) | lan,opt1 |
| Runtime Unbound port | 53 | 5353 |
| AdGuard upstream | 10.10.20.1:5353 | 10.10.20.1:5353 |
| Legacy `<unbound>` section | Present (ignored) | Removed |

## Implementation Plan

### Phase 1: Update OPNsense Template
**File**: `/Users/rasped/privatebox/ansible/templates/opnsense/config-template.xml`

#### Changes Required:
1. **Line 694**: Change port from 53 to 5353
   ```xml
   <!-- Current -->
   <port>53</port>

   <!-- Fixed -->
   <port>5353</port>
   ```

2. **Line 696**: Ensure interfaces are set
   ```xml
   <!-- Current -->
   <active_interface/>

   <!-- Fixed -->
   <active_interface>lan,opt1</active_interface>
   ```

### Phase 2: Add Post-Deployment Cleanup
**New File**: `/Users/rasped/privatebox/ansible/playbooks/services/opnsense-post-config.yml`

```yaml
---
- name: OPNsense Post-Configuration Cleanup
  hosts: proxmox
  gather_facts: yes
  become: yes

  tasks:
    - name: Remove legacy unbound section from config
      command: |
        ssh -i /root/.credentials/opnsense/id_ed25519 \
        -o StrictHostKeyChecking=no root@10.10.20.1 \
        "cp /conf/config.xml /conf/config.xml.bak && \
         sed -i '/<unbound>/,/<\/unbound>/d' /conf/config.xml"
      register: cleanup_result

    - name: Apply Unbound configuration
      command: |
        ssh -i /root/.credentials/opnsense/id_ed25519 \
        -o StrictHostKeyChecking=no root@10.10.20.1 \
        "configctl unbound reconfigure"
      when: cleanup_result.changed

    - name: Verify Unbound on port 5353
      wait_for:
        host: 10.10.20.1
        port: 5353
        timeout: 30
      delegate_to: localhost
```

### Phase 3: Update Deployment Process
**File**: Update existing deployment playbook or create wrapper

1. Deploy OPNsense VM from template
2. Run post-configuration cleanup
3. Verify Unbound is listening on correct port
4. Deploy AdGuard with verified fallback

### Phase 4: Create Validation Script
**New File**: `/Users/rasped/privatebox/tools/validate-dns-stack.sh`

```bash
#!/bin/bash
set -euo pipefail

echo "=== DNS Stack Validation ==="

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Test Unbound on OPNsense
echo -n "Testing Unbound on 10.10.20.1:5353... "
if nc -zv 10.10.20.1 5353 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"

    # Test DNS resolution through Unbound
    echo -n "Testing DNS resolution through Unbound... "
    if dig @10.10.20.1 -p 5353 google.com +short >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
else
    echo -e "${RED}✗${NC}"
fi

# Test AdGuard on Management VM
echo -n "Testing AdGuard on 10.10.20.10:53... "
if nc -zv 10.10.20.10 53 2>/dev/null; then
    echo -e "${GREEN}✓${NC}"

    # Test DNS resolution through AdGuard
    echo -n "Testing DNS resolution through AdGuard... "
    if dig @10.10.20.10 google.com +short >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi

    # Test ad blocking
    echo -n "Testing ad blocking... "
    RESULT=$(dig @10.10.20.10 doubleclick.net +short 2>/dev/null)
    if [[ "$RESULT" == "0.0.0.0" ]] || [[ -z "$RESULT" ]]; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗ (got: $RESULT)${NC}"
    fi
else
    echo -e "${RED}✗${NC}"
fi

# Check if AdGuard can reach Unbound fallback
echo -n "Testing AdGuard → Unbound connectivity... "
ssh root@10.10.20.10 "nc -zv 10.10.20.1 5353" 2>/dev/null
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗${NC}"
fi

echo "=== Validation Complete ==="
```

## Testing Checklist

### Pre-Deployment
- [ ] Verify template has port 5353 in `<unboundplus>`
- [ ] Verify template has correct interfaces in `<unboundplus>`
- [ ] Verify no `<unbound>` section in template

### Post-Deployment
- [ ] OPNsense VM created successfully
- [ ] SSH access to OPNsense working
- [ ] Unbound service running
- [ ] Port 5353 listening on 10.10.20.1
- [ ] No service on port 53 on OPNsense
- [ ] Legacy `<unbound>` section removed from config.xml
- [ ] DNS resolution working through Unbound

### Integration Testing
- [ ] AdGuard deployed successfully
- [ ] AdGuard running on port 53
- [ ] AdGuard can reach Unbound at 10.10.20.1:5353
- [ ] DNS resolution through AdGuard working
- [ ] Ad blocking functional
- [ ] Fallback to Unbound working when Quad9 unavailable

## Rollback Plan

If issues occur:
1. Restore OPNsense config backup: `/conf/config.xml.bak`
2. Reconfigure Unbound: `configctl unbound reconfigure`
3. Update AdGuard to use only Quad9 (remove Unbound fallback)
4. Document issues for troubleshooting

## Implementation Order

1. **Update Template** (5 minutes)
   - Edit config-template.xml
   - Commit changes

2. **Create Validation Script** (10 minutes)
   - Create validate-dns-stack.sh
   - Make executable
   - Test from Proxmox host

3. **Deploy Fresh OPNsense** (20 minutes)
   - Destroy existing OPNsense VM
   - Deploy from updated template
   - Run post-configuration

4. **Validate** (5 minutes)
   - Run validation script
   - Check all services

5. **Update AdGuard** (10 minutes)
   - Redeploy if needed
   - Verify fallback working

## Expected Outcome

After implementation:
- OPNsense Unbound listens on 10.10.20.1:5353
- AdGuard successfully uses Unbound as fallback
- No port conflicts between services
- Clean configuration without legacy sections
- Fully automated deployment without manual intervention

## Monitoring

Post-deployment monitoring points:
1. Unbound service status: `configctl unbound status`
2. Port listening: `sockstat -l | grep 5353`
3. DNS query logs in AdGuard showing Unbound queries
4. Semaphore task logs showing successful deployment

## Documentation Updates

After successful implementation:
1. Update `documentation/network-architecture/*.md` with correct ports
2. Update `CLAUDE.md` if deployment process changes
3. Add note about port 5353 requirement to README
4. Document in changelog/release notes