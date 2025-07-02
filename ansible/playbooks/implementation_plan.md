# Ansible Playbook Implementation Plan

## Executive Summary

This document outlines the comprehensive implementation plan for Ansible playbooks in the PrivateBox project. The implementation follows a phased approach to build a privacy-focused router infrastructure on Proxmox, incorporating OPNSense firewall, AdGuard Home, Unbound DNS, and management tools.

## Project Context

- **Target Infrastructure**: Proxmox VE on Intel N100 mini PCs (8-16GB RAM)
- **Current State**: Basic directory structure with minimal common role
- **Goal**: Complete automation of privacy router deployment and management

## Phase 1: Core Infrastructure Setup (Week 1)

### 1.1 Directory Structure Enhancement

Create the following directory structure:

```
ansible/
├── playbooks/
│   ├── orchestration/
│   │   └── site.yml (update existing)
│   ├── provisioning/
│   │   ├── provision_infrastructure.yml
│   │   ├── provision_opnsense_vm.yml
│   │   └── provision_ubuntu_vm.yml
│   ├── deployment/
│   │   ├── deploy_base_services.yml
│   │   ├── deploy_network_services.yml
│   │   ├── deploy_management_services.yml
│   │   ├── configure_opnsense_initial.yml
│   │   ├── deploy_adguard_home_container.yml
│   │   └── deploy_unbound_dns.yml
│   └── maintenance/
│       ├── common_vm_maintenance.yml
│       ├── update_blocklists.yml
│       ├── backup.yml
│       └── validate_deployment.yml
├── roles/
│   ├── common/ (enhance existing)
│   ├── proxmox/
│   ├── opnsense/
│   ├── adguard_home/
│   ├── unbound_dns/
│   ├── portainer/
│   ├── semaphore/
│   └── security_hardening/
├── inventories/
│   ├── development/
│   │   ├── hosts.yml (update existing)
│   │   ├── group_vars/
│   │   └── dynamic_inventory.py
│   └── production/
│       ├── hosts.yml
│       └── group_vars/
├── group_vars/
│   ├── all.yml
│   ├── proxmox_hosts.yml
│   ├── opnsense_vms.yml
│   ├── ubuntu_servers.yml
│   └── vault/
│       ├── all.yml
│       ├── proxmox_hosts.yml
│       └── ubuntu_servers.yml
└── collections/
    └── requirements.yml
```

### 1.2 Common Role Enhancement

Expand the existing common role with the following tasks:

- **User Management** (`tasks/users.yml`)
  - Create system users with sudo privileges
  - Deploy SSH keys for ansible access
  - Configure user shells and home directories

- **Package Management** (`tasks/packages.yml`)
  - Install essential packages (curl, wget, vim, htop)
  - Configure package repositories
  - Handle OS-specific package names

- **Time Configuration** (`tasks/time.yml`)
  - Set system timezone
  - Configure NTP client
  - Ensure time synchronization

- **SSH Hardening** (`tasks/ssh.yml`)
  - Disable root login
  - Configure key-only authentication
  - Set custom SSH port if defined

- **System Updates** (`tasks/updates.yml`)
  - Update package cache
  - Upgrade system packages
  - Configure unattended upgrades

### 1.3 Dynamic Inventory Implementation

Create Proxmox dynamic inventory script:
- Query Proxmox API for VM list
- Group VMs by type (opnsense_vms, ubuntu_servers)
- Extract IP addresses from QEMU guest agent
- Handle authentication and SSL certificates

### 1.4 Collection Dependencies

Create `collections/requirements.yml`:
```yaml
collections:
  - name: community.general
    version: ">=4.0.0"
  - name: containers.podman
    version: ">=1.8.0"
  - name: community.crypto
    version: ">=2.0.0"
  - name: ansible.posix
    version: ">=1.3.0"
  - name: community.proxmox
    version: ">=1.0.0"
```

## Phase 2: VM Provisioning Playbooks (Week 2)

### 2.1 Proxmox Role Development

Create the proxmox role with sub-tasks:

