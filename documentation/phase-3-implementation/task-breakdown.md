# Phase 3 Implementation Task Breakdown

**Date**: 2025-07-24  
**Objective**: Implement OPNsense network segmentation with 100% automation  
**Approach**: Dynamic, Ansible-first implementation that adapts to any environment

## Overview

This document contains 38 self-contained tasks for implementing Phase 3. Each task is designed to be picked up by any agent with all necessary context, instructions, and verification criteria included.

## Task Format

Each task includes:
- **Objective**: Clear goal statement
- **Prerequisites**: What must be completed first
- **Instructions**: Step-by-step implementation
- **Verification**: How to confirm success
- **Error Handling**: Common issues and solutions
- **Outputs**: What the task produces

---

## 1. Bootstrap Integration Tasks

### Task 1.1: Update Bootstrap Script for Proxmox Discovery

**Objective**: Modify bootstrap to automatically discover and store Proxmox host IP

**Prerequisites**: None

**Instructions**:
1. Edit bootstrap initial setup script
2. Add Proxmox discovery function after network setup
3. Store discovered IP in privatebox-proxmox-host file

**Verification**:
- After bootstrap runs, check for proxmox host file
- Should show IP address of Proxmox host

**Error Handling**:
- If no Proxmox found, log warning but continue
- User can manually create file later
- Bootstrap continues without failure

**Outputs**:
- Proxmox host configuration file
- Log entry about discovery result

---

### Task 1.2: Create Ansible Inventory Template

**Objective**: Update Semaphore setup to add proxmox-host group dynamically

**Prerequisites**: Task 1.1 (Proxmox host file exists)

**Instructions**:
1. Edit Semaphore setup script
2. Modify inventory creation to include proxmox-host
3. Use discovered IP from Task 1.1
4. Add SSH key configuration for Proxmox access
5. Include proper user and become settings

**Verification**:
- Inventory contains both container-host and proxmox-host groups
- Proxmox host has correct IP and SSH settings
- Can run ad-hoc Ansible commands against both groups

**Error Handling**:
- If no Proxmox IP found, create placeholder entry
- Log clear message about missing configuration
- Allow manual update later

**Outputs**:
- Updated inventory with proxmox-host group
- Proper SSH key associations
- Ready for OPNsense deployment tasks

---

## 2. Environment Discovery Tasks

### Task 2.1: Create Dynamic Environment Discovery Playbook

**Objective**: Build playbook that discovers all Proxmox environment details

**Prerequisites**: Task 1.2 (inventory with proxmox-host)

**Instructions**:
1. Create environment discovery playbook
2. Gather Proxmox version and capabilities
3. Discover storage configurations
4. Map network interfaces and bridges
5. Check available resources
6. Save all data to facts cache

**Verification**:
- Facts file created with environment details
- Can read back storage names and types
- Network bridges properly identified
- Resource availability documented

**Error Handling**:
- Handle missing pvesh command gracefully
- Work with limited permissions
- Provide defaults for critical values

**Outputs**:
- Cached facts about Proxmox environment
- Storage configuration details
- Network topology information
- Available resource summary

---

### Task 2.2: Create Ansible Collections Installer

**Objective**: Ensure all required Ansible collections are installed

**Prerequisites**: None

**Instructions**:
1. Create collections requirements file
2. Include community.general and ansible.posix
3. Create installer playbook
4. Add to Semaphore as setup template
5. Document version requirements

**Verification**:
- Collections properly installed
- Can import required modules
- Version compatibility confirmed

**Error Handling**:
- Check existing installations first
- Handle permission issues
- Provide offline installation notes

**Outputs**:
- Collections requirements file
- Installation playbook
- Semaphore template for collections

---

### Task 2.3: Create Network Configuration Discovery

**Objective**: Build comprehensive network topology discovery

**Prerequisites**: Task 2.1 (environment discovery)

**Instructions**:
1. Create network discovery playbook
2. Identify VM network (vmbr0)
3. Find available physical interfaces
4. Detect existing bridges and VLANs
5. Map current IP allocations
6. Generate network topology report

**Verification**:
- All bridges correctly identified
- Physical interfaces mapped
- Current network usage documented
- VLAN capabilities detected

**Error Handling**:
- Handle different Proxmox network setups
- Work with minimal bridge configurations
- Provide sensible defaults

**Outputs**:
- Network topology facts
- Available interface list
- Bridge configuration details
- VLAN readiness assessment

---

### Task 2.4: Create OPNsense Image Manager

**Objective**: Handle OPNsense ISO download and verification

