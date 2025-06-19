# Ansible Technical Implementation Guide

## Overview
This document provides detailed technical specifications for implementing the Ansible playbooks outlined in the organization plan. It includes specific module usage, configuration parameters, dependencies, and implementation details.

## Environment Specifications

### Network Topology
```
Internet
    │
    ├── WAN Interface (eth0) - OPNSense VM
    │   └── LAN Interface (eth1) - 192.168.1.1/24
    │       └── Ubuntu Server VM - 192.168.1.10
    │           ├── AdGuard Home - Port 3000 (Web), 53 (DNS)
    │           ├── Unbound DNS - Port 5335
    │           ├── Portainer - Port 9000
    │           └── Semaphore - Port 3001
```

### VM Specifications
```yaml
# Default VM specifications
vm_defaults:
  opnsense:
    cpu: 2
    memory: 2048  # MB
    disk: 20      # GB
    network_interfaces: 2
    os_type: "other"
    
  ubuntu_server:
    cpu: 4
    memory: 4096  # MB
    disk: 40      # GB
    network_interfaces: 1
    os_type: "l26"  # Linux 2.6+ kernel
```

## Detailed Role Implementations

### 1. Common Role Technical Details

#### File Structure
```
roles/common/
├── tasks/
│   ├── main.yml
│   ├── users.yml
│   ├── packages.yml
│   ├── time.yml
│   ├── ssh.yml
│   └── updates.yml
├── handlers/
│   └── main.yml
├── templates/
│   ├── ssh_config.j2
│   └── ntp.conf.j2
├── files/
│   └── authorized_keys
├── vars/
│   └── main.yml
├── defaults/
│   └── main.yml
└── meta/
    └── main.yml
```

#### Key Tasks Implementation

**tasks/main.yml**
```yaml
---
- name: Include OS-specific variables
  include_vars: "{{ ansible_os_family }}.yml"

- name: Update package cache
  package:
    update_cache: yes
  become: yes

- include_tasks: users.yml
- include_tasks: packages.yml
- include_tasks: time.yml
- include_tasks: ssh.yml
- include_tasks: updates.yml
```

**tasks/users.yml**
```yaml
---
- name: Create system users
  user:
    name: "{{ item.name }}"
    groups: "{{ item.groups | default(['sudo']) }}"
    shell: "{{ item.shell | default('/bin/bash') }}"
    create_home: yes
    state: present
  loop: "{{ common_users }}"
  become: yes

- name: Set up SSH authorized keys
  authorized_key:
    user: "{{ item.name }}"
    key: "{{ item.ssh_key }}"
    state: present
  loop: "{{ common_users }}"
  when: item.ssh_key is defined
  become: yes
```

**tasks/packages.yml**
```yaml
---
- name: Install common packages
  package:
    name: "{{ common_packages }}"
    state: present
  become: yes

- name: Install OS-specific packages
  package:
    name: "{{ common_packages_os_specific }}"
    state: present
  become: yes
  when: common_packages_os_specific is defined
```

### 2. Proxmox Role Technical Details

#### Key Modules and Tasks

**tasks/create_vm.yml**
```yaml
---
- name: Create VM from template
  community.general.proxmox_kvm:
    api_host: "{{ proxmox_api_host }}"
    api_user: "{{ proxmox_api_user }}"
    api_password: "{{ vault_proxmox_api_password }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ vm_config.vmid }}"
    name: "{{ vm_config.name }}"
    memory: "{{ vm_config.memory }}"
    cores: "{{ vm_config.cpu }}"
    scsihw: virtio-scsi-pci
    virtio:
      virtio0: "{{ proxmox_storage }}:{{ vm_config.disk }},format=qcow2"
    net:
      net0: "virtio,bridge={{ vm_config.bridge | default('vmbr0') }}"
    ostype: "{{ vm_config.os_type }}"
    state: present
  register: vm_creation_result

- name: Wait for VM to be created
  pause:
    seconds: 10
  when: vm_creation_result.changed

- name: Start VM
  community.general.proxmox_kvm:
    api_host: "{{ proxmox_api_host }}"
    api_user: "{{ proxmox_api_user }}"
    api_password: "{{ vault_proxmox_api_password }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ vm_config.vmid }}"
    state: started
```

