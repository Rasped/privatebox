# Network Migration Runbook

**Date**: 2025-07-24  
**Version**: 1.0  
**Author**: Claude  
**Estimated Duration**: 4 hours

## Overview

This runbook provides step-by-step procedures for migrating from the current flat network (192.168.1.0/24) to the segmented VLAN architecture with zero downtime.

## Pre-Migration Requirements

### Prerequisites Checklist
- [ ] OPNsense VM deployed and accessible at 10.0.10.100
- [ ] All VLANs configured on OPNsense
- [ ] Proxmox VLAN bridge (vmbr1) created and tested
- [ ] Full backup of Management VM completed
- [ ] Backup of Proxmox network configuration
- [ ] Test client device available
- [ ] Maintenance window scheduled (4 hours)
- [ ] Team notified of maintenance

### Required Access
- [ ] Proxmox host console access (via IPMI or physical)
- [ ] SSH access to Proxmox host
- [ ] SSH access to Management VM
- [ ] OPNsense console access (via Proxmox console)
- [ ] Secondary device for troubleshooting (laptop/phone)

### Tools Required
- SSH client with saved sessions
- Web browser for service testing
- Network scanner (nmap or similar)
- This documentation (printed or offline copy)
- Proxmox mobile app (backup access)

## Migration Phases

### Phase A: Preparation (T-24 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| A.1 | Create VM snapshots | Verify snapshots in Proxmox UI | N/A | 15 min |
| A.2 | Backup network configs | `cp /etc/network/interfaces /etc/network/interfaces.backup` | N/A | 5 min |
| A.3 | Document current IPs | Screenshot all current configurations | N/A | 10 min |
| A.4 | Test console access | Connect via IPMI, test keyboard | Fix access issues | 10 min |
| A.5 | Stage Ansible playbooks | Verify playbooks on Proxmox host | N/A | 5 min |
| A.6 | Download test scripts | Copy health check scripts to Proxmox | N/A | 5 min |

**Total Phase A: 50 minutes**

### Phase B: OPNsense Deployment (T+0)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| B.1 | Run OPNsense VM playbook | VM shows in Proxmox with ID 100 | Delete VM | 5 min |
| B.2 | Complete manual bootstrap | SSH to 10.0.10.100 works | Restart bootstrap | 15 min |
| B.3 | Run configuration playbook | VLANs visible in OPNsense UI | Rerun playbook | 10 min |
| B.4 | Configure firewall rules | Rules listed in UI | Delete and recreate | 15 min |
| B.5 | Test inter-VLAN routing | Ping between test IPs | Check firewall logs | 10 min |
| B.6 | Configure DNS forwarder | Unbound running on port 5353 | Restart service | 5 min |

**Hold Point**: Do not proceed unless OPNsense routing works correctly

**Total Phase B: 60 minutes**

### Phase C: Proxmox Network Setup (T+1 hour)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| C.1 | Create VLAN bridge | `brctl show` shows vmbr1 | Remove bridge | 5 min |
| C.2 | Enable VLAN filtering | Check `/etc/network/interfaces` | Disable filtering | 5 min |
| C.3 | Add temporary mgmt IP | `ip addr add 10.0.10.10/24 dev vmbr1.10` | Remove IP | 5 min |
| C.4 | Test OPNsense access | `ping 10.0.10.1` from Proxmox | Check VLAN config | 5 min |
| C.5 | Update Proxmox network | Edit `/etc/network/interfaces` | Restore backup | 10 min |

**Critical**: Maintain console access throughout - do NOT disconnect

**Configuration for `/etc/network/interfaces`**:
```
auto vmbr1
iface vmbr1 inet manual
    bridge-ports eno2
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids 2-4094

auto vmbr1.10
iface vmbr1.10 inet static
    address 10.0.10.10/24
    gateway 10.0.10.1
```

**Total Phase C: 30 minutes**

