# Implementation: Service-Oriented Ansible Playbooks with Podman Quadlet

## Overview

We will implement a service-oriented approach where each container service gets its own dedicated playbook. This design optimizes for SemaphoreUI usage and maintainability.

## Directory Structure

```
ansible/
├── inventories/
│   ├── production/
│   │   └── hosts.yml
│   └── development/
│       └── hosts.yml
├── group_vars/
│   ├── all/
│   │   ├── main.yml              # Global settings
│   │   └── containers.yml         # Container-wide settings
│   └── privatebox/
│       └── main.yml              # PrivateBox-specific vars
├── playbooks/
│   ├── services/                 # Service deployment playbooks
│   │   ├── adguard.yml          # Deploy AdGuard Home
│   │   ├── pihole.yml           # Alternative: Pi-hole
│   │   └── _template.yml        # Template for new services
│   ├── maintenance/             # Operational playbooks
│   │   ├── update_containers.yml
│   │   └── backup_services.yml
│   └── site.yml                 # Master playbook (optional)
├── files/
│   └── quadlet/                 # Quadlet unit templates
│       ├── adguard.container.j2
│       └── _template.container.j2
└── README.md                    # Documentation
```

## Implementation Details

### 1. Global Variables Structure

**group_vars/all/main.yml:**
```yaml
---
# Global settings for all hosts
ansible_user: privatebox
ansible_become: true
ansible_become_method: sudo

# Paths
privatebox_base_path: /opt/privatebox
```

**group_vars/all/containers.yml:**
```yaml
---
# Container runtime configuration
container_runtime: podman
quadlet_user_path: "{{ ansible_env.HOME }}/.config/containers/systemd"
quadlet_system_path: /etc/containers/systemd
container_data_root: "{{ privatebox_base_path }}/data"
container_config_root: "{{ privatebox_base_path }}/config"

# Use system path for services that need to start at boot
use_system_quadlet: true
```

**group_vars/privatebox/main.yml:**
```yaml
---
# Service-specific default configurations
# These can be overridden in SemaphoreUI

# AdGuard Home
adguard_enabled: true
adguard_version: "latest"
adguard_web_port: 8080      # Avoid 80/443 conflicts
adguard_dns_port: 53
adguard_setup_port: 3001    # Avoid Semaphore's 3000
adguard_data_dir: "{{ container_data_root }}/adguard"
adguard_config_dir: "{{ container_config_root }}/adguard"
```

### 2. Service Playbook Pattern

**playbooks/services/adguard.yml:**
```yaml
---
- name: Deploy AdGuard Home DNS Filter
  hosts: privatebox
  become: true
  
  vars:
    service_name: "AdGuard Home"
    service_description: "Network-wide ads & trackers blocking DNS server"
    
  # Allow override from SemaphoreUI survey
  vars_prompt:
    - name: confirm_deploy
      prompt: "Deploy {{ service_name }}? (yes/no)"
      default: "yes"
      private: no
      
    - name: custom_web_port
      prompt: "Web UI port (default: {{ adguard_web_port }})"
      default: "{{ adguard_web_port }}"
      private: no

  tasks:
    - name: "{{ service_name }} - Pre-deployment checks"
      when: confirm_deploy | bool
      tags: [adguard, preflight]
      block:
        - name: Check if Podman is installed
          command: which podman
          register: podman_check
          changed_when: false
          failed_when: false
          
        - name: Fail if Podman not installed
          fail:
            msg: "Podman is not installed. Please install Podman first."
          when: podman_check.rc != 0
          
        - name: Check for port conflicts
          wait_for:
            port: "{{ item }}"
            state: stopped
            timeout: 1
          loop:
            - "{{ custom_web_port }}"
            - "{{ adguard_dns_port }}"
          ignore_errors: true
          register: port_check
          
        - name: Warn about port conflicts
          debug:
            msg: "Warning: Port {{ item.item }} may be in use"
          loop: "{{ port_check.results }}"
          when: item.failed is defined and not item.failed

    - name: "{{ service_name }} - Deployment"
      when: confirm_deploy | bool
      tags: [adguard, deploy]
      block:
        - name: Create directory structure
          file:
            path: "{{ item }}"
            state: directory
            owner: "{{ ansible_user }}"
            group: "{{ ansible_user }}"
            mode: '0755'
          loop:
            - "{{ adguard_data_dir }}"
            - "{{ adguard_config_dir }}"
            - "{{ quadlet_system_path if use_system_quadlet else quadlet_user_path }}"
            
        - name: Deploy Quadlet unit file
          template:
            src: ../../files/quadlet/adguard.container.j2
            dest: "{{ quadlet_system_path if use_system_quadlet else quadlet_user_path }}/adguard.container"
            owner: root
            group: root
            mode: '0644'
          register: quadlet_deployed
          
        - name: Reload systemd daemon
          systemd:
            daemon_reload: true
          when: quadlet_deployed.changed
            
        - name: Start and enable AdGuard Home
          systemd:
            name: adguard-container.service
            state: started
            enabled: true
            scope: "{{ 'system' if use_system_quadlet else 'user' }}"
            
        - name: Wait for AdGuard Home to be ready
          wait_for:
            port: "{{ custom_web_port }}"
            delay: 5
            timeout: 60
            
    - name: "{{ service_name }} - Post-deployment information"
      when: confirm_deploy | bool
      tags: [adguard, info]
      block:
        - name: Display access information
          debug:
            msg:
              - "{{ service_name }} has been deployed successfully!"
              - "Access the web interface at: http://{{ ansible_host }}:{{ custom_web_port }}"
              - "Initial setup will be required on first access"
              - "DNS server is running on port: {{ adguard_dns_port }}"
              - ""
              - "To use AdGuard as your DNS server:"
              - "  - Set your router's DNS to: {{ ansible_host }}"
              - "  - Or configure individual devices to use: {{ ansible_host }}:{{ adguard_dns_port }}"
```

