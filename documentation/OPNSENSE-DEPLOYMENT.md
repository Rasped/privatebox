# OPNsense Deployment Guide

## Overview

OPNsense is deployed using a pre-configured Proxmox template that provides a minimal, ready-to-use firewall configuration. The template is stored as a GitHub release and can be deployed via Ansible playbook through Semaphore.

## Current Development Access

During configuration phase, access the OPNsense instance:

```bash
# SSH access using temporary key
ssh -i /private/tmp/opnsense-temp-key root@192.168.1.173

# Web UI access
http://192.168.1.173
Username: root
Password: opnsense

# Configuration control commands
configctl interface reload    # Reload interface configs
configctl filter reload       # Reload firewall rules
configctl wireguard restart   # Restart WireGuard service
```

**Note:** These temporary access methods will be removed in final configuration

## Template Information

- **Version**: OPNsense 25.7 (amd64)
- **Current Status**: Configuration complete, ready for testing
- **Location**: 192.168.1.173 (development instance)
- **SSH Key**: `/private/tmp/opnsense-temp-key`
- **Configuration Status**: All core features configured (VLANs, DHCP, Firewall, WireGuard, OpenVPN)
- **Future Release**: Will be packaged as Proxmox template after testing

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
wget https://github.com/Rasped/privatebox/releases/download/v1.0.0-opnsense/vzdump-qemu-101-opnsense.vma.zst

# Transfer to Proxmox host
scp vzdump-qemu-101-opnsense.vma.zst root@192.168.1.10:/tmp/

# SSH to Proxmox and restore
ssh root@192.168.1.10
qmrestore /tmp/vzdump-qemu-101-opnsense.vma.zst 101
qm set 101 --name opnsense-fw --onboot 1
qm start 101
```

## Post-Deployment Configuration

### Accessing OPNsense

1. **SSH Access**:
   - From LAN network (10.10.10.0/24):
     ```bash
     ssh root@10.10.10.1
     ```
   - From Proxmox host to WAN interface:
     ```bash
     SSHPASS='opnsense' sshpass -e ssh root@<WAN_IP>
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

### VLAN Configuration (Completed)

The template includes full VLAN configuration:

**Configured VLANs:**
- VLAN 10: Services (10.10.10.1/24) - No DHCP
- VLAN 20: Trusted LAN (10.10.20.1/24) - DHCP .100-.200
- VLAN 30: Guest (10.10.30.1/24) - DHCP .100-.120
- VLAN 40: IoT Cloud (10.10.40.1/24) - DHCP .100-.200
- VLAN 50: IoT Local (10.10.50.1/24) - DHCP .100-.200
- VLAN 60: Cameras Cloud (10.10.60.1/24) - DHCP .100-.150
- VLAN 70: Cameras Local (10.10.70.1/24) - DHCP .100-.150

**Firewall Rules:** Complete VLAN isolation implemented
**DNS:** Configured to use AdGuard (10.10.10.10) when deployed
**NTP:** Available on all VLAN gateway IPs

### VPN Configuration (Completed)

**WireGuard VPN:**
- Port: 51820 (UDP)
- Tunnel Network: 10.10.100.0/24
- Interface: opt8 (wg0)
- Access: Equivalent to Trusted VLAN
- Note: Keys are placeholders, regenerate on deployment

**OpenVPN:**
- Port: 1194 (UDP)
- Tunnel Network: 10.10.101.0/24
- Interface: opt9 (ovpns1)
- Cipher: AES-256-GCM
- TLS Minimum: 1.2
- Full tunnel mode (redirect-gateway)
- DNS Push: 10.10.10.10 (AdGuard)
- Access: Equivalent to Trusted VLAN
- PKI: CA and certificates are placeholders, regenerate on deployment

## Post-Deployment Tasks

When deploying from the template, these tasks must be completed:

### Security Keys Generation
1. **WireGuard:**
   - Generate server private/public keypair
   - Generate peer keys for each user
   - Update config with real keys

2. **OpenVPN PKI:**
   - Generate Certificate Authority (CA)
   - Generate server certificate and key
   - Generate TLS auth key (ta.key)
   - Generate DH parameters
   - Create client certificates for each user

### Site-Specific Configuration
- Update WAN IP/interface for location
- Adjust DNS servers if needed
- Configure dynamic DNS (optional)
- Set timezone and NTP servers

### Testing
- Verify all VLANs are accessible
- Test both VPN connections
- Confirm firewall rules are working
- Check DNS resolution through AdGuard

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

### VMA Restore Fails

- Ensure filename follows `vzdump-qemu-*` pattern
- Proxmox requires this naming convention for VMA backups
- File must be accessible to qmrestore command

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