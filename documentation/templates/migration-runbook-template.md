# Network Migration Runbook Template

**Date**: [Date]  
**Version**: [Version]  
**Author**: [Author]  
**Estimated Duration**: [X hours]

## Overview

This runbook provides step-by-step procedures for migrating from the current flat network (192.168.1.0/24) to the segmented VLAN architecture.

## Pre-Migration Requirements

### Prerequisites Checklist
- [ ] OPNsense VM deployed and accessible
- [ ] All VLANs configured on Proxmox
- [ ] Backup of all configurations completed
- [ ] Test environment validated
- [ ] Rollback procedures reviewed
- [ ] Communication sent to stakeholders
- [ ] Maintenance window scheduled

### Required Access
- [ ] Proxmox host console access
- [ ] IPMI/iDRAC access (if available)
- [ ] Physical access to server (emergency)
- [ ] Secondary device for troubleshooting

### Tools Required
- SSH client with saved sessions
- Serial console cable (backup)
- Network scanner (nmap/angry IP)
- Documentation printed (offline access)

## Migration Phases

### Phase A: Preparation (T-24 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| A.1 | Create full VM backups | Verify backup files exist | N/A | 30 min |
| A.2 | Document current network | Screenshot all configs | N/A | 15 min |
| A.3 | Test console access | Confirm IPMI working | Fix access issues | 10 min |
| A.4 | Stage configuration files | Files ready on Proxmox | N/A | 5 min |

### Phase B: OPNsense Configuration (T+0)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| B.1 | Configure OPNsense VLANs | VLANs visible in UI | Remove VLAN config | 20 min |
| B.2 | Set up interface IPs | Ping each interface | Reset to defaults | 15 min |
| B.3 | Configure DHCP servers | DHCP pools active | Disable DHCP | 15 min |
| B.4 | Add basic firewall rules | Rules in place | Remove rules | 30 min |

**Hold Point**: Verify OPNsense fully configured before proceeding

### Phase C: Proxmox Network Setup (T+1.5 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| C.1 | Create vmbr1 (VLAN bridge) | Bridge exists | Delete bridge | 5 min |
| C.2 | Configure VLAN awareness | VLAN tag support | Remove VLAN config | 5 min |
| C.3 | Add management VLAN | Can ping gateway | Remove VLAN | 10 min |
| C.4 | Test connectivity | SSH still works | Revert network | 10 min |

**Critical**: Do NOT proceed if SSH access is lost

### Phase D: Service Migration (T+2 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| D.1 | Shutdown Management VM | VM is stopped | Start VM | 2 min |
| D.2 | Change VM network to vmbr1.20 | Config updated | Revert to vmbr0 | 5 min |
| D.3 | Update VM IP to 10.0.20.21 | New IP configured | Revert IP | 10 min |
| D.4 | Start VM and test | Services accessible | Revert all changes | 10 min |

### Phase E: DNS Migration (T+2.5 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| E.1 | Update AdGuard upstream | Points to OPNsense | Revert upstream | 5 min |
| E.2 | Test DNS resolution | nslookup works | Revert DNS config | 10 min |
| E.3 | Update DHCP DNS servers | New DNS in leases | Revert DHCP | 10 min |

### Phase F: Client Migration (T+3 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| F.1 | Move test client to LAN VLAN | Gets DHCP lease | Move back | 10 min |
| F.2 | Verify connectivity | Internet works | Revert VLAN | 10 min |
| F.3 | Migrate remaining clients | All clients moved | Move back | 30 min |

### Phase G: Cleanup (T+4 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| G.1 | Remove old network config | Old IPs gone | Re-add config | 15 min |
| G.2 | Update documentation | Docs current | N/A | 20 min |
| G.3 | Final testing | All services work | Full rollback | 30 min |

## Verification Tests

### Network Connectivity Tests
```bash
# From each VLAN, test:
ping 10.0.X.1          # Gateway
ping 10.0.20.21        # AdGuard
ping 8.8.8.8           # Internet
nslookup google.com    # DNS
```

### Service Availability Tests
```bash
# Test each service:
curl http://10.0.20.21:9000    # Portainer
curl http://10.0.20.21:3000    # Semaphore  
curl http://10.0.20.21:8080    # AdGuard
```

## Rollback Procedures

### Complete Rollback (Emergency)
1. Console into Proxmox host
2. Restore network configuration backup:
   ```bash
   cp /etc/network/interfaces.backup /etc/network/interfaces
   systemctl restart networking
   ```
3. Change VM network back to vmbr0
4. Restore VM IP addresses
5. Restart all services

### Partial Rollback (Specific Service)
1. Stop affected service
2. Revert network configuration
3. Update IP address
4. Restart service
5. Verify functionality

## Post-Migration Tasks

- [ ] Update all documentation
- [ ] Send completion notification
- [ ] Monitor for 24 hours
- [ ] Schedule follow-up review
- [ ] Document lessons learned

## Emergency Contacts

| Role | Name | Contact | Available |
|------|------|---------|-----------|
| Network Admin | | | |
| Backup Admin | | | |
| Management | | | |

## Notes and Warnings

⚠️ **WARNING**: Never lose console access to Proxmox host  
⚠️ **WARNING**: Always test changes on single service first  
⚠️ **WARNING**: Keep rollback window under 15 minutes

## Appendix: Command Reference

### Proxmox Network Commands
```bash
# Show network config
cat /etc/network/interfaces

# Restart networking
systemctl restart networking

# Show bridge info
brctl show
```

### OPNsense Commands
```bash
# Show interface status
ifconfig

# Restart networking
/etc/rc.d/netif restart
```

### Testing Commands
```bash
# Test VLAN connectivity
ping -c 4 10.0.X.1

# Test DNS
dig @10.0.20.21 google.com

# Port scan
nmap -p 22,80,443 10.0.20.21
```