- **VM Creation** (`tasks/create_vm.yml`)
  - Use community.general.proxmox_kvm module
  - Support both creation and modification
  - Handle VM templates and cloning

- **Network Configuration** (`tasks/configure_network.yml`)
  - Configure network bridges
  - Set up VLANs if required
  - Configure firewall rules

- **Storage Management** (`tasks/manage_storage.yml`)
  - Create and attach disks
  - Configure backup storage
  - Manage ISO images

### 2.2 Provision Infrastructure Playbook

`playbooks/provisioning/provision_infrastructure.yml`:
```yaml
---
- name: Provision PrivateBox Infrastructure
  hosts: proxmox_hosts
  gather_facts: yes
  
  tasks:
    - name: Ensure Proxmox host is configured
      include_role:
        name: proxmox
      tags: [proxmox]
    
    - name: Provision OPNSense VM
      include_tasks: provision_opnsense_vm.yml
      tags: [opnsense, provision]
    
    - name: Provision Ubuntu Server VM
      include_tasks: provision_ubuntu_vm.yml
      tags: [ubuntu, provision]
```

### 2.3 OPNSense VM Provisioning

`playbooks/provisioning/provision_opnsense_vm.yml`:
- Download OPNSense ISO if not present
- Create VM with specific requirements:
  - 2 CPU cores, 2GB RAM, 20GB disk
  - Two network interfaces (WAN and LAN)
  - Attach ISO for installation
- Configure boot order
- Start VM for manual OS installation

### 2.4 Ubuntu Server VM Configuration

`playbooks/provisioning/provision_ubuntu_vm.yml`:
- Verify existing Ubuntu VM
- Configure network settings
- Ensure container runtime is installed
- Prepare for service deployment

## Phase 3: Service Deployment Playbooks (Week 3)

### 3.1 OPNSense Configuration

`playbooks/deployment/configure_opnsense_initial.yml`:
- Wait for OPNSense to be accessible
- Configure via API:
  - Set admin password
  - Configure network interfaces
  - Set up basic firewall rules
  - Enable SSH for management
  - Configure DNS settings

### 3.2 AdGuard Home Deployment

`playbooks/deployment/deploy_adguard_home_container.yml`:
- Deploy using Podman/Docker
- Configure persistent storage
- Set up web interface
- Configure upstream DNS (Unbound)
- Import initial blocklists
- Set up DNS-over-HTTPS

### 3.3 Unbound DNS Deployment

`playbooks/deployment/deploy_unbound_dns.yml`:
- Install Unbound package or container
- Configure as recursive resolver
- Enable DNSSEC validation
- Set up root hints
- Configure access control
- Optimize performance settings

### 3.4 Network Services Orchestration

`playbooks/deployment/deploy_network_services.yml`:
```yaml
---
- name: Deploy Network Services
  hosts: all
  
  tasks:
    - name: Configure OPNSense
      include_tasks: configure_opnsense_initial.yml
      when: inventory_hostname in groups['opnsense_vms']
      tags: [opnsense]
    
    - name: Deploy DNS Services
      when: inventory_hostname in groups['ubuntu_servers']
      block:
        - include_tasks: deploy_unbound_dns.yml
          tags: [unbound, dns]
        
        - include_tasks: deploy_adguard_home_container.yml
          tags: [adguard, dns]
```

### 3.5 Management Services

`playbooks/deployment/deploy_management_services.yml`:
- Enhance Portainer configuration
- Deploy Semaphore for Ansible UI
- Configure authentication
- Set up project structure in Semaphore

## Phase 4: Advanced Features and Maintenance (Week 4)

### 4.1 Advanced OPNSense Features

`playbooks/deployment/manage_opnsense_advanced_features.yml`:
- VPN Configuration:
  - WireGuard setup
  - OpenVPN server
  - Client configurations
- IDS/IPS Setup:
  - Suricata configuration
  - Rule management
  - Alert handling
- Traffic Shaping:
  - QoS rules
  - Bandwidth management

### 4.2 Maintenance Playbooks

