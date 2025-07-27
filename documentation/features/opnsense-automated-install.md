# OPNsense Automated Installation via qm sendkey

## Overview

This document describes the 100% hands-off OPNsense deployment using Proxmox's `qm sendkey` command to automate the installation process.

## Solution Architecture

The solution uses a Two-ISO approach:
1. **Main OPNsense DVD ISO** - The standard installer
2. **Config ISO** - Contains `/conf/config.xml` for automatic configuration import

The installation is automated by:
- Using `qm sendkey` to send keystrokes to the VM console
- Navigating through the installer automatically
- Rebooting into a fully configured system

## Implementation Details

### Key Components

1. **Helper Script** (`qm-sendstring.sh`)
   - Simplifies sending strings via qm sendkey
   - Handles character-by-character input with proper delays
   - Supports special characters

2. **Automated Login**
   ```bash
   # Send username "installer"
   /tmp/qm-sendstring.sh {{ opnsense_vm_id }} "installer"
   qm sendkey {{ opnsense_vm_id }} "ret"
   
   # Send password "opnsense"
   /tmp/qm-sendstring.sh {{ opnsense_vm_id }} "opnsense"
   qm sendkey {{ opnsense_vm_id }} "ret"
   ```

3. **Installation Navigation**
   - Accept and continue: `qm sendkey {{ opnsense_vm_id }} "ret"`
   - Select guided install: `qm sendkey {{ opnsense_vm_id }} "ret"`
   - Select disk: `qm sendkey {{ opnsense_vm_id }} "spc"` then `"ret"`
   - Use entire disk: `qm sendkey {{ opnsense_vm_id }} "ret"`
   - GPT/UEFI scheme: `qm sendkey {{ opnsense_vm_id }} "ret"`
   - Complete and reboot: `qm sendkey {{ opnsense_vm_id }} "ret"`

### Timing Considerations

Critical delays are built into the process:
- 30 seconds: Wait for boot to login prompt
- 10 seconds: Wait for installer to start after login
- 2 seconds: Between each installer screen
- 180 seconds: For file copy/installation
- 120 seconds: For reboot and config import

### Boot Order Management

The playbook manages boot order:
1. Initial boot from DVD ISO for installation
2. After installation, switches to boot from disk:
   ```bash
   qm set {{ opnsense_vm_id }} --boot order=scsi0
   ```

## Usage

### Basic Deployment
```bash
ansible-playbook -i inventory.yml opnsense-deploy-two-iso.yml \
  -e "opnsense_ssh_key='ssh-rsa AAAAB3NzaC1yc2E...'"
```

### Custom Configuration
```bash
ansible-playbook -i inventory.yml opnsense-deploy-two-iso.yml \
  -e "opnsense_ssh_key='ssh-rsa AAAAB3NzaC1yc2E...'" \
  -e "opnsense_vm_id=8001" \
  -e "opnsense_lan_ip=192.168.1.100" \
  -e "opnsense_root_password=MySecurePassword"
```

## Process Flow

1. **VM Creation**
   - Creates VM with specified resources
   - Attaches both DVD and config ISOs
   - Configures network interfaces

2. **Automated Installation**
   - VM boots from DVD ISO
   - Script waits for login prompt
   - Logs in as installer/opnsense
   - Navigates installer menus automatically
   - Completes installation and reboots

3. **Configuration Import**
   - System boots from disk
   - OPNsense detects config ISO
   - Automatically imports `/conf/config.xml`
   - Applies all settings (IP, SSH keys, etc.)

4. **Verification**
   - Waits for HTTPS interface
   - Tests connectivity
   - Reports success

## Advantages

1. **100% Hands-Off**: No manual console interaction required
2. **Reliable**: Uses standard installer flow with proper timing
3. **Configurable**: All settings in config.xml are applied
4. **Idempotent**: Checks prevent duplicate VMs

## Requirements

- Proxmox VE host
- Network bridges configured (vmbr0, optionally vmbr1)
- SSH key for OPNsense access
- ~5-7 minutes for complete deployment

## Troubleshooting

### Installation Fails
- Check VM console to see where it stopped
- Verify ISO downloads completed successfully
- Ensure sufficient delays between steps

### Network Not Configured
- Verify config.xml is valid (xmllint check)
- Check config ISO was created properly
- Ensure network bridges exist on Proxmox

### Cannot Access After Installation
- Verify IP address in config matches your network
- Check firewall rules on Proxmox host
- Ensure SSH key was provided correctly