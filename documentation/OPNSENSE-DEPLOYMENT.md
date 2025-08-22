# OPNsense Deployment Guide

## Overview

OPNsense is deployed using a pre-configured Proxmox template that provides a minimal, ready-to-use firewall configuration. The template is stored as a GitHub release and can be deployed via Ansible playbook through Semaphore.

## Template Information

- **Version**: OPNsense 25.7 (amd64)
- **Release**: [v1.0.0-opnsense](https://github.com/Rasped/privatebox/releases/tag/v1.0.0-opnsense)
- **Size**: 766MB (compressed with zstd)
- **Format**: Proxmox VMA backup (`.vma.zst`)

## Default Configuration

### Network Setup
- **WAN Interface (vtnet0)**: DHCP client on bridge vmbr0
- **LAN Interface (vtnet1)**: Static IP 10.10.10.1/24 on bridge vmbr1
- **SSH Access**: Enabled on LAN interface only
- **Firewall Rules**: Default allow LAN to any

### Credentials
- **Username**: root
- **Password**: opnsense

## Deployment Methods

### Method 1: Via Semaphore (Recommended)

1. Log into Semaphore UI (http://192.168.1.20:3000)
2. Navigate to the PrivateBox project
3. Run the "Deploy OPNsense" template
4. Provide:
   - VM ID (e.g., 101)
   - VM Name (e.g., opnsense-fw)
   - Whether to start automatically
   - Whether to apply custom config

### Method 2: Via Ansible CLI

```bash
ansible-playbook -i ansible/inventory.yml \
  ansible/playbooks/services/opnsense-deploy.yml \
  -e vm_id=101 \
  -e vm_name=opnsense-fw \
  -e start_after_restore=yes
```

### Method 3: Manual Deployment

```bash
# Download template
wget https://github.com/Rasped/privatebox/releases/download/v1.0.0-opnsense/opnsense-25.7-template.vma.zst

# Transfer to Proxmox host
scp opnsense-25.7-template.vma.zst root@192.168.1.10:/tmp/

# SSH to Proxmox and restore
ssh root@192.168.1.10
qmrestore /tmp/opnsense-25.7-template.vma.zst 101
qm set 101 --name opnsense-fw --onboot 1
qm start 101
```

## Post-Deployment Configuration

### Accessing OPNsense

1. **SSH Access** (from management network):
   ```bash
   ssh root@10.10.10.1
   ```

2. **Web Interface**:
   - URL: https://10.10.10.1
   - Username: root
   - Password: opnsense

### Applying Custom Configuration

If you have a saved configuration from another OPNsense instance:

1. Save your config as `ansible/files/opnsense/config-custom.xml`
2. Run the deployment playbook with `apply_custom_config=yes`
3. Or manually apply:
   ```bash
   scp config-custom.xml root@10.10.10.1:/conf/config.xml
   ssh root@10.10.10.1 "configctl firmware restart"
   ```

### VLAN Configuration

For the full VLAN setup described in the network architecture:

1. Access OPNsense web UI
2. Navigate to Interfaces → Assignments → VLANs
3. Add VLANs on vtnet1 (LAN):
   - VLAN 10: Infrastructure
   - VLAN 20: Management
   - VLAN 30: Trusted LAN
   - VLAN 40: IoT
   - VLAN 50: Guest
   - VLAN 60: Cameras

4. Assign interfaces for each VLAN
5. Configure IP addresses:
   - VLAN 10: 10.10.10.1/24
   - VLAN 20: 10.10.20.1/24
   - VLAN 30: 10.10.30.1/24
   - VLAN 40: 10.10.40.1/24
   - VLAN 50: 10.10.50.1/24
   - VLAN 60: 10.10.60.1/24

6. Enable DHCP servers as needed
7. Configure firewall rules per the security model

## Integration with PrivateBox

### Network Architecture

OPNsense serves as the central router/firewall for the PrivateBox environment:

```
Internet → ISP Router → OPNsense WAN
                         ↓
                    OPNsense LAN → VLANs → Services
```

### Service Access

- Management VM and services communicate through OPNsense
- VLANs provide network segmentation
- Firewall rules enforce security boundaries

## Backup and Recovery

### Creating a Backup

```bash
# From OPNsense
System → Configuration → Backups → Download
```

### Storing Configuration

Save configurations in:
```
ansible/files/opnsense/
├── config-vm100-backup.xml  # Original template config
├── config-custom.xml        # Your custom config
└── config-production.xml    # Production config
```

## Troubleshooting

### Cannot Access Web UI

1. Verify VM is running: `qm status <VMID>`
2. Check network connectivity: `ping 10.10.10.1`
3. Ensure you're on the correct network segment

### SSH Connection Refused

- SSH is only allowed on LAN interface (10.10.10.1)
- Not accessible from WAN by default
- Use Proxmox console if locked out

### Template Download Fails

- Check GitHub releases page
- Verify network connectivity
- Manual download and transfer as fallback

## Updating the Template

When a new OPNsense version is released:

1. Deploy current template
2. Update OPNsense through web UI
3. Export clean configuration
4. Convert VM to new template
5. Create new GitHub release

## Security Notes

- Change default password immediately after deployment
- Configure proper firewall rules before production use
- Enable two-factor authentication for web UI
- Regularly update OPNsense for security patches