`playbooks/maintenance/common_vm_maintenance.yml`:
- System updates across all VMs
- Log rotation configuration
- Disk space monitoring
- Service health checks
- Certificate renewal

`playbooks/maintenance/update_blocklists.yml`:
- Update AdGuard blocklists
- Refresh Unbound root hints
- Update IDS rules
- Generate reports

`playbooks/maintenance/backup.yml`:
- Backup VM configurations
- Export OPNSense settings
- Backup container data
- Store in designated location

### 4.3 Validation Playbook

`playbooks/maintenance/validate_deployment.yml`:
- Test all services are running
- Verify network connectivity
- Check DNS resolution chain
- Validate firewall rules
- Performance benchmarks

## Phase 5: Integration and Testing (Week 5)

### 5.1 Main Site Playbook Update

Update `ansible/playbooks/site.yml`:
```yaml
---
# Main orchestration playbook for PrivateBox

- import_playbook: provisioning/provision_infrastructure.yml
  tags: [provision]

- import_playbook: deployment/deploy_base_services.yml
  tags: [base]

- import_playbook: deployment/deploy_network_services.yml
  tags: [network]

- import_playbook: deployment/deploy_management_services.yml
  tags: [management]

- import_playbook: maintenance/validate_deployment.yml
  tags: [validate]
```

### 5.2 Semaphore Integration

Configure Semaphore with:
- Project for PrivateBox
- Inventory from dynamic script
- Task templates for each playbook
- Scheduled tasks for maintenance
- Approval workflows for production

### 5.3 Testing Strategy

- **Unit Tests**: Molecule tests for each role
- **Integration Tests**: Full deployment in dev environment
- **Validation Tests**: Service functionality verification
- **Performance Tests**: Resource usage monitoring

## Implementation Guidelines

### Variable Management

Group variables hierarchy:
1. `group_vars/all.yml` - Global defaults
2. `group_vars/<group>.yml` - Group-specific settings
3. `host_vars/<host>.yml` - Host-specific overrides
4. `group_vars/vault/` - Encrypted secrets

### Security Considerations

- All secrets in Ansible Vault
- API keys and passwords never in plaintext
- SSH keys managed separately
- Regular secret rotation
- Audit logging enabled

### Best Practices

1. **Idempotency**: All tasks must be safely repeatable
2. **Tags**: Use consistent tagging for selective execution
3. **Documentation**: Each playbook must have clear documentation
4. **Error Handling**: Implement proper error catching and recovery
5. **Validation**: Always validate changes before applying

## Success Criteria

- [ ] All playbooks execute without errors
- [ ] Services are accessible and functional
- [ ] Dynamic inventory discovers all resources
- [ ] Semaphore can execute all workflows
- [ ] Documentation is complete
- [ ] Security scanning passes
- [ ] Performance meets requirements

## Risk Mitigation

- **Backup Strategy**: Always backup before major changes
- **Rollback Plan**: Document rollback procedures
- **Testing Environment**: Mirror production for testing
- **Gradual Rollout**: Deploy in stages
- **Monitoring**: Implement comprehensive monitoring

## Next Steps

1. Review and approve this implementation plan
2. Set up development environment
3. Begin Phase 1 implementation
4. Weekly progress reviews
5. Adjust timeline as needed

## Appendix: Key Variables

### Required Vault Variables
```yaml
vault_proxmox_api_password: <encrypted>
vault_opnsense_admin_password: <encrypted>
vault_opnsense_api_password: <encrypted>
vault_adguard_admin_password: <encrypted>
vault_semaphore_admin_password: <encrypted>
```

### Network Configuration
```yaml
network_wan_interface: eth0
network_lan_interface: eth1
network_lan_subnet: 192.168.1.0/24
network_lan_gateway: 192.168.1.1
dns_primary: 192.168.1.10
```

### Service Ports
```yaml
service_ports:
  adguard_web: 3000
  adguard_dns: 53
  unbound_dns: 5335
  portainer: 9000
  semaphore: 3001
```

---

This implementation plan provides a structured approach to building the PrivateBox Ansible automation. Each phase builds upon the previous, ensuring a stable and maintainable infrastructure.