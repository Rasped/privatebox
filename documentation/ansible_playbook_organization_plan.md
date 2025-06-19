# Ansible Playbook Organization Plan

## Overview
This document outlines a modular, reusable approach to organizing Ansible playbooks for the privacy-focused router project. The structure follows Ansible best practices with roles, collections, and orchestration playbooks.

## Directory Structure

```
ansible/
├── inventories/
│   ├── production/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   └── development/
│       ├── hosts.yml
│       └── group_vars/
├── roles/
│   ├── common/
│   ├── proxmox/
│   ├── opnsense/
│   ├── adguard_home/
│   ├── unbound_dns/
│   ├── portainer/
│   ├── semaphore/
│   └── security_hardening/
├── playbooks/
│   ├── orchestration/
│   ├── maintenance/
│   ├── deployment/
│   └── provisioning/
├── collections/
│   └── requirements.yml
├── group_vars/
├── host_vars/
├── vault/
├── templates/
├── files/
└── ansible.cfg
```

## Role-Based Organization

### Core Infrastructure Roles

#### 1. `common` Role
**Purpose:** Base configuration for all managed systems
- **Tasks:**
  - User management and SSH key deployment
  - Basic package installation (curl, wget, vim, etc.)
  - Timezone and NTP configuration
  - Basic firewall setup
  - Log rotation configuration
  - System updates

- **Variables:**
  - `common_packages`: List of packages to install
  - `common_users`: User accounts to create
  - `common_timezone`: System timezone
  - `common_ntp_servers`: NTP server list

#### 2. `security_hardening` Role
**Purpose:** Apply security best practices across all systems
- **Tasks:**
  - SSH hardening (disable root login, key-only auth)
  - Fail2ban configuration
  - Unattended upgrades setup
  - File system permissions hardening
  - Audit logging configuration

- **Variables:**
  - `security_ssh_port`: Custom SSH port
  - `security_allowed_users`: List of users allowed SSH access
  - `security_fail2ban_enabled`: Enable/disable fail2ban

#### 3. `proxmox` Role
**Purpose:** Manage Proxmox VE host and VM operations
- **Tasks:**
  - VM creation and configuration
  - Storage management
  - Network bridge configuration
  - Backup configuration
  - Resource monitoring setup

- **Variables:**
  - `proxmox_api_host`: Proxmox API endpoint
  - `proxmox_node`: Target Proxmox node
  - `proxmox_storage`: Default storage location

### Service-Specific Roles

#### 4. `opnsense` Role
**Purpose:** Deploy and configure OPNSense firewall
- **Sub-roles:**
  - `opnsense/provision`: VM creation and OS installation
  - `opnsense/base`: Initial configuration
  - `opnsense/firewall`: Firewall rules and policies
  - `opnsense/vpn`: VPN server configuration
  - `opnsense/ids`: Intrusion Detection System setup

- **Variables:**
  - `opnsense_admin_password`: Admin password (vaulted)
  - `opnsense_wan_interface`: WAN interface name
  - `opnsense_lan_interface`: LAN interface name
  - `opnsense_lan_subnet`: LAN subnet configuration

#### 5. `adguard_home` Role
**Purpose:** Deploy AdGuard Home DNS filtering
- **Tasks:**
  - Container deployment (Podman/Docker)
  - Configuration file management
  - Blocklist management
  - Upstream DNS configuration
  - Web interface setup

- **Variables:**
  - `adguard_container_image`: Container image version
  - `adguard_web_port`: Web interface port
  - `adguard_dns_port`: DNS service port
  - `adguard_blocklists`: List of blocklist URLs

#### 6. `unbound_dns` Role
**Purpose:** Deploy Unbound recursive DNS resolver
- **Tasks:**
  - Package installation or container deployment
  - Configuration file generation
  - DNSSEC validation setup
  - Root hints management
  - Performance tuning

- **Variables:**
  - `unbound_listen_interfaces`: List of interfaces to bind
  - `unbound_access_control`: Access control rules
  - `unbound_forward_zones`: DNS forwarding configuration

#### 7. `portainer` Role
**Purpose:** Manage Portainer container management platform
- **Tasks:**
  - Container deployment
  - Agent deployment for remote management
  - SSL certificate configuration
  - User and team management
  - Template deployment

#### 8. `semaphore` Role
**Purpose:** Deploy and configure Semaphore UI for Ansible
- **Tasks:**
  - Application deployment
  - Database setup
  - Project and inventory configuration
  - User management
  - Git repository integration

## Orchestration Playbooks

### Main Deployment Playbooks

#### 1. `site.yml` - Complete Infrastructure Deployment
```yaml
# High-level orchestration of entire infrastructure
- import_playbook: provisioning/provision_infrastructure.yml
- import_playbook: deployment/deploy_base_services.yml
- import_playbook: deployment/deploy_network_services.yml
- import_playbook: deployment/deploy_management_services.yml
```

