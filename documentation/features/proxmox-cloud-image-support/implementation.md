# Implementation: Proxmox Cloud Image Support

## Chosen Approach

After careful analysis, we will **enhance the existing create_vm task** with cloud image support through conditional logic.

## Rationale

1. **Single Code Path**: One VM creation flow is easier to maintain
2. **Follows Patterns**: Extends existing role without breaking it
3. **Variable Conventions**: Uses established proxmox_vm_* namespace
4. **Backward Compatible**: Existing playbooks continue to work
5. **Progressive Enhancement**: Can extract to separate task later if needed

## Implementation Plan

### Phase 1: Enhance create_vm.yml

The existing task will detect cloud image configuration and handle it:

```yaml
# In roles/proxmox/tasks/create_vm.yml
# Add before VM creation:

- name: Handle cloud image if specified
  include_tasks: prepare_cloud_image.yml
  when: 
    - proxmox_vm_cloud_image_url is defined
    - proxmox_vm_cloud_image_url | length > 0
```

### Phase 2: Create prepare_cloud_image.yml

New task file in the proxmox role:

```yaml
# roles/proxmox/tasks/prepare_cloud_image.yml
---
- name: Set cloud image facts
  set_fact:
    cloud_image_name: "{{ proxmox_vm_cloud_image_url | basename | regex_replace('\\.img$', '') }}"
    cloud_image_cache_dir: "{{ proxmox_cloud_image_cache_dir | default('/var/lib/vz/template/iso') }}"

- name: Ensure cache directory exists
  file:
    path: "{{ cloud_image_cache_dir }}"
    state: directory
    mode: '0755'

- name: Download cloud image
  get_url:
    url: "{{ proxmox_vm_cloud_image_url }}"
    dest: "{{ cloud_image_cache_dir }}/{{ cloud_image_name }}.img"
    checksum: "{{ proxmox_vm_cloud_image_checksum | default(omit) }}"
    timeout: "{{ proxmox_iso_download_timeout | default(600) }}"
  register: cloud_image_download

- name: Create VM without disk first
  set_fact:
    proxmox_vm_disks: {}  # Override to create diskless VM initially
```

### Phase 3: Import Disk After VM Creation

Add to create_vm.yml after VM creation:

```yaml
- name: Import cloud image as VM disk
  include_tasks: import_cloud_image.yml
  when: 
    - proxmox_vm_cloud_image_url is defined
    - vm_creation_result is changed
```

### Phase 4: Cloud-Init Configuration

Add cloud-init support to the existing flow:

```yaml
# In create_vm.yml or import_cloud_image.yml
- name: Configure cloud-init
  command: >
    qm set {{ proxmox_vm_vmid }}
    --ide2 {{ proxmox_disk_storage }}:cloudinit
    --boot c --bootdisk scsi0
    --serial0 socket --vga serial0
  when: proxmox_vm_cloud_init_enabled | default(true)

- name: Set cloud-init network config
  command: >
    qm set {{ proxmox_vm_vmid }}
    --ipconfig0 "ip={{ proxmox_vm_cloud_init_ip | default('dhcp') }},gw={{ proxmox_vm_cloud_init_gw | default('') }}"
  when: proxmox_vm_cloud_init_enabled | default(true)

- name: Set cloud-init user
  command: >
    qm set {{ proxmox_vm_vmid }}
    --ciuser "{{ proxmox_vm_cloud_init_user | default('ubuntu') }}"
    --cipassword "{{ proxmox_vm_cloud_init_password | default('') }}"
  when: 
    - proxmox_vm_cloud_init_enabled | default(true)
    - proxmox_vm_cloud_init_password is defined

- name: Set cloud-init SSH keys
  command: >
    qm set {{ proxmox_vm_vmid }}
    --sshkeys "{{ proxmox_vm_cloud_init_ssh_keys_file }}"
  when:
    - proxmox_vm_cloud_init_enabled | default(true)
    - proxmox_vm_cloud_init_ssh_keys_file is defined
```

## Variable Structure

### New Variables (following conventions):