**Prerequisites**: Task 2.1 (storage discovery)

**Instructions**:
1. Create ISO management playbook
2. Check for existing OPNsense ISOs
3. Download latest stable version if needed
4. Verify checksum
5. Upload to appropriate Proxmox storage
6. Clean up temporary files

**Verification**:
- ISO present in Proxmox storage
- Checksum matches official release
- Old versions cleaned up
- Storage path recorded

**Error Handling**:
- Resume interrupted downloads
- Verify available storage space
- Handle permission issues
- Fallback to manual download instructions

**Outputs**:
- OPNsense ISO in Proxmox storage
- ISO path for VM creation
- Version information recorded

---

### Task 2.5: Create Dynamic VM ID Allocator

**Objective**: Find available VM IDs avoiding conflicts

**Prerequisites**: Task 2.1 (environment discovery)

**Instructions**:
1. Create VM ID discovery playbook
2. List all existing VM IDs
3. Find first available ID starting at 200
4. Validate ID is truly available
5. Reserve ID for OPNsense use

**Verification**:
- Selected ID not in use
- ID in valid range (200-999)
- Can create VM with this ID

**Error Handling**:
- Handle race conditions
- Check both VMs and containers
- Provide manual override option

**Outputs**:
- Available VM ID for OPNsense
- Fact stored for later use

---

### Task 2.6: Create Feature Documentation Structure

**Objective**: Initialize documentation for Phase 3 implementation

**Prerequisites**: None

**Instructions**:
1. Create feature documentation directory
2. Initialize README with implementation status
3. Create analysis document from planning
4. Set up implementation log
5. Create testing checklist

**Verification**:
- Documentation structure exists
- All template files created
- Planning decisions captured

**Error Handling**:
- Check for existing documentation
- Preserve any existing content
- Create backups if needed

**Outputs**:
- Feature documentation structure
- Implementation tracking files
- Testing checklists

---

## 3. OPNsense VM Deployment Tasks

### Task 3.1: Create Adaptive VM Deployment Playbook

**Objective**: Build main OPNsense VM deployment playbook

**Prerequisites**: 
- Task 2.5 (VM ID allocated)
- Task 2.4 (ISO available)

**Instructions**:
1. Create VM deployment playbook
2. Use discovered environment facts
3. Configure VM with optimal settings
4. Attach ISO for installation
5. Configure boot order
6. Set up console access

**Verification**:
- VM created successfully
- Proper CPU and memory allocated
- Console accessible
- Boot order correct

**Error Handling**:
- Clean up on failure
- Check resource availability
- Validate all parameters
- Provide clear error messages

**Outputs**:
- OPNsense VM created
- Console access configured
- Ready for installation

---

### Task 3.2: Create Smart Disk Configuration

**Objective**: Configure optimal disk setup for OPNsense

**Prerequisites**: Task 3.1 (VM exists)

**Instructions**:
1. Determine optimal disk size (32GB minimum)
2. Select fastest available storage
3. Configure disk with VirtIO SCSI
4. Enable discard for thin provisioning
5. Set up appropriate cache mode

**Verification**:
- Disk properly attached
- Correct size allocated
- Performance options enabled
- Thin provisioning working

**Error Handling**:
- Check available storage space
- Handle different storage types
- Fall back to safe defaults
- Log storage decisions

**Outputs**:
- VM disk configured
- Storage optimizations applied
- Performance settings documented

---

### Task 3.3: Create Network Interface Configurator

**Objective**: Set up network interfaces for OPNsense

**Prerequisites**: 
- Task 3.1 (VM exists)
- Task 2.3 (network topology discovered)

**Instructions**:
1. Create network configuration playbook
2. Add WAN interface on vmbr0
3. Create LAN interface for internal network
4. Configure MAC addresses
5. Enable VirtIO network drivers
6. Document interface mapping

**Verification**:
- Two network interfaces present
- Correct bridge assignments
- VirtIO drivers enabled
- MAC addresses set

**Error Handling**:
- Validate bridge availability
- Check for MAC conflicts
- Handle missing bridges
- Provide clear network mapping

**Outputs**:
- Network interfaces configured
- WAN/LAN mapping documented
- Ready for OPNsense setup

---

### Task 3.4: Create VM Start with Health Detection

**Objective**: Start VM and monitor boot process

**Prerequisites**: Task 3.3 (network configured)

**Instructions**:
1. Create VM startup playbook
2. Start OPNsense VM
3. Monitor console output
4. Detect when installer ready
5. Record console access details
6. Set up health monitoring

