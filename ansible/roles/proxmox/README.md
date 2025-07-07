# Proxmox Ansible Role

This role provides comprehensive management capabilities for Proxmox Virtual Environment, including VM creation, network configuration, and storage management.

## Requirements

- Ansible 2.9 or higher
- `community.general` collection installed (`ansible-galaxy collection install community.general`)
- Proxmox VE 6.0 or higher
- API access to Proxmox (either password or API token authentication)

## Role Variables

### Required Variables

- `proxmox_api_host`: Proxmox server hostname or IP address
- `proxmox_api_user`: API username (e.g., `root@pam`)
- `proxmox_api_password` OR `proxmox_api_token_id` + `proxmox_api_token_secret`: Authentication credentials

### Operation Variables

- `proxmox_operation`: Main operation to perform. Options:
  - `create_vm`: Create a new virtual machine
  - `configure_network`: Configure VM network interfaces
  - `manage_storage`: Manage storage operations

### VM Creation Variables

When using `proxmox_operation: create_vm`:
- `proxmox_vm_name`: Name of the VM
- `proxmox_vm_vmid`: Unique VM ID
- `proxmox_vm_node`: Target Proxmox node
- `proxmox_vm_cores`: Number of CPU cores (default: 2)
- `proxmox_vm_memory`: RAM in MB (default: 2048)
- `proxmox_vm_disks`: Dictionary of disk configurations
- `proxmox_vm_networks`: Dictionary of network interfaces

### Cloud Image Variables (Optional)

When creating VMs from cloud images:
- `proxmox_vm_cloud_image_url`: URL to cloud image (triggers cloud image mode)
- `proxmox_vm_cloud_image_checksum`: Optional checksum for verification
- `proxmox_cloud_image_cache_dir`: Cache directory (default: `/var/lib/vz/template/iso`)

### Cloud-Init Variables (Optional)

For cloud-init configuration:
- `proxmox_vm_cloud_init_enabled`: Enable cloud-init (default: true)
- `proxmox_vm_cloud_init_user`: Default username (default: ubuntu)
- `proxmox_vm_cloud_init_password`: User password (SSH keys preferred)
- `proxmox_vm_cloud_init_ssh_keys`: List of SSH public keys
- `proxmox_vm_cloud_init_ip`: IP config - "dhcp" or "192.168.1.100/24"
- `proxmox_vm_cloud_init_gw`: Gateway (required for static IP)
- `proxmox_vm_cloud_init_dns`: DNS servers (space-separated)

### Network Configuration Variables

When using `proxmox_operation: configure_network`:
- `proxmox_vm_vmid`: VM ID to configure
- `proxmox_vm_node`: Node where VM resides
- `proxmox_vm_network_interfaces`: Dictionary of network interfaces to configure
- `proxmox_vm_vlan_interfaces`: Dictionary of VLAN interfaces

### Storage Management Variables

When using `proxmox_operation: manage_storage`:
- `proxmox_storage_operation`: Specific storage operation:
  - `download_iso`: Download ISO to storage
  - `add_disk`: Add disk to VM
  - `resize_disk`: Resize existing disk
  - `configure_backup`: Set up backup schedule
  - `manual_backup`: Create immediate backup
  - `storage_info`: Get storage information

## Example Playbooks

### Create a VM

```yaml
- name: Create OPNsense firewall VM
  hosts: localhost
  tasks:
    - include_role:
        name: proxmox
      vars:
        proxmox_operation: create_vm
        proxmox_api_host: "192.168.1.100"
        proxmox_api_user: "root@pam"
        proxmox_api_password: "{{ vault_proxmox_password }}"
        proxmox_vm_name: "opnsense-fw01"
        proxmox_vm_vmid: 100
        proxmox_vm_node: "pve01"
        proxmox_vm_cores: 2
        proxmox_vm_memory: 4096
        proxmox_vm_disks:
          scsi0: "local-lvm:32,format=raw"
        proxmox_vm_networks:
          net0: "virtio,bridge=vmbr0,firewall=1"
          net1: "virtio,bridge=vmbr1,firewall=1"
```

### Create VM from Cloud Image