### Phase D: Service Migration (T+1.5 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| D.1 | Configure temp DNS forward | OPNsense forwards 10.0.30.1 → 192.168.1.21 | Remove forward | 5 min |
| D.2 | Snapshot Management VM | Snapshot visible in Proxmox | N/A | 2 min |
| D.3 | Shutdown Management VM | `qm status 9000` shows stopped | Start VM | 2 min |
| D.4 | Change VM network | Edit VM config: `net0: virtio,bridge=vmbr1,tag=20` | Revert config | 5 min |
| D.5 | Update VM network config | Mount disk, edit `/etc/netplan/00-installer-config.yaml` | Revert file | 10 min |
| D.6 | Start VM | `qm start 9000` | Check console | 2 min |
| D.7 | Verify services | Access Portainer at 10.0.20.21:9000 | Revert all | 10 min |
| D.8 | Update DNS forward | OPNsense forwards to 10.0.20.21 | Revert forward | 5 min |

**VM Network Configuration** (`/etc/netplan/00-installer-config.yaml`):
```yaml
network:
  version: 2
  ethernets:
    ens18:
      addresses:
        - 10.0.20.21/24
      gateway4: 10.0.20.1
      nameservers:
        addresses:
          - 127.0.0.1
          - 1.1.1.1
```

**Note**: DNS forwarding ensures clients continue to resolve during VM migration

**Total Phase D: 41 minutes**

### Phase E: DNS Migration (T+2 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| E.1 | Update AdGuard upstream | Set upstream to `10.0.20.1:5353` | Revert to 1.1.1.1 | 5 min |
| E.2 | Test DNS path | `dig @10.0.20.21 google.com` | Check AdGuard logs | 5 min |
| E.3 | Update OPNsense DHCP | Set DNS to 10.0.20.21 | Revert DNS | 5 min |
| E.4 | Force DHCP renewal | Test client: `dhclient -r && dhclient` | Manual DNS | 5 min |
| E.5 | Verify resolution | `nslookup google.com` on client | Set manual DNS | 5 min |

**Total Phase E: 25 minutes**

### Phase F: Client Migration (T+2.5 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| F.1 | Create test VLAN interface | Add VLAN 30 to test device | Remove VLAN | 5 min |
| F.2 | Test connectivity | Ping 8.8.8.8, browse internet | Revert network | 10 min |
| F.3 | Update main gateway | Change default route to 10.0.30.1 | Restore route | 5 min |
| F.4 | Migrate first batch | Move 25% of clients | Move back | 15 min |
| F.5 | Monitor and verify | Check service access | Pause migration | 10 min |
| F.6 | Complete migration | Move remaining clients | Emergency revert | 15 min |

**Total Phase F: 60 minutes**

### Phase G: Cleanup (T+3.5 hours)

| Step | Action | Verification | Rollback | Duration |
|------|--------|--------------|----------|----------|
| G.1 | Remove old gateway | Delete 192.168.1.1 route | Re-add route | 5 min |
| G.2 | Update documentation | Git commit changes | N/A | 15 min |
| G.3 | Remove temporary IPs | Clean up transition configs | N/A | 10 min |
| G.4 | Final service test | Test all services from client | Debug issues | 15 min |
| G.5 | Enable monitoring | Configure alerts | N/A | 10 min |

**Total Phase G: 55 minutes**

## Verification Tests

### Network Connectivity Tests
```bash
# From each VLAN test device:
# Test gateway
ping -c 4 10.0.X.1

# Test DNS
nslookup google.com 10.0.20.21
dig @10.0.20.21 privatebox.local

# Test Internet
curl -I https://www.google.com

# Test services (from LAN VLAN)
curl http://10.0.20.21:9000  # Portainer
curl http://10.0.20.21:3000  # Semaphore
curl http://10.0.20.21:8080  # AdGuard
```

### Service Availability Tests
```bash
# Check all services are running
ssh privatebox@10.0.20.21 'sudo systemctl status container-*'

# Verify AdGuard is resolving
dig @10.0.20.21 +short google.com

# Check Semaphore can reach Ansible targets
curl -c /tmp/cookie -X POST -d '{"auth":"admin","password":"<password>"}' http://10.0.20.21:3000/api/auth/login
```

### Firewall Validation
```bash
# Test inter-VLAN blocking (should fail)
# From LAN device:
ping 10.0.10.10  # Should timeout

# From IoT device:
ping 10.0.30.100  # Should timeout

# Test allowed services (should work)
# From LAN:
nslookup test.com 10.0.20.21  # Should resolve
```

## Rollback Procedures

### Complete Rollback (Emergency)
**Use if multiple services fail or network is unstable**

1. Console into Proxmox host
2. Restore network configuration:
   ```bash
   cp /etc/network/interfaces.backup /etc/network/interfaces
   systemctl restart networking
   ```
