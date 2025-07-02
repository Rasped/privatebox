# CRITICAL SECURITY SETUP - MUST READ

## ⚠️ IMMEDIATE ACTION REQUIRED

The vault files in `ansible/group_vars/vault/` contain sensitive credentials and are currently **NOT ENCRYPTED**.

### Step 1: Create Vault Password File
```bash
# Generate a strong vault password
openssl rand -base64 32 > .vault_pass
chmod 600 .vault_pass

# Add to .gitignore if not already there
echo ".vault_pass" >> .gitignore
```

### Step 2: Encrypt ALL Vault Files
```bash
# Encrypt all vault files immediately
ansible-vault encrypt ansible/group_vars/vault/*.yml

# You'll be prompted for the vault password
# Use the password from .vault_pass
```

### Step 3: Generate Secure Passwords
Replace all default passwords before encrypting:

```bash
# Generate secure passwords for each service
echo "vault_proxmox_api_password: \"$(openssl rand -base64 32)\""
echo "vault_adguard_admin_password: \"$(openssl rand -base64 32)\""
echo "vault_portainer_admin_password: \"$(openssl rand -base64 32)\""
echo "vault_semaphore_admin_password: \"$(openssl rand -base64 32)\""
echo "vault_opnsense_root_password: \"$(openssl rand -base64 32)\""
```

### Step 4: Update .gitignore
Ensure these are in your .gitignore:
```
.vault_pass
*.decrypted
**/vault/*.yml.dec
.env
```

## Security Best Practices

1. **Never commit unencrypted vault files**
2. **Use different passwords for each environment**
3. **Rotate passwords every 90 days**
4. **Use API tokens instead of passwords where possible**
5. **Enable 2FA on all administrative interfaces**

## Emergency Response

If vault files were accidentally committed unencrypted:
1. Immediately rotate ALL passwords
2. Revoke and regenerate all API keys
3. Review access logs for unauthorized access
4. Consider the repository compromised

## Verifying Encryption

```bash
# Check if files are encrypted
file ansible/group_vars/vault/*.yml

# Should show: "ASCII text" if NOT encrypted
# Should show: "data" if properly encrypted
```