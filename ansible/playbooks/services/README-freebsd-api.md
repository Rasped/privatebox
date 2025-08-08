# FreeBSD 14.3 Autoinstall via Proxmox API

Automated FreeBSD VM deployment using Proxmox API instead of SSH commands. This playbook creates a fully automated FreeBSD 14.3 installation using config drive and the community.general.proxmox_kvm module.

## Overview

- **Playbook**: `freebsd-autoinstall-api.yml`
- **Method**: Proxmox REST API via Ansible modules
- **Target**: FreeBSD 14.3 VM with static networking
- **Integration**: PrivateBox environment (192.168.1.x subnet)
- **Authentication**: API tokens or username/password

## Key Features

### API-Based Deployment
- Uses `community.general.proxmox_kvm` module
- No SSH required to Proxmox host
- API token authentication support
- Proper error handling and cleanup

### Config Drive Automation
- Builds ISO locally with `genisoimage`
- Uploads via Proxmox API
- Mounts by volume label (`FBSD_CONFIG`)
- Auto-cleanup after deployment

### PrivateBox Integration
- Static IP configuration (192.168.1.55 default)
- Security hardening enabled by default
- Firewall configured for PrivateBox subnet
- SSH key distribution ready

## Environment Variables

Set these in Semaphore environment or as extra vars:

### Required (choose one authentication method)

**API Token Authentication (Recommended):**
```bash
PROXMOX_HOST=192.168.1.10
PROXMOX_USER=root@pam
PROXMOX_TOKEN_ID=automation-token
PROXMOX_TOKEN_SECRET=your-secret-here
```

**Password Authentication:**
```bash
PROXMOX_HOST=192.168.1.10
PROXMOX_USER=root@pam
PROXMOX_PASSWORD=your-password-here
```

### Optional
```bash
SERVICES_PASSWORD=custom-password-here
```

## Usage Examples

### Basic Deployment
```bash
# Using environment variables
ansible-playbook -i inventory.yml ansible/playbooks/services/freebsd-autoinstall-api.yml

# With extra vars
ansible-playbook -i inventory.yml ansible/playbooks/services/freebsd-autoinstall-api.yml \
  -e "vmid=9955 vm_name=freebsd-test vm_static_ip=192.168.1.56"
```

### Using Deployment Profiles
```bash
# Minimal VM (1GB RAM, 1 core, 10GB disk)
ansible-playbook -i inventory.yml ansible/playbooks/services/freebsd-autoinstall-api.yml \
  -e "@ansible/group_vars/all/freebsd-api.yml" \
  -e "deployment_profile=minimal vmid=9950"

# High-performance VM (4GB RAM, 4 cores, 40GB disk)
ansible-playbook -i inventory.yml ansible/playbooks/services/freebsd-autoinstall-api.yml \
  -e "@ansible/group_vars/all/freebsd-api.yml" \
  -e "deployment_profile=performance vmid=9940"
```

### Custom Configuration
```bash
ansible-playbook -i inventory.yml ansible/playbooks/services/freebsd-autoinstall-api.yml \
  -e "vmid=9960" \
  -e "vm_name=freebsd-custom" \
  -e "vm_memory=3072" \
  -e "vm_cores=3" \
  -e "vm_static_ip=192.168.1.60" \
  -e "freebsd_hostname=custom-freebsd"
```

## Configuration Files

### Main Configuration
- **Group vars**: `ansible/group_vars/all/freebsd-api.yml`
- **Templates**: `ansible/templates/freebsd/`
  - `installerconfig.j2` - FreeBSD autoinstall script
  - `postinstall.sh.j2` - Post-installation customization

### VM Profiles Available
- **minimal**: 1GB RAM, 1 core, 10GB disk, basic packages
- **standard**: 2GB RAM, 2 cores, 20GB disk, common packages  
- **performance**: 4GB RAM, 4 cores, 40GB disk, performance tuning

## Network Configuration