3. Stop OPNsense VM:
   ```bash
   qm stop 100
   ```
4. Change Management VM back to vmbr0:
   ```bash
   qm set 9000 --net0 virtio,bridge=vmbr0
   ```
5. Update Management VM IP to 192.168.1.21:
   ```bash
   # Mount VM disk and edit network config
   qm start 9000
   ```
6. Restore client DHCP to original settings

**Time to rollback: 15 minutes**

### Partial Rollback (Service-Specific)
**Use if single service is problematic**

1. Stop affected service:
   ```bash
   ssh privatebox@10.0.20.21 'sudo systemctl stop container-<service>'
   ```
2. If network-related, revert that service's firewall rules
3. Restart service with original configuration
4. Update DNS if AdGuard affected

**Time to rollback: 5-10 minutes**

### DNS-Only Rollback
**Use if DNS resolution fails**

1. Update DHCP to use public DNS:
   ```bash
   # In OPNsense: Services → DHCPv4 → LAN
   # Set DNS servers to 1.1.1.1, 8.8.8.8
   ```
2. Force DHCP renewal on clients
3. Investigate AdGuard/Unbound issue separately

**Time to rollback: 5 minutes**

## Post-Migration Tasks

- [ ] Remove migration snapshots (keep one post-migration)
- [ ] Update all documentation in Git
- [ ] Send completion report to stakeholders
- [ ] Monitor services for 24 hours
- [ ] Schedule team retrospective
- [ ] Update disaster recovery procedures
- [ ] Create new baseline backups
- [ ] Document any issues encountered

## Emergency Contacts

| Role | Name | Contact | Available |
|------|------|---------|-----------|
| Network Admin | Primary | [Phone] | 24/7 |
| Backup Admin | Secondary | [Phone] | Business hours |
| Proxmox Support | N/A | Forum/IRC | Best effort |
| ISP Support | Provider | [Phone] | 24/7 |

## Notes and Warnings

⚠️ **CRITICAL**: Never lose console access to Proxmox host  
⚠️ **CRITICAL**: Always test changes on single device first  
⚠️ **WARNING**: DNS changes propagate slowly - allow 5 min  
⚠️ **WARNING**: Some IoT devices may need manual network reset  
⚠️ **INFO**: Keep migration window under 4 hours to minimize risk

## Appendix: Command Reference

### Proxmox Network Commands
```bash
# Show network config
cat /etc/network/interfaces

# Show bridge status
brctl show
bridge vlan show

# Restart networking (dangerous!)
systemctl restart networking

# Add temporary IP
ip addr add 10.0.10.10/24 dev vmbr1.10

# Show routing table
ip route show
```

### OPNsense Commands
```bash
# Show interface status
ifconfig

# Show VLAN interfaces
ifconfig | grep vlan

# Restart networking
/etc/rc.d/netif restart

# Show firewall rules
pfctl -sr

# Monitor firewall logs
clog -f /var/log/filter.log
```

### Testing Commands
```bash
# Test VLAN connectivity
ping -c 4 -S 10.0.30.100 10.0.30.1

# Test DNS with specific server
dig @10.0.20.21 google.com +short

# Port scan services
nmap -p 22,53,80,443,3000,8080,9000 10.0.20.21

# Check service response time
curl -w "@curl-format.txt" -o /dev/null -s http://10.0.20.21:9000
```

### Ansible Commands
```bash
# Run migration playbook
ansible-playbook -i inventories/production/hosts.yml playbooks/network-migration.yml

# Run with check mode
ansible-playbook -i inventories/production/hosts.yml playbooks/network-migration.yml --check

# Run specific phase
ansible-playbook -i inventories/production/hosts.yml playbooks/network-migration.yml --tags "phase_d"
```

## Migration Timeline Summary

| Phase | Duration | Cumulative |
|-------|----------|------------|
| A: Preparation | 50 min | 0:50 |
| B: OPNsense Setup | 60 min | 1:50 |
| C: Proxmox Network | 30 min | 2:20 |
| D: Service Migration | 31 min | 2:51 |
| E: DNS Migration | 25 min | 3:16 |
| F: Client Migration | 60 min | 4:16 |
| G: Cleanup | 55 min | 5:11 |

**Note**: Includes buffer time. Experienced operator can complete in ~3.5 hours.