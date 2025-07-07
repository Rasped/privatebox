# SSH Key Naming Scheme

This document defines the standardized naming convention for SSH keys used in the PrivateBox infrastructure.

## Overview

SSH keys in PrivateBox follow a hierarchical naming pattern that clearly identifies:
- The target system type (bare metal, VM, container)
- The specific service or purpose
- The access level or use case

## Naming Convention

### Bare Metal Systems

Keys for physical hosts use simple, direct names:

```
proxmox-host         # Primary Proxmox VE host
proxmox-host-2       # Additional Proxmox hosts (if clustered)
```

### Virtual Machines

VM keys use the `vm-` prefix followed by the service name:

```
vm-container-host    # Ubuntu VM hosting containers (Portainer/Semaphore)
vm-opnsense         # OPNsense firewall VM
vm-truenas          # TrueNAS storage VM
```

### Container-Related Keys

Keys for container operations and deployments:

```
podman-deploy       # Deployment operations using Podman
container-registry  # Private container registry access
container-ansible   # Ansible operations within containers (if different from deploy)
```

### Special/Utility Keys

Special purpose keys for specific operations:

```
none               # No authentication (public repos) - auto-created by Semaphore
local-ansible      # Local playbook execution
backup-all         # System-wide backup operations
emergency-access   # Emergency recovery access
```

## Key Properties

### Key Type
All keys should be created with type `ssh` in Semaphore, except for:
- `none` - Type: `none` (for public repositories)
- Password-based keys - Type: `login_password` (discouraged)

### Key Permissions
- All keys should be created with minimum required permissions
- Production keys should have restricted command execution where possible
- Emergency keys should be stored securely and rotated regularly

## Usage Examples

### In Ansible Inventories
```yaml
proxmox_hosts:
  hosts:
    proxmox-01:
      ansible_ssh_private_key_file: "{{ key_store }}/proxmox-host"

container_hosts:
  hosts:
    privatebox-vm:
      ansible_ssh_private_key_file: "{{ key_store }}/vm-container-host"
```

### In Semaphore Tasks
When creating tasks in Semaphore UI, select the appropriate key based on the target:
- Deploying to Proxmox host → `proxmox-host`
- Managing containers → `vm-container-host` or `podman-deploy`
- Configuring firewall → `vm-opnsense`

## Key Rotation Schedule

| Key Name | Rotation Frequency | Last Rotated | Next Rotation |
|----------|-------------------|--------------|---------------|
| proxmox-host | 6 months | Installation | +6 months |
| vm-container-host | 6 months | Installation | +6 months |
| vm-opnsense | 3 months | Installation | +3 months |
| emergency-access | 3 months | Installation | +3 months |

## Security Considerations

1. **Never commit private keys** to version control
2. **Use passphrases** for all production keys
3. **Limit key scope** - create separate keys for different purposes
4. **Monitor key usage** through Semaphore audit logs
5. **Remove unused keys** promptly

## Adding New Keys

When adding new infrastructure components, follow this naming pattern:
1. Determine the system type (bare metal, VM, container)
2. Use the appropriate prefix
3. Add a descriptive service identifier
4. Document the key purpose in Semaphore description field

Example: Adding a new monitoring VM would use `vm-monitoring`