```yaml
- name: Create Ubuntu VM from cloud image
  hosts: localhost
  tasks:
    - include_role:
        name: proxmox
      vars:
        proxmox_operation: create_vm
        proxmox_api_host: "192.168.1.100"
        proxmox_api_user: "root@pam"
        proxmox_api_password: "{{ vault_proxmox_password }}"
        proxmox_vm_name: "ubuntu-cloud-01"
        proxmox_vm_vmid: 200
        proxmox_vm_node: "pve01"
        # Cloud image configuration
        proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['ubuntu-24.04'] }}"
        # Cloud-init configuration
        proxmox_vm_cloud_init_user: "myuser"
        proxmox_vm_cloud_init_ssh_keys:
          - "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
        proxmox_vm_cloud_init_ip: "192.168.1.150/24"
        proxmox_vm_cloud_init_gw: "192.168.1.1"
        proxmox_vm_cloud_init_dns: "8.8.8.8 8.8.4.4"
```

### Configure Network

```yaml
- name: Add VLAN interfaces to VM
  hosts: localhost
  tasks:
    - include_role:
        name: proxmox
      vars:
        proxmox_operation: configure_network
        proxmox_api_host: "192.168.1.100"
        proxmox_api_user: "root@pam"
        proxmox_api_token_id: "ansible"
        proxmox_api_token_secret: "{{ vault_proxmox_token }}"
        proxmox_vm_vmid: 100
        proxmox_vm_node: "pve01"
        proxmox_vm_vlan_interfaces:
          net2: "virtio,bridge=vmbr1,tag=100"
          net3: "virtio,bridge=vmbr1,tag=200"
```

### Download ISO

```yaml
- name: Download Ubuntu Server ISO
  hosts: localhost
  tasks:
    - include_role:
        name: proxmox
      vars:
        proxmox_operation: manage_storage
        proxmox_storage_operation: download_iso
        proxmox_api_host: "192.168.1.100"
        proxmox_api_user: "root@pam"
        proxmox_api_password: "{{ vault_proxmox_password }}"
        proxmox_iso_node: "pve01"
        proxmox_iso_url: "https://releases.ubuntu.com/22.04/ubuntu-22.04.3-live-server-amd64.iso"
        proxmox_iso_filename: "ubuntu-22.04.3-live-server-amd64.iso"
```

### Add Disk to VM

```yaml
- name: Add data disk to VM
  hosts: localhost
  tasks:
    - include_role:
        name: proxmox
      vars:
        proxmox_operation: manage_storage
        proxmox_storage_operation: add_disk
        proxmox_api_host: "192.168.1.100"
        proxmox_api_user: "root@pam"
        proxmox_api_password: "{{ vault_proxmox_password }}"
        proxmox_vm_vmid: 100
        proxmox_disk_size: "100G"
        proxmox_disk_interface: "scsi1"
        proxmox_disk_storage: "local-lvm"
```

## Authentication

The role supports two authentication methods:

1. **Password Authentication**:
   ```yaml
   proxmox_api_user: "root@pam"
   proxmox_api_password: "your-password"
   ```

2. **API Token Authentication** (recommended):
   ```yaml
   proxmox_api_user: "root@pam"
   proxmox_api_token_id: "ansible"
   proxmox_api_token_secret: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
   ```

## VM Templates

The role includes predefined VM templates in `defaults/main.yml`:
- `opnsense`: Optimized for OPNsense firewall
- `ubuntu_server`: General purpose Ubuntu server
- `docker_host`: Docker container host with increased resources

## Predefined Cloud Images

The role includes URLs for common cloud images in `proxmox_cloud_image_urls`:
- `ubuntu-24.04`: Ubuntu 24.04 LTS Server
- `ubuntu-22.04`: Ubuntu 22.04 LTS Server
- `ubuntu-20.04`: Ubuntu 20.04 LTS Server
- `debian-12`: Debian 12 (Bookworm)
- `debian-11`: Debian 11 (Bullseye)
- `centos-9-stream`: CentOS 9 Stream
- `centos-8-stream`: CentOS 8 Stream

Example usage:
```yaml
proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['ubuntu-24.04'] }}"
```

## Handlers

Available handlers that can be notified:
- `restart vm`: Restart a VM
- `stop vm`: Stop a VM
- `start vm`: Start a VM
- `restart proxmox networking`: Restart networking on Proxmox node
- `reload network configuration`: Reload network config without restart
- `wait for vm network`: Wait for VM network connectivity
- `create snapshot`: Create a VM snapshot

## License

MIT

## Author Information

Created by the PrivateBox team for managing Proxmox infrastructure via Ansible.