# Dynamic Inventory Setup Guide

## Overview
The dynamic inventory script (`dynamic_inventory.py`) automatically discovers hosts from your Proxmox infrastructure.

## Setup Instructions

### 1. Make the Script Executable
```bash
chmod +x ansible/inventories/development/dynamic_inventory.py
```

### 2. Set Environment Variables
Create a `.env` file or export these variables:

```bash
export PROXMOX_API_HOST="10.0.0.10"
export PROXMOX_API_USER="ansible@pam"
export PROXMOX_API_PASSWORD="your-password-here"
export PROXMOX_VERIFY_SSL="false"
```

Alternatively, create `ansible/inventories/development/.env`:
```
PROXMOX_API_HOST=10.0.0.10
PROXMOX_API_USER=ansible@pam
PROXMOX_API_PASSWORD=your-password-here
PROXMOX_VERIFY_SSL=false
```

### 3. Install Python Dependencies
The script requires the `proxmoxer` Python library:

```bash
pip3 install proxmoxer requests
```

### 4. Test the Script
```bash
# List all hosts
./ansible/inventories/development/dynamic_inventory.py --list

# Get specific host info
./ansible/inventories/development/dynamic_inventory.py --host <hostname>
```

### 5. Use with Ansible
```bash
# Use dynamic inventory with ansible commands
ansible -i ansible/inventories/development/dynamic_inventory.py all -m ping

# Use with playbooks
ansible-playbook -i ansible/inventories/development/dynamic_inventory.py playbooks/site.yml
```

## Configuration in ansible.cfg
The dynamic inventory is already enabled in ansible.cfg:
```ini
[inventory]
enable_plugins = yaml, ini, script, auto, host_list, constructed
```

## Combining Static and Dynamic Inventory
You can use both static and dynamic inventory together:

```bash
ansible-playbook -i ansible/inventories/development/hosts.yml -i ansible/inventories/development/dynamic_inventory.py playbooks/site.yml
```

## Troubleshooting

### Permission Denied Error
```bash
chmod +x ansible/inventories/development/dynamic_inventory.py
```

### Module Not Found Error
```bash
pip3 install proxmoxer requests python-dotenv
```

### Connection Error
- Verify PROXMOX_API_HOST is correct
- Ensure Proxmox API is accessible
- Check firewall rules
- Verify API credentials

### SSL Certificate Error
Set `PROXMOX_VERIFY_SSL=false` for self-signed certificates

## Security Notes
- Never commit `.env` files with credentials
- Use ansible-vault for production credentials
- Consider using API tokens instead of passwords
- Restrict API user permissions to minimum required