**tasks/configure_vm_network.yml**
```yaml
---
- name: Configure additional network interfaces
  community.general.proxmox_kvm:
    api_host: "{{ proxmox_api_host }}"
    api_user: "{{ proxmox_api_user }}"
    api_password: "{{ vault_proxmox_api_password }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ vm_config.vmid }}"
    net:
      "net{{ item.index }}": "virtio,bridge={{ item.bridge }}"
    update: yes
  loop: "{{ vm_config.additional_networks | default([]) }}"
```

### 3. OPNSense Role Technical Details

#### Sub-role: opnsense/provision

**tasks/main.yml**
```yaml
---
- name: Download OPNSense ISO
  get_url:
    url: "{{ opnsense_iso_url }}"
    dest: "/var/lib/vz/template/iso/{{ opnsense_iso_filename }}"
    mode: '0644'
  delegate_to: "{{ proxmox_node }}"

- name: Create OPNSense VM
  include_role:
    name: proxmox
    tasks_from: create_vm
  vars:
    vm_config:
      vmid: "{{ opnsense_vm_id }}"
      name: "{{ opnsense_vm_name }}"
      memory: "{{ opnsense_memory }}"
      cpu: "{{ opnsense_cpu }}"
      disk: "{{ opnsense_disk }}"
      os_type: "other"
      additional_networks:
        - index: 1
          bridge: "{{ opnsense_lan_bridge }}"

- name: Attach OPNSense ISO
  community.general.proxmox_kvm:
    api_host: "{{ proxmox_api_host }}"
    api_user: "{{ proxmox_api_user }}"
    api_password: "{{ vault_proxmox_api_password }}"
    node: "{{ proxmox_node }}"
    vmid: "{{ opnsense_vm_id }}"
    ide:
      ide2: "{{ proxmox_storage }}:iso/{{ opnsense_iso_filename }},media=cdrom"
    boot: "order=ide2;virtio0"
    update: yes
```

#### Sub-role: opnsense/base

**tasks/main.yml**
```yaml
---
- name: Wait for OPNSense to be accessible
  wait_for:
    host: "{{ opnsense_management_ip }}"
    port: 22
    delay: 30
    timeout: 600

- name: Configure initial OPNSense settings
  uri:
    url: "https://{{ opnsense_management_ip }}/api/core/system/set"
    method: POST
    user: "{{ opnsense_api_user }}"
    password: "{{ vault_opnsense_api_password }}"
    force_basic_auth: yes
    validate_certs: no
    body_format: json
    body:
      system:
        hostname: "{{ opnsense_hostname }}"
        domain: "{{ opnsense_domain }}"
        timezone: "{{ timezone }}"
  register: system_config_result

- name: Configure WAN interface
  uri:
    url: "https://{{ opnsense_management_ip }}/api/interfaces/wan/set"
    method: POST
    user: "{{ opnsense_api_user }}"
    password: "{{ vault_opnsense_api_password }}"
    force_basic_auth: yes
    validate_certs: no
    body_format: json
    body:
      interface:
        enable: "1"
        ipaddr: "dhcp"

- name: Configure LAN interface
  uri:
    url: "https://{{ opnsense_management_ip }}/api/interfaces/lan/set"
    method: POST
    user: "{{ opnsense_api_user }}"
    password: "{{ vault_opnsense_api_password }}"
    force_basic_auth: yes
    validate_certs: no
    body_format: json
    body:
      interface:
        enable: "1"
        ipaddr: "{{ opnsense_lan_ip }}"
        subnet: "{{ opnsense_lan_subnet }}"
```

### 4. AdGuard Home Role Technical Details

