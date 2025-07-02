# Ansible Vault Usage

This directory contains encrypted variables for the PrivateBox Ansible deployment.

## Initial Setup

1. Create your vault password file:
   ```bash
   cp .vault_pass.example .vault_pass
   chmod 600 .vault_pass
   # Edit .vault_pass and set a strong password
   ```

2. Encrypt all vault files:
   ```bash
   ansible-vault encrypt ansible/group_vars/vault/*.yml
   ```

## Managing Vault Files

### View encrypted content:
```bash
ansible-vault view ansible/group_vars/vault/all.yml
```

### Edit encrypted files:
```bash
ansible-vault edit ansible/group_vars/vault/all.yml
```

### Decrypt files (temporary):
```bash
ansible-vault decrypt ansible/group_vars/vault/all.yml
# Make changes
ansible-vault encrypt ansible/group_vars/vault/all.yml
```

### Change vault password:
```bash
ansible-vault rekey ansible/group_vars/vault/*.yml
```

## Required Variables

Before running any playbooks, ensure these vault variables are set:

### Proxmox API Access
- `vault_proxmox_api_host`: Your Proxmox host IP/hostname
- `vault_proxmox_api_user`: API user (e.g., ansible@pam)
- `vault_proxmox_api_password`: API user password
- `vault_proxmox_node`: Proxmox node name

### Service Passwords
- `vault_adguard_admin_password`: AdGuard Home admin password
- `vault_portainer_admin_password`: Portainer admin password
- `vault_semaphore_admin_password`: Semaphore UI admin password
- `vault_opnsense_root_password`: OPNsense root password

## Security Best Practices

1. **Never commit unencrypted vault files** to version control
2. **Use strong passwords** for all services
3. **Rotate passwords regularly**
4. **Limit vault file access** to authorized personnel only
5. **Keep `.vault_pass` file secure** and never commit it

## Creating Proxmox API User

Run these commands on your Proxmox host:

```bash
# Create user
pveum user add ansible@pam --comment "Ansible automation user"

# Set password
pveum passwd ansible@pam

# Create role with necessary permissions
pveum role add Ansible -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.Audit VM.PowerMgmt VM.Console VM.Snapshot VM.Backup Datastore.AllocateSpace Datastore.Audit Pool.Allocate"

# Assign role to user
pveum aclmod / -user ansible@pam -role Ansible
```