Default static networking for PrivateBox environment:
```yaml
vm_static_ip: "192.168.1.55"
vm_netmask: "255.255.255.0"
vm_gateway: "192.168.1.1"
vm_dns1: "8.8.8.8"
vm_dns2: "8.8.4.4"
```

Firewall configured to allow SSH from PrivateBox subnet only.

## Security Features

### Hardening Applied
- SSH security configuration
- Firewall enabled (simple profile)
- System security sysctls
- Unnecessary services disabled
- Process visibility restricted

### User Configuration
- Non-root user created with sudo access
- Password authentication enabled
- SSH key distribution ready
- Wheel group membership

## Installation Process

1. **Pre-flight Checks**: Validate API credentials and settings
2. **ISO Management**: Download FreeBSD ISO and upload to Proxmox
3. **Config Drive**: Generate installerconfig/postinstall, build ISO, upload
4. **VM Creation**: Create VM with proper hardware configuration
5. **Installation**: Start VM, monitor completion via API polling
6. **Post-Install**: Remove ISOs, set boot from disk, restart VM
7. **Validation**: Test SSH connectivity and FreeBSD detection
8. **Cleanup**: Remove temporary files and uploaded config ISO

## Monitoring and Validation

The playbook includes comprehensive validation:
- API connectivity testing
- Installation progress monitoring
- SSH connectivity verification
- FreeBSD system detection
- Deployment information logging

## Troubleshooting

### Common Issues

**Authentication Fails**
```bash
# Check environment variables
echo $PROXMOX_HOST $PROXMOX_USER $PROXMOX_TOKEN_ID

# Verify API access manually
curl -k -H "Authorization: PVEAPIToken=USER@REALM!TOKENID=SECRET" \
  https://PROXMOX_HOST:8006/api2/json/version
```

**VM Creation Fails**
- Verify storage name (`vm_storage`)
- Check network bridge exists (`network_bridge`)
- Ensure VM ID not in use

**Installation Hangs**
- VM may need more time (default: 60 minutes timeout)
- Check Proxmox console for installer status
- Verify config drive ISO mounted correctly

**SSH Test Fails**
- Check firewall rules on Proxmox/network
- Verify static IP configuration
- Ensure installation completed successfully

### Log Files
- **Local**: `/tmp/freebsd-VMID-api-deployment-info.txt`
- **VM**: `/tmp/installerconfig.log` (during install)
- **VM**: `/tmp/install-complete` (success marker)

## Semaphore Integration

This playbook is designed for Semaphore with:
- Environment variable authentication
- Survey variables for customization
- Proper tagging for selective execution
- Deployment profile support

### Template Configuration
```yaml
name: "FreeBSD VM Autoinstall (API)"
environment: "ServicePasswords"
survey_enabled: true
playbook: "ansible/playbooks/services/freebsd-autoinstall-api.yml"
```

## Differences from SSH Version

| Feature | SSH Version | API Version |
|---------|-------------|-------------|
| Proxmox Access | SSH commands | REST API |
| Authentication | SSH keys | API tokens/password |
| VM Operations | `qm` commands | `proxmox_kvm` module |
| Error Handling | Shell exit codes | API responses |
| Concurrency | Sequential | Can be parallel |
| Monitoring | Shell polling | API polling |

## Next Steps

After successful deployment:
1. SSH to FreeBSD VM: `ssh freebsd@192.168.1.55`
2. Install application services
3. Configure monitoring/logging
4. Add to Caddy reverse proxy (if needed)
5. Set up backup procedures

## API Token Setup

To create API tokens in Proxmox (recommended):

1. **Via Web UI**:
   - Navigate to Datacenter → Permissions → API Tokens
   - Add new token for user (e.g., `root@pam`)
   - Copy Token ID and Secret

2. **Via CLI** (on Proxmox):
   ```bash
   pveum user token add root@pam automation-token --privsep=0
   ```

The API method provides better security and auditability than password authentication.