**tasks/main.yml**
```yaml
---
- name: Create AdGuard Home directories
  file:
    path: "{{ item }}"
    state: directory
    owner: "{{ ansible_user }}"
    group: "{{ ansible_user }}"
    mode: '0755'
  loop:
    - "{{ adguard_data_dir }}"
    - "{{ adguard_config_dir }}"

- name: Deploy AdGuard Home container
  containers.podman.podman_container:
    name: adguard-home
    image: "{{ adguard_container_image }}"
    state: started
    restart_policy: always
    ports:
      - "{{ adguard_web_port }}:3000"
      - "{{ adguard_dns_port }}:53/tcp"
      - "{{ adguard_dns_port }}:53/udp"
    volumes:
      - "{{ adguard_data_dir }}:/opt/adguardhome/work:Z"
      - "{{ adguard_config_dir }}:/opt/adguardhome/conf:Z"
    env:
      TZ: "{{ timezone }}"

- name: Wait for AdGuard Home to start
  wait_for:
    host: "{{ ansible_default_ipv4.address }}"
    port: "{{ adguard_web_port }}"
    delay: 10
    timeout: 60

- name: Configure AdGuard Home initial setup
  uri:
    url: "http://{{ ansible_default_ipv4.address }}:{{ adguard_web_port }}/control/install/configure"
    method: POST
    body_format: json
    body:
      web:
        ip: "0.0.0.0"
        port: 3000
      dns:
        ip: "0.0.0.0"
        port: 53
      username: "{{ adguard_admin_user }}"
      password: "{{ vault_adguard_admin_password }}"
  register: adguard_setup_result
  failed_when: 
    - adguard_setup_result.status != 200
    - "'already configured' not in adguard_setup_result.content"

- name: Configure upstream DNS servers
  uri:
    url: "http://{{ ansible_default_ipv4.address }}:{{ adguard_web_port }}/control/dns_config"
    method: POST
    user: "{{ adguard_admin_user }}"
    password: "{{ vault_adguard_admin_password }}"
    force_basic_auth: yes
    body_format: json
    body:
      upstream_dns:
        - "127.0.0.1:{{ unbound_port }}"
        - "1.1.1.1"
        - "8.8.8.8"
      bootstrap_dns:
        - "1.1.1.1"
        - "8.8.8.8"
```

**tasks/update_blocklists.yml**
```yaml
---
- name: Get current filter lists
  uri:
    url: "http://{{ ansible_default_ipv4.address }}:{{ adguard_web_port }}/control/filtering/status"
    method: GET
    user: "{{ adguard_admin_user }}"
    password: "{{ vault_adguard_admin_password }}"
    force_basic_auth: yes
  register: current_filters

- name: Add new blocklist
  uri:
    url: "http://{{ ansible_default_ipv4.address }}:{{ adguard_web_port }}/control/filtering/add_url"
    method: POST
    user: "{{ adguard_admin_user }}"
    password: "{{ vault_adguard_admin_password }}"
    force_basic_auth: yes
    body_format: json
    body:
      name: "{{ item.name }}"
      url: "{{ item.url }}"
      whitelist: false
  loop: "{{ adguard_blocklists }}"
  when: item.url not in (current_filters.json.filters | map(attribute='url') | list)

- name: Update filter lists
  uri:
    url: "http://{{ ansible_default_ipv4.address }}:{{ adguard_web_port }}/control/filtering/refresh"
    method: POST
    user: "{{ adguard_admin_user }}"
    password: "{{ vault_adguard_admin_password }}"
    force_basic_auth: yes
    body_format: json
    body:
      whitelist: false
```

### 5. Unbound DNS Role Technical Details

**tasks/main.yml**
```yaml
---
- name: Install Unbound DNS
  package:
    name: unbound
    state: present
  become: yes

- name: Create Unbound configuration directory
  file:
    path: /etc/unbound/unbound.conf.d
    state: directory
    owner: root
    group: root
    mode: '0755'
  become: yes

- name: Generate Unbound configuration
  template:
    src: unbound.conf.j2
    dest: /etc/unbound/unbound.conf
    owner: root
    group: root
    mode: '0644'
    backup: yes
  become: yes
  notify: restart unbound

- name: Download root hints
  get_url:
    url: https://www.internic.net/domain/named.cache
    dest: /etc/unbound/root.hints
    owner: root
    group: root
    mode: '0644'
  become: yes
  notify: restart unbound

- name: Generate root key for DNSSEC
  command: unbound-anchor -a /etc/unbound/root.key
  args:
    creates: /etc/unbound/root.key
  become: yes
  notify: restart unbound

- name: Set correct permissions on root key
  file:
    path: /etc/unbound/root.key
    owner: unbound
    group: unbound
    mode: '0644'
  become: yes

- name: Start and enable Unbound service
  systemd:
    name: unbound
    state: started
    enabled: yes
  become: yes
```