**Verification**:
- VM starts successfully
- Console output visible
- Installer menu detected
- Can access via console

**Error Handling**:
- Timeout on boot detection
- Handle boot failures
- Provide console access info
- Enable debugging if needed

**Outputs**:
- VM running
- Console access documented
- Ready for installation

---

### Task 3.5: Create State Verification System

**Objective**: Build comprehensive state checking system

**Prerequisites**: All previous deployment tasks

**Instructions**:
1. Create verification playbook
2. Check VM exists and configuration
3. Verify network interfaces
4. Confirm disk configuration
5. Validate console access
6. Generate deployment report

**Verification**:
- All checks pass
- Configuration matches requirements
- Report generated successfully

**Error Handling**:
- Provide detailed failure info
- Suggest remediation steps
- Allow partial success

**Outputs**:
- Deployment verification report
- Configuration summary
- Next steps documentation

---

## 4. OPNsense Installation Automation Tasks

### Task ID: 4.1
**Title**: Create OPNsense Installer Automation

**Objective**: Automate OPNsense installation process via console

**Prerequisites**: Task 3.5 (VM deployed and verified)

**Instructions**:
1. Create console automation playbook
2. Connect to VM console via Proxmox
3. Navigate installer menus
4. Configure disk partitioning
5. Set initial root password
6. Complete base installation

**Verification**:
- Installation completes without errors
- System reboots successfully
- Can detect login prompt
- Base system functional

**Error Handling**:
- Handle installer variations
- Detect and retry on failures
- Provide manual fallback steps
- Log all console interactions

**Outputs**:
- OPNsense base system installed
- Root password set
- Console access maintained

---

### Task ID: 4.2
**Title**: Configure OPNsense Network Interfaces

**Objective**: Set up initial network configuration via console

**Prerequisites**: Task 4.1 (base installation complete)

**Instructions**:
1. Access OPNsense console menu
2. Assign WAN interface
3. Configure LAN interface
4. Set interface IP addresses
5. Configure DHCP for LAN
6. Enable web interface

**Verification**:
- Interfaces properly assigned
- IP addresses configured
- Can ping from OPNsense
- Web interface accessible

**Error Handling**:
- Handle interface detection issues
- Validate IP configurations
- Check for conflicts
- Provide network diagnostics

**Outputs**:
- Network interfaces configured
- Web interface enabled
- Initial connectivity established

---

### Task ID: 4.3
**Title**: Bootstrap OPNsense API Access

**Objective**: Enable and configure API for automation

**Prerequisites**: Task 4.2 (network configured)

**Instructions**:
1. Create API enablement playbook
2. Access web interface programmatically
3. Create API user and credentials
4. Generate API key
5. Store credentials securely
6. Test API connectivity

**Verification**:
- API user created
- Credentials stored safely
- Can make API calls
- Proper permissions set

**Error Handling**:
- Handle web interface variations
- Secure credential storage
- Validate API responses
- Provide troubleshooting

**Outputs**:
- API access configured
- Credentials stored
- Ready for API automation

---

### Task ID: 4.4
**Title**: Create VLAN Configuration Automation

**Objective**: Configure all VLANs via OPNsense API

**Prerequisites**: Task 4.3 (API access ready)

**Instructions**:
1. Create VLAN configuration playbook
2. Define VLAN interfaces via API
3. Assign VLAN IDs and names
4. Configure IP addresses
5. Set up VLAN tagging
6. Enable interfaces

**Verification**:
- All VLANs created
- Proper IDs assigned
- IP addresses configured
- Interfaces active

**Error Handling**:
- Validate VLAN IDs
- Check for duplicates
- Handle API errors
- Provide rollback capability

**Outputs**:
- VLANs fully configured
- Interface mapping documented
- Ready for service migration

---

### Task ID: 4.5
**Title**: Configure DNS and DHCP Services

**Objective**: Set up DNS and DHCP for all VLANs

**Prerequisites**: Task 4.4 (VLANs configured)

**Instructions**:
1. Configure DNS forwarder
2. Set up DHCP scopes per VLAN
3. Configure static mappings
4. Set DNS servers
5. Configure DHCP options
6. Enable services

**Verification**:
- DNS resolution working
- DHCP leases issued
- Correct IP ranges
- Options properly set

**Error Handling**:
- Validate IP ranges
- Check for overlaps
- Test DNS resolution
- Monitor DHCP leases

**Outputs**:
- DNS and DHCP operational
- All VLANs serviced
- Client connectivity ready

---

