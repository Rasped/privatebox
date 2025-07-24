# OPNsense Automation Research Template

**Date**: [Date]  
**Researcher**: [Name]  
**OPNsense Version**: [Target Version]

## Research Objectives

1. Determine automation capabilities for OPNsense deployment
2. Identify minimum manual configuration requirements
3. Design Ansible-based deployment approach
4. Document API capabilities for post-deployment

## VM Creation Research

### Proxmox VM Creation via Ansible

**Method**: SSH to Proxmox + qm commands

```yaml
# Example approach to research:
- name: Create OPNsense VM
  shell: |
    qm create {{ vm_id }} \
      --name opnsense \
      --memory 4096 \
      --cores 2 \
      --sockets 1 \
      --net0 virtio,bridge=vmbr0 \
      --net1 virtio,bridge=vmbr1
```

**Questions to Answer**:
- [ ] Best VM ID to use?
- [ ] Optimal resource allocation?
- [ ] Network interface ordering?
- [ ] Storage configuration?

### ISO/Image Management

**Options to Research**:
1. Pre-downloaded ISO on Proxmox
2. Download ISO via Ansible
3. Cloud image availability?
4. PXE boot options?

**Storage Locations**:
- Local ISO storage: `/var/lib/vz/template/iso/`
- NFS ISO storage: [if applicable]

## Initial Configuration Research

### Configuration Methods

#### Method 1: config.xml Template
**Research Points**:
- [ ] Can we pre-generate config.xml?
- [ ] What's the minimal config.xml structure?
- [ ] How to inject into VM?
- [ ] When is config.xml read?

**Sample config.xml structure**:
```xml
<?xml version="1.0"?>
<opnsense>
  <system>
    <hostname>opnsense</hostname>
    <domain>privatebox.local</domain>
    <!-- Research required fields -->
  </system>
</opnsense>
```

#### Method 2: Console Automation
**Research Points**:
- [ ] Can we use expect scripts?
- [ ] VNC/SPICE automation options?
- [ ] Serial console configuration?
- [ ] Minimum keystrokes required?

#### Method 3: USB Configuration Import
**Research Points**:
- [ ] USB config import supported?
- [ ] How to attach USB to VM?
- [ ] Config file format?

### Required Manual Steps

**Identify Unavoidable Manual Steps**:
1. Initial interface assignment?
2. Admin password setting?
3. Initial IP configuration?
4. Enable SSH/API access?

**Time Estimate**: [X minutes of manual work]

## API Research

### Initial API Access
**Questions**:
- [ ] When is API available?
- [ ] Default API credentials?
- [ ] API enable process?
- [ ] Authentication methods?

### API Capabilities
**Key Endpoints to Research**:
- System configuration
- Interface management  
- Firewall rules
- Service control
- Package installation

**Example API Calls**:
```bash
# Get system info
curl -k https://opnsense.local/api/core/system/status

# Add firewall rule
curl -k -X POST https://opnsense.local/api/firewall/filter/addRule
```

## Bootstrap Options

### Option 1: Modified Installation Image
- [ ] Can we modify installer ISO?
- [ ] Injection points for config?
- [ ] Build process complexity?

### Option 2: Post-Install Script
- [ ] Script execution methods?
- [ ] When to run scripts?
- [ ] Access to filesystem?

### Option 3: Configuration Management
- [ ] Puppet/Ansible agents?
- [ ] Built-in CM support?
- [ ] Custom modules needed?

## Network Configuration

### VLAN Configuration
**Research**:
- [ ] VLAN interface syntax
- [ ] Parent interface requirements
- [ ] Maximum VLANs supported
- [ ] Performance considerations

**Example Configuration**:
```
# To be researched
interface vlan 10
  parent: vtnet1
  ip: 10.0.10.1/24
```

### Interface Assignment
**Questions**:
- [ ] Automatic assignment possible?
- [ ] Persistent naming?
- [ ] MAC-based assignment?

## Service Configuration

### Unbound DNS
- [ ] Config file location
- [ ] API endpoints
- [ ] Custom port configuration
- [ ] Access control syntax

### DHCP Server  
- [ ] Per-VLAN DHCP config
- [ ] Option setting via API
- [ ] Lease management

### Firewall Rules
- [ ] Rule syntax in config.xml
- [ ] API rule format
- [ ] Rule ordering
- [ ] Aliases/groups

## Testing Approach

### Isolated Test Environment
```yaml
# Test VM configuration
test_vm:
  id: 999
  name: opnsense-test
  network: isolated_bridge
```

### Test Scenarios
1. [ ] Clean install automation
2. [ ] Network configuration
3. [ ] Service enablement
4. [ ] API accessibility
5. [ ] Rollback procedures

## Findings Summary

### Automation Feasibility
- **Fully Automated**: [List what can be automated]
- **Partially Automated**: [List partial automation]
- **Manual Required**: [List manual steps]

### Recommended Approach
[Based on research, what's the best path forward?]

### Time Estimates
- VM Creation: [X minutes]
- Initial Config: [X minutes]  
- Network Setup: [X minutes]
- Service Config: [X minutes]
- **Total**: [X minutes]

## Next Steps

1. [ ] Validate findings in test environment
2. [ ] Create proof-of-concept playbook
3. [ ] Document detailed procedures
4. [ ] Review with team

## References

- OPNsense Documentation: https://docs.opnsense.org/
- API Documentation: [URL]
- Community Forums: [Relevant threads]
- GitHub Issues: [Related automation discussions]

## Notes

[Additional observations and considerations]