### 3. Quadlet Template Pattern

**files/quadlet/adguard.container.j2:**
```ini
[Unit]
Description={{ service_description }}
Documentation=https://github.com/AdguardTeam/AdGuardHome
Wants=network-online.target
After=network-online.target

[Container]
Image=docker.io/adguard/adguardhome:{{ adguard_version }}
ContainerName=adguard-home

# Network configuration
PublishPort={{ custom_web_port | default(adguard_web_port) }}:3000
PublishPort={{ adguard_dns_port }}:53/tcp
PublishPort={{ adguard_dns_port }}:53/udp
PublishPort={{ adguard_setup_port }}:3000

# Volume mounts
Volume={{ adguard_data_dir }}:/opt/adguardhome/work:Z
Volume={{ adguard_config_dir }}:/opt/adguardhome/conf:Z

# Security
SecurityLabelDisable=false
NoNewPrivileges=true

# Resource limits (optional)
MemoryLimit=512M
CPUQuota=50%

# Health check
HealthCmd=curl -f http://localhost:3000 || exit 1
HealthInterval=30s
HealthRetries=3
HealthStartPeriod=30s
HealthTimeout=10s

[Service]
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target default.target
```

### 4. Service Template for New Services

**playbooks/services/_template.yml:**
```yaml
---
- name: Deploy {{ SERVICE_NAME }}
  hosts: privatebox
  become: true
  
  vars:
    service_name: "{{ SERVICE_NAME }}"
    service_description: "{{ SERVICE_DESCRIPTION }}"
    
  vars_prompt:
    - name: confirm_deploy
      prompt: "Deploy {{ service_name }}? (yes/no)"
      default: "yes"
      private: no

  tasks:
    - name: "{{ service_name }} - Deployment"
      when: confirm_deploy | bool
      tags: [{{ SERVICE_TAG }}, deploy]
      block:
        # ... deployment tasks following the pattern above
```

## SemaphoreUI Integration

### Job Template Configuration

For each service, create a SemaphoreUI job template:

1. **Template Name**: "Deploy AdGuard Home"
2. **Playbook**: `playbooks/services/adguard.yml`
3. **Inventory**: Select appropriate inventory
4. **Environment**: Production/Development
5. **Survey Variables**:
   ```json
   {
     "confirm_deploy": {
       "type": "boolean",
       "default": true,
       "description": "Confirm deployment"
     },
     "custom_web_port": {
       "type": "integer", 
       "default": 8080,
       "description": "Web UI Port"
     }
   }
   ```

## Advantages of This Implementation

1. **Clear Service Boundaries**: Each service is self-contained
2. **SemaphoreUI Friendly**: One template per service, clear progress
3. **Easy to Extend**: Copy template, modify for new service
4. **Maintainable**: Simple structure, clear patterns
5. **Flexible**: Can override any variable from SemaphoreUI
6. **Professional**: Proper error handling, health checks, logging

## Simplicity Analysis

- **Initial approach**: Complex role-based structure with dependencies
- **Simplified to**: One playbook per service with shared variables
- **Because**: Easier to understand, debug, and extend
- **Trade-offs accepted**: Some code duplication between playbooks, but gained massive clarity