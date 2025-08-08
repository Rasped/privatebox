# FreeBSD 14.3 Autoinstall Playbooks

This directory contains two FreeBSD autoinstall playbooks for different deployment methods:

## Available Playbooks

### 1. SSH Method: `freebsd-autoinstall.yml` 
Traditional SSH-based deployment using `qm` commands directly on Proxmox host.

### 2. API Method: `freebsd-autoinstall-api.yml` (NEW)
Modern API-based deployment using Proxmox REST API with better error handling.

**Recommendation**: Use the API method for new deployments.

---

## SSH Method (Legacy)

This playbook provides fully automated FreeBSD 14.3 VM installation using Proxmox VE and SSH commands.

## Features

- **100% Automated**: No manual intervention required
- **Static IP Configuration**: Pre-configured network settings
- **Security Hardening**: Optional security enhancements
- **Template-based**: Uses Jinja2 templates for installerconfig
- **Config Drive**: ISO-based configuration delivery
- **Semaphore Integration**: Works with existing PrivateBox Semaphore setup

## Quick Start

### Basic Usage

```bash
# Run with default settings (VM ID 9999, IP 192.168.1.100)
ansible-playbook -i ansible/inventory.yml ansible/playbooks/services/freebsd-autoinstall.yml

# Custom VM ID and IP
ansible-playbook -i ansible/inventory.yml ansible/playbooks/services/freebsd-autoinstall.yml \
  -e "vmid=1001" \
  -e "vm_static_ip=192.168.1.101" \
  -e "vm_name=my-freebsd-vm"
```

### Via Semaphore

The playbook is automatically configured for Semaphore with:
- Environment: `ServicePasswords` (uses `SERVICES_PASSWORD` variable)
- Templates generated in Semaphore UI
- SSH key integration with Proxmox

## Configuration Variables

### VM Settings
```yaml
vmid: 9999                    # VM ID in Proxmox
vm_name: "freebsd-vm"         # VM name
vm_memory: 2048               # RAM in MB
vm_cores: 2                   # CPU cores
vm_disk_size: "20G"           # Disk size
vm_storage: "local-lvm"       # Proxmox storage
network_bridge: "vmbr0"       # Network bridge
```

### Network Configuration
```yaml
vm_static_ip: "192.168.1.100"      # Static IP
vm_netmask: "255.255.255.0"        # Subnet mask
vm_gateway: "192.168.1.1"          # Default gateway
vm_dns1: "8.8.8.8"                 # Primary DNS
vm_dns2: "8.8.4.4"                 # Secondary DNS
```

### FreeBSD System Settings
```yaml
freebsd_hostname: "freebsd-auto"    # System hostname
freebsd_username: "freebsd"         # User account
freebsd_password: "changeme"        # User password (use SERVICES_PASSWORD)
freebsd_timezone: "UTC"             # System timezone
freebsd_swap_size: "2G"             # Swap partition size
```

### Security & Hardening
```yaml
freebsd_security_hardening: true    # Enable security hardening
freebsd_ssh_security: true          # SSH security settings
freebsd_enable_firewall: false      # Enable built-in firewall
```

### Package Management
```yaml
freebsd_packages:                   # Default packages
  - "bash"
  - "nano" 
  - "curl"
  - "wget"
  - "git"
freebsd_additional_packages: []     # Extra packages
```

## Advanced Configuration

### Custom SSH Key
```yaml
freebsd_ssh_key: "ssh-rsa AAAAB3N..."
```

### Custom Scripts
```yaml
freebsd_post_install_commands:
  - "echo 'Custom command 1'"
  - "pkg install -y htop"

freebsd_custom_scripts:
  - name: "Custom setup"
    content: |
      #!/bin/sh
      echo "Running custom script"
```

### Performance Tuning
```yaml
freebsd_performance_tuning: true
freebsd_auto_updates: true
```

## Installation Process

1. **Pre-flight Checks**: Validates Proxmox environment
2. **ISO Download**: Downloads FreeBSD 14.3 ISO if needed
3. **Config Generation**: Creates installerconfig and postinstall scripts
4. **Config Drive**: Builds ISO with configurations
5. **VM Creation**: Creates VM with proper settings
6. **Installation**: Automated FreeBSD installation (up to 60 minutes)
7. **Post-Install**: Runs customization scripts
8. **Validation**: Tests SSH connectivity
9. **Cleanup**: Removes temporary files

## Files Created

### Templates
- `ansible/templates/freebsd/installerconfig.j2` - Main installer script
- `ansible/templates/freebsd/postinstall.sh.j2` - Post-installation script

### Temporary Files (auto-cleaned)
- `/tmp/freebsd-config-{vmid}/` - Config drive directory
- `/var/lib/vz/template/iso/freebsd-config-{vmid}.iso` - Config drive ISO

### Permanent Files
- `/tmp/freebsd-{vmid}-deployment-info.txt` - Deployment information

## Integration with PrivateBox

### Inventory Integration
The playbook automatically adds entries to the `freebsd_vms` group:

```yaml
freebsd_vms:
  hosts:
    freebsd-vm:
      ansible_host: 192.168.1.100
      ansible_user: freebsd
      ansible_python_interpreter: /usr/local/bin/python3
```

### Semaphore Integration
- Uses `ServicePasswords` environment
- Integrates with existing SSH key setup
- Follows PrivateBox service-oriented architecture

## Troubleshooting

### Installation Monitoring
The playbook monitors installation for up to 60 minutes. Check VM console:
```bash
qm terminal {vmid}
```

### Installation Logs
On the installed system:
```bash
# Installation log
cat /tmp/installerconfig.log

# Installation completion marker
cat /tmp/install-complete
```

### Common Issues
1. **ISO Download Fails**: Check internet connectivity on Proxmox
2. **VM Creation Fails**: Verify VM ID is available, storage exists
3. **Installation Hangs**: Check VM console, may need manual intervention
4. **SSH Test Fails**: Verify network configuration, firewall settings

## Customization Examples

### OPNsense Preparation
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/services/freebsd-autoinstall.yml \
  -e "vmid=963" \
  -e "vm_name=opnsense-base" \
  -e "vm_memory=4096" \
  -e "freebsd_packages=['bash','nano','curl','wget']" \
  -e "freebsd_hostname=opnsense-temp"
```

### Development VM
```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/services/freebsd-autoinstall.yml \
  -e "vmid=2000" \
  -e "vm_name=freebsd-dev" \
  -e "freebsd_additional_packages=['git','gmake','gcc','python3']" \
  -e "freebsd_performance_tuning=true"
```

## Security Notes

- Default password should be changed immediately after installation
- SSH key authentication recommended for production use
- Security hardening includes firewall rules and kernel settings
- Regular updates should be configured for production systems

## API Method (Recommended)

For the new API-based method, see:
- **Playbook**: `freebsd-autoinstall-api.yml`
- **Documentation**: `README-freebsd-api.md`
- **Test Script**: `test-freebsd-api.sh`

### Key Advantages of API Method
- No SSH access to Proxmox required
- Better error handling and validation
- API token authentication support
- Proper cleanup and resource management
- More secure (no SSH key distribution)

---

## Requirements (SSH Method)

- Proxmox VE host with SSH access
- Internet connectivity for ISO download
- Sufficient storage space (minimum 20GB + ISO size)
- Network bridge configured in Proxmox