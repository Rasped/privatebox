# PrivateBox Ansible - Implementation Recommendations

## Executive Summary

After analyzing the PrivateBox Ansible codebase, I've identified several critical gaps and areas for improvement. While the project has a solid foundation with well-structured directories and comprehensive documentation, many core components are missing or incomplete. This document provides actionable recommendations prioritized by impact and implementation order.

## Current State Analysis

### What's Working Well
- **Directory Structure**: Well-organized following Ansible best practices
- **Documentation**: Comprehensive planning documents in `documentation/` directory
- **Role Scaffolding**: Basic role structure created for all major services
- **Inventory**: Both static and dynamic inventory options available
- **Playbook Organization**: Logical separation of provisioning, deployment, and maintenance tasks

### What's Missing or Incomplete

#### 1. **Critical Missing Files**
- Task files referenced in playbooks don't exist:
  - `ansible/playbooks/provisioning/tasks/network_setup.yml`
  - `ansible/playbooks/provisioning/tasks/storage_setup.yml`
  - `ansible/playbooks/provisioning/tasks/validate_infrastructure.yml`
  - `ansible/playbooks/provisioning/templates/provisioning_report.j2`

#### 2. **Incomplete Role Implementations**
- Most roles only have skeleton files with no actual implementation
- Missing critical functionality in key roles:
  - **proxmox**: VM creation tasks are empty
  - **opnsense**: No actual configuration tasks
  - **adguard_home**: Container deployment not implemented
  - **unbound_dns**: Basic configuration missing

#### 3. **Security Gaps**
- Vault files exist but are empty/placeholder
- No actual secrets management implementation
- Missing SSL/TLS certificate handling
- No implementation of security hardening tasks

#### 4. **Missing Infrastructure Components**
- No Proxmox API connection configuration
- Missing container runtime setup (Docker/Podman)
- No network VLAN configuration implementation
- Storage pool management not implemented

#### 5. **Testing and Validation**
- No Molecule tests for any roles
- Missing integration test playbooks
- No CI/CD pipeline configuration
- Validation playbooks referenced but not implemented

## Priority Recommendations

### High Priority (Blocking Issues)

#### 1. **Fix Missing Task Files**
Create the missing task files that are referenced in existing playbooks:

```yaml
# ansible/playbooks/provisioning/tasks/network_setup.yml
---
- name: Configure Proxmox network bridges
  community.general.proxmox_network:
    api_host: "{{ proxmox_api_host }}"
    api_user: "{{ proxmox_api_user }}"
    api_password: "{{ proxmox_api_password }}"
    node: "{{ proxmox_node }}"
    iface: vmbr1
    type: bridge
    autostart: yes
    bridge_ports: "{{ proxmox_bridge_ports | default('none') }}"
    comments: "PrivateBox internal network"

- name: Configure VLANs
  community.general.proxmox_network:
    api_host: "{{ proxmox_api_host }}"
    api_user: "{{ proxmox_api_user }}"
    api_password: "{{ proxmox_api_password }}"
    node: "{{ proxmox_node }}"
    iface: "vlan{{ item.id }}"
    type: vlan
    vlan_raw_device: "{{ item.device }}"
    autostart: yes
  loop: "{{ proxmox_vlans }}"
  when: proxmox_vlans is defined
```

#### 2. **Implement Proxmox Connection Variables**
Add to `ansible/group_vars/all.yml`:

```yaml
# Proxmox API Configuration
proxmox_api_host: "{{ vault_proxmox_api_host }}"
proxmox_api_user: "{{ vault_proxmox_api_user }}"
proxmox_api_password: "{{ vault_proxmox_api_password }}"
proxmox_api_validate_certs: false
proxmox_node: "pve-dev"

# Network Configuration
proxmox_networks:
  management:
    subnet: "10.10.10.0/24"
    vlan: 10
  services:
    subnet: "10.10.20.0/24"
    vlan: 20
  dmz:
    subnet: "10.10.30.0/24"
    vlan: 30
```

#### 3. **Create ansible.cfg File**
The setup.sh creates this, but it should be checked into the repository:

```ini
[defaults]
host_key_checking = False
inventory = ansible/inventories/development/hosts.yml
roles_path = ansible/roles
collections_path = ~/.ansible/collections
vault_password_file = .vault_pass
interpreter_python = auto_silent

[inventory]
enable_plugins = yaml, ini, script, auto

[privilege_escalation]
become = True
become_method = sudo
become_ask_pass = False
```

#### 4. **Implement Core Role Tasks**

##### proxmox/tasks/create_vm.yml
```yaml
---
- name: Create VM from template
  community.general.proxmox_kvm:
    api_host: "{{ proxmox_api_host }}"
    api_user: "{{ proxmox_api_user }}"
    api_password: "{{ proxmox_api_password }}"
    validate_certs: "{{ proxmox_api_validate_certs }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ vm_id }}"
    name: "{{ vm_name }}"
    clone: "{{ vm_template | default(omit) }}"
    newid: "{{ vm_id }}"
    full: yes
    storage: "{{ vm_storage | default('local-lvm') }}"
    timeout: 300
  when: vm_template is defined

- name: Configure VM resources
  community.general.proxmox_kvm:
    api_host: "{{ proxmox_api_host }}"
    api_user: "{{ proxmox_api_user }}"
    api_password: "{{ proxmox_api_password }}"
    validate_certs: "{{ proxmox_api_validate_certs }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ vm_id }}"
    cores: "{{ vm_cores | default(2) }}"
    memory: "{{ vm_memory | default(2048) }}"
    balloon: "{{ vm_balloon | default(0) }}"
    cpu: "{{ vm_cpu_type | default('host') }}"
    update: yes

- name: Start VM
  community.general.proxmox_kvm:
    api_host: "{{ proxmox_api_host }}"
    api_user: "{{ proxmox_api_user }}"
    api_password: "{{ proxmox_api_password }}"
    validate_certs: "{{ proxmox_api_validate_certs }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ vm_id }}"
    state: started
```