### Task ID: 4.6
**Title**: Create Security Policy Framework

**Objective**: Implement security policies and rules

**Prerequisites**: Task 4.5 (basic services ready)

**Instructions**:
1. Create security policy playbook
2. Implement default deny rules
3. Add management access rules
4. Configure service-specific rules
5. Set up logging
6. Enable intrusion detection

**Verification**:
- Policies properly ordered
- Management access working
- Services accessible as designed
- Logging functional

**Error Handling**:
- Test rule ordering
- Validate rule syntax
- Check for conflicts
- Maintain access fallback

**Outputs**:
- Security policies active
- Proper access control
- Logging configured

---

### Task ID: 4.7
**Title**: Create Automated Backup System

**Objective**: Set up configuration backup automation

**Prerequisites**: Task 4.6 (OPNsense fully configured)

**Instructions**:
1. Create backup automation playbook
2. Configure scheduled backups
3. Store backups securely
4. Implement retention policy
5. Test restore procedure
6. Document recovery steps

**Verification**:
- Backups created on schedule
- Can restore configuration
- Retention working
- Recovery documented

**Error Handling**:
- Handle backup failures
- Validate backup integrity
- Test restore process
- Alert on issues

**Outputs**:
- Automated backup system
- Restore procedures
- Configuration safety net

---

## 5. Firewall Rules Implementation Tasks

### Task 5.1: Create Base Firewall Rules Template

**Objective**: Implement foundational security rules

**Prerequisites**: Task 4.6 (security framework ready)

**Instructions**:
1. Create base rules playbook
2. Implement anti-lockout rule
3. Configure management access
4. Set up default deny
5. Add logging rules
6. Configure rule descriptions

**Verification**:
- Cannot lock out management
- Default deny working
- Logging functional
- Rules well-documented

**Error Handling**:
- Always test with rollback
- Maintain console access
- Validate rule syntax
- Keep emergency access

**Outputs**:
- Base security established
- Management protected
- Logging active

---

### Task 5.2: Implement Inter-VLAN Routing Rules

**Objective**: Configure controlled VLAN communication

**Prerequisites**: Task 5.1 (base rules active)

**Instructions**:
1. Create inter-VLAN rules playbook
2. Define allowed communications
3. Implement security zones
4. Configure stateful rules
5. Add rate limiting
6. Enable connection tracking

**Verification**:
- Allowed traffic flows work
- Blocked traffic denied
- No unauthorized routing
- Performance acceptable

**Error Handling**:
- Test each rule carefully
- Monitor for issues
- Check performance impact
- Document all flows

**Outputs**:
- Inter-VLAN routing configured
- Security zones enforced
- Traffic flows documented

---

### Task 5.3: Create Port Forwarding Rules

**Objective**: Configure external service access

**Prerequisites**: Task 5.2 (routing configured)

**Instructions**:
1. Create port forwarding playbook
2. Define required forwards
3. Implement NAT rules
4. Configure firewall allows
5. Set up logging
6. Document external access

**Verification**:
- Services accessible externally
- Only intended ports open
- NAT working correctly
- Logging captures access

**Error Handling**:
- Test from external network
- Validate NAT translations
- Check for conflicts
- Monitor for scanning

**Outputs**:
- Port forwarding active
- Services accessible
- Security maintained

---

### Task 5.4: Configure VPN Access Rules

**Objective**: Set up secure remote access

**Prerequisites**: Task 5.3 (external access ready)

**Instructions**:
1. Create VPN rules playbook
2. Configure VPN firewall rules
3. Set up user access policies
4. Configure client routes
5. Implement access restrictions
6. Enable VPN logging

**Verification**:
- VPN clients can connect
- Proper access granted
- Restrictions enforced
- Logging functional

**Error Handling**:
- Test various clients
- Validate routing
- Check policy enforcement
- Monitor connections

**Outputs**:
- VPN access configured
- Policies enforced
- Remote access ready

---

### Task 5.5: Create Security Monitoring Rules

**Objective**: Implement comprehensive security monitoring

**Prerequisites**: Task 5.4 (all access configured)

**Instructions**:
1. Create monitoring rules playbook
2. Configure IDS/IPS rules
3. Set up traffic analysis
4. Configure alerts
5. Implement rate limiting
6. Enable threat detection

**Verification**:
- IDS/IPS active
- Alerts generated
- Threats detected
- Performance acceptable

**Error Handling**:
- Tune for false positives
- Monitor performance
- Validate detections
- Adjust thresholds

**Outputs**:
- Security monitoring active
- Threat detection enabled
- Alerting configured

