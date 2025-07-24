# OPNsense Deployment Guide

This guide covers the deployment and configuration of OPNsense firewall using the PrivateBox Ansible playbooks.

## Overview

The OPNsense deployment consists of several modular playbooks that handle different aspects of the firewall configuration:

1. **SSH Key Injection** - Enable passwordless SSH access
2. **API Enablement** - Configure API access for automation
3. **Interface Assignment** - Dynamically assign network interfaces
4. **DHCP Configuration** - Set up DHCP services for all networks
5. **DNS Configuration** - Configure Unbound DNS with optional AdGuard integration
6. **Backup Configuration** - Automated backup and restore procedures

## Prerequisites

- OPNsense VM already created on Proxmox (use VM creation playbooks)
- Network connectivity to both Proxmox host and OPNsense VM
- PrivateBox management VM with Ansible installed

## Quick Start

### Option 1: Complete Setup (Recommended)

Run the complete configuration playbook that executes all steps in sequence:

```bash
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/opnsense-complete.yml \
  -e opnsense_vm_id=9001 \
  -e proxmox_host=192.168.1.10 \
  -e opnsense_host=10.0.0.1
```

### Option 2: Individual Playbooks

Run each playbook separately for more control:

```bash
# 1. Inject SSH keys
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/opnsense-ssh-keys.yml \
  -e opnsense_vm_id=9001 \
  -e proxmox_host=192.168.1.10

# 2. Enable API access
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/opnsense-enable-api.yml \
  -e opnsense_host=10.0.0.1

# 3. Assign interfaces
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/opnsense-assign-interfaces.yml \
  -e opnsense_host=10.0.0.1

# 4. Configure DHCP
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/opnsense-configure-dhcp.yml \
  -e opnsense_host=10.0.0.1

# 5. Configure DNS
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/opnsense-configure-dns.yml \
  -e opnsense_host=10.0.0.1 \
  -e adguard_integration=true

# 6. Create backup
ansible-playbook -i inventories/development/hosts.yml \
  playbooks/services/opnsense-backup.yml \
  -e opnsense_host=10.0.0.1
```

## Configuration Files

### Templates

- `/ansible/templates/opnsense/config.xml.j2` - Main OPNsense configuration template

### Variables

- `/ansible/group_vars/all/opnsense.yml` - Default OPNsense settings

Key variables you can customize:

```yaml
# Network settings
lan_ip: "10.0.0.1"
lan_subnet: "24"
lan_dhcp_start: "10.0.0.100"
lan_dhcp_end: "10.0.0.200"

# VLAN configuration
enable_vlans: true
vlans:
  - name: "IoT"
    tag: 10
    ip: "10.0.10.1"
    subnet: "24"
    dhcp_enabled: true
    
# AdGuard integration
adguard_enabled: true
adguard_ip: "10.0.0.2"
```

## Playbook Details

### 1. SSH Key Injection (`opnsense-ssh-keys.yml`)

This playbook:
- Generates SSH keypair if not exists
- Mounts OPNsense VM disk on Proxmox host
- Injects public key into OPNsense configuration
- Enables SSH and disables password authentication

**Important**: VM must be stopped for disk mounting to work.

### 2. API Enablement (`opnsense-enable-api.yml`)

This playbook:
- Creates API user with admin privileges
- Generates secure API key and secret
- Stores credentials in `/etc/privatebox-opnsense-api-*`
- Tests API connectivity
- Creates example Python client script

### 3. Interface Assignment (`opnsense-assign-interfaces.yml`)

This playbook:
- Discovers available network interfaces
- Assigns WAN and LAN interfaces based on discovery
- Configures VLAN interfaces if enabled
- Saves interface mapping to `/opt/privatebox/config/opnsense-interfaces.conf`

### 4. DHCP Configuration (`opnsense-configure-dhcp.yml`)

This playbook:
- Configures DHCP server for LAN network
- Sets up DHCP for each VLAN if enabled
- Configures static DHCP mappings if defined
- Monitors active DHCP leases

### 5. DNS Configuration (`opnsense-configure-dns.yml`)

This playbook:
- Configures Unbound DNS resolver
- Sets up DNS forwarding (to AdGuard or upstream servers)
- Configures local domain and host overrides
- Sets up access control lists for allowed networks
- Tests DNS resolution

### 6. Backup Configuration (`opnsense-backup.yml`)

This playbook:
- Downloads configuration via API
- Creates timestamped backups
- Generates restore script
- Manages backup retention
- Creates backup inventory

## API Usage

After API enablement, you can interact with OPNsense programmatically:

### Using curl

```bash
# Load credentials
source /opt/privatebox/config/opnsense-api.conf

# Get system status
curl -k -u "$OPNSENSE_API_KEY:$OPNSENSE_API_SECRET" \
  https://$OPNSENSE_HOST/api/core/system/status
```

### Using Python

```python
# Run the example script
python3 /opt/privatebox/scripts/opnsense-api-examples.py 10.0.0.1
```

See `/ansible/files/scripts/opnsense-api-examples.py` for more examples.

## Backup and Restore

### Creating Backups

Backups are automatically created by the backup playbook and stored in:
`/opt/privatebox/backups/opnsense/`

### Restoring from Backup

```bash
# Use the generated restore script
/opt/privatebox/backups/opnsense/scripts/restore-config.sh \
  /opt/privatebox/backups/opnsense/opnsense-backup-2024-01-15.tar.gz \
  10.0.0.1
```

## Troubleshooting

### SSH Key Injection Fails

1. Ensure VM is stopped before running the playbook
2. Verify VM ID is correct
3. Check if Proxmox host has necessary tools (qemu-nbd, kpartx)

### API Connection Issues

1. Verify OPNsense web interface is accessible
2. Check firewall rules allow API access
3. Ensure API user was created successfully
4. Try regenerating API credentials

### DNS Not Resolving

1. Check Unbound service status
2. Verify firewall allows DNS traffic (port 53)
3. Test with dig: `dig @10.0.0.1 google.com`
4. Check access control lists include your network

### DHCP Not Working

1. Verify DHCP service is enabled and running
2. Check interface has correct IP configuration
3. Ensure no other DHCP servers on network
4. Review DHCP logs in OPNsense

## Integration with Other Services

### AdGuard Integration

When AdGuard is deployed, DNS configuration will automatically:
- Detect AdGuard availability
- Configure Unbound to forward queries to AdGuard
- Fall back to upstream DNS if AdGuard is unavailable

### Semaphore Integration

All playbooks include Semaphore metadata for automatic UI generation:
- Job templates are created automatically
- Variables are presented as form fields
- No manual template creation needed

## Security Considerations

1. **API Credentials**: Stored with restricted permissions (0600)
2. **SSH Keys**: Generated with 4096-bit RSA
3. **Backups**: Include checksums for integrity verification
4. **DNS**: DNSSEC enabled by default
5. **Firewall**: Default deny with explicit allow rules

## Next Steps

After OPNsense is configured:

1. Configure firewall rules for your specific needs
2. Set up VPN if required
3. Configure additional services (IDS/IPS, proxy, etc.)
4. Schedule regular backups
5. Monitor logs and alerts

## Support

For issues or questions:
1. Check playbook output for specific errors
2. Review logs on OPNsense: `clog /var/log/system.log`
3. Verify all prerequisites are met
4. Consult OPNsense documentation