**templates/unbound.conf.j2**
```jinja2
server:
    # Listen on all interfaces
{% for interface in unbound_listen_interfaces %}
    interface: {{ interface }}
{% endfor %}
    port: {{ unbound_port }}

    # Access control
{% for acl in unbound_access_control %}
    access-control: {{ acl.network }} {{ acl.action }}
{% endfor %}

    # Performance tuning
    num-threads: {{ ansible_processor_vcpus }}
    msg-cache-slabs: {{ ansible_processor_vcpus }}
    rrset-cache-slabs: {{ ansible_processor_vcpus }}
    infra-cache-slabs: {{ ansible_processor_vcpus }}
    key-cache-slabs: {{ ansible_processor_vcpus }}

    # Cache settings
    rrset-cache-size: {{ unbound_rrset_cache_size }}
    msg-cache-size: {{ unbound_msg_cache_size }}

    # DNSSEC
    auto-trust-anchor-file: /etc/unbound/root.key
    root-hints: /etc/unbound/root.hints

    # Privacy settings
    hide-identity: yes
    hide-version: yes
    qname-minimisation: yes

    # Logging
    verbosity: {{ unbound_verbosity }}
    log-queries: {{ unbound_log_queries | lower }}

{% if unbound_forward_zones is defined %}
# Forward zones
{% for zone in unbound_forward_zones %}
forward-zone:
    name: "{{ zone.name }}"
{% for server in zone.servers %}
    forward-addr: {{ server }}
{% endfor %}
{% endfor %}
{% endif %}
```

## Dynamic Inventory Implementation

### Proxmox Dynamic Inventory Script

**inventory/proxmox_inventory.py**
```python
#!/usr/bin/env python3

import json
import requests
import sys
from urllib3.exceptions import InsecureRequestWarning

# Suppress SSL warnings for self-signed certificates
requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)

class ProxmoxInventory:
    def __init__(self):
        self.proxmox_url = "https://your-proxmox-host:8006"
        self.username = "ansible@pve"
        self.password = "your-password"
        self.verify_ssl = False
        
        self.inventory = {
            '_meta': {
                'hostvars': {}
            }
        }
        
        self.get_ticket()
        self.generate_inventory()

    def get_ticket(self):
        """Authenticate with Proxmox and get authentication ticket"""
        auth_data = {
            'username': self.username,
            'password': self.password
        }
        
        response = requests.post(
            f"{self.proxmox_url}/api2/json/access/ticket",
            data=auth_data,
            verify=self.verify_ssl
        )
        
        if response.status_code == 200:
            ticket_data = response.json()['data']
            self.ticket = ticket_data['ticket']
            self.csrf_token = ticket_data['CSRFPreventionToken']
            self.headers = {
                'Cookie': f"PVEAuthCookie={self.ticket}",
                'CSRFPreventionToken': self.csrf_token
            }
        else:
            raise Exception("Failed to authenticate with Proxmox")

    def generate_inventory(self):
        """Generate Ansible inventory from Proxmox VMs"""
        response = requests.get(
            f"{self.proxmox_url}/api2/json/cluster/resources?type=vm",
            headers=self.headers,
            verify=self.verify_ssl
        )
        
        if response.status_code == 200:
            vms = response.json()['data']
            
            for vm in vms:
                if vm['status'] == 'running':
                    vm_name = vm['name']
                    vm_id = vm['vmid']
                    node = vm['node']
                    
                    # Get VM configuration for more details
                    vm_config = self.get_vm_config(node, vm_id)
                    
                    # Determine groups based on VM name or configuration
                    groups = self.determine_groups(vm_name, vm_config)
                    
                    # Add to groups
                    for group in groups:
                        if group not in self.inventory:
                            self.inventory[group] = {'hosts': []}
                        self.inventory[group]['hosts'].append(vm_name)
                    
                    # Add host variables
                    self.inventory['_meta']['hostvars'][vm_name] = {
                        'ansible_host': self.get_vm_ip(node, vm_id),
                        'proxmox_vmid': vm_id,
                        'proxmox_node': node,
                        'vm_status': vm['status']
                    }

    def get_vm_config(self, node, vmid):
        """Get detailed VM configuration"""
        response = requests.get(
            f"{self.proxmox_url}/api2/json/nodes/{node}/qemu/{vmid}/config",
            headers=self.headers,
            verify=self.verify_ssl
        )
        
        if response.status_code == 200:
            return response.json()['data']
        return {}

    def get_vm_ip(self, node, vmid):
        """Get VM IP address from Proxmox agent"""
        response = requests.get(
            f"{self.proxmox_url}/api2/json/nodes/{node}/qemu/{vmid}/agent/network-get-interfaces",
            headers=self.headers,
            verify=self.verify_ssl
        )
        
        if response.status_code == 200:
            interfaces = response.json()['data']['result']
            for interface in interfaces:
                if 'ip-addresses' in interface:
                    for ip_info in interface['ip-addresses']:
                        if ip_info['ip-address-type'] == 'ipv4' and not ip_info['ip-address'].startswith('127.'):
                            return ip_info['ip-address']
        return None

    def determine_groups(self, vm_name, vm_config):
        """Determine Ansible groups based on VM characteristics"""
        groups = ['all']
        
        if 'opnsense' in vm_name.lower():
            groups.append('opnsense_vms')
        elif 'ubuntu' in vm_name.lower():
            groups.append('ubuntu_servers')
        
        if 'proxy' in vm_name.lower():
            groups.append('proxmox_hosts')
            
        return groups

if __name__ == '__main__':
    inventory = ProxmoxInventory()
    print(json.dumps(inventory.inventory, indent=2))
```

