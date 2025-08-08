# Proxmox API Token Setup Guide

This guide explains how to set up and manage Proxmox API tokens for the PrivateBox automation system.

## Overview

The PrivateBox FreeBSD autoinstall and other automation features require Proxmox API access. This is achieved through API tokens, which provide secure, stateless authentication without exposing root credentials.

## Quick Setup

### 1. Create API Token (on Proxmox host)

```bash
# Option A: Use the automated script
./bootstrap/bootstrap.sh --setup-proxmox-api

# Option B: Manual setup
ssh root@192.168.1.10
pveum user add automation@pve
pveum user token add automation@pve ansible --privsep 1
# SAVE THE TOKEN SECRET - shown only once!
```

### 2. Register in Semaphore (on PrivateBox VM)

```bash
ssh debian@192.168.1.20
sudo /opt/privatebox/scripts/register-proxmox-api.sh
```

## Detailed Instructions

### Step 1: Create Proxmox API Token

#### Automated Method

Run on your Proxmox host:

```bash
cd /path/to/privatebox
./bootstrap/bootstrap.sh --setup-proxmox-api
```

This script will:
- Create the `automation@pve` user
- Generate an API token named `ansible`
- Set appropriate permissions for VM management
- Save credentials to `/root/.proxmox-api-token`
- Test the token to ensure it works

#### Manual Method

If you prefer manual setup:

```bash
# SSH to Proxmox host
ssh root@192.168.1.10

# Create user (if not exists)
pveum user add automation@pve --comment "Automation user for Ansible"

# Create token with privilege separation
pveum user token add automation@pve ansible --privsep 1

# IMPORTANT: Copy the token secret shown - it won't be displayed again!
# Example output:
# ┌──────────────┬──────────────────────────────────────┐
# │ key          │ value                                │
# ├──────────────┼──────────────────────────────────────┤
# │ full-tokenid │ automation@pve!ansible               │
# ├──────────────┼──────────────────────────────────────┤
# │ info         │ {"privsep":"1"}                      │
# ├──────────────┼──────────────────────────────────────┤
# │ value        │ 12345678-90ab-cdef-1234-567890abcdef│
# └──────────────┴──────────────────────────────────────┘

# Set permissions for VM management
pveum acl modify /vms -token 'automation@pve!ansible' -role PVEVMAdmin
pveum acl modify /storage -token 'automation@pve!ansible' -role PVEDatastoreUser
pveum acl modify /nodes -token 'automation@pve!ansible' -role PVEAuditor
pveum acl modify /system -token 'automation@pve!ansible' -role PVEAuditor
```

### Step 2: Register Token in Semaphore

#### Automated Method

Run on the PrivateBox VM:

```bash
ssh debian@192.168.1.20
sudo /opt/privatebox/scripts/register-proxmox-api.sh
```

The script will:
- Prompt for token details (or load from file if transferred)
- Test the token against Proxmox API
- Login to Semaphore automatically
- Create or update the ProxmoxAPI environment
- Confirm successful registration

#### Manual Method via Semaphore API

```bash
# Login to Semaphore
curl -c /tmp/semaphore-cookie -X POST \
  -H 'Content-Type: application/json' \
  -d '{"auth": "admin", "password": "YOUR_PASSWORD"}' \
  http://192.168.1.20:3000/api/auth/login

# Create ProxmoxAPI environment
curl -b /tmp/semaphore-cookie -X POST \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "ProxmoxAPI",
    "project_id": 1,
    "secrets": [
      {"name": "PROXMOX_HOST", "secret": "192.168.1.10"},
      {"name": "PROXMOX_NODE", "secret": "pve"},
      {"name": "PROXMOX_TOKEN_ID", "secret": "automation@pve!ansible"},
      {"name": "PROXMOX_TOKEN_SECRET", "secret": "YOUR-TOKEN-SECRET-HERE"}
    ]
  }' \
  http://192.168.1.20:3000/api/project/1/environment
```

### Step 3: Configure Playbooks

Update your Ansible playbooks to use the ProxmoxAPI environment:

```yaml
# In your playbook
- name: FreeBSD Autoinstall
  hosts: localhost
  vars:
    # These will be loaded from ProxmoxAPI environment
    proxmox_api_host: "{{ lookup('env', 'PROXMOX_HOST') }}"
    proxmox_api_node: "{{ lookup('env', 'PROXMOX_NODE') }}"
    proxmox_api_token_id: "{{ lookup('env', 'PROXMOX_TOKEN_ID') }}"
    proxmox_api_token_secret: "{{ lookup('env', 'PROXMOX_TOKEN_SECRET') }}"
```

In Semaphore job templates, set:
```yaml
environment_id: 3  # ID of ProxmoxAPI environment
```

## Permissions Explained

The token requires specific permissions:

| Permission | Path | Purpose |
|------------|------|---------|
| PVEVMAdmin | /vms | Create, modify, delete VMs |
| PVEDatastoreUser | /storage | Upload ISOs, create disks |
| PVEAuditor | /nodes | View node status |
| PVEAuditor | /system | View system information |

## Security Best Practices

1. **Never commit tokens to git**
   - Use environment variables
   - Store in Semaphore secrets
   - Keep local copies in protected files (mode 600)

2. **Use privilege separation**
   - Always create tokens with `--privsep 1`
   - Grant minimal required permissions
   - Different tokens for different purposes

3. **Rotate tokens regularly**
   - Delete old tokens: `pveum user token remove automation@pve!ansible`
   - Create new tokens periodically
   - Update Semaphore environments after rotation

## Troubleshooting

### Token Test Failed

```bash
# Test directly with curl
curl -sk \
  -H "Authorization: PVEAPIToken=automation@pve!ansible=YOUR-SECRET" \
  https://192.168.1.10:8006/api2/json/version
```

Expected response:
```json
{"data":{"release":"8.0","repoid":"12345678","version":"8.0.3"}}
```

### Permission Denied Errors

Check token permissions:
```bash
# On Proxmox host
pveum user token permissions automation@pve!ansible
```

### Semaphore Environment Not Working

1. Check environment exists:
```bash
curl -s -b /tmp/semaphore-cookie \
  http://192.168.1.20:3000/api/project/1/environment | jq
```

2. Verify secrets are set:
   - Look for ProxmoxAPI environment
   - Check all 4 variables are present

3. Test in playbook:
```yaml
- debug:
    msg: "Token ID: {{ lookup('env', 'PROXMOX_TOKEN_ID') }}"
```

## Files and Locations

- **Token storage (Proxmox)**: `/root/.proxmox-api-token`
- **Setup script**: `bootstrap/scripts/setup-proxmox-api-token.sh`
- **Registration script**: `bootstrap/scripts/register-proxmox-api.sh`
- **FreeBSD playbook**: `ansible/playbooks/services/freebsd-autoinstall-api.yml`

## Related Documentation

- [FreeBSD Autoinstall README](../ansible/playbooks/services/README-freebsd-api.md)
- [Proxmox API Documentation](https://pve.proxmox.com/wiki/Proxmox_VE_API)
- [Semaphore Environment Variables](https://docs.semaphoreui.com/user-guide/environment/)