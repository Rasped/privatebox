# Proxmox Cloud Image Support

## Overview

This feature enhances the existing proxmox role to support VM creation from cloud images, eliminating the need for manual ISO installation or template preparation. It integrates seamlessly with the current role structure while following all established conventions.

## Status

📋 **Documented** - Implementation pending

- ✅ Analysis completed
- ✅ Design follows existing patterns
- ✅ Variable naming conventions honored
- ✅ Integration approach defined
- ⏳ Implementation not started
- ⏳ Testing framework defined

## Quick Start

### Basic Usage

Create an Ubuntu 24.04 VM from cloud image:

```yaml
- name: Create VM from cloud image
  include_role:
    name: proxmox
  vars:
    proxmox_operation: create_vm
    proxmox_vm_name: ubuntu-cloud-vm
    proxmox_vm_vmid: 200
    proxmox_vm_node: pve01
    proxmox_vm_cloud_image_url: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
```

### With Static IP Configuration

```yaml
- name: Create VM with static IP
  include_role:
    name: proxmox
  vars:
    proxmox_operation: create_vm
    proxmox_vm_name: app-server
    proxmox_vm_vmid: 201
    proxmox_vm_node: pve01
    proxmox_vm_cloud_image_url: "https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
    proxmox_vm_cloud_init_ip: "192.168.1.100/24"
    proxmox_vm_cloud_init_gw: "192.168.1.1"
    proxmox_vm_cloud_init_dns: "1.1.1.1 8.8.8.8"
```

### Using Predefined Images

```yaml
- name: Create Debian VM
  include_role:
    name: proxmox
  vars:
    proxmox_operation: create_vm
    proxmox_vm_name: debian-server
    proxmox_vm_vmid: 202
    proxmox_vm_node: pve01
    proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['debian-12'] }}"
    proxmox_vm_cloud_init_ssh_keys:
      - "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
```

## Features

- ✅ Automatic cloud image download and caching
- ✅ Cloud-init configuration support
- ✅ SSH key injection
- ✅ Static and DHCP networking
- ✅ Multiple OS support (Ubuntu, Debian, CentOS)
- ✅ Integrated with existing proxmox role
- ✅ Follows variable naming conventions
- ✅ Backward compatible

## How It Works

1. **Detection**: The create_vm task detects if `proxmox_vm_cloud_image_url` is provided
2. **Download**: Downloads the cloud image to the Proxmox host (with caching)
3. **VM Creation**: Creates a VM using standard proxmox_kvm module
4. **Disk Import**: Imports the cloud image as the VM's primary disk
5. **Cloud-Init**: Configures cloud-init for initial VM setup
6. **Start**: Optionally starts the VM

## Variables

### Cloud Image Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `proxmox_vm_cloud_image_url` | URL to cloud image (triggers cloud mode) | - |
| `proxmox_vm_cloud_image_checksum` | Optional checksum for verification | - |
| `proxmox_cloud_image_cache_dir` | Directory for image cache | `/var/lib/vz/template/iso` |

### Cloud-Init Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `proxmox_vm_cloud_init_enabled` | Enable cloud-init configuration | `true` |
| `proxmox_vm_cloud_init_user` | Default username | `ubuntu` |
| `proxmox_vm_cloud_init_password` | User password (optional) | - |
| `proxmox_vm_cloud_init_ssh_keys` | List of SSH public keys | `[]` |
| `proxmox_vm_cloud_init_ip` | IP configuration | `dhcp` |
| `proxmox_vm_cloud_init_gw` | Gateway (required for static IP) | - |
| `proxmox_vm_cloud_init_dns` | DNS servers | - |

### Predefined Cloud Images

Available in `proxmox_cloud_image_urls`:
- `ubuntu-24.04` - Ubuntu 24.04 LTS
- `ubuntu-22.04` - Ubuntu 22.04 LTS  
- `ubuntu-20.04` - Ubuntu 20.04 LTS
- `debian-12` - Debian 12 (Bookworm)
- `debian-11` - Debian 11 (Bullseye)