## Variable Defaults and Examples

### Default Variables Structure

**group_vars/all.yml**
```yaml
# Timezone and NTP
timezone: "UTC"
ntp_servers:
  - 0.pool.ntp.org
  - 1.pool.ntp.org

# Common packages
common_packages:
  - curl
  - wget
  - vim
  - htop
  - net-tools
  - tmux

# DNS configuration
primary_dns_server: "{{ hostvars[groups['ubuntu_servers'][0]]['ansible_default_ipv4']['address'] }}"
secondary_dns_servers:
  - "1.1.1.1"
  - "8.8.8.8"

# Container settings
container_runtime: podman
container_user: "{{ ansible_user }}"
```

**group_vars/proxmox_hosts.yml**
```yaml
# Proxmox API settings
proxmox_api_host: "{{ ansible_host }}"
proxmox_api_user: "ansible@pve"
proxmox_node: "{{ ansible_hostname }}"
proxmox_storage: "local-lvm"

# Default VM settings
default_vm_settings:
  cpu: 2
  memory: 2048
  disk: 20
  os_type: "l26"
  bridge: "vmbr0"
```

**group_vars/opnsense_vms.yml**
```yaml
# OPNSense specific settings
opnsense_vm_id: 100
opnsense_vm_name: "opnsense-router"
opnsense_hostname: "opnsense"
opnsense_domain: "local"
opnsense_memory: 2048
opnsense_cpu: 2
opnsense_disk: 20

# Network configuration
opnsense_wan_interface: "vtnet0"
opnsense_lan_interface: "vtnet1"
opnsense_lan_ip: "192.168.1.1"
opnsense_lan_subnet: "24"
opnsense_lan_bridge: "vmbr1"

# API configuration
opnsense_api_user: "ansible"
opnsense_management_ip: "{{ opnsense_lan_ip }}"

# ISO settings
opnsense_iso_url: "https://mirror.ams1.nl.leaseweb.net/opnsense/releases/24.1/OPNsense-24.1-dvd-amd64.iso"
opnsense_iso_filename: "OPNsense-24.1-dvd-amd64.iso"
```

