# Multi-Agent Workflow Example: Complete Service Deployment

This example demonstrates how the three PrivateBox agents work together to accomplish a complex task.

## Scenario: Deploy Unbound DNS with AdGuard Integration

### Step 1: User Request
**User**: "I need Unbound DNS deployed as a recursive resolver that forwards specific domains to AdGuard for filtering, with automatic DNSSEC validation and custom root hints."

### Step 2: Orchestrator Analysis and Planning

**privatebox-orchestrator** actions:

1. **Analyzes requirements**:
   - New service: Unbound DNS
   - Integration: Must forward to existing AdGuard
   - Features: DNSSEC, custom root hints
   - Complexity: High (multi-service integration)

2. **Creates task breakdown** (TodoWrite):
   ```
   1. Document Unbound DNS requirements and architecture
   2. Design integration with AdGuard
   3. Plan deployment approach
   4. Implement Unbound deployment automation
   5. Configure DNS forwarding rules
   6. Set up DNSSEC validation
   7. Test complete DNS chain
   8. Update system DNS configuration
   ```

3. **Writes handover document**:

```markdown
# Task Handover: Unbound DNS with AdGuard Integration

## Objective
Deploy Unbound DNS as a recursive resolver with AdGuard integration for specific domain filtering and DNSSEC validation.

## Context
- **Current State**: AdGuard deployed on port 3000, handling DNS filtering
- **Dependencies**: Existing AdGuard instance, system DNS configuration
- **Constraints**: Must not disrupt existing DNS during deployment

## Requirements

### Functional Requirements
- [ ] Unbound as primary recursive resolver
- [ ] Forward specific domains to AdGuard for filtering
- [ ] DNSSEC validation enabled
- [ ] Custom root hints configuration
- [ ] Automatic cache management

### Non-Functional Requirements
- [ ] Sub-100ms resolution time for cached queries
- [ ] 99.9% uptime
- [ ] Automatic restart on failure
- [ ] Log rotation and monitoring

## Technical Specifications
### Architecture
- Unbound listens on 127.0.0.1:5353
- System DNS points to Unbound
- Unbound forwards filtered domains to AdGuard (port 3000)
- Direct recursive resolution for all other domains

### Forwarding Rules
Domains to forward to AdGuard:
- *.doubleclick.net
- *.googlesyndication.com
- *.facebook.com
- [Additional domains from AdGuard lists]

### Implementation Stack
- Container: Podman with Quadlet
- Service: systemd integration
- Configuration: Ansible template
- Monitoring: Health check script

## Success Criteria
- [ ] Unbound container running via systemd
- [ ] DNS resolution working for all domains
- [ ] AdGuard receiving forwarded queries
- [ ] DNSSEC validation operational
- [ ] System using Unbound as resolver

## Resources
- Unbound documentation: https://unbound.docs.nlnetlabs.nl/
- Existing AdGuard deployment: ansible/playbooks/services/deploy-adguard.yml
- Podman Quadlet examples: ansible/group_vars/all.yml

---
*Handover created by*: privatebox-orchestrator
*Date*: 2025-01-25
*For*: automation-engineer
```

4. **Delegates to automation-engineer**:
   ```
   Task(
     subagent_type="automation-engineer",
     description="Implement Unbound DNS deployment",
     prompt="Review handover at documentation/handovers/active/unbound-dns-integration.md and implement the complete solution"
   )
   ```

### Step 3: Implementation by Automation Engineer

**automation-engineer** actions:

1. **Loads Context7 documentation**:
   - `/ansible/ansible-documentation`
   - `/containers/podman`
   - Unbound configuration guides
   - DNS best practices

2. **Designs implementation**:
   - Ansible playbook for deployment
   - Podman Quadlet for systemd
   - Unbound config template
   - Health check script

3. **Creates implementation** (example structure):
   ```
   ansible/playbooks/services/deploy-unbound.yml
   ansible/templates/unbound.conf.j2
   ansible/files/unbound-health-check.sh
   bootstrap/scripts/update-system-dns.sh
   ```

4. **Tests on development environment**:
   ```bash
   ansible-playbook -i inventories/development/hosts.yml \
     playbooks/services/deploy-unbound.yml
   ```

5. **Reports completion** to orchestrator

### Step 4: Issue Discovered During Testing

**Scenario**: Unbound starts but fails to forward queries to AdGuard

**orchestrator** creates debugging handover:

```markdown
# Debugging Request: Unbound DNS Forwarding Failure

## Issue Summary
- **Affected Service**: Unbound DNS
- **Symptoms**: Queries not reaching AdGuard for filtered domains
- **Severity**: High
- **Impact**: DNS filtering not working

## Current State
- Unbound container: Running
- AdGuard container: Running
- Direct queries to AdGuard: Working
- Queries through Unbound: Timeout for filtered domains

## Initial Observations
```
dig @127.0.0.1 -p 5353 doubleclick.net
; <<>> DiG 9.18.18 <<>> @127.0.0.1 -p 5353 doubleclick.net
;; connection timed out; no servers could be reached
```

## Expected Deliverables
1. Root cause of forwarding failure
2. Specific configuration fix
3. Verification steps
```

### Step 5: Debugging by System Debugger

**system-debugger** actions:

1. **Investigates systematically**:
   ```bash
   # Check Unbound logs
   podman logs unbound
   
   # Verify network connectivity
   podman exec unbound ping -c 1 <AdGuard-IP>
   
   # Test DNS resolution from container
   podman exec unbound dig @<AdGuard-IP> -p 3000 test.com
   ```

2. **Discovers root cause**:
   - Unbound container cannot reach AdGuard
   - Podman network isolation preventing container-to-host communication
   - Need to use host networking or proper container networking

3. **Creates diagnostic report**:
   ```markdown
   ## Root Cause Analysis
   
   The Unbound container is using default Podman networking which isolates
   it from the host network where AdGuard is listening. The forwarding
   configuration uses 127.0.0.1:3000 which refers to the container's
   localhost, not the host.
   
   ## Recommendation
   1. Use `ansible_default_ipv4.address` instead of 127.0.0.1 for AdGuard
   2. Or configure Unbound with host networking
   3. Ensure firewall allows container-to-host communication
   
   ## Verification
   After fix, test with:
   podman exec unbound dig @<VM-IP> -p 3000 test.com
   ```

### Step 6: Fix Implementation

**orchestrator**:
1. Reviews debugging report
2. Updates handover with fix requirements
3. Delegates back to automation-engineer

**automation-engineer**:
1. Implements recommended fix
2. Tests thoroughly
3. Confirms resolution

### Step 7: Completion

**orchestrator**:
1. Verifies all success criteria met
2. Moves handover to completed/
3. Updates project documentation
4. Reports success to user

## Key Takeaways

1. **Clear Handoffs**: Each agent knew exactly what to do
2. **No Overlap**: Orchestrator planned, engineer built, debugger diagnosed
3. **Iterative**: Issues led to clear fix cycles
4. **Documentation**: Every decision and finding recorded
5. **Tool Boundaries**: Each agent used only their allowed tools

## Benefits Demonstrated

- **Orchestrator** never touched code, focused on requirements
- **Automation-engineer** had freedom to implement best solution
- **System-debugger** provided analysis without modifying anything
- Clear communication through handover documents
- Complete audit trail of decisions and changes