#### 2. `provision_infrastructure.yml`
```yaml
# Provision VMs and base OS
- hosts: proxmox_hosts
  roles:
    - proxmox
  tasks:
    - name: Create OPNSense VM
      include_role:
        name: opnsense
        tasks_from: provision

    - name: Create Ubuntu Server VM
      include_role:
        name: proxmox
        tasks_from: create_ubuntu_vm
```

#### 3. `deploy_base_services.yml`
```yaml
# Deploy common configuration to all systems
- hosts: all
  roles:
    - common
    - security_hardening
```

#### 4. `deploy_network_services.yml`
```yaml
# Deploy networking and security services
- hosts: opnsense_vms
  roles:
    - opnsense/base
    - opnsense/firewall

- hosts: ubuntu_servers
  roles:
    - adguard_home
    - unbound_dns
```

#### 5. `deploy_management_services.yml`
```yaml
# Deploy management and monitoring services
- hosts: ubuntu_servers
  roles:
    - portainer
    - semaphore
```

### Feature-Specific Playbooks

#### 6. `configure_vpn.yml`
```yaml
# Configure VPN services
- hosts: opnsense_vms
  roles:
    - opnsense/vpn
```

#### 7. `configure_ids.yml`
```yaml
# Configure Intrusion Detection
- hosts: opnsense_vms
  roles:
    - opnsense/ids
```

#### 8. `update_blocklists.yml`
```yaml
# Update DNS blocklists
- hosts: ubuntu_servers
  roles:
    - adguard_home
  tasks:
    - name: Update blocklists
      include_role:
        name: adguard_home
        tasks_from: update_blocklists
```

### Maintenance Playbooks

#### 9. `maintenance.yml`
```yaml
# Regular maintenance tasks
- hosts: all
  roles:
    - common
  tasks:
    - name: Update system packages
      include_role:
        name: common
        tasks_from: update_packages

    - name: Rotate logs
      include_role:
        name: common
        tasks_from: rotate_logs
```

#### 10. `backup.yml`
```yaml
# Backup critical configurations
- hosts: all
  roles:
    - common
  tasks:
    - name: Backup configurations
      include_role:
        name: common
        tasks_from: backup_config
```

## Variable Management Strategy

### Group Variables Structure
```
group_vars/
├── all.yml                 # Variables for all hosts
├── proxmox_hosts.yml      # Proxmox-specific variables
├── opnsense_vms.yml       # OPNSense VM variables
├── ubuntu_servers.yml     # Ubuntu server variables
└── vault/
    ├── all.yml            # Encrypted secrets for all hosts
    ├── proxmox_hosts.yml  # Encrypted Proxmox secrets
    └── ubuntu_servers.yml # Encrypted Ubuntu secrets
```

### Example Variable Organization

#### `group_vars/all.yml`
```yaml
# Common variables
ntp_servers:
  - 0.pool.ntp.org
  - 1.pool.ntp.org

timezone: "UTC"

common_packages:
  - curl
  - wget
  - vim
  - htop

# Network configuration
dns_servers:
  - "{{ hostvars[groups['ubuntu_servers'][0]]['ansible_default_ipv4']['address'] }}"
  - "8.8.8.8"
```

#### `group_vars/vault/all.yml` (encrypted)
```yaml
# Encrypted secrets
vault_proxmox_api_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          [encrypted_content]

vault_opnsense_admin_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          [encrypted_content]
```

## Collection Dependencies

### `collections/requirements.yml`
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
```

## Testing Strategy

### 1. Molecule Testing for Roles
- Each role should have Molecule tests
- Test different scenarios (fresh install, updates, configuration changes)
- Use Docker/Podman for lightweight testing

### 2. Staging Environment
- Mirror production environment for integration testing
- Test complete playbook execution before production deployment

### 3. Validation Playbooks
```yaml
# validate_deployment.yml
- hosts: all
  tasks:
    - name: Verify services are running
      service:
        name: "{{ item }}"
        state: started
      loop: "{{ expected_services }}"
```

## Execution Strategy

### Development Workflow
1. Develop and test individual roles
2. Test feature-specific playbooks
3. Test orchestration playbooks in staging
4. Deploy to production via Semaphore

### Semaphore Integration
- Create separate Semaphore projects for different environments
- Use dynamic inventory with Proxmox
- Implement approval workflows for production deployments
- Set up scheduled maintenance playbooks

## Security Considerations

1. **Ansible Vault:** Encrypt all sensitive variables
2. **SSH Keys:** Use dedicated SSH keys for Ansible
3. **API Access:** Limit API access to specific IP ranges
4. **Audit Logging:** Log all Ansible executions
5. **Secrets Rotation:** Regular rotation of passwords and keys

## Next Steps

1. Create the directory structure
2. Develop the `common` role first
3. Create basic inventory and variable files
4. Implement one service role (e.g., `adguard_home`)
5. Test with a simple orchestration playbook
6. Gradually add more roles and complexity
7. Integrate with Semaphore for execution

This organization provides:
- **Modularity:** Each role is independent and reusable
- **Scalability:** Easy to add new services or modify existing ones
- **Maintainability:** Clear separation of concerns
- **Testability:** Each component can be tested independently
- **Security:** Proper secrets management and access control
