# Phase 3 Implementation Testing Manual

**Version**: 1.0  
**Date**: 2025-07-24  
**Purpose**: Comprehensive testing guide for PrivateBox Phase 3 network segmentation implementation

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Testing Environment Setup](#testing-environment-setup)
4. [Bootstrap Integration Testing](#bootstrap-integration-testing)
5. [Network Discovery and Planning Testing](#network-discovery-and-planning-testing)
6. [OPNsense Deployment Testing](#opnsense-deployment-testing)
7. [Firewall Configuration Testing](#firewall-configuration-testing)
8. [Migration Orchestration Testing](#migration-orchestration-testing)
9. [End-to-End Validation](#end-to-end-validation)
10. [Troubleshooting Guide](#troubleshooting-guide)
11. [Test Results Template](#test-results-template)

## Overview

This manual provides detailed testing procedures for all Phase 3 components. Each test includes:
- **Objective**: What the test validates
- **Prerequisites**: Required setup before testing
- **Test Steps**: Detailed procedure
- **Expected Results**: What success looks like
- **Validation Commands**: How to verify results
- **Rollback Procedure**: How to recover from failures

### Testing Principles

1. **Incremental Testing**: Test each component before proceeding to the next
2. **Safe Testing**: All tests include rollback procedures
3. **Validation First**: Verify prerequisites before executing changes
4. **Documentation**: Record all test results for audit trail

## Prerequisites

### Required Infrastructure

- [ ] Proxmox VE host (version 7.0 or higher)
- [ ] Minimum 16GB RAM, 100GB storage
- [ ] Network with DHCP and Internet access
- [ ] SSH access to Proxmox host as root

### Pre-Testing Checklist

```bash
# On Proxmox host, verify:
pveversion
ip addr show
pvesm status
qm list
```

### Testing Tools Required

```bash
# Install testing utilities on workstation
sudo apt-get update
sudo apt-get install -y curl jq netcat-openbsd nmap ansible
```

## Testing Environment Setup

### 1. Create Test Network Snapshot

Before any testing, create a snapshot of your current network state:

```bash
# Document current network configuration
ip addr show > /tmp/network-before-test.txt
ip route show > /tmp/routes-before-test.txt
iptables-save > /tmp/iptables-before-test.txt
```

### 2. Prepare Test Log Directory

```bash
# Create test results directory
mkdir -p ~/privatebox-test-results/$(date +%Y%m%d)
cd ~/privatebox-test-results/$(date +%Y%m%d)
```

## Bootstrap Integration Testing

### Test 1.1: Proxmox Discovery Function

**Objective**: Verify automatic Proxmox host discovery during bootstrap

**Test Steps**:

1. Deploy fresh Ubuntu VM using quickstart:
```bash
curl -fsSL https://raw.githubusercontent.com/Rasped/privatebox/main/quickstart.sh | sudo bash
```

2. SSH into the deployed VM:
```bash
ssh privatebox@<VM-IP>
```

3. Check if Proxmox was discovered:
```bash
sudo cat /etc/privatebox-proxmox-host
```

**Expected Results**:
- File contains Proxmox host IP address
- No error messages during discovery

**Validation Commands**:
```bash
# Verify Proxmox is accessible from VM
curl -k https://$(cat /etc/privatebox-proxmox-host):8006/api2/json/version
```

### Test 1.2: Semaphore Inventory Creation

**Objective**: Verify Semaphore creates inventory with Proxmox host

**Test Steps**:

1. Access Semaphore UI:
```
http://<VM-IP>:3000
Username: admin
Password: (from /opt/privatebox/credentials/semaphore-admin-password.txt)
```

2. Navigate to Inventory section

3. Verify "Infrastructure" inventory contains:
   - container-host (ubuntu-management)
   - proxmox-host group with discovered IP

**Expected Results**:
- Both host groups present in inventory
- Proxmox host has correct IP address

**Validation Commands**:
```bash
# Check inventory file directly
sudo cat /opt/privatebox/ansible/inventories/development/hosts.yml
```

### Test 1.3: SSH Key Deployment

**Objective**: Verify SSH keys are properly deployed to Proxmox

**Test Steps**:

1. From management VM, test Ansible connectivity:
```bash
cd /opt/privatebox/ansible
ansible -i inventories/development/hosts.yml proxmox-host -m ping
```

**Expected Results**:
- Ping succeeds without password prompt
- Returns "pong" response

**Troubleshooting**:
- If fails, manually deploy SSH key:
```bash
ssh-copy-id -i /home/ubuntuadmin/.ssh/id_rsa root@<PROXMOX-IP>
```

## Network Discovery and Planning Testing

### Test 2.1: Environment Discovery Playbook

**Objective**: Verify Proxmox environment discovery works correctly

**Test Steps**:

1. Run discovery playbook via Semaphore or manually:
```bash
cd /opt/privatebox/ansible
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/discover-environment.yml
```

2. Check discovery results:
```bash
cat /opt/privatebox/ansible/host_vars/proxmox/discovered.yml
```

**Expected Results**:
- Proxmox version detected
- Storage pools listed with available space
- Network bridges identified
- No errors during execution

**Validation Points**:
- [ ] Proxmox version matches actual version
- [ ] At least one storage pool found
- [ ] vmbr0 bridge detected
- [ ] Discovery completed within 30 seconds

### Test 2.2: Network Planning Playbook

**Objective**: Verify network plan generation with conflict detection

**Test Steps**:

1. Run network planning playbook:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/plan-network.yml
```

2. Review generated plan:
```bash
cat /opt/privatebox/ansible/group_vars/all/network_plan.yml
```

**Expected Results**:
- VLAN IDs assigned (10, 20, 30, 40)
- Network subnets configured (10.0.x.0/24)
- No IP conflicts detected
- Service IPs allocated

**Validation Commands**:
```bash
# Verify plan structure
yq eval '.vlan_networks' /opt/privatebox/ansible/group_vars/all/network_plan.yml
```

## OPNsense Deployment Testing

### Test 3.1: OPNsense VM Creation

**Objective**: Verify OPNsense VM can be created with proper configuration

**Prerequisites**:
- Network plan exists (from Test 2.2)
- OPNsense ISO available

**Test Steps**:

1. Download OPNsense ISO:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/download-opnsense.yml
```

2. Create OPNsense VM:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/create-opnsense-vm.yml
```

3. Configure boot settings:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/configure-opnsense-boot.yml
```

**Expected Results**:
- VM created with ID 105 (or next available)
- 5 network interfaces attached
- Boot order set correctly
- Serial console enabled

**Validation Commands**:
```bash
# On Proxmox host
qm config 105 | grep -E "(net|boot|serial)"
```

### Test 3.2: OPNsense Initial Boot

**Objective**: Verify OPNsense boots with generated config.xml

**Test Steps**:

1. Start OPNsense VM:
```bash
# On Proxmox host
qm start 105
```

2. Connect to console:
```bash
qm terminal 105
```

3. Wait for boot completion (2-3 minutes)

4. Verify interfaces are assigned:
   - WAN: vtnet0
   - LAN: vtnet1 (VLAN 10)
   - OPT1: vtnet2 (VLAN 20)
   - OPT2: vtnet3 (VLAN 30)
   - OPT3: vtnet4 (VLAN 40)

**Expected Results**:
- OPNsense boots without errors
- All interfaces detected
- Web GUI accessible on https://10.0.10.1

## Firewall Configuration Testing

### Test 4.1: Base Firewall Rules

**Objective**: Verify base firewall rules are applied correctly

**Prerequisites**:
- OPNsense VM running
- API access enabled

**Test Steps**:

1. Enable API and configure base rules:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/configure-firewall-base.yml
```

2. Verify anti-lockout rule exists:
```bash
curl -k -u "api_key:api_secret" \
  https://10.0.10.1/api/firewall/filter/searchRule?current=1&rowCount=10
```

**Expected Results**:
- Anti-lockout rule as first rule
- Network aliases created
- Default deny policy active

### Test 4.2: Inter-VLAN Routing Rules

**Objective**: Verify VLAN isolation works as designed

**Test Steps**:

1. Apply inter-VLAN rules:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/configure-inter-vlan.yml
```

2. Test connectivity matrix:

| From VLAN | To VLAN | Port | Expected Result |
|-----------|---------|------|-----------------|
| Management | All | All | ✅ Allow |
| Services | Internet | 80,443 | ✅ Allow |
| Services | Management | All | ❌ Block |
| LAN | Services | 53,80,443 | ✅ Allow |
| LAN | Management | All | ❌ Block |
| IoT | Services | 53 | ✅ Allow |
| IoT | LAN | All | ❌ Block |

**Validation Commands**:
```bash
# From each VLAN, test connectivity
ping -c 1 10.0.10.1  # Should work from Management only
curl -I http://10.0.20.21:3000  # Should work from LAN
```

### Test 4.3: Security Monitoring

**Objective**: Verify IDS/IPS and logging configuration

**Test Steps**:

1. Configure security monitoring:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/configure-security-monitoring.yml
```

2. Generate test traffic to trigger logging

3. Check monitoring dashboard:
```bash
/opt/privatebox/scripts/security-monitor.sh
```

**Expected Results**:
- Suricata running if enabled
- Logs being generated
- Alerts configured

## Migration Orchestration Testing

### Test 5.1: Pre-Migration Validation

**Objective**: Verify environment is ready for migration

**Test Steps**:

1. Run pre-migration check:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/pre-migration-check.yml
```

2. Review validation report:
```bash
cat /opt/privatebox/logs/pre-migration-validation-*.log
```

**Expected Results**:
- All critical checks pass
- Rollback script created
- Warnings documented

### Test 5.2: VLAN Bridge Configuration

**Objective**: Verify VLAN bridges are created correctly

**Test Steps**:

1. Configure VLAN bridges:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/configure-vlan-bridges.yml
```

2. Verify bridges on Proxmox:
```bash
# On Proxmox host
ip link show | grep vmbr
bridge vlan show
```

**Expected Results**:
- VLAN bridges 100-105 created
- VLAN tagging configured
- Network connectivity maintained

### Test 5.3: Service Migration

**Objective**: Verify services move to correct VLANs

**Test Steps**:

1. Run service migration in test mode:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/migrate-services.yml \
  -e "test_mode=true"
```

2. Review migration plan

3. Execute actual migration:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/migrate-services.yml
```

**Expected Results**:
- AdGuard moves to Services VLAN (10.0.20.21)
- Portainer moves to Management VLAN (10.0.10.22)
- Semaphore moves to Management VLAN (10.0.10.23)
- Services remain accessible

**Validation Commands**:
```bash
# Test service connectivity
curl -I http://10.0.20.21:3000  # AdGuard
curl -I https://10.0.10.22:9443  # Portainer
curl -I http://10.0.10.23:3000   # Semaphore
```

### Test 5.4: Post-Migration Validation

**Objective**: Verify complete system functionality after migration

**Test Steps**:

1. Run post-migration validation:
```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/post-migration-validation.yml
```

2. Review HTML report:
```bash
# Open in browser
firefox /opt/privatebox/reports/migration-validation-report.html
```

**Expected Results**:
- All tests pass (>95% success rate)
- Services accessible on new IPs
- DNS resolution working
- Firewall rules enforced

## End-to-End Validation

### Complete System Test

Run this after all components are deployed:

```bash
# 1. Test Management Access
ssh privatebox@10.0.10.20
curl -I https://10.0.10.1  # OPNsense GUI

# 2. Test Service Access from LAN
curl http://10.0.20.21:3000  # AdGuard
nslookup google.com 10.0.20.21  # DNS

# 3. Test Internet Access
ping -c 1 8.8.8.8  # From LAN VLAN
ping -c 1 8.8.8.8  # From IoT VLAN (should work)

# 4. Test VLAN Isolation
ping 10.0.10.1  # From Services (should fail)
ping 10.0.30.1  # From IoT (should fail)

# 5. Test VPN Access (if configured)
# Connect with WireGuard client
# Verify access based on configuration
```

## Troubleshooting Guide

### Common Issues and Solutions

#### Issue: Proxmox Discovery Fails
**Symptoms**: No IP in /etc/privatebox-proxmox-host
**Solution**:
```bash
# Manually discover Proxmox
nmap -p 8006 192.168.1.0/24
# Add IP manually
echo "192.168.1.10" | sudo tee /etc/privatebox-proxmox-host
```

#### Issue: Ansible Cannot Connect to Proxmox
**Symptoms**: Permission denied errors
**Solution**:
```bash
# Deploy SSH key manually
ssh-copy-id -i ~/.ssh/id_rsa root@PROXMOX-IP
# Test connection
ansible -i inventories/development/hosts.yml proxmox-host -m ping
```

#### Issue: OPNsense VM Won't Start
**Symptoms**: Error about network device
**Solution**:
```bash
# Check bridge exists
brctl show
# Recreate if missing
ip link add vmbr1 type bridge
```

#### Issue: Services Unreachable After Migration
**Symptoms**: Connection timeout
**Solution**:
```bash
# Check service status
systemctl status container-adguard
# Check IP binding
ss -tlnp | grep :3000
# Restart with new network
systemctl restart container-adguard
```

#### Issue: VLAN Traffic Not Passing
**Symptoms**: No connectivity between VLANs
**Solution**:
```bash
# Check VLAN configuration
bridge vlan show
# Verify firewall rules
# Check OPNsense GUI → Firewall → Rules
```

### Emergency Recovery Procedures

#### Full System Rollback
```bash
# 1. Run rollback script (created during pre-migration)
sudo /opt/privatebox/scripts/rollback-migration.sh

# 2. Restore network configuration
sudo cp /etc/network/interfaces.backup /etc/network/interfaces
sudo systemctl restart networking

# 3. Restore service configurations
sudo systemctl stop container-*
# Restore original network bindings
sudo systemctl start container-*
```

#### OPNsense Factory Reset
```bash
# Console into OPNsense
qm terminal 105
# Select option 4 (Reset to factory defaults)
# Reconfigure manually or restore backup
```

## Test Results Template

Use this template to document your test results:

```markdown
# PrivateBox Phase 3 Test Results

**Tester**: [Name]
**Date**: [YYYY-MM-DD]
**Environment**: [Production/Test]

## Bootstrap Integration
- [ ] Proxmox Discovery: PASS/FAIL
- [ ] Inventory Creation: PASS/FAIL
- [ ] SSH Key Deployment: PASS/FAIL

## Network Discovery
- [ ] Environment Discovery: PASS/FAIL
- [ ] Network Planning: PASS/FAIL

## OPNsense Deployment
- [ ] VM Creation: PASS/FAIL
- [ ] Initial Boot: PASS/FAIL
- [ ] API Access: PASS/FAIL

## Firewall Configuration
- [ ] Base Rules: PASS/FAIL
- [ ] Inter-VLAN Rules: PASS/FAIL
- [ ] Port Forwarding: PASS/FAIL
- [ ] VPN Rules: PASS/FAIL
- [ ] Monitoring: PASS/FAIL

## Migration
- [ ] Pre-Migration Check: PASS/FAIL
- [ ] VLAN Bridges: PASS/FAIL
- [ ] Service Migration: PASS/FAIL
- [ ] DNS/DHCP Update: PASS/FAIL
- [ ] Post-Migration: PASS/FAIL

## Issues Encountered
[List any issues and resolutions]

## Notes
[Additional observations]
```

## Appendix: Quick Test Commands

```bash
# Test All Connectivity
for ip in 10.0.10.1 10.0.20.1 10.0.30.1 10.0.40.1; do
  echo "Testing $ip:"
  ping -c 1 -W 1 $ip && echo "✓ Reachable" || echo "✗ Unreachable"
done

# Test All Services
for service in "10.0.20.21:3000:AdGuard" "10.0.10.22:9443:Portainer" "10.0.10.23:3000:Semaphore"; do
  IFS=':' read -r ip port name <<< "$service"
  echo -n "$name: "
  timeout 2 bash -c "echo >/dev/tcp/$ip/$port" && echo "✓ Online" || echo "✗ Offline"
done

# Generate Test Report
/opt/privatebox/scripts/test-all.sh > test-report-$(date +%Y%m%d-%H%M%S).txt
```

---

This testing manual provides comprehensive procedures to validate every component of the Phase 3 implementation. Follow tests sequentially for best results, and always maintain backups before proceeding with migration steps.