## Integration

This feature is fully integrated with the existing proxmox role:

1. **Same Interface**: Use the standard role inclusion pattern
2. **Same Variables**: All existing `proxmox_vm_*` variables work
3. **Same Operation**: Uses `create_vm` operation, no new operations needed
4. **Backward Compatible**: VMs without cloud images work exactly as before

## Examples

### Minimal Example

```yaml
---
- name: Create cloud-based VM
  hosts: localhost
  tasks:
    - include_role:
        name: proxmox
      vars:
        proxmox_vm_name: test-vm
        proxmox_vm_vmid: 999
        proxmox_vm_node: pve01
        proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['ubuntu-24.04'] }}"
```

### Production Example

```yaml
---
- name: Deploy application server
  hosts: localhost
  tasks:
    - include_role:
        name: proxmox
      vars:
        # VM Basics
        proxmox_vm_name: prod-app-01
        proxmox_vm_vmid: 150
        proxmox_vm_node: pve01
        proxmox_vm_cores: 4
        proxmox_vm_memory: 8192
        
        # Cloud Image
        proxmox_vm_cloud_image_url: "{{ proxmox_cloud_image_urls['ubuntu-22.04'] }}"
        proxmox_vm_cloud_image_checksum: "sha256:..."
        
        # Cloud-Init
        proxmox_vm_cloud_init_user: appuser
        proxmox_vm_cloud_init_ssh_keys:
          - "{{ lookup('file', 'keys/prod-app.pub') }}"
        proxmox_vm_cloud_init_ip: "10.0.1.50/24"
        proxmox_vm_cloud_init_gw: "10.0.1.1"
        proxmox_vm_cloud_init_dns: "10.0.1.10 10.0.1.11"
        
        # Standard VM settings still work
        proxmox_vm_onboot: true
        proxmox_vm_protection: true
        proxmox_vm_description: "Production Application Server"
```

## Implementation Status

### Completed
- 📝 Feature documentation
- 📐 Integration design
- 🔍 Pattern analysis
- ✅ Variable naming

### Pending
- 💻 Code implementation
- 🧪 Testing
- 📚 User documentation updates
- 🔄 Migration guide for old approach

## Comparison with Previous Approach

### ❌ Old Approach (Incorrect)
- Created separate playbooks
- Used non-standard variables (`vm_name` instead of `proxmox_vm_name`)
- Created parallel system
- Broke established conventions

### ✅ New Approach (Correct)
- Extends existing role
- Follows `proxmox_vm_*` naming
- Single integration point
- Maintains all conventions

## Testing

See [testing.md](testing.md) for comprehensive test scenarios.

Key test areas:
- Cloud image download and caching
- VM creation with cloud images
- Cloud-init configuration
- Network configuration (static/DHCP)
- SSH key injection
- Error handling

## Troubleshooting

### Image Download Fails
- Check URL is accessible from Proxmox host
- Verify proxy settings if behind firewall
- Check disk space in cache directory

### VM Creation Fails
- Ensure VMID is unique
- Verify storage has space
- Check Proxmox permissions

### Cloud-Init Not Working
- Verify cloud-init is in the image
- Check serial console for cloud-init output
- Ensure network configuration is correct

## Future Enhancements

1. **Template Creation**: Option to create templates from cloud images
2. **Image Signature Verification**: GPG verification of images
3. **Custom Cloud-Init**: Complex cloud-init configurations
4. **Multi-Architecture**: ARM64 support
5. **Performance**: Parallel VM creation support

## Related Documentation

- [Analysis](analysis.md) - Deep dive into the problem
- [Implementation](implementation.md) - Technical implementation details
- [Alternatives](alternatives.md) - Other approaches considered
- [Testing](testing.md) - Comprehensive test plan
- [Proxmox Role Documentation](../../../ansible/roles/proxmox/README.md)