```yaml
# Cloud image source
proxmox_vm_cloud_image_url: ""  # If set, triggers cloud image mode
proxmox_vm_cloud_image_checksum: ""  # Optional checksum
proxmox_cloud_image_cache_dir: "/var/lib/vz/template/iso"  # Global cache

# Cloud-init configuration
proxmox_vm_cloud_init_enabled: true
proxmox_vm_cloud_init_user: "ubuntu"
proxmox_vm_cloud_init_password: ""  # Optional, SSH keys preferred
proxmox_vm_cloud_init_ssh_keys: []  # List of public keys
proxmox_vm_cloud_init_ssh_keys_file: ""  # Or path to keys file
proxmox_vm_cloud_init_ip: "dhcp"  # Or specific IP like "192.168.1.100/24"
proxmox_vm_cloud_init_gw: ""  # Gateway if static IP
proxmox_vm_cloud_init_dns: ""  # DNS servers
proxmox_vm_cloud_init_domain: ""  # Search domain

# Disk import settings
proxmox_vm_import_disk_format: "qcow2"  # Import format
proxmox_vm_import_disk_size_increase: "+5G"  # Resize after import
```

### Updated defaults/main.yml:

```yaml
# Add to roles/proxmox/defaults/main.yml

# Cloud image defaults
proxmox_cloud_image_urls:
  ubuntu-24.04: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
  ubuntu-22.04: "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
  debian-12: "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  debian-11: "https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"

# Cloud-init defaults
proxmox_vm_cloud_init_enabled: true
proxmox_vm_cloud_init_user: "{{ ansible_user | default('ubuntu') }}"
```

## Usage Examples

### Basic Cloud Image VM:

```yaml
- name: Create Ubuntu VM from cloud image
  include_role:
    name: proxmox
  vars:
    proxmox_operation: create_vm
    proxmox_vm_name: ubuntu-cloud-1
    proxmox_vm_vmid: 200
    proxmox_vm_node: pve01
    proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['ubuntu-24.04'] }}"
```

### With Static IP:

```yaml
- name: Create VM with static IP
  include_role:
    name: proxmox
  vars:
    proxmox_operation: create_vm
    proxmox_vm_name: app-server
    proxmox_vm_vmid: 201
    proxmox_vm_node: pve01
    proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['ubuntu-22.04'] }}"
    proxmox_vm_cloud_init_ip: "192.168.1.100/24"
    proxmox_vm_cloud_init_gw: "192.168.1.1"
    proxmox_vm_cloud_init_dns: "1.1.1.1"
```

### With SSH Keys:

```yaml
- name: Create VM with SSH access
  include_role:
    name: proxmox
  vars:
    proxmox_operation: create_vm
    proxmox_vm_name: secure-vm
    proxmox_vm_vmid: 202
    proxmox_vm_node: pve01
    proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['debian-12'] }}"
    proxmox_vm_cloud_init_ssh_keys:
      - "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
      - "ssh-rsa AAAAB3... admin@example.com"
```

## File Structure

```
ansible/roles/proxmox/
├── tasks/
│   ├── main.yml                    # No changes needed
│   ├── create_vm.yml              # Enhanced with cloud image detection
│   ├── prepare_cloud_image.yml    # New: Download and prepare image
│   ├── import_cloud_image.yml     # New: Import image as disk
│   └── configure_cloud_init.yml   # New: Cloud-init setup
├── defaults/
│   └── main.yml                   # Add cloud image defaults
└── templates/
    └── cloud-init-user-data.j2    # New: Complex cloud-init configs
```

## Integration Points

1. **Existing Variables**: All proxmox_vm_* variables still work
2. **Backward Compatible**: VMs without cloud_image_url work as before
3. **Role Pattern**: Uses same include_role pattern
4. **Error Handling**: Leverages existing retry logic

## Benefits

1. **No New Systems**: Extends existing role
2. **Convention Compliant**: Follows all naming patterns
3. **Progressive**: Can extract logic later if needed
4. **Tested Path**: Uses proven VM creation flow
5. **Single Source**: One place for VM creation logic

## Migration from Old Approach

For any VMs created with the old approach:
```yaml
# Old way (wrong)
ansible-playbook provision_vm_from_cloud_image.yml -e vm_name=test

# New way (correct)
ansible-playbook site.yml -e proxmox_vm_name=test -e proxmox_vm_cloud_image_url=...