**group_vars/ubuntu_servers.yml**
```yaml
# Ubuntu server VM settings
ubuntu_vm_id: 101
ubuntu_vm_name: "ubuntu-server-24.04"
ubuntu_memory: 4096
ubuntu_cpu: 4
ubuntu_disk: 40

# Service configurations
adguard_container_image: "adguard/adguardhome:latest"
adguard_web_port: 3000
adguard_dns_port: 53
adguard_data_dir: "/home/{{ ansible_user }}/adguard/data"
adguard_config_dir: "/home/{{ ansible_user }}/adguard/config"
adguard_admin_user: "admin"

# Unbound DNS settings
unbound_port: 5335
unbound_listen_interfaces:
  - "127.0.0.1"
  - "{{ ansible_default_ipv4.address }}"

unbound_access_control:
  - network: "127.0.0.0/8"
    action: "allow"
  - network: "192.168.1.0/24"
    action: "allow"
  - network: "0.0.0.0/0"
    action: "refuse"

unbound_rrset_cache_size: "256m"
unbound_msg_cache_size: "128m"
unbound_verbosity: 1
unbound_log_queries: false

# AdGuard blocklists
adguard_blocklists:
  - name: "AdGuard DNS filter"
    url: "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"
  - name: "AdAway Default Blocklist"
    url: "https://adaway.org/hosts.txt"
  - name: "Peter Lowe's Ad and tracking server list"
    url: "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblockplus&showintro=1&mimetype=plaintext"

# Portainer settings
portainer_data_dir: "/home/{{ ansible_user }}/portainer"
portainer_web_port: 9000

# Semaphore settings
semaphore_data_dir: "/home/{{ ansible_user }}/semaphore"
semaphore_web_port: 3001
semaphore_db_type: "sqlite"
```

## Error Handling and Validation

### Validation Tasks Example

**validation/validate_services.yml**
```yaml
---
- name: Validate AdGuard Home is running
  uri:
    url: "http://{{ ansible_default_ipv4.address }}:{{ adguard_web_port }}/control/status"
    method: GET
  register: adguard_status
  failed_when: adguard_status.status != 200

- name: Validate Unbound DNS is responding
  command: dig @127.0.0.1 -p {{ unbound_port }} google.com
  register: unbound_test
  failed_when: "'ANSWER SECTION' not in unbound_test.stdout"

- name: Validate OPNSense web interface
  uri:
    url: "https://{{ opnsense_management_ip }}"
    method: GET
    validate_certs: no
  register: opnsense_web
  failed_when: opnsense_web.status != 200

- name: Check VM resource usage
  shell: |
    free -m | awk 'NR==2{printf "%.2f%%", $3*100/$2}'
  register: memory_usage
  
- name: Fail if memory usage is too high
  fail:
    msg: "Memory usage is {{ memory_usage.stdout }}, which is too high"
  when: memory_usage.stdout | float > 80.0
```

## Semaphore Integration Specifications

### Project Configuration
```json
{
  "name": "Privacy Router Infrastructure",
  "repository": {
    "git_url": "https://github.com/your-org/privacy-router-ansible.git",
    "git_branch": "main",
    "ssh_key_id": 1
  },
  "inventory_id": 1,
  "environment": {
    "ANSIBLE_HOST_KEY_CHECKING": "False",
    "ANSIBLE_STDOUT_CALLBACK": "yaml"
  }
}
```

### Task Templates
```json
[
  {
    "name": "Full Infrastructure Deployment",
    "playbook": "site.yml",
    "inventory_id": 1,
    "environment_id": 1,
    "allow_override_args_in_task": true
  },
  {
    "name": "Deploy Network Services",
    "playbook": "playbooks/deployment/deploy_network_services.yml",
    "inventory_id": 1,
    "environment_id": 1
  },
  {
    "name": "Update Blocklists",
    "playbook": "playbooks/maintenance/update_blocklists.yml",
    "inventory_id": 1,
    "environment_id": 1,
    "cron": "0 2 * * *"
  }
]
```

This technical implementation guide provides the specific details needed to implement the Ansible playbooks, including exact module usage, configuration templates, error handling, and integration specifications. Another agent should now have sufficient detail to begin implementation.