### Medium Priority

#### 1. **Implement Dynamic Inventory Integration**
- Add executable permissions to dynamic_inventory.py
- Create environment variable template for Proxmox credentials
- Update documentation on how to use dynamic inventory

#### 2. **Create Collections Requirements**
Create `ansible/collections/requirements.yml`:

```yaml
---
collections:
  - name: community.general
    version: ">=6.0.0"
  - name: containers.podman
    version: ">=1.10.0"
  - name: community.docker
    version: ">=3.0.0"
  - name: ansible.posix
    version: ">=1.5.0"
  - name: community.crypto
    version: ">=2.10.0"
```

#### 3. **Implement Service Deployment Tasks**

##### adguard_home/tasks/main.yml
```yaml
---
- name: Create AdGuard Home directory
  ansible.builtin.file:
    path: "{{ adguard_data_dir }}"
    state: directory
    owner: "{{ adguard_user | default('1000') }}"
    group: "{{ adguard_group | default('1000') }}"
    mode: '0755'

- name: Deploy AdGuard Home container
  containers.podman.podman_container:
    name: adguard-home
    image: "{{ adguard_image }}:{{ adguard_version }}"
    state: started
    restart_policy: unless-stopped
    ports:
      - "53:53/tcp"
      - "53:53/udp"
      - "3000:3000/tcp"
      - "80:80/tcp"
      - "443:443/tcp"
    volumes:
      - "{{ adguard_data_dir }}/work:/opt/adguardhome/work"
      - "{{ adguard_data_dir }}/conf:/opt/adguardhome/conf"
    env:
      TZ: "{{ timezone | default('UTC') }}"
  when: container_runtime == "podman"

- name: Wait for AdGuard Home to start
  ansible.builtin.wait_for:
    port: 3000
    host: "{{ ansible_default_ipv4.address }}"
    delay: 10
    timeout: 60

- name: Configure AdGuard Home
  ansible.builtin.template:
    src: adguard.yaml.j2
    dest: "{{ adguard_data_dir }}/conf/AdGuardHome.yaml"
    owner: "{{ adguard_user | default('1000') }}"
    group: "{{ adguard_group | default('1000') }}"
    mode: '0644'
  notify: restart adguard
```

### Low Priority (Nice to Have)

#### 1. **Add Molecule Testing**
Create basic Molecule tests for each role:

```yaml
# ansible/roles/common/molecule/default/molecule.yml
---
dependency:
  name: galaxy
driver:
  name: docker
platforms:
  - name: instance
    image: quay.io/ansible/ubuntu2204-test:latest
    pre_build_image: true
provisioner:
  name: ansible
  inventory:
    host_vars:
      instance:
        ansible_user: root
verifier:
  name: ansible
```

#### 2. **Add Pre-commit Hooks**
Create `.pre-commit-config.yaml`:

```yaml
---
repos:
  - repo: https://github.com/ansible/ansible-lint
    rev: v6.14.0
    hooks:
      - id: ansible-lint
        files: \.(yaml|yml)$
        exclude: ^documentation/
  
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.4.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
```

## Implementation Roadmap

### Phase 1: Foundation (Week 1)
1. Create missing task files and templates
2. Implement basic Proxmox connection and authentication
3. Set up proper vault structure with example secrets
4. Fix inventory issues and test connectivity

### Phase 2: Core Services (Week 2-3)
1. Implement VM provisioning in proxmox role
2. Create working OPNsense deployment playbook
3. Implement container deployment for AdGuard/Unbound
4. Add basic network configuration

### Phase 3: Management Layer (Week 4)
1. Deploy Portainer for container management
2. Set up Semaphore for Ansible UI
3. Implement backup procedures
4. Create maintenance playbooks

### Phase 4: Security & Testing (Week 5)
1. Implement security hardening role
2. Add SSL/TLS certificate management
3. Create integration tests
4. Document security procedures

### Phase 5: Production Ready (Week 6)
1. Complete documentation
2. Add monitoring and alerting
3. Create disaster recovery procedures
4. Performance optimization

## Quick Wins

To get started immediately:

1. **Run the setup script**: 
   ```bash
   chmod +x setup.sh
   ./setup.sh
   ```

2. **Install required collections**:
   ```bash
   ansible-galaxy collection install -r ansible/collections/requirements.yml
   ```

3. **Create a test playbook** to verify connectivity:
   ```yaml
   # test-connectivity.yml
   ---
   - name: Test connectivity to all hosts
     hosts: all
     gather_facts: no
     tasks:
       - name: Ping test
         ansible.builtin.ping:
   ```

4. **Update inventory** with real IP addresses

5. **Create basic vault file** with minimal secrets

## Security Recommendations

1. **Use Ansible Vault** for all sensitive data
2. **Implement least privilege** - create specific API users for Proxmox
3. **Use SSH keys** exclusively - disable password authentication
4. **Enable firewall rules** before deploying services
5. **Regular security updates** - automate with unattended-upgrades
6. **Audit logging** - implement centralized logging for all operations

## Conclusion

The PrivateBox Ansible project has excellent planning and structure but needs significant implementation work. Following this roadmap will result in a production-ready automation framework for deploying privacy-focused router infrastructure. Start with the high-priority items to unblock basic functionality, then progressively add features and security enhancements.

The most critical next step is fixing the missing files and implementing basic Proxmox connectivity. Once that foundation is in place, the service deployments can proceed in parallel.