---

## 6. Migration Execution Tasks

### Task 6.1: Create Pre-Migration Validation

**Objective**: Ensure environment ready for migration

**Prerequisites**: All previous tasks complete

**Instructions**:
1. Create validation playbook
2. Check all services status
3. Verify network configuration
4. Test firewall rules
5. Validate backup system
6. Generate readiness report

**Verification**:
- All checks pass
- No blocking issues
- Rollback plan ready
- Documentation complete

**Error Handling**:
- Stop on critical issues
- Provide clear remediation
- Test rollback procedure
- Document all findings

**Outputs**:
- Migration readiness confirmed
- Issues resolved
- Go/no-go decision support

---

### Task 6.2: Implement VLAN Bridge Configuration

**Objective**: Configure Proxmox bridges for VLANs

**Prerequisites**: Task 6.1 (validation complete)

**Instructions**:
1. Create bridge configuration playbook
2. Add VLAN bridges to Proxmox
3. Configure VLAN tagging
4. Set up trunk ports
5. Test connectivity
6. Document configuration

**Verification**:
- Bridges created successfully
- VLAN tags working
- No network disruption
- Traffic flowing correctly

**Error Handling**:
- Test incrementally
- Have rollback ready
- Monitor connectivity
- Keep console access

**Outputs**:
- VLAN bridges configured
- Proxmox network ready
- Migration can proceed

---

### Task 6.3: Deploy OPNsense with VLAN Support

**Objective**: Reconfigure OPNsense for production VLANs

**Prerequisites**: Task 6.2 (bridges ready)

**Instructions**:
1. Create VLAN deployment playbook
2. Reconfigure OPNsense interfaces
3. Assign VLANs to interfaces
4. Update firewall rules
5. Test all VLANs
6. Verify routing

**Verification**:
- All VLANs functional
- Routing working
- Firewall rules active
- No connectivity loss

**Error Handling**:
- Test each VLAN
- Monitor for issues
- Have console ready
- Quick rollback plan

**Outputs**:
- OPNsense on VLANs
- Full routing active
- Ready for services

---

### Task 6.4: Migrate Services to VLANs

**Objective**: Move services to appropriate VLANs

**Prerequisites**: Task 6.3 (VLANs active)

**Instructions**:
1. Create service migration playbook
2. Update service network configs
3. Migrate one service at a time
4. Test after each migration
5. Update DNS records
6. Verify all connectivity

**Verification**:
- Services accessible
- Proper VLAN isolation
- DNS resolution working
- No service disruption

**Error Handling**:
- Migrate incrementally
- Test thoroughly
- Quick rollback per service
- Monitor service health

**Outputs**:
- All services migrated
- VLAN isolation active
- Services operational

---

### Task 6.5: Update DNS and DHCP Configuration

**Objective**: Finalize DNS and DHCP for production

**Prerequisites**: Task 6.4 (services migrated)

**Instructions**:
1. Create DNS/DHCP update playbook
2. Update all DNS records
3. Configure DHCP reservations
4. Set up dynamic DNS
5. Test all resolutions
6. Monitor DHCP leases

**Verification**:
- DNS resolution correct
- DHCP assignments working
- Dynamic updates functional
- No conflicts

**Error Handling**:
- Validate all records
- Check for duplicates
- Monitor lease pool
- Test failover

**Outputs**:
- DNS fully operational
- DHCP properly configured
- Name resolution working

---

### Task 6.6: Final Migration Validation

**Objective**: Confirm successful migration completion

**Prerequisites**: Task 6.5 (all services migrated)

**Instructions**:
1. Create final validation playbook
2. Test all services
3. Verify security policies
4. Check performance metrics
5. Validate monitoring
6. Generate completion report

**Verification**:
- All services operational
- Security policies enforced
- Performance acceptable
- Monitoring active

**Error Handling**:
- Document any issues
- Create remediation tasks
- Update documentation
- Plan improvements

**Outputs**:
- Migration complete
- Full documentation
- Operational handover ready

---

## Implementation Notes

1. Each task should be run via Semaphore UI after bootstrap completes
2. Tasks build on each other - complete in order within each section
3. Always verify prerequisites before starting a task
4. Use dynamic discovery instead of hardcoded values
5. Document all decisions and configurations
6. Test thoroughly before proceeding to next task

## Success Criteria

Phase 3 is complete when:
- OPNsense deployed and configured automatically
- All VLANs operational with proper isolation
- Services migrated and functional
- Security policies enforced
- Full automation achieved
- Documentation complete